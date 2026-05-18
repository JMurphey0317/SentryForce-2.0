@IsTest
private class SentryIngestionServiceTest {
    @IsTest
    static void ingestsCreatesAlertsTelemetryAndIncidents() {
        List<SentryEventEnvelope> envelopes = new List<SentryEventEnvelope>();
        for (String eventType : new List<String>{ 'LoginEvent', 'PermissionChange', 'ReportExport' }) {
            SentryEventEnvelope envelope = new SentryEventEnvelope();
            envelope.source = 'EventMonitoring';
            envelope.eventType = eventType;
            envelope.actorId = '005000000000001';
            envelope.occurredAt = System.now();
            envelope.attributes.put('offHours', true);
            envelope.attributes.put('sensitiveAction', true);
            envelope.attributes.put('bulkDownload', eventType == 'ReportExport');
            envelope.attributes.put('exportSizeMb', 650);
            envelopes.add(envelope);
        }

        List<Sentry_Event__c> records = SentryIngestionService.ingest(envelopes, '707000000000001', System.now().addSeconds(-5).getTime());

        System.assertEquals(3, records.size());
        System.assertEquals(3, [SELECT COUNT() FROM Sentry_Event__c]);
        System.assert([SELECT COUNT() FROM Sentry_Alert__c] > 0, 'Expected alerts to be generated');
        System.assert([SELECT COUNT() FROM Sentry_Incident__c] > 0, 'Expected a correlated incident to be generated');
        System.assert([SELECT COUNT() FROM Sentry_Queue_Telemetry__c] > 0, 'Expected queue telemetry to be recorded');
    }

    @IsTest
    static void chunksLargeEnvelopeListsAtTwoHundred() {
        List<SentryEventEnvelope> envelopes = new List<SentryEventEnvelope>();
        for (Integer index = 0; index < 401; index++) {
            SentryEventEnvelope envelope = new SentryEventEnvelope();
            envelope.source = 'Telemetry';
            envelope.eventType = 'ApexExecution';
            envelope.actorId = '00500000000000' + String.valueOf(index).leftPad(3, '0');
            envelopes.add(envelope);
        }

        List<List<SentryEventEnvelope>> chunks = SentryIngestionService.chunkEnvelopes(envelopes, 200);
        System.assertEquals(3, chunks.size());
        System.assertEquals(200, chunks[0].size());
        System.assertEquals(200, chunks[1].size());
        System.assertEquals(1, chunks[2].size());
    }
}
