public with sharing class SentryIngestionQueueable implements Queueable {
    private String serializedEnvelopes;

    public SentryIngestionQueueable(String serializedEnvelopes) {
        this.serializedEnvelopes = serializedEnvelopes;
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

        SentryIngestionService.ingest(envelopes);
    }
}
