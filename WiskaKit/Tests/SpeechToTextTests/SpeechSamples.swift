import AVFoundation
import Core
import Foundation
import Testing

/// Real speech for tests: a system voice speaking a sentence, as 16 kHz mono samples.
enum SpeechSamples {
    static func spoken(_ text: String, voice: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wiska-\(UUID().uuidString).aiff")
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

    /// Feeds audio in 100 ms chunks, like the microphone does, and returns the transcript.
    @MainActor
    static func transcribe(_ audio: [Float], with session: any TranscriptionSession) async throws -> Transcript {
        for start in stride(from: 0, to: audio.count, by: 1_600) {
            session.append(AudioChunk(samples: Array(audio[start..<min(start + 1_600, audio.count)])))
        }
        return try await session.finish()
    }
}
