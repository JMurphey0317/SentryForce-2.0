public with sharing class SentryDetectionRuleService {
    public class DetectionRuleSummary {
        @AuraEnabled public String developerName;
        @AuraEnabled public String ruleName;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String filterJson;
        @AuraEnabled public Decimal riskAdjustment;
        @AuraEnabled public Boolean enabled;
        @AuraEnabled public String alertSeverity;
    }

    public static List<DetectionRuleSummary> getActiveRuleSummaries() {
        List<DetectionRuleSummary> summaries = new List<DetectionRuleSummary>();
        for (Sentry_Detection_Rule__mdt ruleRecord : getRules()) {
            DetectionRuleSummary summary = new DetectionRuleSummary();
            summary.developerName = ruleRecord.DeveloperName;
            summary.ruleName = ruleRecord.Rule_Name__c;
            summary.sourceType = ruleRecord.Source_Type__c;
            summary.filterJson = ruleRecord.Filter_JSON__c;
            summary.riskAdjustment = ruleRecord.Risk_Adjustment__c;
            summary.enabled = ruleRecord.Enabled__c;
            summary.alertSeverity = ruleRecord.Alert_Severity__c;
            summaries.add(summary);
        }
        return summaries;
    }

    public static void applyRules(SentryEventEnvelope envelope, SentryRiskEngine.RiskResult riskResult) {
        if (envelope == null || riskResult == null) {
            return;
        }

        for (Sentry_Detection_Rule__mdt ruleRecord : getRules()) {
            if (!ruleRecord.Enabled__c) {
                continue;
            }
            if (!String.isBlank(ruleRecord.Source_Type__c)
                && ruleRecord.Source_Type__c != envelope.source
                && ruleRecord.Source_Type__c != envelope.eventType) {
                continue;
            }
            if (!matchesFilter(ruleRecord.Filter_JSON__c, envelope.attributes)) {
                continue;
            }

            String ruleLabel = String.isBlank(ruleRecord.Rule_Name__c)
                ? ruleRecord.DeveloperName
                : ruleRecord.Rule_Name__c;
            riskResult.applyAdjustment(
                ruleRecord.Risk_Adjustment__c,
                'detection_rule:' + ruleLabel,
                ruleRecord.Alert_Severity__c
            );
        }
    }

    @TestVisible
    private static List<Sentry_Detection_Rule__mdt> getRules() {
        return [
            SELECT DeveloperName, Rule_Name__c, Source_Type__c, Filter_JSON__c,
                Risk_Adjustment__c, Enabled__c, Alert_Severity__c
            FROM Sentry_Detection_Rule__mdt
            WHERE Enabled__c = true
            ORDER BY DeveloperName ASC
        ];
    }

    @TestVisible
    private static Boolean matchesFilter(String filterJson, Map<String, Object> attributes) {
        if (String.isBlank(filterJson)) {
            return true;
        }

        Map<String, Object> safeAttributes = attributes == null ? new Map<String, Object>() : attributes;
        try {
            Object rawFilter = JSON.deserializeUntyped(filterJson);
            Map<String, Object> filterMap = (Map<String, Object>) rawFilter;
            for (String key : filterMap.keySet()) {
                if (!safeAttributes.containsKey(key)) {
                    return false;
                }
                if (String.valueOf(safeAttributes.get(key)) != String.valueOf(filterMap.get(key))) {
                    return false;
                }
            }
            return true;
        } catch (Exception ex) {
            return JSON.serialize(safeAttributes).contains(filterJson);
        }
    }
}
