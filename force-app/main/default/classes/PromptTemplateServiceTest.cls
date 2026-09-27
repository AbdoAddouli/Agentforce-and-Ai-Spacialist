@IsTest
private class PromptTemplateServiceTest {

    @TestSetup
    static void setup() {
        PromptTemplateService.register('refund_reply', 1, 'Dear customer, your refund is approved.');
        PromptTemplateService.register('refund_reply', 2, 'Dear customer, refund <amount> approved.');
        PromptTemplateService.register('policy_answer', 1, 'Returns are accepted within 30 days.');
    }

    /* ------------------------------------------------------------------ */

    @IsTest
    static void latestVersionResolvesByDefault() {
        PromptTemplateService.ResolvedTemplate resolved =
            PromptTemplateService.resolveLatest('refund_reply');

        System.assert(resolved.found);
        System.assertEquals(2, resolved.version);
        System.assert(resolved.body.contains('<amount>'));
    }

    @IsTest
    static void pinningAMaxVersionIsReproducible() {
        PromptTemplateService.ResolvedTemplate resolved =
            PromptTemplateService.resolve('refund_reply', 1);

        System.assertEquals(1, resolved.version,
            'A pinned version is what makes a regression reproducible');
        System.assertEquals('Dear customer, your refund is approved.', resolved.body);
    }

    @IsTest
    static void unknownTemplateIsNotFoundRatherThanEmpty() {
        PromptTemplateService.ResolvedTemplate resolved =
            PromptTemplateService.resolveLatest('no_such_template');

        System.assert(!resolved.found, 'A missing template is reported, not silently empty');
        System.assertEquals(null, resolved.body);
    }

    @IsTest
    static void versionBelowOneIsNotRegistered() {
        try {
            PromptTemplateService.register('bad', 0, 'text');
            System.assert(false, 'Version 0 is not a version');
        } catch (ArgumentException e) {
            System.assertNotEquals(null, e.getMessage());
        }
    }

    @IsTest
    static void blankTemplateNameIsRejected() {
        try {
            PromptTemplateService.register(null, 1, 'text');
            System.assert(false, 'A template needs a name');
        } catch (ArgumentException e) {
            System.assertNotEquals(null, e.getMessage());
        }
    }

    @IsTest
    static void usageIsLoggedWithVersionAndOutcome() {
        insert new Grounding_Source__c(
            Name = 'KB', Source_Type__c = 'LightningKnowledge',
            Object_Api_Name__c = 'Account', Max_Records__c = 5, Is_Active__c = true
        );
        Id sourceId = [SELECT Id FROM Grounding_Source__c LIMIT 1].Id;
        insert new Agent_Definition__c(
            Name = 'Agent', Agent_Key__c = 'a_v1', Status__c = 'Draft', Version__c = 1,
            Grounding_Source__c = sourceId, Max_Steps__c = 6
        );
        Id agentId = [SELECT Id FROM Agent_Definition__c LIMIT 1].Id;

        Test.startTest();
        PromptTemplateService.logUsage(agentId, 'refund_reply', 2, true, 'happy path');
        PromptTemplateService.logUsage(agentId, 'policy_answer', 1, false, 'grounding miss');
        Test.stopTest();

        List<Prompt_Template_Usage__c> usage = PromptTemplateService.usageFor(agentId);

        System.assertEquals(2, usage.size(), 'Every use is recorded, successful or not');
        for (Prompt_Template_Usage__c u : usage) {
            System.assertNotEquals(null, u.Version__c, 'A prompt use is always versioned');
        }
    }

    @IsTest
    static void longNotesAreTruncatedNotRejected() {
        insert new Grounding_Source__c(
            Name = 'KB2', Source_Type__c = 'LightningKnowledge',
            Object_Api_Name__c = 'Account', Max_Records__c = 5, Is_Active__c = true
        );
        Id sourceId = [SELECT Id FROM Grounding_Source__c LIMIT 1].Id;
        insert new Agent_Definition__c(
            Name = 'Agent2', Agent_Key__c = 'a2_v1', Status__c = 'Draft', Version__c = 1,
            Grounding_Source__c = sourceId, Max_Steps__c = 6
        );
        Id agentId = [SELECT Id FROM Agent_Definition__c WHERE Name = 'Agent2'].Id;

        Test.startTest();
        PromptTemplateService.logUsage(agentId, 'refund_reply', 1, true, 'x'.repeat(400));
        Test.stopTest();

        List<Prompt_Template_Usage__c> usage = PromptTemplateService.usageFor(agentId);
        System.assertEquals(1, usage.size(), 'An over-long note is trimmed, not lost');
        System.assert(usage[0].Notes__c.length() <= 255);
    }
}
