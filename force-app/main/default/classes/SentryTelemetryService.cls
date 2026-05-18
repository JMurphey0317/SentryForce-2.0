public with sharing class SentryTelemetryService {
    public static void recordQueueEnqueued(Integer envelopeCount, String jobId) {
        recordMetric('Enqueue', 'Queued', envelopeCount, null, jobId, null);
    }

    public static void recordQueueCompleted(Integer envelopeCount, String jobId, Long processingLatencyMs) {
        recordMetric('Completed', 'Succeeded', envelopeCount, processingLatencyMs, jobId, null);
    }

    public static void recordQueueFailure(Integer envelopeCount, String jobId, Long processingLatencyMs, Exception failure) {
        recordMetric(
            'Failed',
            'Failed',
            envelopeCount,
            processingLatencyMs,
            jobId,
            failure == null ? null : failure.getMessage()
        );
    }

    public static List<Sentry_Queue_Telemetry__c> getRecentTelemetry(Integer limitSize) {
        Integer effectiveLimit = limitSize == null || limitSize <= 0 ? 10 : limitSize;
        if (effectiveLimit > 50) {
            effectiveLimit = 50;
        }
        return [
            SELECT Id, Name, Metric_Type__c, Status__c, Queue_Name__c, Queue_Depth__c,
                Envelope_Count__c, Processing_Latency_Ms__c, Failed_Jobs__c, Job_Id__c,
                Failure_Message__c, Recorded_At__c
            FROM Sentry_Queue_Telemetry__c
            WITH SECURITY_ENFORCED
            ORDER BY Recorded_At__c DESC
            LIMIT :effectiveLimit
        ];
    }

    private static void recordMetric(
        String metricType,
        String status,
        Integer envelopeCount,
        Long processingLatencyMs,
        String jobId,
        String failureMessage
    ) {
        if (!Schema.sObjectType.Sentry_Queue_Telemetry__c.isCreateable()) {
            return;
        }

        Integer queueDepth = resolveQueueDepth();
        Sentry_Queue_Telemetry__c metric = new Sentry_Queue_Telemetry__c(
            Metric_Type__c = metricType,
            Status__c = status,
            Queue_Name__c = 'SentryIngestionQueueable',
            Queue_Depth__c = queueDepth,
            Envelope_Count__c = envelopeCount,
            Processing_Latency_Ms__c = processingLatencyMs,
            Failed_Jobs__c = metricType == 'Failed' ? 1 : 0,
            Job_Id__c = jobId,
            Failure_Message__c = failureMessage,
            Recorded_At__c = System.now()
        );

        List<SObject> raw = new List<SObject>{ metric };
        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, raw);
        Database.insert(decision.getRecords(), false);
    }

    @TestVisible
    private static Integer resolveQueueDepth() {
        try {
            return [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'Queueable'
                AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
            ];
        } catch (Exception ex) {
            return 0;
        }
    }
}
