public with sharing class SentryNamedCredentialService {
    public static String resolveEndpoint(Sentry_Integration_Config__mdt configRecord) {
        if (configRecord == null) {
            return null;
        }
        return buildEndpoint(
            configRecord.Named_Credential__c,
            configRecord.Path_Suffix__c,
            configRecord.Endpoint__c
        );
    }

    public static String buildEndpoint(String namedCredential, String pathSuffix, String fallbackEndpoint) {
        if (!String.isBlank(namedCredential)) {
            String endpoint = 'callout:' + namedCredential.trim();
            if (!String.isBlank(pathSuffix)) {
                endpoint += pathSuffix.startsWith('/') ? pathSuffix : '/' + pathSuffix;
            }
            return endpoint;
        }
        return fallbackEndpoint;
    }
}
