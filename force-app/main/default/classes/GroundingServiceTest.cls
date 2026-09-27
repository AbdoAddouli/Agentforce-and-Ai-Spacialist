@IsTest
private class GroundingServiceTest {

    private static Id activeSourceId;
    private static Id inactiveSourceId;

    @TestSetup
    static void setup() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(Name = 'Northwind Refund Policy ' + i));
        }
        insert accounts;

        insert new Grounding_Source__c(
            Name = 'Refund Policy KB', Source_Type__c = 'LightningKnowledge',
            Object_Api_Name__c = 'Account', Scope_Json__c = '{"status":"Published"}',
            Max_Records__c = 3, Relevance_Threshold__c = 0.2, Is_Active__c = true
        );
        insert new Grounding_Source__c(
            Name = 'Retired KB', Source_Type__c = 'LightningKnowledge',
            Object_Api_Name__c = 'Account', Max_Records__c = 3, Is_Active__c = false
        );

        activeSourceId = [
            SELECT Id FROM Grounding_Source__c WHERE Name = 'Refund Policy KB'
        ].Id;
        inactiveSourceId = [
            SELECT Id FROM Grounding_Source__c WHERE Name = 'Retired KB'
        ].Id;
    }

    /* ------------------------------------------------------------------ */

    @IsTest
    static void retrievalIsBoundedByMaxRecords() {
        Test.startTest();
        GroundingService.GroundingResult result =
            GroundingService.retrieve(activeSourceId, 'Northwind');
        Test.stopTest();

        System.assert(result.recordsRetrieved > 0, 'Should have found the seeded policies');
        System.assertEquals(3, result.recordsRetrieved, 'Max_Records__c is the ceiling');
    }

    @IsTest
    static void noMatchesIsAMissNotAnError() {
        Test.startTest();
        GroundingService.GroundingResult result =
            GroundingService.retrieve(activeSourceId, 'zzzz_no_such_topic');
        Test.stopTest();

        System.assertEquals(0, result.recordsRetrieved,
            'A miss returns zero, it does not widen the scope');
        System.assertEquals('NO_MATCHES', result.missReason);
    }

    @IsTest
    static void inactiveSourceIsRefused() {
        Test.startTest();
        GroundingService.GroundingResult result =
            GroundingService.retrieve(inactiveSourceId, 'Northwind');
        Test.stopTest();

        System.assertEquals(0, result.recordsRetrieved);
        System.assertEquals('SOURCE_INACTIVE', result.missReason);
    }

    @IsTest
    static void nullSourceIsReportedRatherThanThrowing() {
        Test.startTest();
        GroundingService.GroundingResult result = GroundingService.retrieve(null, 'Northwind');
        Test.stopTest();

        System.assertEquals('NO_SOURCE', result.missReason);
    }

    @IsTest
    static void emptyQueryIsRejectedBeforeTheQueryRuns() {
        Test.startTest();
        GroundingService.GroundingResult result = GroundingService.retrieve(activeSourceId, '');
        Test.stopTest();

        System.assertEquals('EMPTY_QUERY', result.missReason);
    }

    @IsTest
    static void requireContextThrowsOnMiss() {
        try {
            GroundingService.requireContext(activeSourceId, 'zzzz_no_such_topic');
            System.assert(false, 'requireContext must refuse to continue without evidence');
        } catch (GroundingService.GroundingMissException e) {
            System.assert(
                String.valueOf(e.getMessage()).contains('NO_MATCHES'),
                'The miss reason belongs in the message, got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void requireContextReturnsRecordsOnHit() {
        Test.startTest();
        List<SObject> records = GroundingService.requireContext(activeSourceId, 'Northwind');
        Test.stopTest();

        System.assert(!records.isEmpty(), 'A hit returns the records');
    }

    @IsTest
    static void wildcardsInTheQueryAreNotTreatedAsPatterns() {
        Test.startTest();
        GroundingService.GroundingResult result =
            GroundingService.retrieve(activeSourceId, 'Northwind%');
        Test.stopTest();

        System.assertEquals(0, result.recordsRetrieved,
            'A literal % must not match every record');
    }

    @IsTest
    static void activeSourcesExcludesRetired() {
        List<Grounding_Source__c> active = GroundingService.activeSources();
        System.assertEquals(1, active.size(), 'Only the active source is offered');
    }
}
