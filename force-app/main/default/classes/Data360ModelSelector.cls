/**
 * Chooses a Data 360 model from the approved endpoint catalog.
 *
 * Only endpoints in Model_Endpoint_Config__c may be used. Hard-coding a model
 * name in instructions is the defect this class exists to prevent: it bypasses
 * residency, retention and masking review.
 */
public with sharing class Data360ModelSelector {

    public class ModelChoice {
        @AuraEnabled public String modelVersion;
        @AuraEnabled public Id endpointId;
        @AuraEnabled public Decimal estimatedCredits;
        @AuraEnabled public String rationale;
    }

    public class NoApprovedEndpointException extends Exception {}

    public static final Decimal DEFAULT_ESTIMATE = 0.6;

    /* ------------------------------------------------------------------ *
     * Selection
     * ------------------------------------------------------------------ */

    /**
     * Selects the cheapest approved active endpoint.
     *
     * @param residency required data residency, e.g. 'EU'
     * @param zeroRetention required zero-retention guarantee
     * @param maxCredits budget ceiling; a model above it is rejected
     */
    public static ModelChoice select(
        String residency,
        Boolean zeroRetentionRequired,
        Decimal maxCredits
    ) {
        List<Model_Endpoint_Config__c> catalog = [
            SELECT Id, Name, Provider__c, Model_Version__c, Residency__c,
                   Zero_Retention__c, Masking_Policy__c, Approved_By__c,
                   Approved_On__c, Max_Tokens_Per_Call__c, Is_Active__c
            FROM Model_Endpoint_Config__c
            WHERE Is_Active__c = true
            ORDER BY Max_Tokens_Per_Call__c ASC NULLS LAST
        ];

        List<Model_Choice> eligible = new List<Model_Choice>();
        for (Model_Endpoint_Config__c m : catalog) {
            if (!matches(m, residency, zeroRetentionRequired)) {
                continue;
            }
            eligible.add(new ModelChoice(
                modelVersion = m.Model_Version__c,
                endpointId = m.Id,
                estimatedCredits = DEFAULT_ESTIMATE,
                rationale = 'approved ' + m.Provider__c + ' endpoint, residency ' + m.Residency__c
            ));
        }

        if (eligible.isEmpty()) {
            throw new NoApprovedEndpointException(
                'No approved active endpoint matches residency ' + residency
            );
        }

        ModelChoice chosen = null;
        for (ModelChoice c : eligible) {
            if (maxCredits != null && c.estimatedCredits > maxCredits) {
                continue;
            }
            if (chosen == null || c.estimatedCredits < chosen.estimatedCredits) {
                chosen = c;
            }
        }

        if (chosen == null) {
            throw new NoApprovedEndpointException(
                'All approved endpoints exceed the credit ceiling of ' + maxCredits
            );
        }
        return chosen;
    }

    /**
     * Governance guard: an endpoint used for a restricted residency must have
     * a named approver. An unapproved endpoint is never selected, whatever
     * its technical suitability.
     */
    private static Boolean matches(
        Model_Endpoint_Config__c m,
        String residency,
        Boolean zeroRetentionRequired
    ) {
        if (String.isBlank(m.Approved_By__c) || m.Approved_On__c == null) {
            return false;
        }
        if (String.isBlank(m.Masking_Policy__c)) {
            return false;
        }
        if (String.isNotBlank(residency)
            && !String.valueOf(m.Residency__c).equalsIgnoreCase(residency)) {
            return false;
        }
        if (Boolean.TRUE.equals(zeroRetentionRequired) && !m.Zero_Retention__c) {
            return false;
        }
        return true;
    }

    @AuraEnabled(cacheable=true)
    public static List<Model_Endpoint_Config__c> approvedEndpoints() {
        return [
            SELECT Id, Name, Provider__c, Model_Version__c, Residency__c,
                   Zero_Retention__c, Masking_Policy__c, Approved_By__c,
                   Approved_On__c, Max_Tokens_Per_Call__c
            FROM Model_Endpoint_Config__c
            WHERE Is_Active__c = true
              AND Approved_By__c != null
              AND Approved_On__c != null
            ORDER BY Provider__c, Model_Version__c
        ];
    }
}
