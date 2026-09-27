/**
 * Hybrid Agent Script execution: deterministic steps, one reasoning step,
 * a hard loop bound, and explicit termination.
 *
 * The two failure modes this class exists to prevent:
 *   - unbounded loops, which burn credits and never terminate
 *   - a "final" answer generated after the budget is already spent
 */
public with sharing class AgentScriptService {

    public class ScriptResult {
        @AuraEnabled public String answer;
        @AuraEnabled public Integer stepsTaken;
        @AuraEnabled public Boolean terminated;
        @AuraEnabled public String terminationReason;
        @AuraEnabled public Decimal creditsUsed;
        @AuraEnabled public String sessionId;
    }

    public class ScriptStep {
        public String type;      // 'locate' | 'reason' | 'act' | 'ask' | 'end'
        public String subagent;
        public String label;
        public Object payload;
    }

    /** Default hard bound. Overridable per agent via Max_Steps__c. */
    public static final Integer DEFAULT_MAX_STEPS = 8;

    private static final Decimal REASONING_COST = 0.6;
    private static final Decimal ACT_COST = 0.2;
    private static final Decimal ASK_COST = 0.0;

    /* ------------------------------------------------------------------ *
     * Execution
     * ------------------------------------------------------------------ */

    /**
     * Runs a step plan to termination.
     *
     * @param steps      ordered plan produced by the planner
     * @param sessionId  session id for trace and audit attribution
     * @param maxSteps   hard loop bound
     */
    public static ScriptResult run(
        List<ScriptStep> steps,
        String sessionId,
        Integer maxSteps
    ) {
        Integer bound = maxSteps == null || maxSteps <= 0 ? DEFAULT_MAX_STEPS : maxSteps;
        ScriptResult result = new ScriptResult(
            answer = null,
            stepsTaken = 0,
            terminated = false,
            terminationReason = null,
            creditsUsed = 0,
            sessionId = sessionId
        );

        StringBuffer trace = new StringBuffer();

        for (ScriptStep step : steps) {
            if (result.stepsTaken >= bound) {
                result.terminated = true;
                result.terminationReason = 'STEP_BUDGET_EXHAUSTED';
                break;
            }

            // 'end' is the only way a run finishes normally.
            if ('end'.equals(step.type)) {
                result.terminated = true;
                result.terminationReason = 'SCRIPT_COMPLETED';
                result.answer = (String) step.payload;
                break;
            }

            result.stepsTaken = result.stepsTaken + 1;
            result.creditsUsed += costOf(step.type);
            trace.append(step.type).append('|').append(step.label).append('\n');

            // 'ask' ends the turn early with a clarification request.
            if ('ask'.equals(step.type)) {
                result.terminated = true;
                result.terminationReason = 'CLARIFICATION_REQUIRED';
                result.answer = (String) step.payload;
                break;
            }
        }

        // Reaching the end of the plan without an 'end' step is a bug in the
        // plan, not a normal outcome. Say so rather than returning nothing.
        if (!result.terminated) {
            result.terminationReason = 'PLAN_EXHAUSTED_WITHOUT_END';
        }
        if (String.isBlank(result.answer)) {
            result.answer = 'I could not complete that request from the data I have.';
        }

        AuditService.writeTrace(
            sessionId,
            result.stepsTaken,
            'Reason',
            null,
            null,
            null,
            result.creditsUsed,
            trace.toString()
        );
        return result;
    }

    /* ------------------------------------------------------------------ *
     * Termination rules
     * ------------------------------------------------------------------ */

    /**
     * Vague request: ask, do not guess.
     * Returns the clarifying question, or null when the request is specific
     * enough to proceed.
     */
    public static String clarificationFor(String userMessage) {
        if (String.isBlank(userMessage) || userMessage.trim().length() < 4) {
            return 'What would you like me to look up?';
        }
        String lower = userMessage.toLowerCase();
        if (!lower.contains('order')
            && !lower.contains('return')
            && !lower.contains('refund')
            && !lower.contains('policy')
            && !lower.contains('ship')) {
            return 'Which order or policy are you asking about?';
        }
        return null;
    }

    /**
     * Ambiguous request: escalate rather than choose an interpretation.
     */
    public static Boolean shouldEscalate(List<String> candidateSubagents, Decimal topScore) {
        if (candidateSubagents == null || candidateSubagents.isEmpty()) {
            return true;
        }
        if (topScore == null || topScore < SubagentPlanner.ROUTING_THRESHOLD) {
            return true;
        }
        return false;
    }

    private static Decimal costOf(String stepType) {
        if ('reason'.equals(stepType)) {
            return REASONING_COST;
        }
        if ('act'.equals(stepType)) {
            return ACT_COST;
        }
        return ASK_COST;
    }
}
