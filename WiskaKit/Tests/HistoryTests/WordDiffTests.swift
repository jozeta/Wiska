import Testing
@testable import History

struct WordDiffTests {
    func changed(_ tokens: [DiffToken]) -> [String] { tokens.filter(\.changed).map(\.text) }

    @Test func identicalTextsHaveNoChanges() {
        let diff = WordDiff.diff(raw: "see you soon", final: "see you soon")
        #expect(changed(diff.heard).isEmpty)
        #expect(changed(diff.pasted).isEmpty)
        #expect(diff.pasted.map(\.text) == ["see", "you", "soon"])
    }

    @Test func removedFillersAreChangedInHeard() {
        let diff = WordDiff.diff(raw: "um I think uh so", final: "I think so")
        #expect(changed(diff.heard) == ["um", "uh"])
        #expect(changed(diff.pasted).isEmpty)
    }

    @Test func punctuationAndCaseAreNotChanges() {
        let diff = WordDiff.diff(raw: "hi anna see you tuesday", final: "Hi Anna, see you Tuesday.")
        #expect(changed(diff.heard).isEmpty)
        #expect(changed(diff.pasted).isEmpty)
        #expect(diff.pasted.map(\.text) == ["Hi", "Anna,", "see", "you", "Tuesday."])
    }

    @Test func selfCorrectionKeepsOnlyTheCorrection() {
        let diff = WordDiff.diff(raw: "tuesday no wait wednesday", final: "Wednesday.")
        #expect(changed(diff.heard) == ["tuesday", "no", "wait"])
        #expect(changed(diff.pasted).isEmpty)
    }

    @Test func rewordedSentence() {
        let diff = WordDiff.diff(raw: "send it asap", final: "please send it soon")
        #expect(changed(diff.heard) == ["asap"])
        #expect(changed(diff.pasted) == ["please", "soon"])
    }

    @Test func emptyInputs() {
        #expect(WordDiff.diff(raw: "", final: "Hi").pasted == [DiffToken(text: "Hi", changed: true)])
        #expect(WordDiff.diff(raw: "um", final: "").heard == [DiffToken(text: "um", changed: true)])
    }
}
