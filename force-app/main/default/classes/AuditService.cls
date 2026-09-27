/**
 * Every write to the observability objects goes through here.
 *
 * A session that cannot be reconstructed is an agent that cannot be fixed,
 * so the four objects this writes are the product, not a log.
 */
public with sharing class AuditService {

    /* ------------------------------------------------------------------ *
     * Trace
     * ------------------------------------------------------------------ */

    public static void writeTrace(
        String sessionId,
        Integer stepNumber,
        String stepType,
        String subagentName,
        Integer recordsRetrieved,
        String actionName,
        Decimal credits,
        String detail
    ) {
        try {
            insert new Agent_Session_Trace__c(
                Name = 'TRC-' + sessionId + '-' + String.valueOf(stepNumber),
                Session_Id__c = sessionId,
                Step_Number__c = stepNumber,
                Step_Type__c = stepType,
                Subagent_Name__c = subagentName,
                Records_Retrieved__c = recordsRetrieved,
                Action_Name__c = actionName,
                Cost_Flex_Credits__c = credits,
                Detail__c = truncate(detail, 32768)
            );
        } catch (Exception e) {
            // Observability must never break the run it observes.
        }
    }

    /* ------------------------------------------------------------------ *
     * Interaction
     * ------------------------------------------------------------------ */

    public static void logInteraction(
        String sessionId,
        Id agentId,
        Integer turnNumber,
        String userMessage,
        String agentResponse,
        String outcome,
        Decimal creditsUsed
    ) {
        try {
            insert new Agent_Interaction_Log__c(
                Name = 'INT-' + sessionId + '-' + String.valueOf(turnNumber),
                Session_Id__c = sessionId,
                Agent_Definition__c = agentId,
                Turn_Number__c = turnNumber,
                User_Message__c = truncate(userMessage, 32768),
                Agent_Response__c = truncate(agentResponse, 32768),
                Outcome__c = outcome,
                Credits_Used__c = creditsUsed
            );
        } catch (Exception e) {
        }
    }

    /* ------------------------------------------------------------------ *
     * Credits
     * ------------------------------------------------------------------ */

    /**
     * Records consumption against a cost center so budget alerts have
     * something to sum.
     */
    public static void recordCredits(
        String sessionId,
        Id agentId,
        String stepType,
        Decimal credits,
        String costCenter
    ) {
        try {
            insert new Flex_Credit_Ledger__c(
                Name = 'CRD-' + sessionId + '-' + String.valueOf(Datetime.now().getTime()),
                Session_Id__c = sessionId,
                Agent_Definition__c = agentId,
                Step_Type__c = stepType,
                Credits__c = credits,
                Cost_Center__c = costCenter,
                Recorded_On__c = Datetime.now()
            );
        } catch (Exception e) {
        }
    }

    /* ------------------------------------------------------------------ *
     * Token accounting
     * ------------------------------------------------------------------ */

    public static void recordTokens(
        String sessionId,
        Id agentId,
        Integer inputTokens,
        Integer outputTokens
    ) {
        try {
            insert new Token_Usage__c(
                Name = 'TOK-' + sessionId + '-' + String.valueOf(Datetime.now().getTime()),
                Session_Id__c = sessionId,
                Agent_Definition__c = agentId,
                Input_Tokens__c = inputTokens,
                Output_Tokens__c = outputTokens,
                Total_Tokens__c = (inputTokens == null ? 0 : inputTokens)
                    + (outputTokens == null ? 0 : outputTokens),
                Recorded_On__c = Datetime.now()
            );
        } catch (Exception e) {
        }
    }

    /* ------------------------------------------------------------------ *
     * Queries
     * ------------------------------------------------------------------ */

    /** Reconstructs a session. This is the query that makes debugging possible. */
    @AuraEnabled(cacheable=true)
    public static List<Agent_Session_Trace__c> traceFor(String sessionId) {
        return [
            SELECT Id, Step_Number__c, Step_Type__c, Subagent_Name__c,
                   Records_Retrieved__c, Action_Name__c, Cost_Flex_Credits__c, Detail__c
            FROM Agent_Session_Trace__c
            WHERE Session_Id__c = :sessionId
            ORDER BY Step_Number__c ASC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Decimal totalCreditsForSession(String sessionId) {
        List<Flex_Credit_Ledger__c> rows = [
            SELECT Credits__c
            FROM Flex_Credit_Ledger__c
            WHERE Session_Id__c = :sessionId
        ];
        Decimal total = 0;
        for (Flex_Credit_Ledger__c r : rows) {
            total += r.Credits__c == null ? 0 : r.Credits__c;
        }
        return total;
    }

    /** Failed actions only. This is the actionable slice of the audit log. */
    @AuraEnabled(cacheable=true)
    public static List<Agent_Action_Audit__c> failedActions(Integer recentDays) {
        Datetime cutoff = Datetime.now().addDays(recentDays == null ? 7 : recentDays);
        return [
            SELECT Id, Name, Session_Id__c, Action_Definition__c,
                   Error_Code__c, Parameters_Json__c, Duration_Ms__c
            FROM Agent_Action_Audit__c
            WHERE Success__c = false AND CreatedDate >= :cutoff
            ORDER BY CreatedDate DESC
        ];
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }
}
