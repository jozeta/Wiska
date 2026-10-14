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

    @Test func anInterjectionIsNeverGluedIntoAnotherTurn() {
        let turns = MeetingTranscription.turns(from: [
            segment("A", 0, 4), segment("B", 4.2, 4.8), segment("A", 5, 9),
        ], sampleCount: 9 * 16_000)
        #expect(turns.map(\.speaker) == [.person(1), .person(2), .person(1)])
        #expect(turns[1].range == Int(4.2 * 16_000)..<Int(4.8 * 16_000))
    }

    @Test func overlappingAudioGoesToWhoeverWasTalking() {
        let turns = MeetingTranscription.turns(from: [segment("A", 0, 10), segment("B", 8, 14)],
                                               sampleCount: 14 * 16_000)
        #expect(turns.map(\.range) == [0..<(10 * 16_000), (10 * 16_000)..<(14 * 16_000)])
        #expect(turns.map(\.over) == [nil, .person(1)])
    }

    @Test func aVoiceEntirelyInsideAnotherTurnIsNotTranscribedTwice() {
        let turns = MeetingTranscription.turns(from: [segment("A", 0, 10), segment("B", 3, 5), segment("C", 11, 15)],
                                               sampleCount: 15 * 16_000)
        #expect(turns.map(\.speaker) == [.person(1), .person(2)])   // C is the second voice heard on its own
        #expect(turns.map(\.range) == [0..<(10 * 16_000), (11 * 16_000)..<(15 * 16_000)])
    }

    @Test func longTurnsAreSplitAtAPause() {
        // 40 s of speech with a pause at 22–23 s: the split lands in the pause, not mid-word at 30 s.
        let speech: (Int) -> [Float] = { seconds in (0..<(seconds * 16_000)).map { Float(sin(Double($0) * 0.05) * 0.3) } }
        let audio = speech(22) + [Float](repeating: 0, count: 16_000) + speech(17)
        let turns = MeetingTranscription.turns(from: [segment("A", 0, 40)], sampleCount: audio.count, audio: audio)
        #expect(turns.count == 2)
        #expect((22 * 16_000...23 * 16_000).contains(turns[0].range.upperBound))
        #expect(turns[1].range.lowerBound == turns[0].range.upperBound)
        #expect(turns.map(\.over) == [nil, nil])
    }

    @Test func talkingOverSomeoneIsShownAndNotMergedAway() {
        let segments = [
            MeetingSegment(speaker: .person(1), start: 0, text: "The budget is fine."),
            MeetingSegment(speaker: .person(2), start: 10, text: "Not quite.", over: .person(1)),
            MeetingSegment(speaker: .person(2), start: 12, text: "We're over by a bit."),
        ]
        #expect(MeetingTranscription.transcript(segments, names: [.person(1): "Anna"]) == """
        [0:00] Anna: The budget is fine.

        [0:10] Speaker 2 (over Anna): Not quite. We're over by a bit.
        """)
    }

    @Test func aTurnsOverlapCarriesIntoItsSegment() async throws {
        let others = [Float](repeating: 0.1, count: 14 * 16_000)
        let turns = MeetingTranscription.turns(from: [segment("A", 0, 10), segment("B", 8, 14)], sampleCount: others.count)
        let segments = try await MeetingTranscription.run(you: [], others: others, othersTurns: turns,
                                                          session: { EchoSession($0.displayName) }, progress: { _ in })
        #expect(segments.map(\.over) == [nil, .person(1)])
    }
}

/// Without headphones the microphone hears the call too: that leak isn't you speaking.
@MainActor
struct MeetingBleedTests {
    func tone(_ seconds: Double, _ step: Double, _ level: Float) -> [Float] {
        (0..<Int(seconds * 16_000)).map { Float(sin(Double($0) * step)) * level }
    }
    func quiet(_ seconds: Double) -> [Float] { Array(repeating: 0, count: Int(seconds * 16_000)) }
    /// The call as the microphone hears it from the speakers: quieter and a little late.
    func leak(_ call: [Float]) -> [Float] { Array((quiet(0.01) + call.map { $0 * 0.2 }).prefix(call.count)) }
    func rms(_ samples: ArraySlice<Float>) -> Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1))).squareRoot()
    }

    @Test func theCallLeakingIntoTheMicIsRemoved() {
        let call = tone(3, 0.05, 0.3) + quiet(1) + tone(3, 0.07, 0.3)
        let cleaned = MeetingTranscription.withoutBleed(leak(call), call: call)
        #expect(rms(cleaned.audio[...]) < MeetingTranscription.silence)
        #expect(cleaned.removed > 5 * 16_000)
    }

    @Test func yourVoiceOverTheLeakIsKept() {
        let call = tone(10, 0.05, 0.3)
        var mic = leak(call)
        let yours = tone(2, 0.11, 0.3)
        for index in yours.indices { mic[4 * 16_000 + index] += yours[index] }
        let cleaned = MeetingTranscription.withoutBleed(mic, call: call).audio
        #expect(cleaned[(4 * 16_000)..<(6 * 16_000)] == mic[(4 * 16_000)..<(6 * 16_000)])
        // Away from your words' edges (50 ms is kept either side), the leak is gone.
        #expect(rms(cleaned[0..<(3_800 * 16)]) < MeetingTranscription.silence)
        #expect(rms(cleaned[(6_200 * 16)...]) < MeetingTranscription.silence)
    }

    @Test func withHeadphonesNothingChanges() {
        let mic = tone(3, 0.11, 0.3) + quiet(7)
        let call = quiet(5) + tone(5, 0.05, 0.3)
        let cleaned = MeetingTranscription.withoutBleed(mic, call: call)
        #expect(cleaned.audio == mic)
    }

    @Test func aMicThatOnlyHeardTheCallGivesNoLinesOfYours() async throws {
        let call = tone(8, 0.05, 0.3)
        let segments = try await MeetingTranscription.run(you: leak(call), others: call, every: 10, searching: 1,
                                                          session: { EchoSession($0.displayName) }, progress: { _ in })
        #expect(segments.map(\.speaker) == [.others])
    }
}

