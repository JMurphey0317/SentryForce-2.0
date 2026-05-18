public with sharing class SentryRetentionService {
    public static Date resolveRetentionDate(String eventType) {
        List<Sentry_Retention_Policy__mdt> policies = [
            SELECT Event_Type__c, Operational_Days__c, Compliance_Days__c
            FROM Sentry_Retention_Policy__mdt
            WHERE Event_Type__c = :eventType
            LIMIT 1
        ];

        Integer days = 90;
        if (!policies.isEmpty() && policies[0].Operational_Days__c != null) {
            days = Integer.valueOf(policies[0].Operational_Days__c);
        }

        return Date.today().addDays(days);
    }

    public class CleanupBatch implements Database.Batchable<SObject>, Schedulable {
        public Database.QueryLocator start(Database.BatchableContext bc) {
            return Database.getQueryLocator([
                SELECT Id, Retention_Until__c, Compliance_Archived__c
                FROM Sentry_Event__c
                WHERE Retention_Until__c < :Date.today()
            ]);
        }

        public void execute(Database.BatchableContext bc, List<Sentry_Event__c> scope) {
            List<Sentry_Event__c> toArchive = new List<Sentry_Event__c>();
            for (Sentry_Event__c record : scope) {
                record.Compliance_Archived__c = true;
                toArchive.add(record);
            }
            update toArchive;
        }

        public void finish(Database.BatchableContext bc) {
        }

        public void execute(SchedulableContext sc) {
            Database.executeBatch(new CleanupBatch(), 200);
        }
    }
}
