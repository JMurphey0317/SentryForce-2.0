public with sharing class SentryAlertSuppressionService {
    public class SuppressionDecision {
        @AuraEnabled public Boolean suppress;
        @AuraEnabled public String suppressionKey;
        @AuraEnabled public String reason;

        public SuppressionDecision() {
            suppress = false;
        }
    }

    public static SuppressionDecision evaluate(SentryEventEnvelope envelope, SentryRiskEngine.RiskResult riskResult) {
        SuppressionDecision decision = new SuppressionDecision();
        if (envelope == null || riskResult == null) {
            return decision;
        }
        Map<String, Object> attributes = envelope.attributes == null ? new Map<String, Object>() : envelope.attributes;

        String severity = riskResult.severity;
        String suppressionKey = buildSuppressionKey(envelope, severity);
        decision.suppressionKey = suppressionKey;

        for (Sentry_Suppression_Rule__mdt ruleRecord : getRules()) {
            if (!ruleRecord.Enabled__c) {
                continue;
            }

            if (ruleRecord.Rule_Type__c == 'DuplicateWindow'
                && suppressDuplicateAlert(suppressionKey, ruleRecord.Window_Minutes__c)) {
                decision.suppress = true;
                decision.reason = 'Duplicate alert inside suppression window';
                return decision;
            }

            if (ruleRecord.Rule_Type__c == 'IntegrationUser'
                && matchesIntegrationUser(envelope.actorId, ruleRecord.Match_Value__c)) {
                decision.suppress = true;
                decision.reason = 'Integration user suppression';
                return decision;
            }

            if (ruleRecord.Rule_Type__c == 'LowRiskSandbox'
                && asBoolean(attributes.get('sandbox'))
                && riskResult.score < normalizeDecimal(ruleRecord.Minimum_Risk__c, 40)) {
                decision.suppress = true;
                decision.reason = 'Low-risk sandbox suppression';
                return decision;
            }
        }
        return decision;
    }

    @TestVisible
    private static String buildSuppressionKey(SentryEventEnvelope envelope, String severity) {
        return String.join(new List<String>{
            String.isBlank(envelope.actorId) ? 'unknown' : envelope.actorId,
            String.isBlank(envelope.eventType) ? 'event' : envelope.eventType,
            String.isBlank(severity) ? 'Medium' : severity
        }, ':');
    }

    @TestVisible
    private static List<Sentry_Suppression_Rule__mdt> getRules() {
        return [
            SELECT DeveloperName, Rule_Name__c, Rule_Type__c, Window_Minutes__c,
                Match_Value__c, Minimum_Risk__c, Enabled__c
            FROM Sentry_Suppression_Rule__mdt
            WHERE Enabled__c = true
            ORDER BY DeveloperName ASC
        ];
    }

    private static Boolean suppressDuplicateAlert(String suppressionKey, Decimal windowMinutes) {
        Integer effectiveWindow = Integer.valueOf(normalizeDecimal(windowMinutes, 30));
        return [
            SELECT COUNT()
            FROM Sentry_Alert__c
            WHERE Suppression_Key__c = :suppressionKey
            AND CreatedDate >= :System.now().addMinutes(-effectiveWindow)
            WITH SECURITY_ENFORCED
        ] > 0;
    }

    private static Boolean matchesIntegrationUser(String actorId, String matchValue) {
        if (String.isBlank(actorId)) {
            return false;
        }
        String normalizedActor = actorId.toLowerCase();
        String normalizedMatch = String.isBlank(matchValue) ? 'integration' : matchValue.toLowerCase();
        return normalizedActor.contains(normalizedMatch);
    }

    private static Decimal normalizeDecimal(Decimal value, Decimal fallbackValue) {
        return value == null ? fallbackValue : value;
    }

    private static Boolean asBoolean(Object value) {
        if (value == null) {
            return false;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return String.valueOf(value).toLowerCase() == 'true';
    }
}
