/**
 * Entry point for every agent lifecycle operation.
 *
 * All business logic lives here rather than in Agent_DefinitionTrigger so it
 * is unit-testable without DML and without trigger context.
 */
public with sharing class AgentLifecycleService {

    /** Thrown when a definition is used in a way its configuration forbids. */
    public class AgentConfigException extends Exception {}

    public class ValidationResult {
        @AuraEnabled public Boolean isValid;
        @AuraEnabled public List<String> errors;
    }

    /* ------------------------------------------------------------------ *
     * Validation
     * ------------------------------------------------------------------ */

    /**
     * Invariants that must hold before an agent may become Active.
     * Called from the trigger on before insert and before update.
     */
    public static List<String> validate(List<Agent_Definition__c> agents) {
        List<String> errors = new List<String>();
        for (Agent_Definition__c a : agents) {
            errors.addAll(validateOne(a));
        }
        return errors;
    }

    private static List<String> validateOne(Agent_Definition__c a) {
        List<String> errors = new List<String>();

        if (a.Status__c == 'Active') {
            if (String.isBlank(a.Instructions__c)) {
                errors.add(a.Agent_Key__c + ': instructions are required before activation.');
            }
            if (a.Reviewed_On__c == null || String.isBlank(a.Reviewed_By__c)) {
                errors.add(a.Agent_Key__c + ': an active agent needs a named reviewer and a review date.');
            }
            if (a.Grounding_Source__c == null) {
                errors.add(a.Agent_Key__c + ': an active agent needs a grounding source.');
            }
            if (a.Max_Steps__c == null || a.Max_Steps__c <= 0) {
                errors.add(a.Agent_Key__c + ': an active agent needs a positive Max_Steps__c bound.');
            }
        }
        return errors;
    }

    /* ------------------------------------------------------------------ *
     * Step bounds
     * ------------------------------------------------------------------ */

    /** True when the step budget is exhausted. The caller must then escalate. */
    public static Boolean stepBudgetExhausted(Agent_Definition__c agent, Integer stepsTaken) {
        if (agent == null || agent.Max_Steps__c == null) {
            return false;
        }
        return stepsTaken >= agent.Max_Steps__c;
    }

    /* ------------------------------------------------------------------ *
     * Lifecycle transitions
     * ------------------------------------------------------------------ */

    public static void activate(Id agentId) {
        Agent_Definition__c a = [
            SELECT Id, Status__c, Instructions__c, Reviewed_By__c, Reviewed_On__c,
                   Grounding_Source__c, Max_Steps__c
            FROM Agent_Definition__c
            WHERE Id = :agentId
            LIMIT 1
        ];
        if (a == null) {
            throw new AgentConfigException('Agent not found: ' + agentId);
        }
        a.Status__c = 'Active';
        List<String> errors = validateOne(a);
        if (!errors.isEmpty()) {
            throw new AgentConfigException(String.join(errors, ' | '));
        }
        update a;
    }

    public static void retire(Id agentId) {
        Agent_Definition__c a = new Agent_Definition__c(
            Id = agentId,
            Status__c = 'Retired'
        );
        update a;
    }

    /* ------------------------------------------------------------------ *
     * Versioning
     * ------------------------------------------------------------------ */

    /**
     * Bumps the version when the instructions change, so a behavioural
     * regression can be diffed against the release that caused it.
     */
    public static void versionIfInstructionsChanged(
        Map<Id, String> oldInstructions,
        List<Agent_Definition__c> newAgents
    ) {
        List<Agent_Definition__c> toUpdate = new List<Agent_Definition__c>();
        for (Agent_Definition__c a : newAgents) {
            String oldText = oldInstructions.get(a.Id);
            if (oldText != null && oldText != a.Instructions__c) {
                a.Version__c = (a.Version__c == null ? 1 : a.Version__c) + 1;
                a.Status__c = 'In Review';
                toUpdate.add(a);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /* ------------------------------------------------------------------ *
     * Lookup
     * ------------------------------------------------------------------ */

    public static List<Agent_Definition__c> activeAgents() {
        return [
            SELECT Id, Name, Agent_Key__c, Instructions__c, Version__c,
                   Max_Steps__c, Grounding_Source__c
            FROM Agent_Definition__c
            WHERE Status__c = 'Active'
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Agent_Definition__c findActiveByKey(String agentKey) {
        List<Agent_Definition__c> found = [
            SELECT Id, Name, Agent_Key__c, Instructions__c, Version__c,
                   Max_Steps__c, Grounding_Source__c
            FROM Agent_Definition__c
            WHERE Agent_Key__c = :agentKey AND Status__c = 'Active'
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }
}
