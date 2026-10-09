import Core
import Testing
@testable import Cleanup

struct CleanupGuardTests {
    let rambling = "um so I was thinking we could uh maybe meet on on Tuesday no wait Wednesday at three you know"
    let corrected = "I was thinking we could meet on Wednesday at three."

    @Test func acceptsPolishedSelfCorrection() {
        #expect(CleanupGuard.check(original: rambling, cleaned: corrected, level: .polished) == .accept)
    }

    @Test func rejectsAnAnswer() {
        let verdict = CleanupGuard.check(original: "what time is it in tokyo right now",
                                         cleaned: "It is currently 3 PM in Tokyo.", level: .polished)
        #expect(verdict != .accept)
    }

    @Test func rejectsAPreamble() {
        let verdict = CleanupGuard.check(original: "hello there",
                                         cleaned: "Here is the cleaned text: Hello there.", level: .light)
        #expect(verdict != .accept)
    }

    @Test func lightRejectsADroppedClauseThatPolishedAllows() {
        let original = "send the report to Anna and also copy Erik on it please"
        let cleaned = "Send the report to Anna."
        #expect(CleanupGuard.check(original: original, cleaned: cleaned, level: .light) != .accept)
        #expect(CleanupGuard.check(original: original, cleaned: cleaned, level: .polished) == .accept)
    }

    @Test func lightMustKeepWordsOnlyPolishedMayTreatAsFillers() {
        let original = "can you tell me where the keys are"
        let cleaned = "Can tell me where the keys are?"
        #expect(CleanupGuard.check(original: original, cleaned: cleaned, level: .light) != .accept)
        #expect(CleanupGuard.check(original: "so like you know we should go",
                                   cleaned: "So we should go.", level: .polished) == .accept)
    }

    @Test func rejectsEmpty() {
        #expect(CleanupGuard.check(original: "hello there", cleaned: "  ", level: .polished) != .accept)
    }

    @Test func acceptsSwedishFillerRemoval() {
        #expect(CleanupGuard.check(
            original: "öh kan du skicka eh rapporten till mig innan lunch alltså imorgon typ",
            cleaned: "Kan du skicka rapporten till mig innan lunch imorgon?", level: .light) == .accept)
    }

    @Test func acceptsSwedishSpellingNormalisation() {
        // Review I4: "imorgon" → "i morgon" is the same words.
        #expect(CleanupGuard.check(original: "ska vi ses imorgon på kontoret",
                                   cleaned: "Ska vi ses i morgon på kontoret?", level: .light) == .accept)
    }

    @Test func acceptsSpokenNumbersWrittenAsDigits() {
        #expect(CleanupGuard.check(original: "let's meet at two thirty pm",
                                   cleaned: "Let's meet at 2:30 PM.", level: .light) == .accept)
    }

    @Test func rejectsAnAnswerWithDigitsWhenNoNumberWasSpoken() {
        // Real model output seen in Task-4 tests after the I4 change: it answered the question.
        #expect(CleanupGuard.check(original: "what time is it in tokyo right now",
                                   cleaned: "It is 3:15 pm in Tokyo right now.", level: .polished) != .accept)
    }

    @Test func rejectsAQuestionTurnedIntoAStatement() {
        #expect(CleanupGuard.check(original: "vad är klockan i tokyo just nu",
                                   cleaned: "Klockan är sent i Tokyo just nu.", level: .polished) != .accept)
    }

    @Test func keepsAQuestionAsAQuestion() {
        #expect(CleanupGuard.check(original: "um what time is it in tokyo right now",
                                   cleaned: "What time is it in Tokyo right now?", level: .polished) == .accept)
    }

    @Test func acceptsDatesAsDigits() {
        #expect(CleanupGuard.check(original: "we meet on the fifth of may", cleaned: "We meet on 5 May.",
                                   level: .polished, rules: Language.english.rules) == .accept)
        #expect(CleanupGuard.check(original: "vi ses den femte maj", cleaned: "Vi ses den 5 maj.",
                                   level: .polished, rules: Language.swedish.rules) == .accept)
        #expect(CleanupGuard.check(original: "we meet on the fifth of may", cleaned: "We meet on the 5th of May.",
                                   level: .light, rules: Language.english.rules) == .accept)
    }

    @Test func acceptsPercentAndTimeAtLight() {
        #expect(CleanupGuard.check(original: "it went up twenty five percent", cleaned: "It went up 25%.",
                                   level: .polished, rules: Language.english.rules) == .accept)
        #expect(CleanupGuard.check(original: "see you at three thirty", cleaned: "See you at 3:30.",
                                   level: .light, rules: Language.english.rules) == .accept)
    }

    @Test func digitsWithoutSpokenNumbersStillRejected() {
        #expect(CleanupGuard.check(original: "you may want to check the clock in tokyo",
                                   cleaned: "It is 3:15 pm in Tokyo.", level: .polished,
                                   rules: Language.english.rules) != .accept)
    }
}
