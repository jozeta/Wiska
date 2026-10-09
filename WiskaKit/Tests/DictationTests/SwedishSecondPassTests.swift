import Core
import Testing
@testable import Dictation

@MainActor
final class FakeRecognizer: BatchRecognizer {
    var isReady = true
    var text = "Jag har ett stort hus."
    var error: Error?
    var delay: Duration = .zero
    private(set) var prepared = 0
    private(set) var heard: [[Float]] = []
    func prepare() { prepared += 1 }
    func transcribe(_ samples: [Float], language: Language) async throws -> String {
        heard.append(samples)
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return text
    }
}

@MainActor
struct SwedishSecondPassTests {
    let primary = SessionsTranscriber(.apple)
    let recognizer = FakeRecognizer()

    func run(_ heard: String, language: Language?, enabled: Bool = true,
             samples: Int = 2) async throws -> Transcript {
        let transcriber = SwedishSecondPassTranscriber(primary: primary, recognizer: recognizer, isEnabled: { enabled })
        let session = try await transcriber.makeSession(language: .automatic)
        let fake = primary.sessions[SessionsTranscriber.key(.automatic)]!
        fake.result = .success(heard)
        fake.language = language
        session.append(AudioChunk(samples: Array(repeating: 0.1, count: samples)))
        return try await session.finish()
    }

    @Test func swedishIsRetranscribed() async throws {
        let transcript = try await run("jag har en stor hus", language: .swedish)
        #expect(transcript.text == "Jag har ett stort hus.")
        #expect(transcript.engine == .kbWhisper)
        #expect(transcript.language == .swedish)
        #expect(recognizer.heard == [[0.1, 0.1]])
    }

    @Test func otherLanguagesAndTheSwitchOffAreUntouched() async throws {
        #expect(try await run("hello there", language: .english).text == "hello there")
        #expect(try await run("jag har en stor hus", language: .swedish, enabled: false).text == "jag har en stor hus")
        recognizer.isReady = false
        #expect(try await run("jag har en stor hus", language: .swedish).text == "jag har en stor hus")
        #expect(recognizer.heard.isEmpty)
    }

    @Test func failuresAndJunkKeepTheFirstEngine() async throws {
        recognizer.error = CancellationError()
        #expect(try await run("jag har en stor hus", language: .swedish).text == "jag har en stor hus")
        recognizer.error = nil
        recognizer.text = "Tack för att du tittade!"
        #expect(try await run("hm", language: .swedish).text == "hm")
    }

    @Test func slowSecondPassFallsBackInTime() async throws {
        recognizer.delay = .seconds(10)
        let start = ContinuousClock.now
        let transcript = try await run("jag har en stor hus", language: .swedish)
        #expect(transcript.text == "jag har en stor hus")
        #expect(ContinuousClock.now - start < .seconds(4))
    }

    @Test func budgetGrowsWithLength() {
        #expect(SecondPassSession.budget(forSamples: 16_000 * 5) == .seconds(3))
        #expect(SecondPassSession.budget(forSamples: 16_000 * 120) == .seconds(30))
    }

    /// fn press: the model starts loading while the user speaks — only when it may be used.
    @Test func prepareIsCalledAtSessionStart() async throws {
        _ = try await SwedishSecondPassTranscriber(primary: primary, recognizer: recognizer, isEnabled: { true })
            .makeSession(language: .automatic)
        #expect(recognizer.prepared == 1)
        _ = try await SwedishSecondPassTranscriber(primary: primary, recognizer: recognizer, isEnabled: { false })
            .makeSession(language: .automatic)
        #expect(recognizer.prepared == 1)
    }

    @Test func forwardsReadinessAndEngine() {
        let transcriber = SwedishSecondPassTranscriber(primary: primary, recognizer: recognizer, isEnabled: { true })
        #expect(transcriber.engine == .apple)
        #expect(transcriber.isReady == primary.isReady)
    }
}

/// Cleanup pass: no load and no kept audio when KB-Whisper can't be used for this dictation.
@MainActor
struct SwedishSecondPassCleanupTests {
    let primary = SessionsTranscriber(.apple)
    let recognizer = FakeRecognizer()

    /// fn+⇧ fixed to English: KB-Whisper (1.5 GB) isn't loaded for it.
    @Test func noLoadForAnotherFixedLanguage() async throws {
        let transcriber = SwedishSecondPassTranscriber(primary: primary, recognizer: recognizer, isEnabled: { true })
        _ = try await transcriber.makeSession(language: .fixed(.english))
        #expect(recognizer.prepared == 0)
        _ = try await transcriber.makeSession(language: .fixed(.swedish))
        _ = try await transcriber.makeSession(language: .automatic)
        #expect(recognizer.prepared == 2)
    }

    /// The recording is only kept when the second pass can run.
    @Test func audioIsOnlyKeptWhenUsable() async throws {
        let off = try await SwedishSecondPassTranscriber(primary: primary, recognizer: recognizer, isEnabled: { false })
            .makeSession(language: .automatic) as! SecondPassSession
        #expect(!off.keepsAudio)
        recognizer.isReady = false
        let notInstalled = try await SwedishSecondPassTranscriber(primary: primary, recognizer: recognizer, isEnabled: { true })
            .makeSession(language: .automatic) as! SecondPassSession
        #expect(!notInstalled.keepsAudio)
        let english = try await SwedishSecondPassTranscriber(primary: primary, recognizer: FakeRecognizer(), isEnabled: { true })
            .makeSession(language: .fixed(.english)) as! SecondPassSession
        #expect(!english.keepsAudio)
        let usable = try await SwedishSecondPassTranscriber(primary: primary, recognizer: FakeRecognizer(), isEnabled: { true })
            .makeSession(language: .automatic) as! SecondPassSession
        #expect(usable.keepsAudio)
    }
}
