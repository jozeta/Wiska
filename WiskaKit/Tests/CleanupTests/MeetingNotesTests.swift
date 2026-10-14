import Testing
@testable import Cleanup

@MainActor
struct MeetingNotesTests {
    func transcript(paragraphs: Int, words: Int) -> String {
        (1...paragraphs).map { index in
            "[0:\(index)] Speaker 1: " + Array(repeating: "word", count: words).joined(separator: " ")
        }.joined(separator: "\n\n")
    }

    @Test func aShortMeetingIsSummarisedInOneGo() async throws {
        var prompts: [String] = []
        let notes = try await MeetingNotes.write(transcript(paragraphs: 3, words: 50), language: nil, partWords: 1_000,
                                                 generate: { _, prompt in prompts.append(prompt); return "NOTES" },
                                                 progress: { _ in })
        #expect(notes == "NOTES")
        #expect(prompts.count == 1)
        #expect(prompts[0].contains("Speaker 1:"))
    }

    @Test func aLongMeetingIsSummarisedInPartsThenCombined() async throws {
        var systems: [String] = []
        var progress: [Double] = []
        let notes = try await MeetingNotes.write(transcript(paragraphs: 10, words: 300), language: nil, partWords: 1_000,
                                                 generate: { system, _ in
                                                     systems.append(system)
                                                     return system == MeetingNotes.combineInstructions ? "FINAL" : "part"
                                                 }, progress: { progress.append($0) })
        #expect(notes == "FINAL")
        #expect(systems.filter { $0 == MeetingNotes.partInstructions }.count == 4)   // 3000 words in ≤1000-word parts
        #expect(systems.last == MeetingNotes.combineInstructions)
        #expect(progress.last == 1)
    }

    @Test func partsKeepWholeParagraphs() {
        let parts = MeetingNotes.parts(transcript(paragraphs: 5, words: 100), maxWords: 250)
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { $0.hasPrefix("[0:") })
    }

    @Test func markdownAndTrailingSpacesAreTidied() {
        #expect(MeetingNotes.clean("## Summary  \n- **Anna** agreed.  \n") == "Summary\n- Anna agreed.")
    }

    @Test func notesAskForTheSpokenLanguage() async throws {
        var prompt = ""
        _ = try await MeetingNotes.write("[0:01] You: Hej allihop.", language: .swedish, generate: { _, p in prompt = p; return "x" },
                                         progress: { _ in })
        #expect(prompt.contains("Swedish"))
    }
}
