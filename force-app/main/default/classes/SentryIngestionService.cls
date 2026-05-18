public with sharing class SentryIngestionService {
    private static final Integer DEFAULT_CHUNK_SIZE = 200;

    @AuraEnabled
    public static void ingestAsync(List<SentryEventEnvelope> envelopes) {
        for (List<SentryEventEnvelope> chunk : chunkEnvelopes(envelopes, DEFAULT_CHUNK_SIZE)) {
            Long enqueuedAtMs = DateTime.now().getTime();
            Id jobId = System.enqueueJob(new SentryIngestionQueueable(JSON.serialize(chunk), enqueuedAtMs));
            SentryTelemetryService.recordQueueEnqueued(chunk.size(), String.valueOf(jobId));
        }
    }

    public static List<Sentry_Event__c> ingest(List<SentryEventEnvelope> envelopes) {
        return ingest(envelopes, null, null);
    }

    public static List<Sentry_Event__c> ingest(List<SentryEventEnvelope> envelopes, String queueJobId, Long enqueuedAtMs) {
        List<Sentry_Event__c> insertedRecords = new List<Sentry_Event__c>();
        for (List<SentryEventEnvelope> chunk : chunkEnvelopes(envelopes, DEFAULT_CHUNK_SIZE)) {
            insertedRecords.addAll(ingestChunk(chunk, queueJobId, enqueuedAtMs));
        }
        return insertedRecords;
    }

    private static List<Sentry_Event__c> ingestChunk(List<SentryEventEnvelope> envelopes, String queueJobId, Long enqueuedAtMs) {
        if (envelopes == null || envelopes.isEmpty()) {
            return new List<Sentry_Event__c>();
        }

        Set<String> actorIds = new Set<String>();
        for (SentryEventEnvelope envelope : envelopes) {
            if (!String.isBlank(envelope.actorId)) {
                actorIds.add(envelope.actorId);
            }
        }

        Map<String, Integer> actorCounts = SentryActorActivityService.getActorCounts(actorIds);
        List<Sentry_Event__c> records = new List<Sentry_Event__c>();
        List<SentryRiskEngine.RiskResult> riskResults = new List<SentryRiskEngine.RiskResult>();

        for (SentryEventEnvelope envelope : envelopes) {
            Integer actorEventsLastHour = actorCounts.containsKey(envelope.actorId) ? actorCounts.get(envelope.actorId) : 0;
            SentryRiskEngine.RiskResult risk = SentryRiskEngine.evaluate(envelope, actorCounts);
            SentryAnomalyEnrichmentService.AnomalyResult anomaly = SentryAnomalyEnrichmentService.enrich(envelope, actorEventsLastHour);
            risk.applyAnomaly(anomaly);
            SentryDetectionRuleService.applyRules(envelope, risk);
            risk.finalizeSeverity();

            Date retentionDate = SentryRetentionService.resolveRetentionDate(envelope.eventType);
            records.add(new Sentry_Event__c(
                Event_Source__c = envelope.source,
                Event_Type__c = envelope.eventType,
                Occurred_At__c = envelope.occurredAt == null ? System.now() : envelope.occurredAt,
                Actor_Id__c = envelope.actorId,
                Risk_Score__c = risk.score,
                Risk_Factors__c = String.join(risk.factors, ';'),
                Payload__c = envelope.payloadAsJson(),
                Retention_Until__c = retentionDate,
                Compliance_Archived__c = false,
                Anomaly_Score__c = anomaly.score,
                Anomaly_Factors__c = String.join(anomaly.factors, ';'),
                Processing_Latency_Ms__c = enqueuedAtMs == null ? null : (System.now().getTime() - enqueuedAtMs)
            ));
            riskResults.add(risk);
        }

        if (!Schema.sObjectType.Sentry_Event__c.isCreateable()) {
            return new List<Sentry_Event__c>();
        }

        List<SObject> raw = new List<SObject>();
        raw.addAll(records);
        List<SObject> sanitizedRaw = Security.stripInaccessible(AccessType.CREATABLE, raw).getRecords();
        List<Sentry_Event__c> sanitizedRecords = new List<Sentry_Event__c>();
        for (SObject recordItem : sanitizedRaw) {
            sanitizedRecords.add((Sentry_Event__c) recordItem);
        }
        insert sanitizedRecords;

        Map<Id, Id> incidentByEventId = SentryCorrelationService.correlate(sanitizedRecords);
        SentryAlertingService.createAlerts(sanitizedRecords, riskResults, envelopes, incidentByEventId);
        if (!String.isBlank(queueJobId) && enqueuedAtMs != null) {
            SentryTelemetryService.recordQueueCompleted(
                envelopes.size(),
                queueJobId,
                System.now().getTime() - enqueuedAtMs
            );
        }
        return sanitizedRecords;
    }

    @TestVisible
    private static List<List<SentryEventEnvelope>> chunkEnvelopes(List<SentryEventEnvelope> envelopes, Integer chunkSize) {
        List<List<SentryEventEnvelope>> chunks = new List<List<SentryEventEnvelope>>();
        if (envelopes == null || envelopes.isEmpty()) {
            return chunks;
        }

        Integer effectiveChunkSize = chunkSize == null || chunkSize <= 0 ? DEFAULT_CHUNK_SIZE : chunkSize;
        if (effectiveChunkSize > DEFAULT_CHUNK_SIZE) {
            effectiveChunkSize = DEFAULT_CHUNK_SIZE;
        }
        for (Integer startIndex = 0; startIndex < envelopes.size(); startIndex += effectiveChunkSize) {
            Integer endIndex = Math.min(startIndex + effectiveChunkSize, envelopes.size());
            chunks.add(envelopes.subList(startIndex, endIndex));
        }
        return chunks;
    }
}
