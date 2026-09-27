@IsTest
private class Data360ModelSelectorTest {

    @TestSetup
    static void setup() {
        insert new List<Model_Endpoint_Config__c>{
            new Model_Endpoint_Config__c(
                Name = 'EU Approved Small', Provider__c = 'Salesforce',
                Model_Version__c = 'sf-small-eu', Residency__c = 'EU',
                Zero_Retention__c = true, Masking_Policy__c = 'PII masked',
                Approved_By__c = 'dpo@example.com', Approved_On__c = Date.today(),
                Max_Tokens_Per_Call__c = 4000, Is_Active__c = true
            ),
            new Model_Endpoint_Config__c(
                Name = 'EU Approved Large', Provider__c = 'Salesforce',
                Model_Version__c = 'sf-large-eu', Residency__c = 'EU',
                Zero_Retention__c = true, Masking_Policy__c = 'PII masked',
                Approved_By__c = 'dpo@example.com', Approved_On__c = Date.today(),
                Max_Tokens_Per_Call__c = 32000, Is_Active__c = true
            ),
            new Model_Endpoint_Config__c(
                Name = 'Unapproved EU', Provider__c = 'Partner',
                Model_Version__c = 'partner-eu', Residency__c = 'EU',
                Zero_Retention__c = true, Masking_Policy__c = 'PII masked',
                Approved_By__c = null, Approved_On__c = null,
                Max_Tokens_Per_Call__c = 1000, Is_Active__c = true
            ),
            new Model_Endpoint_Config__c(
                Name = 'EU No Retention', Provider__c = 'Salesforce',
                Model_Version__c = 'sf-eu-retention', Residency__c = 'EU',
                Zero_Retention__c = false, Masking_Policy__c = 'PII masked',
                Approved_By__c = 'dpo@example.com', Approved_On__c = Date.today(),
                Max_Tokens_Per_Call__c = 2000, Is_Active__c = true
            ),
            new Model_Endpoint_Config__c(
                Name = 'US Only', Provider__c = 'Salesforce',
                Model_Version__c = 'sf-us', Residency__c = 'US',
                Zero_Retention__c = true, Masking_Policy__c = 'PII masked',
                Approved_By__c = 'dpo@example.com', Approved_On__c = Date.today(),
                Max_Tokens_Per_Call__c = 1000, Is_Active__c = true
            )
        };
    }

    /* ------------------------------------------------------------------ */

    @IsTest
    static void unapprovedEndpointIsNeverSelected() {
        Data360ModelSelector.ModelChoice choice =
            Data360ModelSelector.select('EU', true, 5.0);

        System.assertNotEquals('partner-eu', choice.modelVersion,
            'Technically suitable is not the same as approved');
        System.assertNotEquals(null, choice.rationale, 'A selection states its reason');
    }

    @IsTest
    static void residencyIsEnforced() {
        Data360ModelSelector.ModelChoice choice =
            Data360ModelSelector.select('EU', false, 5.0);

        System.assertNotEquals('sf-us', choice.modelVersion,
            'A US endpoint must not serve an EU residency requirement');
    }

    @IsTest
    static void zeroRetentionIsEnforcedWhenRequired() {
        Data360ModelSelector.ModelChoice choice =
            Data360ModelSelector.select('EU', true, 5.0);

        for (Model_Endpoint_Config__c m : Data360ModelSelector.approvedEndpoints()) {
            if (m.Model_Version__c == choice.modelVersion) {
                System.assert(m.Zero_Retention__c, 'Zero retention was required');
            }
        }
    }

    @IsTest
    static void smallestApprovedEndpointIsChosen() {
        Data360ModelSelector.ModelChoice choice =
            Data360ModelSelector.select('EU', true, 5.0);

        System.assertEquals('sf-small-eu', choice.modelVersion,
            'The smallest approved endpoint minimises cost');
    }

    @IsTest
    static void noMatchingResidencyRaises() {
        try {
            Data360ModelSelector.select('APAC', true, 5.0);
            System.assert(false, 'A residency with no approved endpoint must fail loudly');
        } catch (Data360ModelSelector.NoApprovedEndpointException e) {
            System.assert(String.valueOf(e.getMessage()).contains('APAC'));
        }
    }

    @IsTest
    static void endpointWithoutMaskingPolicyIsIneligible() {
        insert new Model_Endpoint_Config__c(
            Name = 'No Masking', Provider__c = 'BYO', Model_Version__c = 'byo-eu',
            Residency__c = 'APAC', Zero_Retention__c = true, Masking_Policy__c = null,
            Approved_By__c = 'dpo@example.com', Approved_On__c = Date.today(),
            Max_Tokens_Per_Call__c = 1000, Is_Active__c = true
        );

        try {
            Data360ModelSelector.select('APAC', true, 5.0);
            System.assert(false, 'An endpoint with no masking policy is not eligible');
        } catch (Data360ModelSelector.NoApprovedEndpointException e) {
            System.assertNotEquals(null, e.getMessage());
        }
    }

    @IsTest
    static void inactiveEndpointIsNotOffered() {
        List<Model_Endpoint_Config__c> approved = Data360ModelSelector.approvedEndpoints();
        for (Model_Endpoint_Config__c m : approved) {
            System.assert(m.Is_Active__c, 'Only active endpoints are offered');
            System.assertNotEquals(null, m.Approved_By__c);
            System.assertNotEquals(null, m.Approved_On__c);
        }
    }
}
