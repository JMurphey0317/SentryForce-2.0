public with sharing class SentryMonitoringController {
    public class DashboardData {
        @AuraEnabled public List<Sentry_Event__c> recentEvents;
        @AuraEnabled public List<Sentry_Alert__c> recentAlerts;
        @AuraEnabled public List<Sentry_Retrieval_Job__c> retrievalJobs;

        public DashboardData() {
            recentEvents = new List<Sentry_Event__c>();
            recentAlerts = new List<Sentry_Alert__c>();
            retrievalJobs = new List<Sentry_Retrieval_Job__c>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        DashboardData data = new DashboardData();
        data.recentEvents = [
            SELECT Id, Name, Event_Source__c, Event_Type__c, Occurred_At__c, Actor_Id__c, Risk_Score__c, Risk_Factors__c
            FROM Sentry_Event__c
            ORDER BY Occurred_At__c DESC
            LIMIT 25
        ];
        data.recentAlerts = [
            SELECT Id, Name, Severity__c, Status__c, Channel__c, Message__c, Event__c
            FROM Sentry_Alert__c
            ORDER BY CreatedDate DESC
            LIMIT 25
        ];
        data.retrievalJobs = [
            SELECT Id, Name, Source__c, Status__c, Started_At__c, Completed_At__c, Result_Summary__c
            FROM Sentry_Retrieval_Job__c
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];
        return data;
    }

    @AuraEnabled
    public static void runElfRetrieval() {
        SentryElfRetrievalService.startJobForRecentLogs();
    }
}
