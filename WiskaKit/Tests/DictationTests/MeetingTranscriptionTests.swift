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
                                                              labels.append(speaker.displayName)
                                                              return EchoSession(speaker.displayName)
                                                          }, progress: { _ in })
        #expect(segments.map(\.speaker) == [.you, .others])
        #expect(segments[0].start < segments[1].start)
        #expect(labels == ["You", "Others"])   // the silent halves were never transcribed
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
        let segments = try await MeetingTranscription.run(you: [], others: [], session: { EchoSession($0.displayName) },
                                                          progress: { _ in })
        #expect(segments.isEmpty)
    }
}

/// Telling the people on the call apart: their turns, names and sample lines.
@MainActor
struct MeetingSpeakerTests {
    func segment(_ speaker: String, _ start: Double, _ end: Double) -> VoiceSegment {
        VoiceSegment(speaker: speaker, start: start, end: end)
    }

    @Test func turnsMergeASpeakersCloseSegmentsAndNumberSpeakersInOrder() {
        let turns = MeetingTranscription.turns(from: [
            segment("S7", 0, 4), segment("S7", 4.5, 9),      // one turn: a short pause
            segment("S2", 9.2, 15),
            segment("S7", 16, 20),
        ], sampleCount: 20 * 16_000, maxSeconds: 30)
        #expect(turns.map(\.speaker) == [.person(1), .person(2), .person(1)])
        #expect(turns[0].range == 0..<(9 * 16_000))
        #expect(turns[1].range.lowerBound == Int(9.2 * 16_000))
    }

    @Test func longTurnsAreSplitForTheEngine() {
        let turns = MeetingTranscription.turns(from: [segment("A", 0, 70)], sampleCount: 70 * 16_000, maxSeconds: 30)
        #expect(turns.count == 3)
        #expect(turns.allSatisfy { $0.speaker == .person(1) && $0.range.count <= 30 * 16_000 })
        #expect(turns.last?.range.upperBound == 70 * 16_000)
    }

    @Test func turnsStayInsideTheAudio() {
        let turns = MeetingTranscription.turns(from: [segment("A", 8, 12)], sampleCount: 10 * 16_000, maxSeconds: 30)
        #expect(turns.first?.range == (8 * 16_000)..<(10 * 16_000))
    }

    @Test func eachTurnIsTranscribedAndLabelled() async throws {
        let others = [Float](repeating: 0.1, count: 20 * 16_000)
        let turns = MeetingTranscription.turns(from: [segment("A", 0, 8), segment("B", 10, 20)],
                                               sampleCount: others.count, maxSeconds: 30)
        let segments = try await MeetingTranscription.run(you: [], others: others, othersTurns: turns,
                                                          session: { EchoSession($0.displayName) }, progress: { _ in })
        #expect(segments.map(\.speaker) == [.person(1), .person(2)])
        #expect(segments.map(\.text) == ["Speaker 1 8s", "Speaker 2 10s"])
    }

    @Test func namesReplaceSpeakerLabelsEverywhere() {
        let segments = [
            MeetingSegment(speaker: .person(1), start: 0, text: "Hi."),
            MeetingSegment(speaker: .person(10), start: 5, text: "Hello."),
        ]
        let names: [Speaker: String] = [.person(1): "Anna"]
        #expect(MeetingTranscription.transcript(segments, names: names) == "[0:00] Anna: Hi.\n\n[0:05] Speaker 10: Hello.")
        #expect(MeetingTranscription.rename("Speaker 1 will call Speaker 10.", names: names) == "Anna will call Speaker 10.")
    }

    @Test func eachSpeakerGetsASampleLine() {
        let segments = [
            MeetingSegment(speaker: .you, start: 0, text: "Shall we start?"),
            MeetingSegment(speaker: .person(1), start: 3, text: "Yes."),
            MeetingSegment(speaker: .person(1), start: 9, text: "The numbers came in yesterday, all good."),
        ]
        let samples = MeetingTranscription.samples(segments)
        #expect(samples.map(\.speaker) == [.person(1)])
        #expect(samples.first?.line == "The numbers came in yesterday, all good.")
    }
}

