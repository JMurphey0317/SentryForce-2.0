public with sharing class SentryCorrelationService {
    public static Map<Id, Id> correlate(List<Sentry_Event__c> eventRecords) {
        Map<Id, Id> incidentByEventId = new Map<Id, Id>();
        if (eventRecords == null || eventRecords.isEmpty()) {
            return incidentByEventId;
        }

        List<Sentry_Correlation_Rule__mdt> rules = [
            SELECT DeveloperName, MasterLabel, Event_Pattern__c, Time_Window_Minutes__c,
                Minimum_Risk__c, Escalation_Severity__c, Enabled__c, Minimum_Event_Count__c
            FROM Sentry_Correlation_Rule__mdt
            WHERE Enabled__c = true
            ORDER BY DeveloperName ASC
        ];
        if (rules.isEmpty()) {
            return incidentByEventId;
        }

        Set<String> actorIds = new Set<String>();
        Set<String> ruleNames = new Set<String>();
        for (Sentry_Event__c eventRecord : eventRecords) {
            if (!String.isBlank(eventRecord.Actor_Id__c)) {
                actorIds.add(eventRecord.Actor_Id__c);
            }
        }
        for (Sentry_Correlation_Rule__mdt ruleRecord : rules) {
            ruleNames.add(ruleRecord.DeveloperName);
        }

        Map<String, Sentry_Incident__c> incidentCache = new Map<String, Sentry_Incident__c>();
        if (!actorIds.isEmpty() && !ruleNames.isEmpty()) {
            for (Sentry_Incident__c incidentRecord : [
                SELECT Id, Severity__c, Status__c, Actor__c, Risk_Score__c,
                    First_Event__c, Last_Event__c, Summary__c, Correlation_Rule__c
                FROM Sentry_Incident__c
                WHERE Actor__c IN :actorIds
                AND Correlation_Rule__c IN :ruleNames
                AND Status__c != 'Resolved'
                WITH SECURITY_ENFORCED
            ]) {
                incidentCache.put(buildIncidentKey(incidentRecord.Actor__c, incidentRecord.Correlation_Rule__c), incidentRecord);
            }
        }

        List<Sentry_Incident__c> incidentsToInsert = new List<Sentry_Incident__c>();
        List<Sentry_Incident__c> incidentsToUpdate = new List<Sentry_Incident__c>();
        Map<String, Set<Id>> linkedEventIdsByIncidentKey = new Map<String, Set<Id>>();

        for (Sentry_Event__c eventRecord : eventRecords) {
            if (String.isBlank(eventRecord.Actor_Id__c)) {
                continue;
            }
            for (Sentry_Correlation_Rule__mdt ruleRecord : rules) {
                CorrelationMatch match = evaluateRule(eventRecord, ruleRecord);
                if (!match.isMatch) {
                    continue;
                }

                String incidentKey = buildIncidentKey(eventRecord.Actor_Id__c, ruleRecord.DeveloperName);
                Sentry_Incident__c incidentRecord = incidentCache.get(incidentKey);
                if (incidentRecord == null) {
                    incidentRecord = new Sentry_Incident__c(
                        Severity__c = String.isBlank(ruleRecord.Escalation_Severity__c) ? 'High' : ruleRecord.Escalation_Severity__c,
                        Status__c = 'Open',
                        Actor__c = eventRecord.Actor_Id__c,
                        Risk_Score__c = match.maxRiskScore,
                        First_Event__c = match.firstEventId,
                        Last_Event__c = match.lastEventId,
                        Summary__c = 'Correlation match for ' + ruleRecord.MasterLabel,
                        Correlation_Rule__c = ruleRecord.DeveloperName
                    );
                    incidentCache.put(incidentKey, incidentRecord);
                    incidentsToInsert.add(incidentRecord);
                } else {
                    incidentRecord.Severity__c = moreSevereSeverity(incidentRecord.Severity__c, ruleRecord.Escalation_Severity__c);
                    incidentRecord.Status__c = incidentRecord.Status__c == null ? 'Open' : incidentRecord.Status__c;
                    Decimal currentRiskScore = incidentRecord.Risk_Score__c == null ? 0 : incidentRecord.Risk_Score__c;
                    incidentRecord.Risk_Score__c = currentRiskScore > match.maxRiskScore ? currentRiskScore : match.maxRiskScore;
                    incidentRecord.First_Event__c = incidentRecord.First_Event__c == null ? match.firstEventId : incidentRecord.First_Event__c;
                    incidentRecord.Last_Event__c = match.lastEventId;
                    incidentRecord.Summary__c = 'Correlation match for ' + ruleRecord.MasterLabel;
                    if (incidentRecord.Id != null && !incidentsToUpdate.contains(incidentRecord)) {
                        incidentsToUpdate.add(incidentRecord);
                    }
                }

                if (!linkedEventIdsByIncidentKey.containsKey(incidentKey)) {
                    linkedEventIdsByIncidentKey.put(incidentKey, new Set<Id>());
                }
                linkedEventIdsByIncidentKey.get(incidentKey).addAll(match.eventIds);
            }
        }

        insertIncidents(incidentsToInsert);
        updateIncidents(incidentsToUpdate);

        List<Sentry_Incident_Event__c> junctionsToInsert = new List<Sentry_Incident_Event__c>();
        for (String incidentKey : linkedEventIdsByIncidentKey.keySet()) {
            Sentry_Incident__c incidentRecord = incidentCache.get(incidentKey);
            if (incidentRecord == null || incidentRecord.Id == null) {
                continue;
            }
            for (Id eventId : linkedEventIdsByIncidentKey.get(incidentKey)) {
                incidentByEventId.put(eventId, incidentRecord.Id);
                junctionsToInsert.add(new Sentry_Incident_Event__c(
                    Incident__c = incidentRecord.Id,
                    Event__c = eventId
                ));
            }
        }
        insertIncidentEvents(junctionsToInsert);
        return incidentByEventId;
    }

    private class CorrelationMatch {
        Boolean isMatch;
        Decimal maxRiskScore;
        Id firstEventId;
        Id lastEventId;
        Set<Id> eventIds;

        CorrelationMatch() {
            isMatch = false;
            maxRiskScore = 0;
            eventIds = new Set<Id>();
        }
    }

    private static CorrelationMatch evaluateRule(Sentry_Event__c eventRecord, Sentry_Correlation_Rule__mdt ruleRecord) {
        CorrelationMatch match = new CorrelationMatch();
        Set<String> expectedTypes = parsePattern(ruleRecord.Event_Pattern__c);
        if (expectedTypes.isEmpty() || !expectedTypes.contains(eventRecord.Event_Type__c)) {
            return match;
        }

        Integer windowMinutes = ruleRecord.Time_Window_Minutes__c == null ? 60 : Integer.valueOf(ruleRecord.Time_Window_Minutes__c);
        Decimal minimumRisk = ruleRecord.Minimum_Risk__c == null ? 0 : ruleRecord.Minimum_Risk__c;
        Integer minimumEventCount = ruleRecord.Minimum_Event_Count__c == null
            ? expectedTypes.size()
            : Integer.valueOf(ruleRecord.Minimum_Event_Count__c);

        List<Sentry_Event__c> recentEvents = [
            SELECT Id, Event_Type__c, Risk_Score__c, Occurred_At__c
            FROM Sentry_Event__c
            WHERE Actor_Id__c = :eventRecord.Actor_Id__c
            AND Event_Type__c IN :expectedTypes
            AND Risk_Score__c >= :minimumRisk
            AND Occurred_At__c >= :System.now().addMinutes(-windowMinutes)
            WITH SECURITY_ENFORCED
            ORDER BY Occurred_At__c ASC
            LIMIT 200
        ];

        Set<String> observedTypes = new Set<String>();
        for (Sentry_Event__c recentEvent : recentEvents) {
            observedTypes.add(recentEvent.Event_Type__c);
            match.eventIds.add(recentEvent.Id);
            Decimal recentRiskScore = recentEvent.Risk_Score__c == null ? 0 : recentEvent.Risk_Score__c;
            match.maxRiskScore = match.maxRiskScore > recentRiskScore ? match.maxRiskScore : recentRiskScore;
            if (match.firstEventId == null) {
                match.firstEventId = recentEvent.Id;
            }
            match.lastEventId = recentEvent.Id;
        }

        match.isMatch = observedTypes.size() == expectedTypes.size() && match.eventIds.size() >= minimumEventCount;
        return match;
    }

    private static Set<String> parsePattern(String eventPattern) {
        Set<String> values = new Set<String>();
        if (String.isBlank(eventPattern)) {
            return values;
        }
        for (String token : eventPattern.split('[;,\\n]+')) {
            String normalized = token == null ? null : token.trim();
            if (!String.isBlank(normalized)) {
                values.add(normalized);
            }
        }
        return values;
    }

    private static String buildIncidentKey(String actorId, String ruleName) {
        return actorId + '::' + ruleName;
    }

    private static String moreSevereSeverity(String currentSeverity, String newSeverity) {
        if (severityRank(newSeverity) > severityRank(currentSeverity)) {
            return newSeverity;
        }
        return currentSeverity;
    }

    private static Integer severityRank(String severity) {
        if (severity == 'Critical') {
            return 4;
        }
        if (severity == 'High') {
            return 3;
        }
        if (severity == 'Medium') {
            return 2;
        }
        return 1;
    }

    private static void insertIncidents(List<Sentry_Incident__c> incidents) {
        if (incidents.isEmpty() || !Schema.sObjectType.Sentry_Incident__c.isCreateable()) {
            return;
        }
        List<SObject> raw = new List<SObject>();
        raw.addAll(incidents);
        List<SObject> sanitized = Security.stripInaccessible(AccessType.CREATABLE, raw).getRecords();
        Database.insert(sanitized, false);
        for (Integer index = 0; index < incidents.size() && index < sanitized.size(); index++) {
            incidents[index].Id = ((Sentry_Incident__c) sanitized[index]).Id;
        }
    }

    private static void updateIncidents(List<Sentry_Incident__c> incidents) {
        if (incidents.isEmpty() || !Schema.sObjectType.Sentry_Incident__c.isUpdateable()) {
            return;
        }
        List<Sentry_Incident__c> updateableIncidents = new List<Sentry_Incident__c>();
        for (Sentry_Incident__c incidentRecord : incidents) {
            if (incidentRecord.Id != null) {
                updateableIncidents.add(incidentRecord);
            }
        }
        if (updateableIncidents.isEmpty()) {
            return;
        }
        List<SObject> raw = new List<SObject>();
        raw.addAll(updateableIncidents);
        Database.update(Security.stripInaccessible(AccessType.UPDATABLE, raw).getRecords(), false);
    }

    private static void insertIncidentEvents(List<Sentry_Incident_Event__c> junctions) {
        if (junctions.isEmpty() || !Schema.sObjectType.Sentry_Incident_Event__c.isCreateable()) {
            return;
        }
        List<SObject> raw = new List<SObject>();
        raw.addAll(junctions);
        Database.insert(Security.stripInaccessible(AccessType.CREATABLE, raw).getRecords(), false);
    }
}
