import AVFoundation
import Foundation
import Testing
import Dictation
@testable import Parakeet

/// Downloads the real models (~14 MB) into a temporary folder and tells two voices apart.
/// Opt-in: WISKA_LIVE_DIARIZATION=<folder with a1, b1, a2, b2 .aiff>.
struct SpeakerDiarizerLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_LIVE_DIARIZATION"] != nil))
    func twoVoicesAreToldApart() async throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WISKA_LIVE_DIARIZATION"]!)
        var samples: [Float] = []
        var expected: [(String, Double, Double)] = []
        for name in ["a1", "b1", "a2", "b2"] {
            let start = Double(samples.count) / 16_000
            samples += try load(folder.appendingPathComponent("\(name).aiff"))
            expected.append((String(name.prefix(1)), start, Double(samples.count) / 16_000))
            samples += [Float](repeating: 0, count: 8_000)   // half a second between turns
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("diarizer-\(UUID())")
            .appendingPathComponent("speaker-diarization-coreml")
        try await DiarizerDownloader().download(to: directory, progress: { _ in })
        let segments = try await SpeakerDiarizer.segments(in: samples, directory: directory)
        print("DIARIZATION", segments.map { "\($0.speaker) \(String(format: "%.1f–%.1f", $0.start, $0.end))" })
        // Each expected turn's middle is covered by one speaker; a's turns share one, b's the other.
        func speaker(at time: Double) -> String? { segments.first { $0.start <= time && time <= $0.end }?.speaker }
        let found = expected.map { speaker(at: ($0.1 + $0.2) / 2) }
        print("TURNS", found)
        #expect(found[0] != nil && found[0] == found[2])
        #expect(found[1] != nil && found[1] == found[3])
        #expect(found[0] != found[1])
    }

    /// b cuts in over the middle of a's long turn, mixed into one track like a call: the turns
    /// never overlap, so no audio is transcribed twice.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_LIVE_DIARIZATION"] != nil))
    func talkingOverSomeoneGivesTurnsThatDontOverlap() async throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WISKA_LIVE_DIARIZATION"]!)
        var samples = try load(folder.appendingPathComponent("a1.aiff")) + load(folder.appendingPathComponent("a2.aiff"))
        let interjection = try load(folder.appendingPathComponent("b1.aiff"))
        let at = samples.count / 2
        samples += [Float](repeating: 0, count: max(0, at + interjection.count - samples.count))
        for index in interjection.indices { samples[at + index] += interjection[index] }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("diarizer-\(UUID())")
            .appendingPathComponent("speaker-diarization-coreml")
        try await DiarizerDownloader().download(to: directory, progress: { _ in })
        let voices = try await SpeakerDiarizer.segments(in: samples, directory: directory)
            .map { VoiceSegment(speaker: $0.speaker, start: $0.start, end: $0.end) }
        print("DIARIZATION", voices.map { "\($0.speaker) \(String(format: "%.1f–%.1f", $0.start, $0.end))" })
        let turns = MeetingTranscription.turns(from: voices, sampleCount: samples.count, audio: samples)
        print("TURNS", turns.map { "\($0.speaker.displayName)\($0.over.map { " over \($0.displayName)" } ?? "") "
            + String(format: "%.1f–%.1f", Double($0.range.lowerBound) / 16_000, Double($0.range.upperBound) / 16_000) })
        #expect(zip(turns, turns.dropFirst()).allSatisfy { $0.range.upperBound <= $1.range.lowerBound })
        #expect(turns.first?.speaker == .person(1))
    }

    func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: file.processingFormat, to: output)!
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: input)
        let result = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 1_024)!
        var given = false
        _ = converter.convert(to: result, error: nil) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true
            status.pointee = .haveData
            return input
        }
        return Array(UnsafeBufferPointer(start: result.floatChannelData![0], count: Int(result.frameLength)))
    }
}
