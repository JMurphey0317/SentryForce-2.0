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
            envelope.occurredAt = parseDatetime(item.get('occurredAt'));
            envelope.attributes = item.containsKey('attributes') && item.get('attributes') != null
                ? (Map<String, Object>) item.get('attributes')
                : new Map<String, Object>();
            envelopes.add(envelope);
        }

        SentryIngestionService.ingest(envelopes);
    }

    @TestVisible
    private static Datetime parseDatetime(Object inputValue) {
        if (inputValue == null) {
            return System.now();
        }

        if (inputValue instanceof Datetime) {
            return (Datetime) inputValue;
        }

        String value = String.valueOf(inputValue);
        Pattern allowedIsoPattern = Pattern.compile('^[0-9TtZz:+\\-.]+$');
        if (!allowedIsoPattern.matcher(value).matches()) {
            return System.now();
        }

        try {
            return (Datetime) JSON.deserialize('"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"', Datetime.class);
        } catch (Exception e) {
            return System.now();
        }
    }
}
