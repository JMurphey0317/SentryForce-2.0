public with sharing class SentryAnomalyEnrichmentService {
    public class AnomalyResult {
        @AuraEnabled public Decimal score;
        @AuraEnabled public Decimal riskAdjustment;
        @AuraEnabled public List<String> factors;

        public AnomalyResult() {
            score = 0;
            riskAdjustment = 0;
            factors = new List<String>();
        }
    }

    public static AnomalyResult enrich(SentryEventEnvelope envelope, Integer actorEventsLastHour) {
        AnomalyResult result = new AnomalyResult();
        if (envelope == null) {
            return result;
        }

        Map<String, Object> attrs = envelope.attributes == null ? new Map<String, Object>() : envelope.attributes;

        if (envelope.eventType == 'LoginEvent' && asBoolean(attrs.get('offHours'))) {
            result.score += 25;
            result.factors.add('baseline_login_hours_deviation');
        }

        if ((envelope.eventType == 'APIEvent' || envelope.eventType == 'ApexExecution')
            && actorEventsLastHour != null && actorEventsLastHour >= 20) {
            result.score += 20;
            result.factors.add('baseline_api_volume_spike');
        }

        Integer exportSizeMb = parseInteger(attrs.get('exportSizeMb'));
        if (envelope.eventType == 'ReportExport' && exportSizeMb != null && exportSizeMb >= 500) {
            result.score += 20;
            result.factors.add('baseline_export_size_spike');
        }

        if (asBoolean(attrs.get('countryChange')) || asBoolean(attrs.get('impossibleTravel'))) {
            result.score += 15;
            result.factors.add('baseline_geographic_pattern_change');
        }

        if (result.score > 100) {
            result.score = 100;
        }

        result.riskAdjustment = result.score / 4;
        if (result.riskAdjustment > 25) {
            result.riskAdjustment = 25;
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
        } catch (Exception ex) {
            return null;
        }
    }
}
