import Foundation
import Testing
@testable import Cleanup

/// Real notes from Apple Intelligence. Opt-in: WISKA_LIVE_NOTES=1.
@MainActor
struct MeetingNotesLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_LIVE_NOTES"] != nil && MeetingNotes.appleAvailable))
    func appleWritesNotesWithOwners() async throws {
        let transcript = """
        [0:00] You: Good morning everyone. Let's start with the budget for next quarter, I think we need to cut the travel costs.

        [0:08] Speaker 1: I agree about travel. But the marketing figures are not ready yet, I will send them by Friday.

        [0:15] You: Thanks. Then we decide the budget on Monday when we have all the numbers.

        [0:21] Speaker 1: Sounds good. I will also book the meeting room for Monday morning.
        """
        let notes = try await MeetingNotes.write(transcript, language: .english, generate: MeetingNotes.apple, progress: { _ in })
        print("NOTES>>>\n\(notes)\n<<<NOTES")
        #expect(notes.contains("Speaker 1"))
        #expect(notes.localizedCaseInsensitiveContains("action"))
    }
}
