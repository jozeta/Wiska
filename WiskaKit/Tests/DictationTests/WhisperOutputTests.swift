import Testing
@testable import Dictation

struct WhisperOutputTests {
    @Test func ordinaryCorrectionsAreAccepted() {
        #expect(WhisperOutput.accept("Jag har ett stort hus.", over: "jag har en stor hus"))
        #expect(WhisperOutput.accept("Hej", over: "hej"))
    }

    @Test func emptyOrMuchLongerIsRejected() {
        #expect(!WhisperOutput.accept("  ", over: "jag har en stor hus"))
        // 2 × 1 + 4 = 6 words allowed for a one-word dictation.
        #expect(!WhisperOutput.accept("Ja och sen gick vi hem till mamma och åt", over: "ja"))
    }

    @Test func hallucinationsAreRejected() {
        #expect(!WhisperOutput.accept("Tack för att du tittade!", over: "tack"))
        #expect(!WhisperOutput.accept("Textning: Amara.org", over: "hm"))
        // Said for real: kept.
        #expect(WhisperOutput.accept("Tack för att du tittade på huset.", over: "tack för att du tittade på huset"))
    }

    @Test func wordErrorRateCountsWordEdits() {
        #expect(VoiceBenchmark.wordErrorRate(reference: "Jag har ett stort hus.", hypothesis: "jag har ett stort hus") == 0)
        #expect(VoiceBenchmark.wordErrorRate(reference: "jag har ett stort hus", hypothesis: "jag har en stor hus") == 0.4)
        #expect(VoiceBenchmark.wordErrorRate(reference: "jag har ett hus", hypothesis: "") == 1)
        #expect(VoiceBenchmark.sentences.count == 5)
        #expect(VoiceBenchmark.sentences[0] == "Jag har ett stort hus och en liten trädgård.")
    }
}
