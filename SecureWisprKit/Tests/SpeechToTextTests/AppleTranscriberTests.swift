import AVFoundation
import Core
import Foundation
import Speech
import Testing
@testable import SpeechToText

@MainActor
struct AppleTranscriberTests {
    /// Speaks `text` with the system voice into a temp AIFF and returns 16 kHz mono samples.
    private func spokenSamples(_ text: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("securewispr-\(UUID().uuidString).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, text]
        try say.run()
        say.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: buffer)
        return try PCMConverter(from: file.processingFormat, to: .speech16kMono).convert(buffer).floatSamples
    }

    @Test(.enabled(if: SpeechTranscriber.isAvailable), .timeLimit(.minutes(2)))
    func transcribesSpokenEnglish() async throws {
        let samples = try spokenSamples("hello world this is a test")
        let transcriber = AppleTranscriber()
        let session = try await transcriber.makeSession(language: .fixed(.english))
        // Feed in 100 ms chunks, like the microphone does.
        for start in stride(from: 0, to: samples.count, by: 1_600) {
            session.append(AudioChunk(samples: Array(samples[start..<min(start + 1_600, samples.count)])))
        }
        let transcript = try await session.finish()
        // SpeechTranscriber punctuates ("Hello, world, this is a test."), so compare letters only.
        let words = transcript.text.lowercased().filter { $0.isLetter || $0 == " " }
        #expect(words.contains("hello world this is a test"))
        #expect(transcript.locale.identifier.hasPrefix("en"))
        #expect(transcriber.isReady)
    }

    @Test(.enabled(if: SpeechTranscriber.isAvailable), .timeLimit(.minutes(1)))
    func silenceGivesEmptyText() async throws {
        let session = try await AppleTranscriber().makeSession(language: .fixed(.english))
        session.append(AudioChunk(samples: Array(repeating: 0, count: 16_000)))
        let transcript = try await session.finish()
        #expect(transcript.text.isEmpty)
    }
}
