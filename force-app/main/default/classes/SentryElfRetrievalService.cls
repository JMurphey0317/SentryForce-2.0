public with sharing class SentryElfRetrievalService implements Schedulable {
    public void execute(SchedulableContext sc) {
        startJobForRecentLogs();
    }

    @AuraEnabled
    public static Id startJobForRecentLogs() {
        Sentry_Retrieval_Job__c job = new Sentry_Retrieval_Job__c(
            Source__c = 'EventLogFile',
            Status__c = 'Running',
            Started_At__c = System.now(),
            Result_Summary__c = 'Retrieving latest EventLogFile records'
        );
        insert job;

        Integer countLogs = [
            SELECT count()
            FROM EventLogFile
            WHERE LogDate = :Date.today().addDays(-1)
        ];

        job.Status__c = 'Succeeded';
        job.Completed_At__c = System.now();
        job.Result_Summary__c = 'Located ' + countLogs + ' EventLogFile rows for previous day.';
        update job;

        return job.Id;
    }
}
