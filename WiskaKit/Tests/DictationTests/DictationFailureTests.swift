import Testing
@testable import Dictation

struct DictationFailureTests {
    @Test func commandFailureMessages() {
        #expect(DictationFailure.writeFailed.message == "Couldn't write — try again")
        #expect(DictationFailure.editUnavailable.message == "Command mode needs Apple Intelligence")
        #expect(DictationFailure.selectionTooLong.message == "Selection too long")
        #expect(DictationFailure.editFailed.message == "Couldn't edit — try again")
        #expect(DictationFailure.editRefused.message == "Apple Intelligence won't edit this text")
    }
}
