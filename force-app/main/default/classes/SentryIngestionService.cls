public with sharing class SentryIngestionService {
    @AuraEnabled
    public static void ingestAsync(List<SentryEventEnvelope> envelopes) {
        System.enqueueJob(new SentryIngestionQueueable(JSON.serialize(envelopes)));
    }

    public static List<Sentry_Event__c> ingest(List<SentryEventEnvelope> envelopes) {
        if (envelopes == null || envelopes.isEmpty()) {
            return new List<Sentry_Event__c>();
        }

        List<Sentry_Event__c> records = new List<Sentry_Event__c>();

        for (SentryEventEnvelope envelope : envelopes) {
            Integer actorEventsLastHour = getActorEventCountLastHour(envelope.actorId, envelope.eventType);
            SentryRiskEngine.RiskResult risk = SentryRiskEngine.evaluate(envelope, actorEventsLastHour);

            Date retentionDate = SentryRetentionService.resolveRetentionDate(envelope.eventType);
            Sentry_Event__c record = new Sentry_Event__c(
                Event_Source__c = envelope.source,
                Event_Type__c = envelope.eventType,
                Occurred_At__c = envelope.occurredAt == null ? System.now() : envelope.occurredAt,
                Actor_Id__c = envelope.actorId,
                Risk_Score__c = risk.score,
                Risk_Factors__c = String.join(risk.factors, ';'),
                Payload__c = envelope.payloadAsJson(),
                Retention_Until__c = retentionDate,
                Compliance_Archived__c = false
            );
            records.add(record);
        }

        insert records;

        for (Integer i = 0; i < records.size(); i++) {
            SentryRiskEngine.RiskResult risk = SentryRiskEngine.evaluate(envelopes[i], getActorEventCountLastHour(envelopes[i].actorId, envelopes[i].eventType));
            if (risk.isAnomalous()) {
                SentryAlertingService.createAlert(records[i], risk);
            }
        }

        return records;
    }

    private static Integer getActorEventCountLastHour(String actorId, String eventType) {
        if (String.isBlank(actorId)) {
            return 0;
        }

        Datetime startWindow = System.now().addHours(-1);
        return [
            SELECT count()
            FROM Sentry_Event__c
            WHERE Actor_Id__c = :actorId
            AND Event_Type__c = :eventType
            AND Occurred_At__c >= :startWindow
        ];
    }
}
