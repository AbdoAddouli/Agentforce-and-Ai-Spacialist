@IsTest
private class AgentLifecycleServiceTest {

    private static Id groundingId;

    @TestSetup
    static void setup() {
        Grounding_Source__c source = new Grounding_Source__c(
            Name = 'Policy KB',
            Source_Type__c = 'LightningKnowledge',
            Object_Api_Name__c = 'Account',
            Max_Records__c = 5,
            Relevance_Threshold__c = 0.2,
            Is_Active__c = true
        );
        insert source;
        groundingId = source.Id;
    }

    private static Agent_Definition__c validAgent() {
        return new Agent_Definition__c(
            Name = 'Order Status Agent',
            Agent_Key__c = 'order_status_v1',
            Instructions__c = 'Answer only from retrieved policy. Ask if the order number is missing.',
            Status__c = 'Active',
            Version__c = 1,
            Reviewed_By__c = 'platform.lead@example.com',
            Reviewed_On__c = Date.today(),
            Grounding_Source__c = groundingId,
            Max_Steps__c = 8
        );
    }

    /* ------------------------------------------------------------------ */

    @IsTest
    static void activationRequiresReviewAttribution() {
        Agent_Definition__c agent = validAgent();
        agent.Reviewed_By__c = null;
        agent.Reviewed_On__c = null;

        List<String> errors = AgentLifecycleService.validate(new List<Agent_Definition__c>{ agent });

        System.assertEquals(1, errors.size(), 'Missing reviewer should be exactly one error');
        System.assert(
            errors[0].contains('named reviewer'),
            'Error should name the missing control, got: ' + errors[0]
        );
    }

    @IsTest
    static void activationRequiresGroundingSource() {
        Agent_Definition__c agent = validAgent();
        agent.Grounding_Source__c = null;

        List<String> errors = AgentLifecycleService.validate(new List<Agent_Definition__c>{ agent });

        System.assertEquals(1, errors.size());
        System.assert(errors[0].contains('grounding source'), 'Got: ' + errors[0]);
    }

    @IsTest
    static void activationRequiresPositiveStepBound() {
        Agent_Definition__c agent = validAgent();
        agent.Max_Steps__c = 0;

        List<String> errors = AgentLifecycleService.validate(new List<Agent_Definition__c>{ agent });

        System.assertEquals(1, errors.size());
        System.assert(errors[0].contains('Max_Steps__c'), 'Got: ' + errors[0]);
    }

    @IsTest
    static void draftAgentMayBeIncomplete() {
        Agent_Definition__c draft = new Agent_Definition__c(
            Name = 'Draft',
            Agent_Key__c = 'draft_v1',
            Status__c = 'Draft'
        );

        List<String> errors = AgentLifecycleService.validate(new List<Agent_Definition__c>{ draft });

        System.assertEquals(0, errors.size(), 'A draft is allowed to be incomplete');
    }

    @IsTest
    static void validAgentPassesValidation() {
        List<String> errors = AgentLifecycleService.validate(new List<Agent_Definition__c>{ validAgent() });
        System.assertEquals(0, errors.size(), 'A complete agent should validate: ' + errors);
    }

    @IsTest
    static void triggerRejectsActivationWithoutReviewer() {
        Agent_Definition__c agent = validAgent();
        agent.Reviewed_By__c = null;

        try {
            insert agent;
            System.assert(false, 'Insert should have failed validation');
        } catch (DmlException e) {
            System.assert(
                String.valueOf(e.getMessage()).contains('named reviewer'),
                'Trigger should surface the service error, got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void stepBudgetIsExhaustedAtTheBound() {
        Agent_Definition__c agent = validAgent();

        System.assert(!AgentLifecycleService.stepBudgetExhausted(agent, 7), '7 of 8 is within budget');
        System.assert(AgentLifecycleService.stepBudgetExhausted(agent, 8), '8 of 8 is exhausted');
        System.assert(AgentLifecycleService.stepBudgetExhausted(agent, 9), 'Past the bound is exhausted');
    }

    @IsTest
    static void instructionChangeBumpsVersionAndReturnsToReview() {
        Agent_Definition__c agent = validAgent();
        insert agent;

        Test.startTest();
        agent.Instructions__c = 'Answer only from retrieved policy. Never quote a figure that is not in a record.';
        update agent;
        Test.stopTest();

        Agent_Definition__c reloaded = [
            SELECT Version__c, Status__c FROM Agent_Definition__c WHERE Id = :agent.Id
        ];
        System.assertEquals(2, reloaded.Version__c, 'An instruction change is a version change');
        System.assertEquals('In Review', reloaded.Status__c, 'A changed agent returns to review');
    }

    @IsTest
    static void activateAndRetireRoundTrip() {
        Agent_Definition__c draft = new Agent_Definition__c(
            Name = 'Returns',
            Agent_Key__c = 'returns_v1',
            Instructions__c = 'Quote only recorded figures.',
            Status__c = 'Draft',
            Version__c = 1,
            Grounding_Source__c = groundingId,
            Max_Steps__c = 6
        );
        insert draft;

        Test.startTest();
        AgentLifecycleService.activate(draft.Id);
        Test.stopTest();

        System.assertEquals(
            'Active',
            [SELECT Status__c FROM Agent_Definition__c WHERE Id = :draft.Id].Status__c
        );

        AgentLifecycleService.retire(draft.Id);
        System.assertEquals(
            'Retired',
            [SELECT Status__c FROM Agent_Definition__c WHERE Id = :draft.Id].Status__c
        );
    }

    @IsTest
    static void findActiveByKeyIgnoresRetiredAgents() {
        Agent_Definition__c draft = new Agent_Definition__c(
            Name = 'Shipping',
            Agent_Key__c = 'shipping_v1',
            Instructions__c = 'Quote only recorded delivery dates.',
            Status__c = 'Draft',
            Version__c = 1,
            Grounding_Source__c = groundingId,
            Max_Steps__c = 5
        );
        insert draft;
        AgentLifecycleService.activate(draft.Id);

        Test.startTest();
        Agent_Definition__c found = AgentLifecycleService.findActiveByKey('shipping_v1');
        Agent_Definition__c missing = AgentLifecycleService.findActiveByKey('nope_v1');
        Test.stopTest();

        System.assertNotEquals(null, found, 'An active agent should be findable by key');
        System.assertEquals('shipping_v1', found.Agent_Key__c, 'The wrong agent was returned');
        System.assertEquals(null, missing, 'An unknown key must not return an agent');
    }
}
