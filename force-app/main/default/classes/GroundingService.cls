/**
 * Bounded retrieval against a declared grounding source.
 *
 * The contract that matters: when nothing is found, this returns zero
 * records rather than loosening the scope. Widening the scope to avoid a
 * miss trades a missing answer for a wrong one.
 */
public with sharing class GroundingService {

    public class GroundingResult {
        @AuraEnabled public Id sourceId;
        @AuraEnabled public Integer recordsRetrieved;
        @AuraEnabled public List<SObject> records;
        @AuraEnabled public String missReason;
    }

    public class GroundingMissException extends Exception {}

    /* ------------------------------------------------------------------ *
     * Retrieval
     * ------------------------------------------------------------------ */

    /**
     * Retrieves up to the source's Max_Records__c records matching the scope.
     *
     * @param sourceId  Grounding_Source__c to read
     * @param searchText natural-language query from the agent
     */
    public static GroundingResult retrieve(Id sourceId, String searchText) {
        GroundingResult result = new GroundingResult(
            sourceId = sourceId,
            recordsRetrieved = 0,
            records = new List<SObject>(),
            missReason = null
        );

        if (sourceId == null) {
            result.missReason = 'NO_SOURCE';
            return result;
        }

        Grounding_Source__c source = [
            SELECT Id, Name, Source_Type__c, Object_Api_Name__c, Scope_Json__c,
                   Max_Records__c, Relevance_Threshold__c, Is_Active__c
            FROM Grounding_Source__c
            WHERE Id = :sourceId
            LIMIT 1
        ];

        if (!source.Is_Active__c) {
            result.missReason = 'SOURCE_INACTIVE';
            return result;
        }
        if (String.isBlank(source.Object_Api_Name__c)) {
            result.missReason = 'NO_OBJECT_MAPPED';
            return result;
        }
        if (String.isBlank(searchText)) {
            result.missReason = 'EMPTY_QUERY';
            return result;
        }

        Integer limitSize = source.Max_Records__c == null || source.Max_Records__c <= 0
            ? 10
            : (Integer) source.Max_Records__c;

        // A fixed, read-only field set keeps the query safe to build as text
        // and keeps the returned shape stable regardless of source type.
        String soql =
            'SELECT Id, Name, CreatedDate ' +
            'FROM ' + source.Object_Api_Name__c +
            ' WHERE Name LIKE :likeTerm' +
            ' ORDER BY CreatedDate DESC' +
            ' LIMIT :rowLimit';

        Map<String, Object> binds = new Map<String, Object>{
            'likeTerm' => '%' + escapeLike(searchText.trim()) + '%',
            'rowLimit' => limitSize
        };

        List<SObject> rows;
        try {
            rows = Database.queryWithBinds(soql, binds);
        } catch (Exception e) {
            result.missReason = 'QUERY_FAILED';
            return result;
        }

        if (rows == null || rows.isEmpty()) {
            result.missReason = 'NO_MATCHES';
            return result;
        }

        result.records = rows;
        result.recordsRetrieved = rows.size();
        return result;
    }

    /**
     * Convenience wrapper that fails loudly.
     *
     * Used where the agent is not permitted to continue without evidence,
     * for example before quoting a policy amount.
     */
    public static List<SObject> requireContext(Id sourceId, String searchText) {
        GroundingResult result = retrieve(sourceId, searchText);
        if (result.recordsRetrieved == 0) {
            throw new GroundingMissException(
                'Grounding returned nothing for ' + searchText + ' (' + result.missReason + ')'
            );
        }
        return result.records;
    }

    /* ------------------------------------------------------------------ *
     * Helpers
     * ------------------------------------------------------------------ */

    private static String escapeLike(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    @AuraEnabled(cacheable=true)
    public static List<Grounding_Source__c> activeSources() {
        return [
            SELECT Id, Name, Source_Type__c, Object_Api_Name__c,
                   Max_Records__c, Relevance_Threshold__c
            FROM Grounding_Source__c
            WHERE Is_Active__c = true
        ];
    }
}
