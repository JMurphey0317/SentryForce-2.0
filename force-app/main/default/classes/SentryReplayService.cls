public with sharing class SentryReplayService {
    public static Id startReplay(Datetime startDate, Datetime endDate, String ruleName, Integer batchSize) {
        if (!Schema.sObjectType.Sentry_Replay_Job__c.isCreateable()) {
            return null;
        }

        Integer effectiveBatchSize = normalizeBatchSize(batchSize);
        Sentry_Replay_Job__c replayJob = new Sentry_Replay_Job__c(
            Status__c = 'Queued',
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Rule_Name__c = ruleName,
            Progress_Percent__c = 0,
            Processed_Count__c = 0,
            Batch_Size__c = effectiveBatchSize,
            Started_At__c = System.now()
        );
        List<SObject> raw = new List<SObject>{ replayJob };
        List<SObject> sanitized = Security.stripInaccessible(AccessType.CREATABLE, raw).getRecords();
        Database.insert(sanitized, false);
        replayJob.Id = sanitized.isEmpty() ? null : ((Sentry_Replay_Job__c) sanitized[0]).Id;
        if (replayJob.Id != null) {
            Database.executeBatch(new ReplayBatch(replayJob.Id, startDate, endDate, ruleName), effectiveBatchSize);
        }
        return replayJob.Id;
    }

    private static Integer normalizeBatchSize(Integer batchSize) {
        Integer effectiveBatchSize = batchSize == null ? 100 : batchSize;
        if (effectiveBatchSize < 50) {
            effectiveBatchSize = 50;
        }
        if (effectiveBatchSize > 200) {
            effectiveBatchSize = 200;
        }
        return effectiveBatchSize;
    }

    public class ReplayBatch implements Database.Batchable<SObject>, Database.Stateful {
        private Id replayJobId;
        private Datetime startDate;
        private Datetime endDate;
        private String ruleName;
        private Integer processedCount = 0;
        private Integer totalCount;

        public ReplayBatch(Id replayJobId, Datetime startDate, Datetime endDate, String ruleName) {
            this.replayJobId = replayJobId;
            this.startDate = startDate == null ? System.now().addDays(-1) : startDate;
            this.endDate = endDate == null ? System.now() : endDate;
            this.ruleName = ruleName;
            this.totalCount = countScopedEvents();
        }

        public Database.QueryLocator start(Database.BatchableContext bc) {
            if (String.isBlank(ruleName)) {
                return Database.getQueryLocator([
                    SELECT Id, Event_Source__c, Event_Type__c, Occurred_At__c, Actor_Id__c, Payload__c
                    FROM Sentry_Event__c
                    WHERE Occurred_At__c >= :startDate
                    AND Occurred_At__c <= :endDate
                    WITH SECURITY_ENFORCED
                    ORDER BY Occurred_At__c ASC
                ]);
            }

            String likeRuleName = '%' + ruleName + '%';
            return Database.getQueryLocator([
                SELECT Id, Event_Source__c, Event_Type__c, Occurred_At__c, Actor_Id__c, Payload__c
                FROM Sentry_Event__c
                WHERE Occurred_At__c >= :startDate
                AND Occurred_At__c <= :endDate
                AND Risk_Factors__c LIKE :likeRuleName
                WITH SECURITY_ENFORCED
                ORDER BY Occurred_At__c ASC
            ]);
        }

        public void execute(Database.BatchableContext bc, List<Sentry_Event__c> scope) {
            updateReplayJob('Running', null);
            List<SentryEventEnvelope> envelopes = new List<SentryEventEnvelope>();
            for (Sentry_Event__c eventRecord : scope) {
                SentryEventEnvelope envelope = new SentryEventEnvelope();
                envelope.source = eventRecord.Event_Source__c + ':Replay';
                envelope.eventType = eventRecord.Event_Type__c;
                envelope.actorId = eventRecord.Actor_Id__c;
                envelope.occurredAt = eventRecord.Occurred_At__c;
                envelope.attributes = deserializeAttributes(eventRecord.Payload__c);
                envelope.attributes.put('replayed', true);
                envelope.attributes.put('replayJobId', replayJobId);
                envelopes.add(envelope);
            }
            SentryIngestionService.ingest(envelopes);
            processedCount += scope.size();
            updateReplayJob('Running', null);
        }

        public void finish(Database.BatchableContext bc) {
            updateReplayJob('Completed', null);
        }

        private void updateReplayJob(String status, String failureMessage) {
            if (!Schema.sObjectType.Sentry_Replay_Job__c.isUpdateable()) {
                return;
            }
            Decimal progress = totalCount == 0 ? 100 : (Decimal.valueOf(processedCount) / Decimal.valueOf(totalCount)) * 100;
            if (progress > 100) {
                progress = 100;
            }
            Sentry_Replay_Job__c updateRecord = new Sentry_Replay_Job__c(
                Id = replayJobId,
                Status__c = status,
                Progress_Percent__c = progress,
                Processed_Count__c = processedCount,
                Failure_Message__c = failureMessage,
                Completed_At__c = status == 'Completed' || status == 'Failed' ? System.now() : null
            );
            List<SObject> raw = new List<SObject>{ updateRecord };
            Database.update(Security.stripInaccessible(AccessType.UPDATABLE, raw).getRecords(), false);
        }

        private Integer countScopedEvents() {
            if (String.isBlank(ruleName)) {
                return [
                    SELECT COUNT()
                    FROM Sentry_Event__c
                    WHERE Occurred_At__c >= :startDate
                    AND Occurred_At__c <= :endDate
                    WITH SECURITY_ENFORCED
                ];
            }

            String likeRuleName = '%' + ruleName + '%';
            return [
                SELECT COUNT()
                FROM Sentry_Event__c
                WHERE Occurred_At__c >= :startDate
                AND Occurred_At__c <= :endDate
                AND Risk_Factors__c LIKE :likeRuleName
                WITH SECURITY_ENFORCED
            ];
        }

        private Map<String, Object> deserializeAttributes(String payload) {
            if (String.isBlank(payload)) {
                return new Map<String, Object>();
            }
            try {
                return (Map<String, Object>) JSON.deserializeUntyped(payload);
            } catch (Exception ex) {
                return new Map<String, Object>();
            }
        }
    }
}
