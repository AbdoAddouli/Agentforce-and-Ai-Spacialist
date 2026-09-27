/**
 * Batch evaluation harness.
 *
 * A test case is only useful if it states the rule it checks, so every
 * result carries the failures as text. A pass/fail flag with no reason is
 * the thing this class exists to avoid.
 */
public with sharing class TestHarnessService {

    public class CaseResult {
        @AuraEnabled public String caseId;
        @AuraEnabled public Boolean passed;
        @AuraEnabled public Integer assertions;
        @AuraEnabled public Integer failures;
        @AuraEnabled public Decimal creditsUsed;
        @AuraEnabled public List<String> failureDetail;
    }

    public class RunSummary {
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer passed;
        @AuraEnabled public Integer failed;
        @AuraEnabled public Decimal passRate;
        @AuraEnabled public Decimal totalCredits;
    }

    /* ------------------------------------------------------------------ *
     * Run
     * ------------------------------------------------------------------ */

    /**
     * Executes a suite of Agent_Interaction_Log__c style cases and writes
     * Agent_Test_Run__c for each.
     *
     * @param agentId agent under test
     * @param cases   map of caseId to expected-answer text
     */
    public static RunSummary runSuite(
        Id agentId,
        Map<String, String> cases,
        Map<String, String> actualResponses
    ) {
        List<CaseResult> results = new List<CaseResult>();
        RunSummary summary = new RunSummary(
            total = 0, passed = 0, failed = 0, passRate = 0, totalCredits = 0
        );

        if (cases == null || cases.isEmpty()) {
            return summary;
        }

        for (String caseId : cases.keySet()) {
            String expected = cases.get(caseId);
            String actual = actualResponses == null ? null : actualResponses.get(caseId);

            List<String> failures = new List<String>();
            if (String.isBlank(actual)) {
                failures.add('no response recorded for ' + caseId);
            } else if (!String.valueOf(expected).equalsIgnoreCase(String.valueOf(actual))) {
                failures.add(
                    'expected "' + expected + '" but received "' + actual + '"'
                );
            }

            // Never assert on grounding success. A legitimately empty result
            // is correct behaviour, and a test that fails on it teaches the
            // wrong lesson.
            Decimal credits = actual == null ? 0 : 0.8;

            CaseResult result = new CaseResult(
                caseId = caseId,
                passed = failures.isEmpty(),
                assertions = 1,
                failures = failures.size(),
                creditsUsed = credits,
                failureDetail = failures
            );
            results.add(result);
            summary.totalCredits += credits;
            persist(agentId, result, expected);
        }

        summary.total = results.size();
        for (CaseResult r : results) {
            if (r.passed) {
                summary.passed = summary.passed + 1;
            } else {
                summary.failed = summary.failed + 1;
            }
        }
        summary.passRate = summary.total == 0
            ? 0
            : ((Decimal) summary.passed / (Decimal) summary.total) * 100;
        return summary;
    }

    /**
     * Domain weights from the published exam blueprint, used to order the
     * revision queue after a failed run.
     */
    public static Map<String, Decimal> domainWeights() {
        return new Map<String, Decimal>{
            'AI Agents' => 35,
            'Prompt Engineering' => 20,
            'Data 360 Fundamentals' => 20,
            'Testing, Deployment & Maintenance' => 10,
            'Governance & Observability' => 10,
            'Multi-Agent Orchestration' => 5
        };
    }

    /** Revise hardest where points were lost, not where the syllabus starts. */
    @AuraEnabled(cacheable=false)
    public static String buildRevisionPlan(Map<String, Integer> failuresByDomain) {
        Map<String, Decimal> weights = domainWeights();
        List<String> ordered = new List<String>();
        List<Integer> counts = new List<Integer>();

        for (String domain : weights.keySet()) {
            Integer missed = failuresByDomain == null ? 0 : failuresByDomain.get(domain);
            Decimal pointsLost = (Decimal) (missed == null ? 0 : missed) / 60 * 100;
            ordered.add(domain);
            counts.add((Integer) pointsLost);
        }

        // Insertion sort: few domains, and stable output matters for a plan.
        for (Integer i = 1; i < counts.size(); i++) {
            Integer key = counts[i];
            String keyDomain = ordered[i];
            Integer j = i - 1;
            while (j >= 0 && counts[j] < key) {
                counts[j + 1] = counts[j];
                ordered[j + 1] = ordered[j];
                j = j - 1;
            }
            counts[j + 1] = key;
            ordered[j + 1] = keyDomain;
        }

        String plan = 'Revise in this order:\n';
        for (Integer i = 0; i < ordered.size(); i++) {
            plan += (i + 1) + '. ' + ordered[i] + ' (' + counts[i] + '% of the paper)\n';
        }
        return plan;
    }

    private static void persist(Id agentId, CaseResult result, String expected) {
        try {
            insert new Agent_Test_Run__c(
                Name = 'RUN-' + result.caseId,
                Case_Id__c = result.caseId,
                Category__c = 'Functional',
                Answer__c = expected,
                Passed__c = result.passed,
                Failures__c = String.join(result.failureDetail, ' | '),
                Credits_Used__c = result.creditsUsed,
                Run_On__c = Datetime.now()
            );
        } catch (Exception e) {
        }
    }
}
