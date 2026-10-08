import Core
import Testing
@testable import Cleanup

struct DictionaryCorrectorTests {
    private func fix(_ text: String, words: [String] = [], _ replacements: [(String, String)] = []) -> String {
        DictionaryCorrector.apply(text, dictionary: PersonalDictionary(
            words: words, replacements: replacements.map { Replacement(heard: $0.0, written: $0.1) }))
    }

    @Test func replacementsAreCaseInsensitiveWholeWords() {
        #expect(fix("please loop in Secure whisper today", [("secure whisper", "SecureWispr")])
                == "please loop in SecureWispr today")
        #expect(fix("secure, whisper", [("secure whisper", "SecureWispr")]) == "SecureWispr")
        #expect(fix("insecure whispering", [("secure whisper", "SecureWispr")]) == "insecure whispering")
    }

    @Test func nearMissIsCorrected() {
        #expect(fix("send the Kvarnholman report", words: ["Kvarnholmen"]) == "send the Kvarnholmen report")
    }

    @Test func punctuationAroundTheWordIsKept() {
        #expect(fix("to Kvarnholman.", words: ["Kvarnholmen"]) == "to Kvarnholmen.")
        #expect(fix("(Kvarnholman),", words: ["Kvarnholmen"]) == "(Kvarnholmen),")
    }

    @Test func multiWordEntries() {
        #expect(fix("send to Ylva Zeterström now", words: ["Ylva Zetterström"]) == "send to Ylva Zetterström now")
    }

    @Test func casingIsFixed() {
        #expect(fix("ask jozeta", words: ["Jozeta"]) == "ask Jozeta")
    }

    @Test func distantRealNamesAreNotTouched() {
        #expect(fix("ask Josef today", words: ["Jozeta"]) == "ask Josef today")
    }

    @Test func shortEntriesNeverFuzzyMatch() {
        #expect(fix("Anne said hi", words: ["Anna"]) == "Anne said hi")
    }

    @Test func firstLetterMustMatch() {
        #expect(fix("Carlsson called", words: ["Karlsson"]) == "Carlsson called")
    }

    @Test func distanceLimitsDependOnLength() {
        #expect(fix("Kvarnholmn", words: ["Kvarnholmen"]) == "Kvarnholmen")       // 11 letters, 1 edit
        #expect(fix("Kvarnhalman", words: ["Kvarnholmen"]) == "Kvarnholmen")      // 2 edits allowed
        #expect(fix("Kvorrhalman", words: ["Kvarnholmen"]) == "Kvorrhalman")      // 4 edits: no
        #expect(fix("Jozita", words: ["Jozeta"]) == "Jozeta")                     // 6 letters, 1 edit
        #expect(fix("Josita", words: ["Jozeta"]) == "Josita")                     // 2 edits: no
    }

    @Test func inflectedFormsAreLeftAlone() {
        #expect(fix("på Kvarnholmens kontor", words: ["Kvarnholmen"]) == "på Kvarnholmens kontor")
        #expect(fix("Stockholms stad", words: ["Stockholm"]) == "Stockholms stad")
    }

    @Test func replacementIsIdempotentWhenWrittenContainsHeard() {
        let once = fix("try wispr now", [("wispr", "Secure Wispr")])
        #expect(once == "try Secure Wispr now")
        #expect(fix(once, [("wispr", "Secure Wispr")]) == "try Secure Wispr now")
    }

    @Test func specialCharactersAreLiteral() {
        #expect(fix("I write c plus plus", [("c plus plus", "C++")]) == "I write C++")
        #expect(fix("version a.b (beta) ships", [("(beta)", "β")]) == "version a.b β ships")
    }

    @Test func applyingTwiceChangesNothing() {
        let dictionary = ["Kvarnholmen", "Ylva Zetterström"]
        let once = fix("Kvarnholman och Ylva Zeterström", words: dictionary)
        #expect(fix(once, words: dictionary) == once)
    }

    @Test func emptyDictionaryChangesNothing() {
        #expect(fix("hello Kvarnholman") == "hello Kvarnholman")
    }

    // MARK: Review fixes

    /// Stand-in for the app's spell checker: words that exist in Swedish/English.
    static let lexicon: Set<String> = ["hann", "hinna", "klart", "klara", "kallt", "kalla", "hurry", "frank",
                                       "marie", "erik", "och", "and", "jag", "inte", "det"]

    private func fixKnowing(_ text: String, words: [String]) -> String {
        DictionaryCorrector.apply(text, dictionary: PersonalDictionary(words: words),
                                  isKnownWord: { Self.lexicon.contains($0.lowercased()) })
    }

    @Test(arguments: [
        ("jag hann inte, vi ska hinna", ["Hanna"]),
        ("det är klart, vi kan klara det", ["Klara"]),
        ("det är kallt och kalla vindar", ["Kalle"]),
        ("hurry up, be frank", ["Harry", "Frank"]),
        ("Marie and Erik", ["Maria", "Erika"]),
    ])
    func ordinaryWordsNeverBecomeNames(text: String, words: [String]) {
        // Review C1: a real word is never "corrected" into a dictionary term.
        #expect(fixKnowing(text, words: words) == text)
    }

    @Test func unknownMisspellingsAreStillFixedWithALexicon() {
        #expect(fixKnowing("send the Kvarnholman report och jozeta", words: ["Kvarnholmen", "Jozeta"])
                == "send the Kvarnholmen report och Jozeta")
    }

    @Test func caseOnlyReplacementsWork() {
        // Review I1.
        let rules = [("github", "GitHub"), ("macos", "macOS")]
        let once = fix("my github and macos", rules)
        #expect(once == "my GitHub and macOS")
        #expect(fix(once, rules) == once)
    }

    @Test func largeDictionaryIsFast() {
        // Review I2: ~2 minutes of speech against a 200-entry dictionary, in a debug build.
        let entries = (0..<200).map { "Namnet\($0)xyz" } + ["Kvarnholmen", "Ylva Zetterström"]
        let text = Array(repeating: "vi ska ses på Kvarnholman med Ylva Zeterström imorgon klockan tre", count: 34)
            .joined(separator: " ")
        let dictionary = PersonalDictionary(words: entries)
        let start = ContinuousClock.now
        let out = DictionaryCorrector.apply(text, dictionary: dictionary)
        #expect(ContinuousClock.now - start < .milliseconds(40))
        #expect(out.contains("Kvarnholmen") && !out.contains("Kvarnholman"))
    }
}
