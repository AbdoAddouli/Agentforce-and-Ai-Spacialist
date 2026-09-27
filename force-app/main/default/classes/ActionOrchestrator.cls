/**
 * The single sanctioned path for taking an action.
 *
 * Every call is validated against its Action_Definition__c, gated on the
 * approval requirement, and written to Agent_Action_Audit__c regardless of
 * outcome. The audit record is written in the finally-equivalent path so a
 * failure is as traceable as a success.
 */
public with sharing class ActionOrchestrator {

    public class ActionResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Boolean needsHuman;
        @AuraEnabled public String actionKey;
        @AuraEnabled public Object data;
        @AuraEnabled public String errorCode;
        @AuraEnabled public Decimal durationMs;
    }

    /** Pluggable business logic for a declared action. */
    public interface AgentActionHandler {
        Object run(Map<String, Object> params);
    }

    private static final Map<String, AgentActionHandler> HANDLERS =
        new Map<String, AgentActionHandler>();

    public static void registerHandler(String actionKey, AgentActionHandler handler) {
        HANDLERS.put(actionKey, handler);
    }

    /* ------------------------------------------------------------------ *
     * Execution
     * ------------------------------------------------------------------ */

    /**
     * Executes one action and records the attempt.
     *
     * @param actionKey   key declared on Action_Definition__c
     * @param params      input parameters
     * @param sessionId   session to attribute the audit record to
     * @param needsApproval set by the caller when a human has already approved
     */
    public static ActionResult executeStep(
        String actionKey,
        Map<String, Object> params,
        String sessionId,
        Boolean needsApproval
    ) {
        Datetime started = Datetime.now();
        ActionResult result = new ActionResult(
            success = false,
            needsHuman = Boolean.TRUE.equals(needsApproval),
            actionKey = actionKey,
            data = null,
            errorCode = null,
            durationMs = 0
        );

        Action_Definition__c def = lookupDefinition(actionKey);

        if (def == null) {
            result.errorCode = 'UNKNOWN_ACTION';
        } else if (!def.Is_Active__c) {
            result.errorCode = 'ACTION_INACTIVE';
        } else if (def.Requires_Approval__c && !Boolean.TRUE.equals(needsApproval)) {
            result.errorCode = 'APPROVAL_REQUIRED';
        } else {
            AgentActionHandler handler = HANDLERS.get(actionKey);
            if (handler == null) {
                result.errorCode = 'NO_HANDLER_REGISTERED';
            } else {
                try {
                    result.data = handler.run(params == null ? new Map<String, Object>() : params);
                    result.success = true;
                } catch (Exception e) {
                    result.errorCode = 'ACTION_THREW';
                }
            }
        }

        result.durationMs = decimal.valueOf(
            String.valueOf((Datetime.now() - started).getTime())
        );
        writeAudit(actionKey, def, params, result, sessionId);
        return result;
    }

    /* ------------------------------------------------------------------ *
     * Helpers
     * ------------------------------------------------------------------ */

    private static Action_Definition__c lookupDefinition(String actionKey) {
        if (String.isBlank(actionKey)) {
            return null;
        }
        List<Action_Definition__c> found = [
            SELECT Id, Name, Action_Key__c, Is_Active__c,
                   Requires_Approval__c, Handler__c, Input_Schema__c
            FROM Action_Definition__c
            WHERE Action_Key__c = :actionKey
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    private static void writeAudit(
        String actionKey,
        Action_Definition__c def,
        Map<String, Object> params,
        ActionResult result,
        String sessionId
    ) {
        try {
            insert new Agent_Action_Audit__c(
                Name = 'ACT-' + sessionId + '-' + String.valueOf(Datetime.now().getTime()),
                Session_Id__c = sessionId,
                Action_Definition__c = def == null ? null : def.Id,
                Parameters_Json__c = serialize(params),
                Result_Json__c = serialize(result.data),
                Success__c = result.success,
                Error_Code__c = result.errorCode,
                Duration_Ms__c = result.durationMs == null ? 0 : result.durationMs,
                Created_By_Agent__c = true
            );
        } catch (Exception e) {
            // Never let an audit failure mask the caller's outcome.
        }
    }

    private static String serialize(Object value) {
        try {
            return value == null ? null : JSON.serialize(value);
        } catch (Exception e) {
            return null;
        }
    }

    /* ------------------------------------------------------------------ *
     * Catalog
     * ------------------------------------------------------------------ */

    @AuraEnabled(cacheable=true)
    public static List<Action_Definition__c> declaredActions(Id agentId) {
        return [
            SELECT Id, Name, Action_Key__c, Input_Schema__c, Output_Schema__c,
                   Requires_Approval__c, Handler__c
            FROM Action_Definition__c
            WHERE Agent_Definition__c = :agentId AND Is_Active__c = true
        ];
    }
}
