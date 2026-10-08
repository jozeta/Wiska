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
}
