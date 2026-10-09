import AVFoundation
import Core
import Foundation
import Testing
@testable import KBWhisper

/// KB-Whisper on macOS's Swedish voice. `WISKA_REAL_MODEL=1 swift test --filter KBWhisperRealTests`
/// (or through xcodebuild with TEST_RUNNER_WISKA_REAL_MODEL=1). Needs the downloaded model.
@MainActor
struct KBWhisperRealTests {
    nonisolated static var enabled: Bool { ProcessInfo.processInfo.environment["WISKA_REAL_MODEL"] == "1" }

    static func spoken(_ text: String, voice: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wiska-\(UUID().uuidString).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, text]
        try say.run()
        say.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return try PCMConverter(from: file.processingFormat, to: .speech16kMono).convert(buffer).floatSamples
    }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(5)))
    func transcribesSwedish() async throws {
        let recognizer = KBWhisperRecognizer(store: KBWhisperModelStore())
        #expect(recognizer.isReady)
        let samples = try Self.spoken("Jag har ett stort hus och en liten trädgård.", voice: "Alva")
        let start = ContinuousClock.now
        let text = try await recognizer.transcribe(samples, language: .swedish)
        print("KB:", text.debugDescription, ContinuousClock.now - start)
        #expect(text.lowercased().contains("ett stort hus"), "\(text)")
        // Loaded now: the time a dictation sees after the fn press has loaded the model.
        let warmStart = ContinuousClock.now
        let again = try await recognizer.transcribe(samples, language: .swedish)
        print("KB warm:", again.debugDescription, ContinuousClock.now - warmStart)
    }
}
