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

    @Test func rejectsEmpty() {
        #expect(CleanupGuard.check(original: "hello there", cleaned: "  ", level: .polished) != .accept)
    }

    @Test func acceptsSwedishFillerRemoval() {
        #expect(CleanupGuard.check(
            original: "öh kan du skicka eh rapporten till mig innan lunch alltså imorgon typ",
            cleaned: "Kan du skicka rapporten till mig innan lunch imorgon?", level: .light) == .accept)
    }
}
