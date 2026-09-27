@IsTest
private class AgentRouterTest {

    private static Id agentId;

    @TestSetup
    static void setup() {
        insert new Grounding_Source__c(
            Name = 'Support KB', Source_Type__c = 'LightningKnowledge',
            Object_Api_Name__c = 'Account', Max_Records__c = 5,
            Relevance_Threshold__c = 0.2, Is_Active__c = true
        );
        Id sourceId = [SELECT Id FROM Grounding_Source__c LIMIT 1].Id;

        insert new Agent_Definition__c(
            Name = 'Support Agent', Agent_Key__c = 'support_v1', Status__c = 'Draft',
            Instructions__c = 'Answer only from retrieved records.',
            Version__c = 1, Reviewed_By__c = 'lead@example.com', Reviewed_On__c = Date.today(),
            Grounding_Source__c = sourceId, Max_Steps__c = 8
        );
        agentId = [SELECT Id FROM Agent_Definition__c LIMIT 1].Id;
        AgentLifecycleService.activate(agentId);
    }

    /* ------------------------------------------------------------------ */

    @IsTest
    static void specificRequestIsAnsweredAndTraced() {
        Test.startTest();
        AgentRouter.SessionResult result =
            AgentRouter.handleTurn(agentId, 'r-1', 'Where is my order 1001?');
        Test.stopTest();

        System.assertEquals('Answered', result.outcome, 'Got: ' + result.terminationReason);
        System.assertEquals('Order Status', result.subagentName);
        System.assert(!result.needsHuman, 'A confident route should not escalate');
    }

    @IsTest
    static void vagueRequestIsRefusedNotGuessed() {
        Test.startTest();
        AgentRouter.SessionResult result = AgentRouter.handleTurn(agentId, 'r-2', 'hi');
        Test.stopTest();

        System.assertEquals('Refused', result.outcome);
        System.assertEquals('CLARIFICATION_REQUIRED', result.terminationReason);
        System.assert(result.needsHuman);
    }

    @IsTest
    static void unroutableRequestEscalates() {
        Test.startTest();
        AgentRouter.SessionResult result =
            AgentRouter.handleTurn(agentId, 'r-3', 'What is the meaning of life?');
        Test.stopTest();

        System.assertEquals('Escalated', result.outcome, 'The decline path must be reachable');
        System.assertEquals(null, result.subagentName);
        System.assert(result.needsHuman);
    }

    @IsTest
    static void inactiveAgentIsRefusedNotRun() {
        AgentLifecycleService.retire(agentId);

        Test.startTest();
        AgentRouter.SessionResult result =
            AgentRouter.handleTurn(agentId, 'r-4', 'Where is my order 1001?');
        Test.stopTest();

        System.assertEquals('Refused', result.outcome);
        System.assertEquals('AGENT_NOT_ACTIVE', result.terminationReason);
    }

    @IsTest
    static void nullAgentDoesNotThrow() {
        Test.startTest();
        AgentRouter.SessionResult result =
            AgentRouter.handleTurn(null, 'r-5', 'Where is my order 1001?');
        Test.stopTest();

        System.assertEquals('Refused', result.outcome);
        System.assertEquals('AGENT_NOT_ACTIVE', result.terminationReason);
    }

    @IsTest
    static void everyTurnIsLoggedAndAttributed() {
        Test.startTest();
        AgentRouter.handleTurn(agentId, 'r-6', 'Where is my order 1001?');
        AgentRouter.handleTurn(agentId, 'r-7', 'hi');
        Test.stopTest();

        List<Agent_Interaction_Log__c> logs = [
            SELECT Id, Outcome__c, Credits_Used__c
            FROM Agent_Interaction_Log__c
            WHERE Session_Id__c IN ('r-6', 'r-7')
        ];
        System.assertEquals(2, logs.size(), 'Both turns are logged, whatever the outcome');
    }

    @IsTest
    static void escalationStillCostsAndIsStillTraced() {
        Test.startTest();
        AgentRouter.SessionResult result =
            AgentRouter.handleTurn(agentId, 'r-8', 'What is the meaning of life?');
        Test.stopTest();

        System.assert(result.creditsUsed > 0, 'A declined route still consumes a step');
        System.assert(
            !AuditService.traceFor('r-8').isEmpty(),
            'An escalation is a traceable event'
        );
    }

    @IsTest
    static void sessionTerminatesWithinTheDeclaredStepBound() {
        Test.startTest();
        AgentRouter.SessionResult result =
            AgentRouter.handleTurn(agentId, 'r-9', 'Where is my order 1001?');
        Test.stopTest();

        System.assert(result.stepsTaken <= 8, 'The declared bound of 8 was respected');
    }
}
