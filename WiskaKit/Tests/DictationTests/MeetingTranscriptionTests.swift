import Core
import Foundation
import Testing
@testable import Dictation

/// Echoes how many samples it heard, so tests can see which pieces were transcribed.
@MainActor
private final class EchoSession: TranscriptionSession {
    let label: String
    private var count = 0
    init(_ label: String) { self.label = label }
    func append(_ chunk: AudioChunk) { count += chunk.samples.count }
    func finish() async throws -> Transcript {
        Transcript(text: "\(label) \(count / 16_000)s", locale: Language.english.locale, language: .english)
    }
    func cancel() {}
}

@MainActor
struct MeetingTranscriptionTests {
    let rate = 16_000
    func speech(_ seconds: Int) -> [Float] { (0..<(seconds * 16_000)).map { Float(sin(Double($0) * 0.05) * 0.3) } }
    func silence(_ seconds: Int) -> [Float] { Array(repeating: 0, count: seconds * 16_000) }

    @Test func silentStretchesAreSkippedAndTurnsInterleaveByTime() async throws {
        // You speak for the first 10 s; the others for the next 10 s.
        let you = speech(10) + silence(10)
        let others = silence(10) + speech(10)
        var labels: [String] = []
        let segments = try await MeetingTranscription.run(you: you, others: others, every: 10, searching: 1,
                                                          session: { speaker in
                                                              labels.append(speaker.rawValue)
                                                              return EchoSession(speaker.rawValue)
                                                          }, progress: { _ in })
        #expect(segments.map(\.speaker) == [.you, .others])
        #expect(segments[0].start < segments[1].start)
        #expect(labels == ["you", "others"])   // the silent halves were never transcribed
    }

    @Test func theTranscriptMergesASpeakersTurnsAndShowsTimes() {
        let segments = [
            MeetingSegment(speaker: .you, start: 5, text: "Hello all."),
            MeetingSegment(speaker: .you, start: 25, text: "Shall we start?"),
            MeetingSegment(speaker: .others, start: 65, text: "Yes, go ahead."),
            MeetingSegment(speaker: .you, start: 3_700, text: "Thanks."),
        ]
        #expect(MeetingTranscription.transcript(segments) == """
        [0:05] You: Hello all. Shall we start?

        [1:05] Others: Yes, go ahead.

        [1:01:40] You: Thanks.
        """)
    }

    @Test func emptyAudioGivesNoSegments() async throws {
        let segments = try await MeetingTranscription.run(you: [], others: [], session: { EchoSession($0.rawValue) },
                                                          progress: { _ in })
        #expect(segments.isEmpty)
    }
}
