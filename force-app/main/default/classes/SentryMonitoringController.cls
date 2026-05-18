public with sharing class SentryMonitoringController {
    public class DashboardData {
        @AuraEnabled public List<Sentry_Event__c> recentEvents;
        @AuraEnabled public List<Sentry_Alert__c> recentAlerts;
        @AuraEnabled public List<Sentry_Retrieval_Job__c> retrievalJobs;
        @AuraEnabled public List<Sentry_Incident__c> recentIncidents;
        @AuraEnabled public List<Sentry_Queue_Telemetry__c> queueTelemetry;
        @AuraEnabled public List<Sentry_Connector_Delivery__c> connectorDeliveries;
        @AuraEnabled public List<SentryAnalyticsService.MetricCard> metrics;
        @AuraEnabled public List<SentryAnalyticsService.TrendPoint> timeline;
        @AuraEnabled public List<SentryAnalyticsService.HeatmapCell> heatmap;
        @AuraEnabled public List<SentryFeatureLicenseService.FeatureStatus> featureLicenses;
        @AuraEnabled public List<SentryDetectionRuleService.DetectionRuleSummary> detectionRules;

        public DashboardData() {
            recentEvents = new List<Sentry_Event__c>();
            recentAlerts = new List<Sentry_Alert__c>();
            retrievalJobs = new List<Sentry_Retrieval_Job__c>();
            recentIncidents = new List<Sentry_Incident__c>();
            queueTelemetry = new List<Sentry_Queue_Telemetry__c>();
            connectorDeliveries = new List<Sentry_Connector_Delivery__c>();
            metrics = new List<SentryAnalyticsService.MetricCard>();
            timeline = new List<SentryAnalyticsService.TrendPoint>();
            heatmap = new List<SentryAnalyticsService.HeatmapCell>();
            featureLicenses = new List<SentryFeatureLicenseService.FeatureStatus>();
            detectionRules = new List<SentryDetectionRuleService.DetectionRuleSummary>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        DashboardData data = new DashboardData();
        data.recentEvents = [
            SELECT Id, Name, Event_Source__c, Event_Type__c, Occurred_At__c, Actor_Id__c,
                Risk_Score__c, Risk_Factors__c, Anomaly_Score__c, Anomaly_Factors__c
            FROM Sentry_Event__c
            WITH SECURITY_ENFORCED
            ORDER BY Occurred_At__c DESC
            LIMIT 25
        ];
        data.recentAlerts = [
            SELECT Id, Name, Severity__c, Status__c, Channel__c, Message__c, Event__c,
                Suppressed__c, Incident__c
            FROM Sentry_Alert__c
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 25
        ];
        data.retrievalJobs = [
            SELECT Id, Name, Source__c, Status__c, Started_At__c, Completed_At__c, Result_Summary__c
            FROM Sentry_Retrieval_Job__c
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];
        data.recentIncidents = [
            SELECT Id, Name, Severity__c, Status__c, Actor__c, Risk_Score__c,
                First_Event__c, Last_Event__c, Summary__c, Correlation_Rule__c
            FROM Sentry_Incident__c
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 25
        ];
        data.queueTelemetry = SentryTelemetryService.getRecentTelemetry(10);
        data.connectorDeliveries = [
            SELECT Id, Name, Connector__c, Status__c, Retry_Count__c, Last_Attempt_At__c, Health_Status__c
            FROM Sentry_Connector_Delivery__c
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];
        data.metrics = SentryAnalyticsService.getMetricCards();
        data.timeline = SentryAnalyticsService.getTimeline();
        data.heatmap = SentryAnalyticsService.getThreatHeatmap();
        data.featureLicenses = SentryFeatureLicenseService.getFeatureStatuses();
        data.detectionRules = SentryDetectionRuleService.getActiveRuleSummaries();
        return data;
    }

    @AuraEnabled
    public static void runElfRetrieval() {
        SentryElfRetrievalService.startJobForRecentLogs();
    }

    @AuraEnabled
    public static Id startReplay(Datetime startDate, Datetime endDate, String ruleName, Integer batchSize) {
        return SentryReplayService.startReplay(startDate, endDate, ruleName, batchSize);
    }

    @AuraEnabled(cacheable=true)
    public static SentryRiskEngine.RiskResult simulateDetection(String source, String eventType, String actorId, String attributesJson) {
        SentryEventEnvelope envelope = new SentryEventEnvelope();
        envelope.source = source;
        envelope.eventType = eventType;
        envelope.actorId = actorId;
        envelope.occurredAt = System.now();
        envelope.attributes = String.isBlank(attributesJson)
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(attributesJson);

        Map<String, Integer> actorCounts = String.isBlank(actorId)
            ? new Map<String, Integer>()
            : SentryActorActivityService.getActorCounts(new Set<String>{ actorId });
        Integer actorCount = actorCounts.containsKey(actorId) ? actorCounts.get(actorId) : 0;
        SentryRiskEngine.RiskResult risk = SentryRiskEngine.evaluate(envelope, actorCounts);
        risk.applyAnomaly(SentryAnomalyEnrichmentService.enrich(envelope, actorCount));
        SentryDetectionRuleService.applyRules(envelope, risk);
        risk.finalizeSeverity();
        return risk;
    }

    @AuraEnabled
    public static void updateAlertStatus(Id alertId, String statusValue, String assignedAnalyst) {
        if (!Schema.sObjectType.Sentry_Alert__c.isUpdateable()) {
            return;
        }
        Sentry_Alert__c updateRecord = new Sentry_Alert__c(
            Id = alertId,
            Status__c = statusValue,
            Assigned_Analyst__c = assignedAnalyst
        );
        List<SObject> raw = new List<SObject>{ updateRecord };
        Database.update(Security.stripInaccessible(AccessType.UPDATABLE, raw).getRecords(), false);
    }
}
