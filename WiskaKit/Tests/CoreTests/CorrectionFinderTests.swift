import Testing
@testable import Core

/// What the user fixed in the text Wiska just pasted, as dictionary suggestions.
struct CorrectionFinderTests {
    /// Ordinary words: everything except names and Wiska's mishearings.
    func known(_ word: String) -> Bool {
        !["wiska", "wisca", "johan", "zetterström", "setterström"].contains(word.lowercased())
    }

    func find(_ before: String, _ after: String, pasted: String) -> [Correction] {
        CorrectionFinder.corrections(before: before, after: after, pasted: pasted, isKnownWord: known)
    }

    @Test func aFixedNameInThePastedTextIsFound() {
        let before = "Dear team,\nI tried Wisca today and it works."
        let after = "Dear team,\nI tried Wiska today and it works."
        #expect(find(before, after, pasted: "I tried Wisca today and it works.") == [Correction(heard: "Wisca", written: "Wiska")])
    }

    @Test func twoWordFixesAndPunctuationAround() {
        let before = "Thanks, Johan Setterström! See you."
        let after = "Thanks, Johan Zetterström! See you."
        #expect(find(before, after, pasted: before) == [Correction(heard: "Setterström", written: "Zetterström")])
    }

    @Test func ordinaryWordChoicesAreNotSuggested() {
        #expect(find("I put it over their.", "I put it over there.", pasted: "I put it over their.").isEmpty)
    }

    @Test func editsOutsideThePastedTextAreIgnored() {
        let before = "Wisca wrote this. I pasted this part."
        let after = "Wiska wrote this. I pasted this part."
        #expect(find(before, after, pasted: "I pasted this part.").isEmpty)
    }

    @Test func rewritesAndAdditionsAreNotCorrections() {
        let pasted = "Let us meet at Wisca on Monday."
        #expect(find(pasted, pasted + " Bring the report and the numbers please.", pasted: pasted).isEmpty)
        #expect(find(pasted, "Totally different text now, nothing alike at all here.", pasted: pasted).isEmpty)
        #expect(find(pasted, pasted, pasted: pasted).isEmpty)
    }

    @Test func unrelatedReplacementsAreNotSuggested() {
        // Not a mishearing: nothing alike.
        #expect(find("Ask Wisca now.", "Ask Johan now.", pasted: "Ask Wisca now.").isEmpty)
    }

    @Test func aCaseFixForANameIsSuggested() {
        #expect(find("ask wiska.", "ask Wiska.", pasted: "ask wiska.") == [Correction(heard: "wiska", written: "Wiska")])
    }
}
