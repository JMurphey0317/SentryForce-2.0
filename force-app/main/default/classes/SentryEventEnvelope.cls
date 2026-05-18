public class SentryEventEnvelope {
    @AuraEnabled public String source;
    @AuraEnabled public String eventType;
    @AuraEnabled public Datetime occurredAt;
    @AuraEnabled public String actorId;
    @AuraEnabled public Map<String, Object> attributes;

    public SentryEventEnvelope() {
        this.attributes = new Map<String, Object>();
    }

    public String payloadAsJson() {
        return JSON.serialize(attributes);
    }
}
