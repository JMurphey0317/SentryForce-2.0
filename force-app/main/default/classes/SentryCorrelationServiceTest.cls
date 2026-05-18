@IsTest
private class SentryCorrelationServiceTest {
    @IsTest
    static void correlatesMatchingPatternIntoSingleIncident() {
        List<Sentry_Event__c> events = new List<Sentry_Event__c>{
            new Sentry_Event__c(
                Event_Source__c = 'EventMonitoring',
                Event_Type__c = 'LoginEvent',
                Occurred_At__c = System.now(),
                Actor_Id__c = '005000000000001',
                Risk_Score__c = 80,
                Risk_Factors__c = 'credential_stuffing_pattern',
                Payload__c = '{}',
                Retention_Until__c = Date.today().addDays(30),
                Compliance_Archived__c = false
            ),
            new Sentry_Event__c(
                Event_Source__c = 'EventMonitoring',
                Event_Type__c = 'PermissionChange',
                Occurred_At__c = System.now(),
                Actor_Id__c = '005000000000001',
                Risk_Score__c = 85,
                Risk_Factors__c = 'privilege_escalation',
                Payload__c = '{}',
                Retention_Until__c = Date.today().addDays(30),
                Compliance_Archived__c = false
            ),
            new Sentry_Event__c(
                Event_Source__c = 'EventMonitoring',
                Event_Type__c = 'ReportExport',
                Occurred_At__c = System.now(),
                Actor_Id__c = '005000000000001',
                Risk_Score__c = 90,
                Risk_Factors__c = 'suspicious_report_export',
                Payload__c = '{}',
                Retention_Until__c = Date.today().addDays(30),
                Compliance_Archived__c = false
            )
        };
        insert events;

        Map<Id, Id> incidentByEventId = SentryCorrelationService.correlate(events);

        System.assertEquals(3, incidentByEventId.size());
        System.assertEquals(1, [SELECT COUNT() FROM Sentry_Incident__c]);
        System.assertEquals(3, [SELECT COUNT() FROM Sentry_Incident_Event__c]);
    }
}
