/**
 * Lexical relevance scoring for retrieved records.
 *
 * The limitation is deliberate and stated: this is term overlap, not
 * semantics. A semantically similar but wrong record can outrank the
 * correct one. Max_Records__c and the status filter mitigate that; they do
 * not solve it.
 */
public with sharing class RetrievalRelevance {

    public class ScoredRecord {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String label;
        @AuraEnabled public Decimal score;
    }

    private static final Set<String> STOP_WORDS = new Set<String>{
        'the', 'a', 'an', 'is', 'are', 'was', 'for', 'to', 'of', 'and',
        'in', 'on', 'at', 'it', 'my', 'our', 'with', 'about', 'what', 'how'
    };

    /* ------------------------------------------------------------------ *
     * Scoring
     * ------------------------------------------------------------------ */

    /**
     * Scores every record's text against the query.
     * @param texts label text per record, in the same order as recordIds
     */
    public static List<ScoredRecord> score(
        String query,
        List<Id> recordIds,
        List<String> texts
    ) {
        List<ScoredRecord> scored = new List<ScoredRecord>();
        if (recordIds == null || texts == null) {
            return scored;
        }

        Set<String> queryTerms = tokenize(query);

        for (Integer i = 0; i < recordIds.size(); i++) {
            String text = i < texts.size() ? texts[i] : null;
            scored.add(new ScoredRecord(
                recordId = recordIds[i],
                label = text,
                score = similarity(queryTerms, text)
            ));
        }

        scored.sort((ScoredRecord a, ScoredRecord b) => Decimal.compare(b.score, a.score));
        return scored;
    }

    /**
     * Filters to records at or above the source's threshold.
     * A threshold of zero returns everything, which is a configuration error
     * rather than a relevance decision.
     */
    public static List<ScoredRecord> aboveThreshold(
        List<ScoredRecord> scored,
        Decimal threshold
    ) {
        Decimal floor = threshold == null || threshold <= 0 ? 0.1 : threshold;
        List<ScoredRecord> kept = new List<ScoredRecord>();
        for (ScoredRecord s : scored) {
            if (s.score >= floor) {
                kept.add(s);
            }
        }
        return kept;
    }

    /**
     * Relevance and volume together decide the most common grounding defect:
     * retrieving too much. Returns the highest-scoring record.
     */
    public static ScoredRecord best(List<ScoredRecord> scored) {
        return scored == null || scored.isEmpty() ? null : scored[0];
    }

    /* ------------------------------------------------------------------ *
     * Internals
     * ------------------------------------------------------------------ */

    private static Set<String> tokenize(String value) {
        Set<String> terms = new Set<String>();
        if (String.isBlank(value)) {
            return terms;
        }
        for (String part : value.toLowerCase().split('[^a-z0-9]+')) {
            if (part.length() > 2 && !STOP_WORDS.contains(part)) {
                terms.add(part);
            }
        }
        return terms;
    }

    /** Jaccard-style overlap of query terms present in the text. */
    private static Decimal similarity(Set<String> queryTerms, String text) {
        if (queryTerms == null || queryTerms.isEmpty()) {
            return 0;
        }
        Set<String> textTerms = tokenize(text);
        if (textTerms.isEmpty()) {
            return 0;
        }
        Integer hits = 0;
        for (String term : queryTerms) {
            if (textTerms.contains(term)) {
                hits = hits + 1;
            }
        }
        return (Decimal) hits / (Decimal) queryTerms.size();
    }
}
