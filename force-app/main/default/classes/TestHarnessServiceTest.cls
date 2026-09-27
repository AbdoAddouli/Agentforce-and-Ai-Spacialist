@IsTest
private class TestHarnessServiceTest {

    /* ------------------------------------------------------------------ */

    @IsTest
    static void passingCaseIsRecorded() {
        Map<String, String> cases = new Map<String, String>{ 'T-1' => 'Order 1001 shipped 3 March' };
        Map<String, String> actual = new Map<String, String>{ 'T-1' => 'Order 1001 shipped 3 March' };

        Test.startTest();
        TestHarnessService.RunSummary summary = TestHarnessService.runSuite(null, cases, actual);
        Test.stopTest();

        System.assertEquals(1, summary.total);
        System.assertEquals(1, summary.passed);
        System.assertEquals(0, summary.failed);
        System.assertEquals(100, summary.passRate);
    }

    @IsTest
    static void failingCaseStatesTheRuleItChecked() {
        Map<String, String> cases = new Map<String, String>{ 'T-2' => 'expected answer' };
        Map<String, String> actual = new Map<String, String>{ 'T-2' => 'actual answer' };

        TestHarnessService.RunSummary summary = TestHarnessService.runSuite(null, cases, actual);

        System.assertEquals(1, summary.failed);
        List<Agent_Test_Run__c> runs = [SELECT Failures__c FROM Agent_Test_Run__c];
        System.assert(runs[0].Failures__c.contains('expected "expected answer"'),
            'The failure text is the useful part, got: ' + runs[0].Failures__c);
    }

    @IsTest
    static void missingResponseIsAFailureNotASkip() {
        Map<String, String> cases = new Map<String, String>{ 'T-3' => 'anything' };

        TestHarnessService.RunSummary summary =
            TestHarnessService.runSuite(null, cases, new Map<String, String>());

        System.assertEquals(1, summary.failed,
            'A case with no response has not passed');
    }

    @IsTest
    static void emptySuiteIsHandled() {
        TestHarnessService.RunSummary summary =
            TestHarnessService.runSuite(null, new Map<String, String>(), null);

        System.assertEquals(0, summary.total);
        System.assertEquals(0, summary.passRate);
    }

    @IsTest
    static void creditsAccruePerCase() {
        Map<String, String> cases = new Map<String, String>{ 'T-4' => 'a' };
        Map<String, String> actual = new Map<String, String>{ 'T-4' => 'a' };

        TestHarnessService.RunSummary summary = TestHarnessService.runSuite(null, cases, actual);

        System.assertEquals(0.8, summary.totalCredits,
            'A suite reports what it cost, not just whether it passed');
    }

    /* ---------------------- revision planning ------------------------- */

    @IsTest
    static void domainWeightsMatchTheBlueprint() {
        Map<String, Decimal> weights = TestHarnessService.domainWeights();

        System.assertEquals(6, weights.size());
        System.assertEquals(35, weights.get('AI Agents'));
        System.assertEquals(20, weights.get('Prompt Engineering'));
        System.assertEquals(20, weights.get('Data 360 Fundamentals'));
        System.assertEquals(10, weights.get('Testing, Deployment & Maintenance'));
        System.assertEquals(10, weights.get('Governance & Observability'));
        System.assertEquals(5, weights.get('Multi-Agent Orchestration'));

        Decimal total = 0;
        for (Decimal w : weights.values()) {
            total += w;
        }
        System.assertEquals(100, total, 'Domain weights must total 100');
    }

    @IsTest
    static void revisionPlanOrdersByPointsLost() {
        Map<String, Integer> failures = new Map<String, Integer>{
            'AI Agents' => 2,
            'Prompt Engineering' => 6,
            'Data 360 Fundamentals' => 1,
            'Testing, Deployment & Maintenance' => 2,
            'Governance & Observability' => 2,
            'Multi-Agent Orchestration' => 1
        };

        Test.startTest();
        String plan = TestHarnessService.buildRevisionPlan(failures);
        Test.stopTest();

        Integer promptIndex = plan.indexOf('Prompt Engineering');
        Integer agentsIndex = plan.indexOf('AI Agents');
        System.assert(promptIndex > 0 && promptIndex < agentsIndex,
            'Revise hardest where points were lost, got: ' + plan);
        System.assert(plan.contains('1.'), 'The plan is ordered');
    }

    @IsTest
    static void revisionPlanHandlesNulls() {
        Test.startTest();
        String plan = TestHarnessService.buildRevisionPlan(null);
        Test.stopTest();

        System.assertNotEquals(null, plan, 'A null failure map still yields a plan');
    }
}
