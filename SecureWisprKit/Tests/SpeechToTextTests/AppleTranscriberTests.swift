import AVFoundation
import Core
import Foundation
import Speech
import Testing
@testable import SpeechToText

@MainActor
struct AppleTranscriberTests {
    /// Speaks `text` with the system voice into a temp AIFF and returns 16 kHz mono samples.
    private func spokenSamples(_ text: String, voice: String = "Samantha") throws -> [Float] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("securewispr-\(UUID().uuidString).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, text]
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

    private func transcribe(_ samples: [Float], _ choice: LanguageChoice,
                            transcriber: AppleTranscriber = AppleTranscriber()) async throws -> Transcript {
        let session = try await transcriber.makeSession(language: choice)
        for start in stride(from: 0, to: samples.count, by: 1_600) {
            session.append(AudioChunk(samples: Array(samples[start..<min(start + 1_600, samples.count)])))
        }
        return try await session.finish()
    }

    @Test(.timeLimit(.minutes(2)))
    func transcribesSpokenSwedish() async throws {
        let samples = try spokenSamples("Kan du skicka rapporten till mig innan lunch imorgon", voice: "Alva")
        let transcript = try await transcribe(samples, .fixed(.swedish))
        #expect(transcript.text.lowercased().contains("rapporten"))
        #expect(transcript.language == .swedish)
        #expect(transcript.locale.identifier == "sv_SE")
        #expect((transcript.confidence ?? 0) > 0.5)
    }

    @Test(.timeLimit(.minutes(2)))
    func englishTranscriptCarriesConfidenceAndLanguage() async throws {
        let samples = try spokenSamples("Can you send me the quarterly report before lunch tomorrow")
        let transcript = try await transcribe(samples, .fixed(.english))
        #expect(transcript.language == .english)
        #expect((transcript.confidence ?? 0) > 0.5)
    }

    @Test func transcriberIsReadyOnlyAfterBothLanguagesPrepared() async throws {
        let transcriber = AppleTranscriber()
        #expect(!transcriber.isReady)
        try await transcriber.prepare()
        #expect(transcriber.isReady)
    }
}
