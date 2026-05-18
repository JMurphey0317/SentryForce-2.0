@IsTest
private class SentryRiskEngineTest {
    @IsTest
    static void evaluatesCredentialStuffingOffHoursAndAnomalySignals() {
        SentryEventEnvelope envelope = new SentryEventEnvelope();
        envelope.source = 'EventMonitoring';
        envelope.eventType = 'LoginEvent';
        envelope.actorId = '005000000000001';
        envelope.occurredAt = System.now();
        envelope.attributes.put('offHours', true);
        envelope.attributes.put('sensitiveAction', true);
        envelope.attributes.put('countryChange', true);

        SentryRiskEngine.RiskResult result = SentryRiskEngine.evaluate(
            envelope,
            new Map<String, Integer>{ '005000000000001' => 9 }
        );
        result.applyAnomaly(SentryAnomalyEnrichmentService.enrich(envelope, 9));
        result.finalizeSeverity();

        System.assert(result.score >= 70, 'Expected anomalous score');
        System.assert(result.factors.contains('credential_stuffing_pattern'));
        System.assert(result.factors.contains('off_hours_sensitive_action'));
        System.assert(result.factors.contains('baseline_geographic_pattern_change'));
        System.assertEquals('High', result.severity);
    }

    @IsTest
    static void appliesDetectionRulesAndSeverityEscalation() {
        SentryEventEnvelope envelope = new SentryEventEnvelope();
        envelope.source = 'Telemetry';
        envelope.eventType = 'ReportExport';
        envelope.actorId = '005000000000001';
        envelope.occurredAt = System.now();
        envelope.attributes.put('bulkDownload', true);
        envelope.attributes.put('exportSizeMb', 650);

        SentryRiskEngine.RiskResult result = SentryRiskEngine.evaluate(envelope, 0);
        result.applyAnomaly(SentryAnomalyEnrichmentService.enrich(envelope, 0));
        SentryDetectionRuleService.applyRules(envelope, result);
        result.finalizeSeverity();

        System.assertEquals(true, result.factors.contains('detection_rule:High Risk Report Export'));
        System.assertEquals(true, result.score >= 65);
        System.assertEquals('High', result.severity);
    }
}
