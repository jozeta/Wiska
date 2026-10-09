import Testing
@testable import Dictation

struct DictationFailureTests {
    @Test func commandFailureMessages() {
        #expect(DictationFailure.noSelection.message == "Select text first")
        #expect(DictationFailure.editUnavailable.message == "Command mode needs Apple Intelligence")
        #expect(DictationFailure.selectionTooLong.message == "Selection too long")
        #expect(DictationFailure.editFailed.message == "Couldn't edit — try again")
    }
}
