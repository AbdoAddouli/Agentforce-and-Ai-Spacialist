@IsTest
private class ActionOrchestratorTest {

    private static Id agentId;

    /** Stub handler so execution can be tested without a live integration. */
    private class EchoHandler implements ActionOrchestrator.AgentActionHandler {
        public Object run(Map<String, Object> params) {
            return 'echo:' + params.get('value');
        }
    }

    private class ThrowingHandler implements ActionOrchestrator.AgentActionHandler {
        public Object run(Map<String, Object> params) {
            throw new CalloutException('upstream unavailable');
        }
    }

    @TestSetup
    static void setup() {
        Grounding_Source__c source = new Grounding_Source__c(
            Name = 'KB', Source_Type__c = 'LightningKnowledge',
            Object_Api_Name__c = 'Account', Max_Records__c = 5, Is_Active__c = true
        );
        insert source;
        insert new Agent_Definition__c(
            Name = 'Test Agent', Agent_Key__c = 'test_v1', Status__c = 'Draft',
            Version__c = 1, Grounding_Source__c = source.Id, Max_Steps__c = 6
        );
        agentId = [SELECT Id FROM Agent_Definition__c LIMIT 1].Id;

        insert new List<Action_Definition__c>{
            new Action_Definition__c(
                Name = 'Read Order', Action_Key__c = 'read_order', Is_Active__c = true,
                Requires_Approval__c = false, Agent_Definition__c = agentId,
                Input_Schema__c = '{"value":"string"}', Output_Schema__c = '{"result":"string"}'
            ),
            new Action_Definition__c(
                Name = 'Issue Refund', Action_Key__c = 'issue_refund', Is_Active__c = true,
                Requires_Approval__c = true, Agent_Definition__c = agentId
            ),
            new Action_Definition__c(
                Name = 'Retired Action', Action_Key__c = 'retired_action', Is_Active__c = false,
                Agent_Definition__c = agentId
            )
        };
    }

    private static ActionOrchestrator.ActionResult call(String key, Boolean approved) {
        return ActionOrchestrator.executeStep(
            key, new Map<String, Object>{ 'value' => 'A-1' }, 'sess-1', approved
        );
    }

    /* ------------------------------------------------------------------ */

    @IsTest
    static void unregisteredHandlerIsReportedNotSwallowed() {
        ActionOrchestrator.ActionResult result = call('read_order', false);

        System.assert(!result.success, 'A missing handler is not a success');
        System.assertEquals('NO_HANDLER_REGISTERED', result.errorCode);
    }

    @IsTest
    static void unknownActionIsRejected() {
        ActionOrchestrator.ActionResult result = call('no_such_action', false);

        System.assert(!result.success);
        System.assertEquals('UNKNOWN_ACTION', result.errorCode,
            'An undeclared action must not run');
    }

    @IsTest
    static void inactiveActionIsRejected() {
        ActionOrchestrator.ActionResult result = call('retired_action', true);

        System.assert(!result.success);
        System.assertEquals('ACTION_INACTIVE', result.errorCode);
    }

    @IsTest
    static void approvalRequiredActionBlocksWithoutApproval() {
        ActionOrchestrator.ActionResult result = call('issue_refund', false);

        System.assert(!result.success, 'An approval-gated action must not execute');
        System.assertEquals('APPROVAL_REQUIRED', result.errorCode);
    }

    @IsTest
    static void approvalRequiredActionRunsWhenApproved() {
        ActionOrchestrator.registerHandler('issue_refund', new EchoHandler());

        Test.startTest();
        ActionOrchestrator.ActionResult result = call('issue_refund', true);
        Test.stopTest();

        System.assert(result.success, 'Approved action should execute: ' + result.errorCode);
        System.assert(result.needsHuman, 'The approved call still records that a human was involved');
        System.assertEquals('echo:A-1', result.data);
    }

    @IsTest
    static void handlerExceptionBecomesActionThrew() {
        ActionOrchestrator.registerHandler('read_order', new ThrowingHandler());

        Test.startTest();
        ActionOrchestrator.ActionResult result = call('read_order', false);
        Test.stopTest();

        System.assert(!result.success, 'A throwing handler is a failure');
        System.assertEquals('ACTION_THREW', result.errorCode);
    }

    @IsTest
    static void everyAttemptIsAuditedIncludingFailures() {
        Test.startTest();
        call('no_such_action', false);
        call('retired_action', true);
        call('issue_refund', false);
        Test.stopTest();

        List<Agent_Action_Audit__c> audits = [
            SELECT Success__c, Error_Code__c, Session_Id__c
            FROM Agent_Action_Audit__c
            WHERE Session_Id__c = 'sess-1'
        ];

        System.assertEquals(3, audits.size(),
            'A failed action is as traceable as a successful one');
        Integer failures = 0;
        for (Agent_Action_Audit__c a : audits) {
            if (!a.Success__c) {
                failures = failures + 1;
                System.assertNotEquals(null, a.Error_Code__, 'Every failure carries an error code');
            }
        }
        System.assertEquals(3, failures);
    }

    @IsTest
    static void nullParametersDoNotThrow() {
        ActionOrchestrator.registerHandler('read_order', new EchoHandler());

        Test.startTest();
        ActionOrchestrator.ActionResult result = ActionOrchestrator.executeStep(
            'read_order', null, 'sess-2', false
        );
        Test.stopTest();

        System.assert(result.success, 'Null params should default to an empty map');
    }

    @IsTest
    static void declaredActionsReturnsOnlyActive() {
        List<Action_Definition__c> declared = ActionOrchestrator.declaredActions(agentId);

        System.assertEquals(2, declared.size(), 'Only the two active actions are declared');
    }
}
