@IsTest
private class SentryIngestionServiceTest {
    @IsTest
    static void ingestsAndCreatesAlertForAnomalousEvent() {
        SentryEventEnvelope envelope = new SentryEventEnvelope();
        envelope.source = 'EventMonitoring';
        envelope.eventType = 'LoginEvent';
        envelope.actorId = '005000000000001';
        envelope.occurredAt = System.now();
        envelope.attributes.put('offHours', true);
        envelope.attributes.put('sensitiveAction', true);

        List<SentryEventEnvelope> records = new List<SentryEventEnvelope>();

        for (Integer i = 0; i < 8; i++) {
            SentryEventEnvelope historical = new SentryEventEnvelope();
            historical.source = 'EventMonitoring';
            historical.eventType = 'LoginEvent';
            historical.actorId = '005000000000001';
            historical.occurredAt = System.now().addMinutes(-10);
            historical.attributes.put('offHours', false);
            historical.attributes.put('sensitiveAction', false);
            records.add(historical);
        }

        SentryIngestionService.ingest(records);
        SentryIngestionService.ingest(new List<SentryEventEnvelope>{ envelope });

        System.assertEquals(9, [SELECT COUNT() FROM Sentry_Event__c WHERE Event_Type__c = 'LoginEvent']);
        System.assertEquals(1, [SELECT COUNT() FROM Sentry_Alert__c]);
    }
}
