/**
 * Per-step credit attribution and budget enforcement.
 *
 * Sits below AgentScriptService so that every step is costed at the point
 * it is taken, not estimated at the end of a session.
 */
public with sharing class TokenUsageService {

    public class UsageResult {
        @AuraEnabled public String sessionId;
        @AuraEnabled public Decimal stepCredits;
        @AuraEnabled public Decimal sessionCredits;
        @AuraEnabled public Decimal budget;
        @AuraEnabled public Boolean budgetExceeded;
        @AuraEnabled public String costCenter;
    }

    /* Unit costs. Flex Credit consumption is priced per step type, so the
     * cheapest saving available is usually fewer reasoning passes, not a
     * smaller model. */
    public static final Decimal REASONING_COST = 0.6;
    public static final Decimal GROUNDING_COST = 0.1;
    public static final Decimal ACTION_COST = 0.2;
    public static final Decimal SUBAGENT_COST = 0.3;

    public static Decimal costForStep(String stepType) {
        if ('reason'.equals(stepType)) {
            return REASONING_COST;
        }
        if ('ground'.equals(stepType)) {
            return GROUNDING_COST;
        }
        if ('act'.equals(stepType)) {
            return ACTION_COST;
        }
        if ('subagent'.equals(stepType)) {
            return SUBAGENT_COST;
        }
        return 0;
    }

    /**
     * Records one step's consumption and reports whether the session is now
     * over its daily budget.
     *
     * @param budget daily budget in Flex Credits; null means unbounded
     */
    public static UsageResult record(
        String sessionId,
        Id agentId,
        String stepType,
        Decimal budget,
        String costCenter
    ) {
        Decimal stepCredits = costForStep(stepType);
        Decimal prior = AuditService.totalCreditsForSession(sessionId);

        AuditService.recordCredits(sessionId, agentId, stepType, stepCredits, costCenter);
        AuditService.writeTrace(
            sessionId,
            1,
            stepType,
            null,
            null,
            null,
            stepCredits,
            'cost ' + stepCredits + ' credit(s) for step ' + stepType
        );

        Decimal sessionCredits = prior + stepCredits;
        return new UsageResult(
            sessionId = sessionId,
            stepCredits = stepCredits,
            sessionCredits = sessionCredits,
            budget = budget,
            budgetExceeded = budget != null && sessionCredits > budget,
            costCenter = costCenter
        );
    }

    /** Running total for one cost center over a window. Feeds the budget alert flow. */
    @AuraEnabled(cacheable=true)
    public static Decimal totalForCostCenter(String costCenter, Integer days) {
        Datetime cutoff = Datetime.now().addDays(days == null ? 30 : days);
        List<Flex_Credit_Ledger__c> rows = [
            SELECT Credits__c
            FROM Flex_Credit_Ledger__c
            WHERE Cost_Center__c = :costCenter AND Recorded_On__c >= :cutoff
        ];
        Decimal total = 0;
        for (Flex_Credit_Ledger__c r : rows) {
            total += r.Credits__c == null ? 0 : r.Credits__c;
        }
        return total;
    }
}
