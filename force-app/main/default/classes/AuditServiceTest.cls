@IsTest
private class AuditServiceTest {

    /* ------------------------------------------------------------------ */

    @IsTest
    static void traceIsWrittenPerStep() {
        Test.startTest();
        AuditService.writeTrace('a1', 1, 'Reason', 'Order Status', 3, null, 0.6, 'detail');
        AuditService.writeTrace('a1', 2, 'Act', 'Order Status', null, 'read_order', 0.2, 'detail');
        Test.stopTest();

        List<Agent_Session_Trace__c> traces = AuditService.traceFor('a1');

        System.assertEquals(2, traces.size());
        System.assertEquals(1, traces[0].Step_Number__c, 'Traces come back in step order');
        System.assertEquals(3, traces[0].Records_Retrieved__c);
    }

    @IsTest
    static void overlongDetailIsTruncatedNotRejected() {
        Test.startTest();
        AuditService.writeTrace('a2', 1, 'Reason', null, null, null, 0.6, 'x'.repeat(40000));
        Test.stopTest();

        System.assertEquals(1, AuditService.traceFor('a2').size());
    }

    @IsTest
    static void creditsSumPerSession() {
        Test.startTest();
        AuditService.recordCredits('a3', null, 'Reason', 0.6, 'Support');
        AuditService.recordCredits('a3', null, 'Act', 0.2, 'Support');
        Test.stopTest();

        System.assertEquals(0.8, AuditService.totalCreditsForSession('a3'));
    }

    @IsTest
    static void creditsDoNotLeakBetweenSessions() {
        Test.startTest();
        AuditService.recordCredits('a4', null, 'Reason', 0.6, 'Support');
        AuditService.recordCredits('a5', null, 'Reason', 0.6, 'Support');
        Decimal four = AuditService.totalCreditsForSession('a4');
        Decimal five = AuditService.totalCreditsForSession('a5');
        Test.stopTest();

        System.assertEquals(0.6, four, 'Each session is costed independently');
        System.assertEquals(0.6, five);
    }

    @IsTest
    static void failedActionsAreTheActionableSlice() {
        insert new Grounding_Source__c(
            Name = 'KB', Source_Type__c = 'LightningKnowledge',
            Object_Api_Name__c = 'Account', Max_Records__c = 5, Is_Active__c = true
        );
        Id sourceId = [SELECT Id FROM Grounding_Source__c LIMIT 1].Id;
        insert new Agent_Definition__c(
            Name = 'A', Agent_Key__c = 'a_v1', Status__c = 'Draft', Version__c = 1,
            Grounding_Source__c = sourceId, Max_Steps__c = 5
        );
        Id agentId = [SELECT Id FROM Agent_Definition__c LIMIT 1].Id;
        insert new Action_Definition__c(
            Name = 'Read', Action_Key__c = 'read_order', Is_Active__c = true,
            Agent_Definition__c = agentId
        );
        Id actionId = [SELECT Id FROM Action_Definition__c LIMIT 1].Id;

        insert new List<Agent_Action_Audit__c>{
            new Agent_Action_Audit__c(
                Name = 'AUD-ok', Session_Id__c = 'a6', Action_Definition__c = actionId,
                Success__c = true, Created_By_Agent__c = true
            ),
            new Agent_Action_Audit__c(
                Name = 'AUD-fail', Session_Id__c = 'a6', Action_Definition__c = actionId,
                Success__c = false, Error_Code__c = 'ACTION_THREW', Created_By_Agent__c = true
            )
        };

        Test.startTest();
        List<Agent_Action_Audit__c> failures = AuditService.failedActions(7);
        Test.stopTest();

        System.assertEquals(1, failures.size(), 'Only the failure is returned');
        System.assertEquals('ACTION_THREW', failures[0].Error_Code__c);
    }

    @IsTest
    static void anEmptySessionTotalsZero() {
        System.assertEquals(0, AuditService.totalCreditsForSession('never_used'));
    }

    @IsTest
    static void interactionLogToleratesMissingAgent() {
        Test.startTest();
        AuditService.logInteraction('a7', null, 1, 'hello', 'hi', 'Answered', 0.8);
        Test.stopTest();

        List<Agent_Interaction_Log__c> logs = [
            SELECT Session_Id__c, Outcome__c FROM Agent_Interaction_Log__c
            WHERE Session_Id__c = 'a7'
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('Answered', logs[0].Outcome__c);
    }
}
