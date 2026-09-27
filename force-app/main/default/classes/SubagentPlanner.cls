/**
 * Scores candidate subagents and routes to at most one.
 *
 * A routing system that must return a subagent for every request is not
 * routing, it is guessing. ROUTING_THRESHOLD is the escape hatch.
 */
public with sharing class SubagentPlanner {

    /** Below this score, no subagent is confident enough to own the request. */
    public static final Decimal ROUTING_THRESHOLD = 0.60;

    public class Candidate {
        @AuraEnabled public String name;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String rationale;
    }

    public class RoutingDecision {
        @AuraEnabled public String subagentName;
        @AuraEnabled public Decimal score;
        @AuraEnabled public Boolean needsHuman;
        @AuraEnabled public String reason;
        @AuraEnabled public List<Candidate> candidates;
    }

    /* ------------------------------------------------------------------ *
     * Routing
     * ------------------------------------------------------------------ */

    /**
     * Scores each candidate by term overlap with the user message.
     *
     * Deliberately simple and inspectable. The exam and the platform both
     * reward a reason you can read back, not a score you cannot.
     */
    public static RoutingDecision route(String userMessage, List<String> candidateNames) {
        RoutingDecision decision = new RoutingDecision(
            subagentName = null,
            score = 0,
            needsHuman = true,
            reason = 'NO_CANDIDATES',
            candidates = new List<Candidate>()
        );

        if (String.isBlank(userMessage) || candidateNames == null || candidateNames.isEmpty()) {
            return decision;
        }

        String haystack = userMessage.toLowerCase();
        List<Candidate> scored = new List<Candidate>();

        for (String name : candidateNames) {
            if (String.isBlank(name)) {
                continue;
            }
            Decimal score = scoreAgainst(haystack, name);
            scored.add(new Candidate(
                name = name,
                score = score,
                rationale = 'term overlap with "' + name + '"'
            ));
        }

        if (scored.isEmpty()) {
            decision.reason = 'NO_SCORABLE_CANDIDATES';
            return decision;
        }

        scored.sort((Candidate a, Candidate b) => Decimal.compare(b.score, a.score));
        decision.candidates = scored;

        Candidate best = scored[0];
        decision.score = best.score;

        if (best.score < ROUTING_THRESHOLD) {
            // No subagent clears the bar. This is a designed outcome, not an error.
            decision.subagentName = null;
            decision.needsHuman = true;
            decision.reason = 'BELOW_THRESHOLD';
            return decision;
        }

        if (scored.size() > 1 && scored[1].score == best.score) {
            // Two equally confident routes is ambiguity, not a coin flip.
            decision.subagentName = null;
            decision.needsHuman = true;
            decision.reason = 'AMBIGUOUS_TIE';
            return decision;
        }

        decision.subagentName = best.name;
        decision.needsHuman = false;
        decision.reason = 'ROUTED';
        return decision;
    }

    /** Fraction of the subagent name's terms present in the message. */
    private static Decimal scoreAgainst(String haystack, String name) {
        List<String> terms = new List<String>();
        for (String part : name.toLowerCase().split('[\\s_-]+')) {
            if (!String.isBlank(part) && part.length() > 2) {
                terms.add(part);
            }
        }
        if (terms.isEmpty()) {
            return 0;
        }
        Integer hits = 0;
        for (String term : terms) {
            if (haystack.contains(term)) {
                hits = hits + 1;
            }
        }
        return (Decimal) hits / (Decimal) terms.size();
    }

    /* ------------------------------------------------------------------ *
     * Plan construction
     * ------------------------------------------------------------------ */

    /**
     * Builds a step plan for a routed request: locate evidence, reason once,
     * then end. A single reasoning step is the cost control.
     */
    public static List<AgentScriptService.ScriptStep> buildPlan(
        String subagentName,
        String userMessage,
        Id groundingSourceId
    ) {
        List<AgentScriptService.ScriptStep> plan =
            new List<AgentScriptService.ScriptStep>();

        if (String.isBlank(subagentName)) {
            plan.add(new AgentScriptService.ScriptStep(
                type = 'ask',
                subagent = null,
                label = 'no_route',
                payload = 'I am not sure which team handles that. I will pass this to a human.'
            ));
            return plan;
        }

        plan.add(new AgentScriptService.ScriptStep(
            type = 'locate',
            subagent = subagentName,
            label = 'grounding_lookup',
            payload = groundingSourceId
        ));
        plan.add(new AgentScriptService.ScriptStep(
            type = 'reason',
            subagent = subagentName,
            label = 'single_reasoning_pass',
            payload = userMessage
        ));
        plan.add(new AgentScriptService.ScriptStep(
            type = 'end',
            subagent = subagentName,
            label = 'terminate',
            payload = null
        ));
        return plan;
    }
}
