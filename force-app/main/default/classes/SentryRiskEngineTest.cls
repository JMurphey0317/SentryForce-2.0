@IsTest
private class SentryRiskEngineTest {
    @IsTest
    static void evaluatesCredentialStuffingAndOffHoursSignals() {
        SentryEventEnvelope envelope = new SentryEventEnvelope();
        envelope.source = 'EventMonitoring';
        envelope.eventType = 'LoginEvent';
        envelope.actorId = '005000000000001';
        envelope.occurredAt = System.now();
        envelope.attributes.put('offHours', true);
        envelope.attributes.put('sensitiveAction', true);

        SentryRiskEngine.RiskResult result = SentryRiskEngine.evaluate(envelope, 9);

        System.assert(result.score >= 70, 'Expected anomalous score');
        System.assert(result.factors.contains('credential_stuffing_pattern'));
        System.assert(result.factors.contains('off_hours_sensitive_action'));
    }

    @IsTest
    static void evaluatesPerformanceAndApexSignals() {
        SentryEventEnvelope envelope = new SentryEventEnvelope();
        envelope.source = 'Telemetry';
        envelope.eventType = 'ApexExecution';
        envelope.actorId = '005000000000001';
        envelope.occurredAt = System.now();
        envelope.attributes.put('durationMs', 12000);
        envelope.attributes.put('exceptionRaised', true);

        SentryRiskEngine.RiskResult result = SentryRiskEngine.evaluate(envelope, 0);

        System.assertEquals(true, result.factors.contains('long_running_apex'));
        System.assertEquals(true, result.factors.contains('unexpected_apex_exception'));
    }
}
