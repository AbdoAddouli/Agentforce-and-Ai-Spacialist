@IsTest
private class RetrievalRelevanceTest {

    private static final List<Id> IDS = new List<Id>{ 'a01', 'a02', 'a03' };
    private static final List<String> TEXTS = new List<String>{
        'Refund policy: returns accepted within 30 days of delivery',
        'Shipping: standard delivery takes 3 to 5 working days',
        'Warranty: covers manufacturing defects for 24 months'
    };

    /* ------------------------------------------------------------------ */

    @IsTest
    static void exactTopicScoresHighest() {
        List<RetrievalRelevance.ScoredRecord> scored =
            RetrievalRelevance.score('refund returns policy', IDS, TEXTS);

        System.assertEquals('a01', scored[0].recordId,
            'The refund article is the relevant one, got: ' + scored[0].label);
    }

    @IsTest
    static void shippingQuestionRanksShippingArticleFirst() {
        List<RetrievalRelevance.ScoredRecord> scored =
            RetrievalRelevance.score('shipping delivery working days', IDS, TEXTS);

        System.assertEquals('a02', scored[0].recordId);
    }

    @IsTest
    static void unrelatedQueryScoresZeroEverywhere() {
        List<RetrievalRelevance.ScoredRecord> scored =
            RetrievalRelevance.score('pension contributions', IDS, TEXTS);

        for (RetrievalRelevance.ScoredRecord s : scored) {
            System.assertEquals(0, s.score, 'No term overlap means no relevance');
        }
    }

    @IsTest
    static void thresholdFiltersLowScores() {
        List<RetrievalRelevance.ScoredRecord> scored =
            RetrievalRelevance.score('refund policy warranty shipping', IDS, TEXTS);
        List<RetrievalRelevance.ScoredRecord> kept =
            RetrievalRelevance.aboveThreshold(scored, 0.3);

        System.assert(kept.size() < scored.size(), 'The threshold should remove something');
        for (RetrievalRelevance.ScoredRecord s : kept) {
            System.assert(s.score >= 0.3, 'A kept record must be at or above the threshold');
        }
    }

    @IsTest
    static void zeroThresholdFallsBackToASensibleFloor() {
        List<RetrievalRelevance.ScoredRecord> scored =
            RetrievalRelevance.score('pension contributions', IDS, TEXTS);
        List<RetrievalRelevance.ScoredRecord> kept =
            RetrievalRelevance.aboveThreshold(scored, 0);

        System.assertEquals(0, kept.size(),
            'A zero threshold is a config error, not a licence to return everything');
    }

    @IsTest
    static void stopWordsDoNotCountAsMatches() {
        List<RetrievalRelevance.ScoredRecord> scored =
            RetrievalRelevance.score('the of and', IDS, TEXTS);

        for (RetrievalRelevance.ScoredRecord s : scored) {
            System.assertEquals(0, s.score, 'Stop words carry no signal');
        }
    }

    @IsTest
    static void bestReturnsNullForAnEmptySet() {
        System.assertEquals(null, RetrievalRelevance.best(new List<RetrievalRelevance.ScoredRecord>()));
    }

    @IsTest
    static void nullInputsAreHandledWithoutThrowing() {
        List<RetrievalRelevance.ScoredRecord> scored = RetrievalRelevance.score('query', null, null);
        System.assertEquals(0, scored.size());
    }

    @IsTest
    static void scoreIsNeverAboveOne() {
        List<RetrievalRelevance.ScoredRecord> scored =
            RetrievalRelevance.score('refund policy', IDS, TEXTS);

        for (RetrievalRelevance.ScoredRecord s : scored) {
            System.assert(s.score >= 0 && s.score <= 1, 'Scores must be a proportion');
        }
    }
}
