public with sharing class SentryActorActivityService {
    public static Map<String, Integer> getActorCounts(Set<String> actorIds) {
        Map<String, Integer> counts = new Map<String, Integer>();
        if (actorIds == null || actorIds.isEmpty()) {
            return counts;
        }

        for (String actorId : actorIds) {
            if (!String.isBlank(actorId)) {
                counts.put(actorId, 0);
            }
        }

        if (counts.isEmpty()) {
            return counts;
        }

        Datetime startWindow = System.now().addHours(-1);
        for (AggregateResult result : [
            SELECT Actor_Id__c actorId, COUNT(Id) total
            FROM Sentry_Event__c
            WHERE Actor_Id__c IN :counts.keySet()
            AND Occurred_At__c >= :startWindow
            WITH SECURITY_ENFORCED
            GROUP BY Actor_Id__c
        ]) {
            counts.put(
                (String) result.get('actorId'),
                Integer.valueOf(String.valueOf(result.get('total')))
            );
        }
        return counts;
    }
}
