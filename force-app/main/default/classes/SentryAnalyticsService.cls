public with sharing class SentryAnalyticsService {
    public class MetricCard {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String helperText;
    }

    public class TrendPoint {
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
    }

    public class HeatmapCell {
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
    }

    public static List<MetricCard> getMetricCards() {
        List<MetricCard> cards = new List<MetricCard>();
        cards.add(buildCard('Open incidents', String.valueOf([
            SELECT COUNT()
            FROM Sentry_Incident__c
            WHERE Status__c != 'Resolved'
            WITH SECURITY_ENFORCED
        ]), 'Correlation and analyst queue'));
        cards.add(buildCard('Open alerts', String.valueOf([
            SELECT COUNT()
            FROM Sentry_Alert__c
            WHERE Status__c != 'Resolved'
            WITH SECURITY_ENFORCED
        ]), 'Suppression-aware alert backlog'));

        Decimal avgRisk = 0;
        List<Sentry_Event__c> recentEvents = [
            SELECT Risk_Score__c
            FROM Sentry_Event__c
            WHERE Occurred_At__c >= :System.now().addDays(-1)
            WITH SECURITY_ENFORCED
            LIMIT 200
        ];
        if (!recentEvents.isEmpty()) {
            Decimal totalRisk = 0;
            for (Sentry_Event__c eventRecord : recentEvents) {
                totalRisk += eventRecord.Risk_Score__c == null ? 0 : eventRecord.Risk_Score__c;
            }
            avgRisk = totalRisk / recentEvents.size();
        }
        cards.add(buildCard('Avg risk (24h)', String.valueOf(avgRisk.setScale(2)), 'Detection + anomaly enriched'));

        Long latestLatency = 0;
        List<Sentry_Queue_Telemetry__c> recentTelemetry = [
            SELECT Processing_Latency_Ms__c
            FROM Sentry_Queue_Telemetry__c
            WITH SECURITY_ENFORCED
            ORDER BY Recorded_At__c DESC
            LIMIT 1
        ];
        if (!recentTelemetry.isEmpty() && recentTelemetry[0].Processing_Latency_Ms__c != null) {
            latestLatency = recentTelemetry[0].Processing_Latency_Ms__c.longValue();
        }
        cards.add(buildCard('Queue latency', String.valueOf(latestLatency) + ' ms', 'SentryForce self-observability'));
        return cards;
    }

    public static List<TrendPoint> getTimeline() {
        Map<String, Integer> countsByDay = new Map<String, Integer>();
        for (Integer i = 6; i >= 0; i--) {
            countsByDay.put(String.valueOf(Date.today().addDays(-i)), 0);
        }

        for (Sentry_Event__c eventRecord : [
            SELECT Occurred_At__c
            FROM Sentry_Event__c
            WHERE Occurred_At__c >= :System.now().addDays(-7)
            WITH SECURITY_ENFORCED
            ORDER BY Occurred_At__c DESC
            LIMIT 500
        ]) {
            String key = String.valueOf(eventRecord.Occurred_At__c.date());
            countsByDay.put(key, (countsByDay.containsKey(key) ? countsByDay.get(key) : 0) + 1);
        }

        List<TrendPoint> points = new List<TrendPoint>();
        for (String key : countsByDay.keySet()) {
            TrendPoint point = new TrendPoint();
            point.label = key;
            point.value = countsByDay.get(key);
            points.add(point);
        }
        return points;
    }

    public static List<HeatmapCell> getThreatHeatmap() {
        Map<String, Integer> countsByActor = new Map<String, Integer>();
        for (Sentry_Event__c eventRecord : [
            SELECT Actor_Id__c
            FROM Sentry_Event__c
            WHERE Occurred_At__c >= :System.now().addHours(-12)
            WITH SECURITY_ENFORCED
            ORDER BY Occurred_At__c DESC
            LIMIT 200
        ]) {
            String label = String.isBlank(eventRecord.Actor_Id__c) ? 'Unknown actor' : eventRecord.Actor_Id__c;
            countsByActor.put(label, (countsByActor.containsKey(label) ? countsByActor.get(label) : 0) + 1);
        }

        List<HeatmapCell> cells = new List<HeatmapCell>();
        for (String actorId : countsByActor.keySet()) {
            HeatmapCell cell = new HeatmapCell();
            cell.label = actorId;
            cell.value = countsByActor.get(actorId);
            cells.add(cell);
        }
        return cells.size() > 12 ? cells.subList(0, 12) : cells;
    }

    private static MetricCard buildCard(String label, String value, String helperText) {
        MetricCard card = new MetricCard();
        card.label = label;
        card.value = value;
        card.helperText = helperText;
        return card;
    }
}
