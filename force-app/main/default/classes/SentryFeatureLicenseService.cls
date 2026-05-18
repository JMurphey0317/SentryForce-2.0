public with sharing class SentryFeatureLicenseService {
    public class FeatureStatus {
        @AuraEnabled public String featureName;
        @AuraEnabled public Boolean available;
        @AuraEnabled public String detail;
    }

    public static List<FeatureStatus> getFeatureStatuses() {
        Map<String, Schema.SObjectType> describeMap = Schema.getGlobalDescribe();
        List<FeatureStatus> statuses = new List<FeatureStatus>();
        statuses.add(buildStatus('Shield', describeMap.containsKey('PlatformEncryptionKey'), 'Heuristic based on encryption metadata availability'));
        statuses.add(buildStatus('Event Monitoring', describeMap.containsKey('EventLogFile'), 'Required for ELF and login telemetry retrieval'));
        statuses.add(buildStatus('Transaction Security', describeMap.containsKey('TransactionSecurityEvent'), 'Required for policy-backed real-time controls'));
        statuses.add(buildStatus('CDC', hasChangeEvents(describeMap), 'Heuristic based on ChangeEvent entities in the org'));
        statuses.add(buildStatus('Platform Events', describeMap.containsKey('PlatformEventUsageMetric'), 'Required for EMP API live streaming surfaces'));
        return statuses;
    }

    private static Boolean hasChangeEvents(Map<String, Schema.SObjectType> describeMap) {
        for (String objectName : describeMap.keySet()) {
            if (objectName != null && objectName.endsWith('ChangeEvent')) {
                return true;
            }
        }
        return false;
    }

    private static FeatureStatus buildStatus(String featureName, Boolean available, String detail) {
        FeatureStatus status = new FeatureStatus();
        status.featureName = featureName;
        status.available = available;
        status.detail = detail;
        return status;
    }
}
