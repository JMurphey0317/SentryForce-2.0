public with sharing class SentryRiskEngine {
    public class RiskResult {
        @AuraEnabled public Decimal score;
        @AuraEnabled public List<String> factors;
        @AuraEnabled public String severity;
        @AuraEnabled public Decimal anomalyScore;

        public RiskResult() {
            this.score = 0;
            this.factors = new List<String>();
            this.severity = 'Low';
            this.anomalyScore = 0;
        }

        public Boolean isAnomalous() {
            return score >= 70 || severity == 'High' || severity == 'Critical';
        }

        public void applyAdjustment(Decimal adjustment, String factor, String requestedSeverity) {
            if (adjustment != null) {
                score += adjustment;
            }
            if (!String.isBlank(factor) && !factors.contains(factor)) {
                factors.add(factor);
            }
            if (!String.isBlank(requestedSeverity) && severityRank(requestedSeverity) > severityRank(severity)) {
                severity = requestedSeverity;
            }
            finalizeSeverity();
        }

        public void applyAnomaly(SentryAnomalyEnrichmentService.AnomalyResult anomaly) {
            if (anomaly == null) {
                return;
            }
            anomalyScore = anomaly.score;
            for (String factor : anomaly.factors) {
                if (!factors.contains(factor)) {
                    factors.add(factor);
                }
            }
            if (anomaly.riskAdjustment != null) {
                score += anomaly.riskAdjustment;
            }
            finalizeSeverity();
        }

        public void finalizeSeverity() {
            if (score > 100) {
                score = 100;
            }
            if (severityRank(severity) < severityRank(deriveSeverity(score))) {
                severity = deriveSeverity(score);
            }
        }
    }

    public static RiskResult evaluate(SentryEventEnvelope eventEnvelope, Map<String, Integer> actorCounts) {
        Integer actorEventsLastHour = actorCounts == null || String.isBlank(eventEnvelope.actorId) || !actorCounts.containsKey(eventEnvelope.actorId)
            ? 0
            : actorCounts.get(eventEnvelope.actorId);
        return evaluate(eventEnvelope, actorEventsLastHour);
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

        result.finalizeSeverity();
        return result;
    }

    @TestVisible
    private static String deriveSeverity(Decimal score) {
        Decimal normalizedScore = score == null ? 0 : score;
        if (normalizedScore >= 90) {
            return 'Critical';
        }
        if (normalizedScore >= 70) {
            return 'High';
        }
        if (normalizedScore >= 40) {
            return 'Medium';
        }
        return 'Low';
    }

    @TestVisible
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
