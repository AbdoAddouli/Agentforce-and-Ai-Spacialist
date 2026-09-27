@IsTest
private class SubagentPlannerTest {

    private static final List<String> CANDIDATES = new List<String>{
        'Order Status', 'Returns And Refunds', 'Product Questions', 'Shipping'
    };

    /* ------------------------------------------------------------------ */

    @IsTest
    static void clearRequestRoutesToTheMatchingSubagent() {
        SubagentPlanner.RoutingDecision decision =
            SubagentPlanner.route('Where is my order 1001?', CANDIDATES);

        System.assertEquals('Order Status', decision.subagentName);
        System.assert(!decision.needsHuman, 'A confident route should not escalate');
        System.assertEquals('ROUTED', decision.reason);
    }

    @IsTest
    static void productQuestionRoutesToProductQuestions() {
        SubagentPlanner.RoutingDecision decision =
            SubagentPlanner.route('Does the warranty cover a cracked screen?', CANDIDATES);

        System.assertEquals('Product Questions', decision.subagentName);
    }

    @IsTest
    static void unrecognisedRequestDeclinesToRoute() {
        SubagentPlanner.RoutingDecision decision =
            SubagentPlanner.route('What is the meaning of life?', CANDIDATES);

        System.assertEquals(null, decision.subagentName,
            'A router that must always answer is guessing');
        System.assert(decision.needsHuman, 'Below threshold escalates by design');
        System.assertEquals('BELOW_THRESHOLD', decision.reason);
    }

    @IsTest
    static void ambiguousTieDeclinesRatherThanCoining() {
        SubagentPlanner.RoutingDecision decision =
            SubagentPlanner.route('order', CANDIDATES);

        System.assert(decision.needsHuman, 'An ambiguous request escalates');
        System.assert(
            'AMBIGUOUS_TIE'.equals(decision.reason) || 'BELOW_THRESHOLD'.equals(decision.reason),
            'Ambiguity has a named reason, got: ' + decision.reason
        );
        System.assertEquals(null, decision.subagentName, 'A tie must not be broken arbitrarily');
    }

    @IsTest
    static void emptyCandidatesEscalate() {
        SubagentPlanner.RoutingDecision decision =
            SubagentPlanner.route('Where is my order 1001?', new List<String>());

        System.assert(decision.needsHuman);
        System.assertEquals('NO_CANDIDATES', decision.reason);
    }

    @IsTest
    static void blankMessageEscalates() {
        SubagentPlanner.RoutingDecision decision = SubagentPlanner.route('  ', CANDIDATES);
        System.assert(decision.needsHuman, 'Nothing to route on is an escalation');
    }

    @IsTest
    static void candidatesAreReturnedWithRationale() {
        SubagentPlanner.RoutingDecision decision =
            SubagentPlanner.route('Where is my order 1001?', CANDIDATES);

        System.assertEquals(CANDIDATES.size(), decision.candidates.size());
        for (SubagentPlanner.Candidate c : decision.candidates) {
            System.assertNotEquals(null, c.rationale, 'A score you cannot explain is a bug');
        }
        System.assert(
            decision.candidates[0].score >= decision.candidates[decision.candidates.size() - 1].score,
            'Candidates should be ordered by descending score'
        );
    }

    @IsTest
    static void thresholdIsTheDocumentedValue() {
        System.assertEquals(0.60, SubagentPlanner.ROUTING_THRESHOLD,
            'The threshold is a documented tuning point');
    }

    /* ---------------------- plan construction -------------------------- */

    @IsTest
    static void planForRoutedRequestEndsExplicitly() {
        List<AgentScriptService.ScriptStep> plan = SubagentPlanner.buildPlan(
            'Order Status', 'Where is my order 1001?', null
        );

        System.assertEquals(3, plan.size(), 'locate, reason, end');
        System.assertEquals('locate', plan[0].type);
        System.assertEquals('reason', plan[1].type);
        System.assertEquals('end', plan[2].type,
            'Every plan must contain an explicit end step');
    }

    @IsTest
    static void planForUnroutedRequestAsksRatherThanReasoning() {
        List<AgentScriptService.ScriptStep> plan =
            SubagentPlanner.buildPlan(null, 'Where is my order 1001?', null);

        System.assertEquals(1, plan.size());
        System.assertEquals('ask', plan[0].type,
            'With no route there is nothing to reason about');
    }

    @IsTest
    static void unroutedPlanTerminatesWithAClarification() {
        List<AgentScriptService.ScriptStep> plan =
            SubagentPlanner.buildPlan(null, 'Where is my order 1001?', null);

        Test.startTest();
        AgentScriptService.ScriptResult result = AgentScriptService.run(plan, 'sess-t1', 8);
        Test.stopTest();

        System.assert(result.terminated);
        System.assertEquals('CLARIFICATION_REQUIRED', result.terminationReason);
    }
}
