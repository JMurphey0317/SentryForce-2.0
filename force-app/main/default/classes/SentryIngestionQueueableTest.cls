@IsTest
private class SentryIngestionQueueableTest {
    @IsTest
    static void parseDatetimeHandlesIso8601WithMillisecondsAndOffset() {
        Datetime parsed = SentryIngestionQueueable.parseDatetime('2026-05-18T18:43:58.366Z');
        System.assertNotEquals(null, parsed);

        Datetime parsedOffset = SentryIngestionQueueable.parseDatetime('2026-05-18T13:43:58.366-05:00');
        System.assertNotEquals(null, parsedOffset);
    }
}
