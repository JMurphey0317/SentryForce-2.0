public with sharing class SentryIngestionQueueable implements Queueable {
    private String serializedEnvelopes;
    private Long enqueuedAtMs;

    public SentryIngestionQueueable(String serializedEnvelopes, Long enqueuedAtMs) {
        this.serializedEnvelopes = serializedEnvelopes;
        this.enqueuedAtMs = enqueuedAtMs;
    }

    public void execute(QueueableContext context) {
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(serializedEnvelopes);
        List<SentryEventEnvelope> envelopes = new List<SentryEventEnvelope>();

        for (Object entry : raw) {
            Map<String, Object> item = (Map<String, Object>) entry;
            SentryEventEnvelope envelope = new SentryEventEnvelope();
            envelope.source = (String) item.get('source');
            envelope.eventType = (String) item.get('eventType');
            envelope.actorId = (String) item.get('actorId');
            envelope.occurredAt = item.containsKey('occurredAt') && item.get('occurredAt') != null
                ? Datetime.valueOfGmt(String.valueOf(item.get('occurredAt')).replace('T', ' ').replace('Z', ''))
                : System.now();
            envelope.attributes = item.containsKey('attributes') && item.get('attributes') != null
                ? (Map<String, Object>) item.get('attributes')
                : new Map<String, Object>();
            envelopes.add(envelope);
        }

        try {
            SentryIngestionService.ingest(envelopes, context.getJobId(), enqueuedAtMs);
        } catch (Exception ex) {
            SentryTelemetryService.recordQueueFailure(
                envelopes.size(),
                context.getJobId(),
                enqueuedAtMs == null ? null : (System.now().getTime() - enqueuedAtMs),
                ex
            );
            throw ex;
        }
    }
}
