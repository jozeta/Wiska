import Testing
@testable import Core

struct PhraseMatcherTests {
    @Test func bareWordsIgnoreCaseAndPunctuation() {
        #expect(PhraseMatcher.bareWords("  Insert, my SIGNATURE. ") == ["insert", "my", "signature"])
        #expect(PhraseMatcher.bareWords(" — ") == [])
        #expect(PhraseMatcher.bare("Formal.") == "formal")
    }

    @Test func matchesExactPluralAndOneEditOnLongWords() {
        #expect(PhraseMatcher.matches(["insert", "my", "address"][...], ["insert", "my", "address"]))
        #expect(PhraseMatcher.matches(["bullets"][...], ["bullet"]))
        #expect(PhraseMatcher.matches(["boxes"][...], ["box"]))
        #expect(PhraseMatcher.matches(["formel"][...], ["formal"]))     // 6 letters: one edit allowed
        #expect(!PhraseMatcher.matches(["fax"][...], ["fix"]))          // 3 letters: exact only
        #expect(!PhraseMatcher.matches(["insert", "my"][...], ["insert", "my", "address"]))
    }

    @Test func editDistanceStopsAtTheLimit() {
        #expect(PhraseMatcher.editDistance("kitten", "sitting") == 3)
        #expect(PhraseMatcher.editDistance("", "abc") == 3)
        #expect(PhraseMatcher.editDistance("abcdef", "uvwxyz", limit: 1) > 1)
    }
}
