@IsTest
private class SentryAlertingServiceTest {
    private class FailingSlackMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new CalloutException('Simulated callout failure');
        }
    }

    @IsTest
    static void sendSlackNotificationHandlesFailureWithoutThrowing() {
        Test.setMock(HttpCalloutMock.class, new FailingSlackMock());

        Test.startTest();
        SentryAlertingService.sendSlackNotification('https://hooks.slack.com/services/mock/mock/mock', new Map<String, Object>{
            'text' => 'test'
        });
        Test.stopTest();

        System.assert(true, 'Expected no exception to escape sendSlackNotification failure path.');
    }
}
