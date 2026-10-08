import Core
import Dictation
import Foundation
import SpeechToText
import Testing
@testable import Parakeet

@MainActor
struct HybridRealAudioTests {
    func speak(_ text: String, voice: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hy-\(UUID().uuidString).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, text]
        try say.run()
        say.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: url) }
        return try AVAudioFileReader.samples16k(url)
    }

    func transcribe(_ samples: [Float]) async throws -> Transcript {
        let parakeet = ParakeetTranscriber(store: ParakeetModelStore())
        try await parakeet.prepare()
        let hybrid = HybridTranscriber(parakeet: parakeet, apple: AppleTranscriber(),
                                       appleLanguages: [.swedish], fallbackLanguage: { .english })
        let session = try await hybrid.makeSession(language: .automatic)
        for start in stride(from: 0, to: samples.count, by: 1_600) {
            session.append(AudioChunk(samples: Array(samples[start..<min(start + 1_600, samples.count)])))
        }
        return try await session.finish()
    }

    @Test(.enabled(if: ParakeetTests.completedInstallPresent), .timeLimit(.minutes(3)))
    func englishComesFromParakeet() async throws {
        let transcript = try await transcribe(try speak("Can you send me the quarterly report before lunch tomorrow",
                                                        voice: "Samantha"))
        #expect(transcript.engine == .parakeet)
        #expect(transcript.text.lowercased().contains("quarterly report"))
    }

    @Test(.enabled(if: ParakeetTests.completedInstallPresent), .timeLimit(.minutes(3)))
    func swedishComesFromApple() async throws {
        let transcript = try await transcribe(try speak(
            "Vi gick igenom siffrorna för tredje kvartalet och resultatet ser bättre ut än väntat", voice: "Alva"))
        #expect(transcript.engine == .apple)
        #expect(transcript.language == .swedish)
        #expect(transcript.text.lowercased().contains("gick igenom"))
    }
}
