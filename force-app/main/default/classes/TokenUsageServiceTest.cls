@IsTest
private class TokenUsageServiceTest {

    private static Id agentId;

    @TestSetup
    static void setup() {
        insert new Grounding_Source__c(
            Name = 'KB', Source_Type__c = 'LightningKnowledge',
            Object_Api_Name__c = 'Account', Max_Records__c = 5, Is_Active__c = true
        );
        Id sourceId = [SELECT Id FROM Grounding_Source__c LIMIT 1].Id;
        insert new Agent_Definition__c(
            Name = 'Agent', Agent_Key__c = 'a_v1', Status__c = 'Draft', Version__c = 1,
            Grounding_Source__c = sourceId, Max_Steps__c = 8
        );
        agentId = [SELECT Id FROM Agent_Definition__c LIMIT 1].Id;
    }

    /* ------------------------------------------------------------------ */

    @IsTest
    static void stepCostsMatchThePublishedTable() {
        System.assertEquals(0.6, TokenUsageService.costForStep('reason'));
        System.assertEquals(0.1, TokenUsageService.costForStep('ground'));
        System.assertEquals(0.2, TokenUsageService.costForStep('act'));
        System.assertEquals(0.3, TokenUsageService.costForStep('subagent'));
        System.assertEquals(0, TokenUsageService.costForStep('ask'));
    }

    @IsTest
    static void unknownStepTypeIsFreeRatherThanGuessed() {
        System.assertEquals(0, TokenUsageService.costForStep('something_new'),
            'An uncosted step is not silently charged at the highest rate');
    }

    @IsTest
    static void recordAccruesAcrossStepsInASession() {
        Test.startTest();
        TokenUsageService.record('s1', agentId, 'ground', 5, 'Support');
        TokenUsageService.record('s1', agentId, 'reason', 5, 'Support');
        Test.stopTest();

        System.assertEquals(
            0.7,
            AuditService.totalCreditsForSession('s1'),
            'Two differently-priced steps sum correctly'
        );
    }

    @IsTest
    static void budgetIsExceededOnlyOnceTheCeilingIsPassed() {
        Test.startTest();
        TokenUsageService.UsageResult under =
            TokenUsageService.record('s2', agentId, 'reason', 1.0, 'Support');
        TokenUsageService.UsageResult over =
            TokenUsageService.record('s2', agentId, 'reason', 1.0, 'Support');
        Test.stopTest();

        System.assert(!under.budgetExceeded, '0.6 of a 1.0 budget is within budget');
        System.assert(over.budgetExceeded, '1.2 of a 1.0 budget is over');
    }

    @IsTest
    static void unboundedBudgetNeverAlerts() {
        Test.startTest();
        TokenUsageService.UsageResult result =
            TokenUsageService.record('s3', agentId, 'reason', null, 'Support');
        Test.stopTest();

        System.assert(!result.budgetExceeded, 'A null budget means unbounded');
    }

    @IsTest
    static void ledgerAggregatesPerCostCenter() {
        Test.startTest();
        TokenUsageService.record('s4', agentId, 'reason', null, 'Support');
        TokenUsageService.record('s5', agentId, 'reason', null, 'Support');
        TokenUsageService.record('s6', agentId, 'reason', null, 'Research');
        Decimal support = TokenUsageService.totalForCostCenter('Support', 30);
        Test.stopTest();

        System.assertEquals(1.2, support, 'The budget alert sums by cost center');
    }

    @IsTest
    static void everyStepWritesBothALedgerRowAndATrace() {
        Test.startTest();
        TokenUsageService.record('s7', agentId, 'act', null, 'Support');
        Test.stopTest();

        System.assertEquals(0.2, AuditService.totalCreditsForSession('s7'),
            'The action step was charged at the action rate');
        System.assert(!AuditService.traceFor('s7').isEmpty(),
            'A charged step must be traceable to its cost');
    }

    @IsTest
    static void tokenAccountingTotalsBothDirections() {
        Test.startTest();
        AuditService.recordTokens('s8', agentId, 1200, 400);
        Test.stopTest();

        Token_Usage__c usage = [
            SELECT Input_Tokens__c, Output_Tokens__c, Total_Tokens__c
            FROM Token_Usage__c
            WHERE Session_Id__c = 's8'
            LIMIT 1
        ];
        System.assertEquals(1200, usage.Input_Tokens__c);
        System.assertEquals(400, usage.Output_Tokens__c);
        System.assertEquals(1600, usage.Total_Tokens__c);
    }
}
