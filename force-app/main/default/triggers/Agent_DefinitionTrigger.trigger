/**
 * Thin by design. All behaviour lives in AgentLifecycleService so it can be
 * tested without DML and without trigger context.
 *
 * Named Agent_DefinitionTrigger because Salesforce requires a trigger's name
 * to be the sObject name followed by "Trigger".
 */
trigger Agent_DefinitionTrigger on Agent_Definition__c (before insert, before update) {
    List<String> errors = AgentLifecycleService.validate(Trigger.new);
    if (!errors.isEmpty()) {
        for (String message : errors) {
            Trigger.new[0].addError(message);
        }
        return;
    }

    if (Trigger.isUpdate) {
        Map<Id, String> oldInstructions = new Map<Id, String>();
        for (Agent_Definition__c prior : Trigger.old) {
            oldInstructions.put(prior.Id, prior.Instructions__c);
        }
        AgentLifecycleService.versionIfInstructionsChanged(oldInstructions, Trigger.new);
    }
}
