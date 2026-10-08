import AVFoundation
import Core
import Foundation
import Testing
@testable import Parakeet

final class FakeBackend: SpeechRecognizerBackend, @unchecked Sendable {
    var text = "Kan du skicka rapporten till mig innan lunch imorgon?"
    var receivedCounts: [Int] = []
    func transcribe(_ samples: [Float]) async throws -> String {
        receivedCounts.append(samples.count)
        return text
    }
}

@MainActor
struct ParakeetTests {
    @Test func guessesSwedishAndEnglish() {
        #expect(LanguageGuess.detect("Kan du skicka rapporten till mig innan lunch imorgon") == .swedish)
        #expect(LanguageGuess.detect("Can you send me the quarterly report before lunch") == .english)
        #expect(LanguageGuess.detect("") == nil)
    }

    @Test func sessionTranscribesBufferedAudioAndDetectsLanguage() async throws {
        let backend = FakeBackend()
        let session = ParakeetSession(backend: backend)
        session.append(AudioChunk(samples: Array(repeating: 0.1, count: 16_000)))
        session.append(AudioChunk(samples: Array(repeating: 0.1, count: 8_000)))
        let transcript = try await session.finish()
        #expect(backend.receivedCounts == [24_000])
        #expect(transcript.language == .swedish)
        #expect(transcript.locale.identifier == "sv_SE")
        #expect(transcript.text.hasPrefix("Kan du"))
    }

    @Test func shortAudioIsPaddedToOneSecond() async throws {
        let backend = FakeBackend()
        let session = ParakeetSession(backend: backend)
        session.append(AudioChunk(samples: Array(repeating: 0.1, count: 4_000)))
        _ = try await session.finish()
        #expect(backend.receivedCounts == [16_000])
    }

    @Test func noAudioGivesEmptyTranscriptWithoutCallingBackend() async throws {
        let backend = FakeBackend()
        let transcript = try await ParakeetSession(backend: backend).finish()
        #expect(transcript.text.isEmpty)
        #expect(backend.receivedCounts.isEmpty)
    }

    @Test func cancelledSessionDoesNotTranscribe() async throws {
        let backend = FakeBackend()
        let session = ParakeetSession(backend: backend)
        session.append(AudioChunk(samples: [0.1]))
        session.cancel()
        let transcript = try await session.finish()
        #expect(transcript.text.isEmpty)
        #expect(backend.receivedCounts.isEmpty)
    }

    @Test func transcriberRefusesWhenModelMissing() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        let transcriber = ParakeetTranscriber(store: store, loader: { _ in FakeBackend() })
        await #expect(throws: ParakeetError.modelNotInstalled) { try await transcriber.prepare() }
        #expect(!transcriber.isReady)
    }

    @Test func transcriberLoadsAndMakesSessions() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true))
        let transcriber = ParakeetTranscriber(store: store, loader: { _ in FakeBackend() })
        try await transcriber.prepare()
        #expect(transcriber.isReady)
        let session = try await transcriber.makeSession(language: .fixed(.english))   // choice ignored
        session.append(AudioChunk(samples: Array(repeating: 0.1, count: 16_000)))
        #expect(try await session.finish().language == .swedish)
    }

    @Test func removingModelMakesTranscriberNotReady() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true))
        let transcriber = ParakeetTranscriber(store: store, loader: { _ in FakeBackend() })
        try await transcriber.prepare()
        store.remove()
        #expect(!transcriber.isReady)
    }

    @Test(.enabled(if: FluidAudioDownloader().exists(at: ParakeetModelStore.defaultDirectory)),
          .timeLimit(.minutes(3)))
    func realParakeetTranscribesEnglish() async throws {
        let transcriber = ParakeetTranscriber(store: ParakeetModelStore())
        try await transcriber.prepare()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pk-\(UUID().uuidString).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Samantha", "-o", url.path, "hello world this is a test"]
        try say.run()
        say.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFileReader.samples16k(url)
        let session = try await transcriber.makeSession(language: .automatic)
        session.append(AudioChunk(samples: file))
        let transcript = try await session.finish()
        #expect(transcript.text.lowercased().contains("hello world"))
    }
}

enum AVAudioFileReader {
    static func samples16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return try PCMConverter(from: file.processingFormat, to: .speech16kMono).convert(buffer).floatSamples
    }
}
