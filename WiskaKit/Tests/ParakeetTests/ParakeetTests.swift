import AVFoundation
import Core
import Foundation
import Testing
@testable import Parakeet

struct StubLoadError: Error {}

final class FakeBackend: SpeechRecognizerBackend, @unchecked Sendable {
    var text = "Kan du skicka rapporten till mig innan lunch imorgon?"
    var receivedCounts: [Int] = []
    func transcribe(_ samples: [Float]) async throws -> String {
        receivedCounts.append(samples.count)
        return text
    }
}

final class CountingLoader: @unchecked Sendable {
    var calls = 0
    var fail = false
    var delay: Duration = .zero
}

@MainActor
struct ParakeetTests {
    private func installedStore() throws -> ParakeetModelStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent(ParakeetModelStore.completionMarker))
        return ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true))
    }

    private func transcriber(_ store: ParakeetModelStore, _ counter: CountingLoader) -> ParakeetTranscriber {
        ParakeetTranscriber(store: store, loader: { _ in
            counter.calls += 1
            if counter.delay > .zero { try await Task.sleep(for: counter.delay) }
            if counter.fail { throw StubLoadError() }
            return FakeBackend()
        })
    }

    @Test func concurrentPreparesLoadOnce() async throws {
        let counter = CountingLoader()
        counter.delay = .milliseconds(50)
        let t = transcriber(try installedStore(), counter)
        async let a: Void = t.prepare()
        async let b: Void = t.prepare()
        _ = try await (a, b)
        #expect(counter.calls == 1)
    }

    @Test func failedLoadIsNotRetriedOnEveryPress() async throws {
        let counter = CountingLoader()
        counter.fail = true
        let t = transcriber(try installedStore(), counter)
        _ = try? await t.prepare()
        _ = try? await t.prepare()
        #expect(counter.calls == 1)
        t.forgetLoadFailure()
        counter.fail = false
        try await t.prepare()
        #expect(counter.calls == 2)
        #expect(t.isReady)
    }
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
        let store = try installedStore()
        let transcriber = ParakeetTranscriber(store: store, loader: { _ in FakeBackend() })
        try await transcriber.prepare()
        #expect(transcriber.isReady)
        let session = try await transcriber.makeSession(language: .fixed(.english))   // choice ignored
        session.append(AudioChunk(samples: Array(repeating: 0.1, count: 16_000)))
        #expect(try await session.finish().language == .swedish)
    }

    @Test func removingModelMakesTranscriberNotReady() async throws {
        let store = try installedStore()
        let transcriber = ParakeetTranscriber(store: store, loader: { _ in FakeBackend() })
        try await transcriber.prepare()
        store.remove()
        #expect(!transcriber.isReady)
    }

    @Test func removingModelReleasesTheLoadedModel() async throws {
        let store = try installedStore()
        weak var loaded: FakeBackend?
        let transcriber = ParakeetTranscriber(store: store, loader: { _ in
            let backend = FakeBackend()
            loaded = backend
            return backend
        })
        try await transcriber.prepare()
        #expect(loaded != nil)
        store.remove()
        #expect(loaded == nil)
    }

    /// Only run against a *completed* install made by the app: constructing a store on an
    /// unmarked folder deletes it as a partial download, and tests must never touch user data.
    nonisolated static var completedInstallPresent: Bool {
        let dir = ParakeetModelStore.defaultDirectory
        return FluidAudioDownloader().exists(at: dir) && FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(ParakeetModelStore.completionMarker).path)
    }

    @Test(.enabled(if: ParakeetTests.completedInstallPresent),
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
