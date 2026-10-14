import Core
import Foundation
import Testing
@testable import KBWhisper

struct FakeWhisper: WhisperModel {
    func transcribe(_ samples: [Float], language: String, prompt: String?) throws -> String { "\(language): \(samples.count)" }
}

@MainActor
struct KBWhisperRecognizerTests {
    func readyStore() -> KBWhisperModelStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kb-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data("x".utf8).write(to: directory.appendingPathComponent(KBWhisperModelStore.fileName))
        try? Data().write(to: directory.appendingPathComponent(KBWhisperModelStore.completionMarker))
        return KBWhisperModelStore(directory: directory, downloader: FakeFileDownloader(), freeSpace: { nil })
    }

    @Test func transcribesSwedishThroughTheRuntime() async throws {
        let recognizer = KBWhisperRecognizer(store: readyStore(),
                                             runtime: ModelRuntime<any WhisperModel> { _ in FakeWhisper() })
        #expect(recognizer.isReady)
        #expect(try await recognizer.transcribe([0, 0, 0], language: .swedish) == "sv: 3")
        #expect(recognizer.isLoaded)
        await #expect(throws: (any Error).self) { try await recognizer.transcribe([0], language: .english) }
    }

    @Test func loadFailureMakesItUnavailableUntilRemoved() async {
        let recognizer = KBWhisperRecognizer(store: readyStore(), runtime: ModelRuntime<any WhisperModel> { _ in
            throw CocoaError(.fileReadCorruptFile)
        })
        await #expect(throws: (any Error).self) { try await recognizer.transcribe([0], language: .swedish) }
        #expect(!recognizer.isReady)
        #expect(recognizer.loadError != nil)
        recognizer.remove()
        #expect(recognizer.loadError == nil)
    }

    @Test func prepareLoadsInTheBackground() async throws {
        let recognizer = KBWhisperRecognizer(store: readyStore(),
                                             runtime: ModelRuntime<any WhisperModel> { _ in FakeWhisper() })
        recognizer.prepare()
        try await Task.sleep(for: .milliseconds(100))
        #expect(recognizer.isLoaded)
    }

    @Test func statusTexts() {
        #expect(KBWhisperRecognizer.statusText(.notDownloaded, loaded: false, loadError: nil) == "Not downloaded")
        #expect(KBWhisperRecognizer.statusText(.downloading(0.42), loaded: false, loadError: nil) == "Downloading 42 %")
        #expect(KBWhisperRecognizer.statusText(.ready, loaded: false, loadError: nil) == "Ready")
        #expect(KBWhisperRecognizer.statusText(.ready, loaded: true, loadError: nil) == "Loaded")
        #expect(KBWhisperRecognizer.statusText(.ready, loaded: false, loadError: "bad") == "Couldn't load: bad")
        #expect(KBWhisperRecognizer.statusText(.failed("Needs about 2 GB free"), loaded: false, loadError: nil)
                == "Needs about 2 GB free")
    }
}

struct WhisperPaddingTests {
    /// whisper.cpp ignores input under 1 s: short clips ("Ja", "Tack") are padded with silence.
    @Test func shortClipsArePadded() {
        #expect(WhisperContext.padded([Float](repeating: 0.5, count: 8_000)).count == 19_200)
        #expect(WhisperContext.padded([Float](repeating: 0.5, count: 8_000)).prefix(8_000).allSatisfy { $0 == 0.5 })
        #expect(WhisperContext.padded([Float](repeating: 0.5, count: 40_000)).count == 40_000)
    }
}
