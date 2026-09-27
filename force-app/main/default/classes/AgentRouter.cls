/**
 * The agent's front door: route, plan, execute, audit.
 *
 * This is the single place a session's lifecycle is decided, so termination
 * and escalation have exactly one implementation.
 */
public with sharing class AgentRouter {

    public class SessionResult {
        @AuraEnabled public String sessionId;
        @AuraEnabled public String answer;
        @AuraEnabled public String outcome;          // Answered | Escalated | Refused | Failed
        @AuraEnabled public String subagentName;
        @AuraEnabled public Integer stepsTaken;
        @AuraEnabled public Decimal creditsUsed;
        @AuraEnabled public String terminationReason;
        @AuraEnabled public Boolean needsHuman;
    }

    /* ------------------------------------------------------------------ *
     * Handle one turn
     * ------------------------------------------------------------------ */

    /**
     * Routes a user message to a subagent, runs the plan, and records the
     * turn. Never throws: every path returns a SessionResult.
     */
    public static SessionResult handleTurn(
        Id agentId,
        String sessionId,
        String userMessage
    ) {
        SessionResult result = new SessionResult(
            sessionId = sessionId,
            answer = null,
            outcome = 'Failed',
            subagentName = null,
            stepsTaken = 0,
            creditsUsed = 0,
            terminationReason = null,
            needsHuman = false
        );

        try {
            Agent_Definition__c agent = loadAgent(agentId);
            if (agent == null) {
                result.answer = 'That agent is not available.';
                result.outcome = 'Refused';
                result.terminationReason = 'AGENT_NOT_ACTIVE';
                return result;
            }

            // 1. Vagueness: ask, do not guess.
            String clarification = AgentScriptService.clarificationFor(userMessage);
            if (clarification != null) {
                result.answer = clarification;
                result.outcome = 'Refused';
                result.needsHuman = true;
                result.terminationReason = 'CLARIFICATION_REQUIRED';
                AuditService.logInteraction(
                    sessionId, agentId, 1, userMessage, clarification, result.outcome, 0
                );
                return result;
            }

            // 2. Routing, with a decline path.
            List<String> candidates = new List<String>{
                'Order Status', 'Returns And Refunds', 'Product Questions', 'Shipping'
            };
            SubagentPlanner.RoutingDecision decision =
                SubagentPlanner.route(userMessage, candidates);

            if (decision.needsHuman) {
                result.answer = 'I am not confident which team handles that. '
                    + 'I have passed this to a human.';
                result.outcome = 'Escalated';
                result.needsHuman = true;
                result.subagentName = null;
                result.terminationReason = decision.reason;
                result.creditsUsed = 0.2;
                AuditService.writeTrace(
                    sessionId, 1, 'Escalate', null, 0, null, result.creditsUsed,
                    'routing declined: ' + decision.reason
                );
                AuditService.recordCredits(sessionId, agentId, 'Escalate', result.creditsUsed, 'Support');
                AuditService.logInteraction(
                    sessionId, agentId, 1, userMessage, result.answer, result.outcome, result.creditsUsed
                );
                return result;
            }

            // 3. Plan and execute.
            List<AgentScriptService.ScriptStep> plan = SubagentPlanner.buildPlan(
                decision.subagentName, userMessage, agent.Grounding_Source__c
            );

            if (AgentLifecycleService.stepBudgetExhausted(agent, 0)) {
                result.answer = 'That request needs a human agent.';
                result.outcome = 'Escalated';
                result.needsHuman = true;
                result.terminationReason = 'STEP_BUDGET_EXHAUSTED';
                return result;
            }

            AgentScriptService.ScriptResult run = AgentScriptService.run(
                plan, sessionId, (Integer) agent.Max_Steps__c
            );

            result.answer = run.answer;
            result.subagentName = decision.subagentName;
            result.stepsTaken = run.stepsTaken;
            result.creditsUsed = run.creditsUsed;
            result.terminationReason = run.terminationReason;
            result.outcome = run.answer == null ? 'Failed' : 'Answered';

            AuditService.recordCredits(
                sessionId, agentId, 'Reason', run.creditsUsed, 'Support'
            );
            AuditService.logInteraction(
                sessionId, agentId, 1, userMessage, run.answer, result.outcome, run.creditsUsed
            );
        } catch (Exception e) {
            // A failed session is still a logged session.
            result.outcome = 'Failed';
            result.needsHuman = true;
            result.terminationReason = 'UNHANDLED_EXCEPTION';
            result.answer = 'Something went wrong. I have passed this to a human.';
            try {
                AuditService.writeTrace(
                    sessionId, 0, 'Escalate', null, 0, null, 0, 'unhandled: ' + e.getMessage()
                );
            } catch (Exception ignore) {
            }
        }
        return result;
    }

    private static Agent_Definition__c loadAgent(Id agentId) {
        if (agentId == null) {
            return null;
        }
        List<Agent_Definition__c> found = [
            SELECT Id, Name, Agent_Key__c, Instructions__c, Status__c,
                   Max_Steps__c, Grounding_Source__c
            FROM Agent_Definition__c
            WHERE Id = :agentId AND Status__c = 'Active'
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }
}
