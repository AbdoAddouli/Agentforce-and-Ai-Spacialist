/**
 * Versioned prompt template resolution and usage logging.
 *
 * A prompt change is a change to production behaviour, so it needs a
 * version, a log, and a reason to exist that is more than "someone edited
 * the text".
 */
public with sharing class PromptTemplateService {

    public class ResolvedTemplate {
        @AuraEnabled public String templateName;
        @AuraEnabled public Integer version;
        @AuraEnabled public String body;
        @AuraEnabled public Boolean found;
    }

    /** In-process template catalog, versioned by name. */
    private static final Map<String, Map<Integer, String>> CATALOG =
        new Map<String, Map<Integer, String>>();

    /* ------------------------------------------------------------------ *
     * Registration
     * ------------------------------------------------------------------ */

    public static void register(String templateName, Integer version, String body) {
        if (String.isBlank(templateName) || version == null || version < 1) {
            throw new ArgumentException('Template name and a positive version are required.');
        }
        if (!CATALOG.containsKey(templateName)) {
            CATALOG.put(templateName, new Map<Integer, String>());
        }
        CATALOG.get(templateName).put(version, body);
    }

    /* ------------------------------------------------------------------ *
     * Resolution
     * ------------------------------------------------------------------ */

    /**
     * Resolves the highest registered version at or below maxVersion.
     *
     * Pinning the version is what makes a regression reproducible: a test
     * that resolved v1 last month resolved v1 again today.
     */
    public static ResolvedTemplate resolve(String templateName, Integer maxVersion) {
        ResolvedTemplate resolved = new ResolvedTemplate(
            templateName = templateName,
            version = null,
            body = null,
            found = false
        );

        if (String.isBlank(templateName) || !CATALOG.containsKey(templateName)) {
            return resolved;
        }

        Map<Integer, String> versions = CATALOG.get(templateName);
        Integer ceiling = maxVersion == null ? Integer.MAX_VALUE : maxVersion;
        Integer best = null;

        for (Integer v : versions.keySet()) {
            if (v <= ceiling && (best == null || v > best)) {
                best = v;
            }
        }

        if (best == null) {
            return resolved;
        }

        resolved.version = best;
        resolved.body = versions.get(best);
        resolved.found = true;
        return resolved;
    }

    public static ResolvedTemplate resolveLatest(String templateName) {
        return resolve(templateName, null);
    }

    /* ------------------------------------------------------------------ *
     * Usage logging
     * ------------------------------------------------------------------ */

    /**
     * Records that a template was used, and whether the use succeeded.
     * Prompt_Template_Usage__c is what makes a prompt change traceable to a
     * behaviour change.
     */
    public static void logUsage(
        Id agentId,
        String templateName,
        Integer version,
        Boolean success,
        String notes
    ) {
        try {
            insert new Prompt_Template_Usage__c(
                Name = 'PTU-' + templateName + '-v' + String.valueOf(version),
                Template_Name__c = templateName,
                Version__c = version,
                Agent_Definition__c = agentId,
                Used_On__c = Date.today(),
                Success__c = Boolean.TRUE.equals(success),
                Notes__c = notes == null || notes.length() <= 255 ? notes : notes.substring(0, 255)
            );
        } catch (Exception e) {
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Prompt_Template_Usage__c> usageFor(Id agentId) {
        return [
            SELECT Id, Template_Name__c, Version__c, Used_On__c, Success__c, Notes__c
            FROM Prompt_Template_Usage__c
            WHERE Agent_Definition__c = :agentId
            ORDER BY Used_On__c DESC
        ];
    }
}
