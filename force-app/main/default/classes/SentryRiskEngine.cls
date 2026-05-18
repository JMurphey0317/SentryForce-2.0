public with sharing class SentryRiskEngine {
    public class RiskResult {
        @AuraEnabled public Decimal score;
        @AuraEnabled public List<String> factors;

        public RiskResult() {
            this.score = 0;
            this.factors = new List<String>();
        }

        public Boolean isAnomalous() {
            return score >= 70;
        }
    }

    public static RiskResult evaluate(SentryEventEnvelope eventEnvelope, Integer actorEventsLastHour) {
        RiskResult result = new RiskResult();
        Map<String, Object> attrs = eventEnvelope.attributes == null ? new Map<String, Object>() : eventEnvelope.attributes;

        if (eventEnvelope.eventType == 'LoginEvent' && actorEventsLastHour != null && actorEventsLastHour >= 8) {
            result.score += 45;
            result.factors.add('credential_stuffing_pattern');
        }

        if (eventEnvelope.eventType == 'SessionHijacking' || asBoolean(attrs.get('impossibleTravel'))) {
            result.score += 40;
            result.factors.add('session_hijacking_signal');
        }

        if (eventEnvelope.eventType == 'ReportExport' && asBoolean(attrs.get('bulkDownload'))) {
            result.score += 30;
            result.factors.add('suspicious_report_export');
        }

        if (asBoolean(attrs.get('offHours')) && asBoolean(attrs.get('sensitiveAction'))) {
            result.score += 25;
            result.factors.add('off_hours_sensitive_action');
        }

        if (eventEnvelope.eventType == 'LightningPageView' && attrs.containsKey('loadTimeMs')) {
            Integer loadTimeMs = parseInteger(attrs.get('loadTimeMs'));
            if (loadTimeMs != null && loadTimeMs >= 8000) {
                result.score += 20;
                result.factors.add('lightning_performance_degradation');
            }
        }

        if (eventEnvelope.eventType == 'ApexExecution' && attrs.containsKey('durationMs')) {
            Integer durationMs = parseInteger(attrs.get('durationMs'));
            if (durationMs != null && durationMs >= 10000) {
                result.score += 20;
                result.factors.add('long_running_apex');
            }
            if (asBoolean(attrs.get('exceptionRaised'))) {
                result.score += 20;
                result.factors.add('unexpected_apex_exception');
            }
        }

        if (result.score > 100) {
            result.score = 100;
        }

        return result;
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

    private static Integer parseInteger(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return Integer.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }
}
