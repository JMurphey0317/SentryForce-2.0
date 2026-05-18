public with sharing class SentryAlertingService {
    public static void createAlert(Sentry_Event__c eventRecord, SentryRiskEngine.RiskResult riskResult) {
        Sentry_Alert__c alertRecord = new Sentry_Alert__c(
            Severity__c = riskResult.score >= 90 ? 'Critical' : 'High',
            Status__c = 'Open',
            Channel__c = 'Salesforce',
            Message__c = 'Anomalous ' + eventRecord.Event_Type__c + ' detected. Score=' + String.valueOf(riskResult.score),
            Event__c = eventRecord.Id
        );
        insert alertRecord;

        notifySlack(alertRecord, eventRecord, riskResult);
    }

    @TestVisible
    private static void notifySlack(Sentry_Alert__c alertRecord, Sentry_Event__c eventRecord, SentryRiskEngine.RiskResult riskResult) {
        List<Sentry_Integration_Config__mdt> configs = [
            SELECT Channel__c, Endpoint__c, Enabled__c
            FROM Sentry_Integration_Config__mdt
            WHERE Channel__c = 'Slack' AND Enabled__c = true
            LIMIT 1
        ];

        if (configs.isEmpty() || String.isBlank(configs[0].Endpoint__c)) {
            return;
        }

        sendSlackNotification(configs[0].Endpoint__c, new Map<String, Object>{
            'text' => 'SentryForce Alert: ' + alertRecord.Message__c,
            'eventType' => eventRecord.Event_Type__c,
            'riskScore' => riskResult.score,
            'factors' => riskResult.factors
        });
    }

    @TestVisible
    private static void sendSlackNotification(String endpoint, Map<String, Object> payload) {
        HttpRequest request = new HttpRequest();
        request.setMethod('POST');
        request.setEndpoint(endpoint);
        request.setHeader('Content-Type', 'application/json');
        request.setBody(JSON.serialize(payload));

        Http http = new Http();
        try {
            http.send(request);
        } catch (Exception e) {
            String safeEndpoint = String.isBlank(endpoint) ? 'n/a' : '***' + endpoint.substring(Math.max(endpoint.length() - 8, 0));
            System.debug(LoggingLevel.WARN, 'Slack notification failed for endpoint ' + safeEndpoint + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }
}
