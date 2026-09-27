@IsTest
private class AgentScriptServiceTest {

    private static AgentScriptService.ScriptStep step(String type, String label, Object payload) {
        return new AgentScriptService.ScriptStep(
            type = type, subagent = 'Order Status', label = label, payload = payload
        );
    }

    private static List<AgentScriptService.ScriptStep> happyPlan() {
        return new List<AgentScriptService.ScriptStep>{
            step('locate', 'grounding_lookup', null),
            step('reason', 'single_pass', null),
            step('end', 'terminate', 'Order 1001 shipped on 3 March.')
        };
    }

    /* ------------------------------------------------------------------ */

    @IsTest
    static void planWithEndStepTerminatesNormally() {
        Test.startTest();
        AgentScriptService.ScriptResult result =
            AgentScriptService.run(happyPlan(), 'sess-1', 8);
        Test.stopTest();

        System.assert(result.terminated, 'A plan with an end step terminates');
        System.assertEquals('SCRIPT_COMPLETED', result.terminationReason);
        System.assertEquals(2, result.stepsTaken, 'The end step is not counted as work');
        System.assertEquals('Order 1001 shipped on 3 March.', result.answer);
    }

    @IsTest
    static void loopBoundStopsAnUnboundedPlan() {
        List<AgentScriptService.ScriptStep> looping = new List<AgentScriptService.ScriptStep>();
        for (Integer i = 0; i < 50; i++) {
            looping.add(step('reason', 'pass_' + i, null));
        }

        Test.startTest();
        AgentScriptService.ScriptResult result = AgentScriptService.run(looping, 'sess-2', 5);
        Test.stopTest();

        System.assertEquals(5, result.stepsTaken, 'The hard bound is enforced');
        System.assert(result.terminated, 'Exhausting the budget is still a termination');
        System.assertEquals('STEP_BUDGET_EXHAUSTED', result.terminationReason);
    }

    @IsTest
    static void exhaustedBudgetNeverReturnsTheLastGeneratedAnswer() {
        List<AgentScriptService.ScriptStep> looping = new List<AgentScriptService.ScriptStep>();
        for (Integer i = 0; i < 20; i++) {
            looping.add(step('reason', 'pass_' + i, 'UNVERIFIED ' + i));
        }

        Test.startTest();
        AgentScriptService.ScriptResult result = AgentScriptService.run(looping, 'sess-3', 3);
        Test.stopTest();

        System.assert(
            !String.valueOf(result.answer).contains('UNVERIFIED'),
            'A budget-exhausted run must not present unverified output as an answer: '
            + result.answer
        );
    }

    @IsTest
    static void clarificationStepEndsTheTurnEarly() {
        List<AgentScriptService.ScriptStep> asking = new List<AgentScriptService.ScriptStep>{
            step('locate', 'grounding_lookup', null),
            step('ask', 'need_order_number', 'Which order number?'),
            step('reason', 'never_reached', null)
        };

        Test.startTest();
        AgentScriptService.ScriptResult result = AgentScriptService.run(asking, 'sess-4', 8);
        Test.stopTest();

        System.assertEquals('CLARIFICATION_REQUIRED', result.terminationReason);
        System.assertEquals('Which order number?', result.answer);
        System.assertEquals(2, result.stepsTaken, 'The step after ask is not executed');
    }

    @IsTest
    static void planWithoutEndStepIsReportedAsAPlanBug() {
        List<AgentScriptService.ScriptStep> noEnd = new List<AgentScriptService.ScriptStep>{
            step('locate', 'grounding_lookup', null),
            step('reason', 'single_pass', null)
        };

        Test.startTest();
        AgentScriptService.ScriptResult result = AgentScriptService.run(noEnd, 'sess-5', 8);
        Test.stopTest();

        System.assertEquals('PLAN_EXHAUSTED_WITHOUT_END', result.terminationReason,
            'Running out of plan is a plan defect, not a normal completion');
        System.assert(!String.isBlank(result.answer), 'A fallback answer is still returned');
    }

    @IsTest
    static void creditsAccrueOnlyForCostedSteps() {
        Test.startTest();
        AgentScriptService.ScriptResult result =
            AgentScriptService.run(happyPlan(), 'sess-6', 8);
        Test.stopTest();

        // locate (0) + reason (0.6) + end (0)
        System.assertEquals(0.6, result.creditsUsed, 'Only reasoning is charged here');
    }

    @IsTest
    static void defaultBoundAppliesWhenNoneIsGiven() {
        List<AgentScriptService.ScriptStep> looping = new List<AgentScriptService.ScriptStep>();
        for (Integer i = 0; i < 30; i++) {
            looping.add(step('reason', 'pass_' + i, null));
        }

        Test.startTest();
        AgentScriptService.ScriptResult nullBound =
            AgentScriptService.run(looping, 'sess-7', null);
        AgentScriptService.ScriptResult zeroBound =
            AgentScriptService.run(looping, 'sess-8', 0);
        Test.stopTest();

        System.assertEquals(AgentScriptService.DEFAULT_MAX_STEPS, nullBound.stepsTaken);
        System.assertEquals(AgentScriptService.DEFAULT_MAX_STEPS, zeroBound.stepsTaken,
            'A zero bound falls back to the default rather than looping forever');
    }

    /* ---------------------- termination rules ------------------------- */

    @IsTest
    static void vagueRequestProducesAClarification() {
        System.assertNotEquals(null, AgentScriptService.clarificationFor('hi'),
            'A greeting is not actionable');
        System.assertNotEquals(null, AgentScriptService.clarificationFor('   '),
            'Whitespace is not a request');
        System.assertNotEquals(null, AgentScriptService.clarificationFor('tell me about it'),
            'A request with no recognised entity needs clarification');
    }

    @IsTest
    static void specificRequestNeedsNoClarification() {
        System.assertEquals(null, AgentScriptService.clarificationFor('Where is order 1001?'),
            'A specific order question should proceed');
        System.assertEquals(null, AgentScriptService.clarificationFor('What is the refund policy?'),
            'A specific policy question should proceed');
    }

    @IsTest
    static void escalationTriggersOnWeakOrAbsentRouting() {
        System.assert(AgentScriptService.shouldEscalate(null, 0.9), 'No candidates escalates');
        System.assert(AgentScriptService.shouldEscalate(new List<String>{'Order Status'}, 0.2),
            'Below threshold escalates');
        System.assert(!AgentScriptService.shouldEscalate(new List<String>{'Order Status'}, 0.9),
            'A confident route does not escalate');
    }

    @IsTest
    static void runWritesASessionTrace() {
        Test.startTest();
        AgentScriptService.run(happyPlan(), 'sess-9', 8);
        Test.stopTest();

        List<Agent_Session_Trace__c> traces = [
            SELECT Step_Number__c, Cost_Flex_Credits__c
            FROM Agent_Session_Trace__c
            WHERE Session_Id__c = 'sess-9'
        ];
        System.assert(!traces.isEmpty(), 'A run is always traceable');
    }
}
