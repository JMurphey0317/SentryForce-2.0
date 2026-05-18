public with sharing class SentryOutboundConnectorService {
    public static void dispatchAlerts(List<Sentry_Alert__c> alertRecords) {
        if (alertRecords == null || alertRecords.isEmpty()) {
            return;
        }

        List<Sentry_Integration_Config__mdt> connectorConfigs = [
            SELECT DeveloperName, Channel__c, Enabled__c, Endpoint__c, Integration_Type__c,
                Named_Credential__c, External_Credential__c, Path_Suffix__c, Max_Retry_Count__c
            FROM Sentry_Integration_Config__mdt
            WHERE Enabled__c = true
            AND Integration_Type__c IN ('Splunk', 'Datadog', 'Sentinel', 'Elastic', 'QRadar')
            ORDER BY DeveloperName ASC
        ];
        if (connectorConfigs.isEmpty() || !Schema.sObjectType.Sentry_Connector_Delivery__c.isCreateable()) {
            return;
        }

        List<Sentry_Connector_Delivery__c> deliveries = new List<Sentry_Connector_Delivery__c>();
        for (Sentry_Alert__c alertRecord : alertRecords) {
            for (Sentry_Integration_Config__mdt connectorConfig : connectorConfigs) {
                deliveries.add(new Sentry_Connector_Delivery__c(
                    Connector__c = connectorConfig.Integration_Type__c,
                    Status__c = 'Pending',
                    Payload__c = JSON.serialize(new Map<String, Object>{
                        'alertId' => alertRecord.Id,
                        'message' => alertRecord.Message__c,
                        'severity' => alertRecord.Severity__c,
                        'status' => alertRecord.Status__c
                    }),
                    Target_Reference__c = connectorConfig.DeveloperName,
                    Retry_Count__c = 0,
                    Health_Status__c = 'Pending',
                    Alert__c = alertRecord.Id
                ));
            }
        }

        List<SObject> raw = new List<SObject>();
        raw.addAll(deliveries);
        Database.SaveResult[] results = Database.insert(Security.stripInaccessible(AccessType.CREATABLE, raw).getRecords(), false);

        List<Id> deliveryIds = new List<Id>();
        Integer index = 0;
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                deliveryIds.add(result.getId());
            }
            index++;
        }

        if (!deliveryIds.isEmpty()) {
            System.enqueueJob(new DeliveryQueueable(deliveryIds));
        }
    }

    public class DeliveryQueueable implements Queueable, Database.AllowsCallouts {
        private List<Id> deliveryIds;

        public DeliveryQueueable(List<Id> deliveryIds) {
            this.deliveryIds = deliveryIds;
        }

        public void execute(QueueableContext context) {
            Map<String, Sentry_Integration_Config__mdt> configsByDeveloperName = new Map<String, Sentry_Integration_Config__mdt>();
            for (Sentry_Integration_Config__mdt configRecord : [
                SELECT DeveloperName, Channel__c, Enabled__c, Endpoint__c, Integration_Type__c,
                    Named_Credential__c, External_Credential__c, Path_Suffix__c, Max_Retry_Count__c
                FROM Sentry_Integration_Config__mdt
                WHERE Enabled__c = true
            ]) {
                configsByDeveloperName.put(configRecord.DeveloperName, configRecord);
            }

            List<Sentry_Connector_Delivery__c> deliveries = [
                SELECT Id, Connector__c, Status__c, Payload__c, Target_Reference__c,
                    Retry_Count__c, Last_Attempt_At__c, Failure_Message__c, Health_Status__c
                FROM Sentry_Connector_Delivery__c
                WHERE Id IN :deliveryIds
                WITH SECURITY_ENFORCED
            ];

            Http http = new Http();
            for (Sentry_Connector_Delivery__c delivery : deliveries) {
                Sentry_Integration_Config__mdt configRecord = configsByDeveloperName.get(delivery.Target_Reference__c);
                if (configRecord == null) {
                    delivery.Status__c = 'DeadLetter';
                    delivery.Health_Status__c = 'MissingConfig';
                    delivery.Failure_Message__c = 'No active integration config found.';
                    delivery.Last_Attempt_At__c = System.now();
                    continue;
                }

                HttpRequest request = new HttpRequest();
                request.setMethod('POST');
                request.setHeader('Content-Type', 'application/json');
                request.setEndpoint(SentryNamedCredentialService.resolveEndpoint(configRecord));
                request.setBody(delivery.Payload__c);

                try {
                    HttpResponse response = http.send(request);
                    delivery.Last_Attempt_At__c = System.now();
                    if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                        delivery.Status__c = 'Sent';
                        delivery.Health_Status__c = 'Healthy';
                        delivery.Failure_Message__c = null;
                    } else {
                        applyFailureState(delivery, configRecord, 'HTTP ' + response.getStatusCode() + ' ' + response.getBody());
                    }
                } catch (Exception ex) {
                    delivery.Last_Attempt_At__c = System.now();
                    applyFailureState(delivery, configRecord, ex.getMessage());
                }
            }

            if (!deliveries.isEmpty() && Schema.sObjectType.Sentry_Connector_Delivery__c.isUpdateable()) {
                List<SObject> raw = new List<SObject>();
                raw.addAll(deliveries);
                Database.update(Security.stripInaccessible(AccessType.UPDATABLE, raw).getRecords(), false);
            }
        }

        private static void applyFailureState(
            Sentry_Connector_Delivery__c delivery,
            Sentry_Integration_Config__mdt configRecord,
            String failureMessage
        ) {
            Integer maxRetries = configRecord.Max_Retry_Count__c == null ? 3 : Integer.valueOf(configRecord.Max_Retry_Count__c);
            Integer retryCount = delivery.Retry_Count__c == null ? 0 : Integer.valueOf(delivery.Retry_Count__c);
            retryCount++;
            delivery.Retry_Count__c = retryCount;
            delivery.Failure_Message__c = failureMessage;
            delivery.Health_Status__c = 'Degraded';
            delivery.Status__c = retryCount >= maxRetries ? 'DeadLetter' : 'Failed';
        }
    }
}
