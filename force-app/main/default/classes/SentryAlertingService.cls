public with sharing class SentryAlertingService {
    public static void createAlert(Sentry_Event__c eventRecord, SentryRiskEngine.RiskResult riskResult) {
        createAlerts(
            new List<Sentry_Event__c>{ eventRecord },
            new List<SentryRiskEngine.RiskResult>{ riskResult },
            new List<SentryEventEnvelope>{ new SentryEventEnvelope() },
            new Map<Id, Id>()
        );
    }

    public static void createAlerts(
        List<Sentry_Event__c> eventRecords,
        List<SentryRiskEngine.RiskResult> riskResults,
        List<SentryEventEnvelope> envelopes,
        Map<Id, Id> incidentByEventId
    ) {
        if (eventRecords == null || eventRecords.isEmpty() || !Schema.sObjectType.Sentry_Alert__c.isCreateable()) {
            return;
        }

        List<Sentry_Alert__c> alertsToInsert = new List<Sentry_Alert__c>();
        for (Integer index = 0; index < eventRecords.size(); index++) {
            SentryRiskEngine.RiskResult riskResult = riskResults[index];
            if (riskResult == null || !riskResult.isAnomalous()) {
                continue;
            }

            SentryEventEnvelope envelope = envelopes != null && envelopes.size() > index ? envelopes[index] : new SentryEventEnvelope();
            SentryAlertSuppressionService.SuppressionDecision suppressionDecision = SentryAlertSuppressionService.evaluate(envelope, riskResult);
            Boolean suppressed = suppressionDecision != null && suppressionDecision.suppress;

            alertsToInsert.add(new Sentry_Alert__c(
                Severity__c = riskResult.severity,
                Status__c = suppressed ? 'Resolved' : 'Open',
                Channel__c = 'Salesforce',
                Message__c = 'Anomalous ' + eventRecords[index].Event_Type__c + ' detected. Score=' + String.valueOf(riskResult.score),
                Event__c = eventRecords[index].Id,
                Suppressed__c = suppressed,
                Suppression_Key__c = suppressionDecision == null ? null : suppressionDecision.suppressionKey,
                Incident__c = incidentByEventId != null && incidentByEventId.containsKey(eventRecords[index].Id)
                    ? incidentByEventId.get(eventRecords[index].Id)
                    : null
            ));
        }

        if (alertsToInsert.isEmpty()) {
            return;
        }

        List<SObject> raw = new List<SObject>();
        raw.addAll(alertsToInsert);
        List<SObject> sanitized = Security.stripInaccessible(AccessType.CREATABLE, raw).getRecords();
        insert sanitized;

        List<Sentry_Alert__c> notifyableAlerts = new List<Sentry_Alert__c>();
        List<Id> notifyAlertIds = new List<Id>();
        for (SObject sanitizedRecord : sanitized) {
            Sentry_Alert__c alertRecord = (Sentry_Alert__c) sanitizedRecord;
            if (!alertRecord.Suppressed__c) {
                notifyableAlerts.add(alertRecord);
                notifyAlertIds.add(alertRecord.Id);
            }
        }
        if (!notifyAlertIds.isEmpty()) {
            notifySlackAsync(notifyAlertIds);
            SentryOutboundConnectorService.dispatchAlerts(notifyableAlerts);
        }
    }

    @future(callout=true)
    private static void notifySlackAsync(List<Id> alertIds) {
        if (alertIds == null || alertIds.isEmpty()) {
            return;
        }

        List<Sentry_Integration_Config__mdt> configs = [
            SELECT DeveloperName, Channel__c, Endpoint__c, Enabled__c, Integration_Type__c,
                Named_Credential__c, External_Credential__c, Path_Suffix__c
            FROM Sentry_Integration_Config__mdt
            WHERE Enabled__c = true
            AND (Channel__c = 'Slack' OR Integration_Type__c = 'Slack')
            ORDER BY DeveloperName ASC
            LIMIT 1
        ];
        if (configs.isEmpty()) {
            return;
        }

        Map<Id, Sentry_Alert__c> alertsById = new Map<Id, Sentry_Alert__c>([
            SELECT Id, Severity__c, Status__c, Message__c,
                Event__r.Event_Type__c, Event__r.Risk_Score__c, Event__r.Risk_Factors__c
            FROM Sentry_Alert__c
            WHERE Id IN :alertIds
            WITH SECURITY_ENFORCED
        ]);
        if (alertsById.isEmpty()) {
            return;
        }

        Http http = new Http();
        for (Id alertId : alertsById.keySet()) {
            Sentry_Alert__c alertRecord = alertsById.get(alertId);
            HttpRequest request = new HttpRequest();
            request.setMethod('POST');
            request.setEndpoint(SentryNamedCredentialService.resolveEndpoint(configs[0]));
            request.setHeader('Content-Type', 'application/json');
            request.setBody(JSON.serialize(new Map<String, Object>{
                'text' => 'SentryForce Alert: ' + alertRecord.Message__c,
                'eventType' => alertRecord.Event__r.Event_Type__c,
                'riskScore' => alertRecord.Event__r.Risk_Score__c,
                'factors' => String.isBlank(alertRecord.Event__r.Risk_Factors__c)
                    ? new List<String>()
                    : alertRecord.Event__r.Risk_Factors__c.split(';')
            }));
            try {
                http.send(request);
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'Slack notification failed: ' + ex.getMessage());
            }
        }
    }
}
