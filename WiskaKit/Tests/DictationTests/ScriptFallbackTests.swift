import Core
import Testing
@testable import Dictation

@MainActor
struct ScriptFallbackTests {
    let parakeet = SessionsTranscriber(.parakeet)
    let apple = SessionsTranscriber(.apple)

    func run(_ heard: String, choice: LanguageChoice = .automatic) async throws -> Transcript {
        let transcriber = ScriptFallbackTranscriber(primary: parakeet, fallback: apple)
        let session = try await transcriber.makeSession(language: choice)
        parakeet.sessions[SessionsTranscriber.key(choice)]!.result = .success(heard)
        session.append(AudioChunk(samples: [0.1, 0.2]))
        session.append(AudioChunk(samples: [0.3]))
        return try await session.finish()
    }

    @Test func latinTextIsKept() async throws {
        let transcript = try await run("git status")
        #expect(transcript.text == "git status")
        #expect(apple.sessions.isEmpty)
    }

    @Test func accentedLatinIsKept() async throws {
        #expect(try await run("Vi ses på fredag, Øystein. Ça va? Größe").text == "Vi ses på fredag, Øystein. Ça va? Größe")
        #expect(apple.sessions.isEmpty)
    }

    /// Parakeet heard "git status" as Russian: Apple re-transcribes the same audio.
    @Test func foreignScriptIsRetranscribedByApple() async throws {
        let transcriber = ScriptFallbackTranscriber(primary: parakeet, fallback: apple)
        let session = try await transcriber.makeSession(language: .fixed(.english))
        parakeet.sessions[SessionsTranscriber.key(.fixed(.english))]!.result = .success("Кит стейтас")
        session.append(AudioChunk(samples: [0.1, 0.2]))
        session.append(AudioChunk(samples: [0.3]))
        // Apple's session is made only when needed, after Parakeet's text is in.
        #expect(apple.sessions.isEmpty)
        let transcript = try await session.finish()
        #expect(transcript.text == "hello world")   // the fake Apple session's text
        #expect(transcript.engine == .apple)
        #expect(apple.sessions[SessionsTranscriber.key(.fixed(.english))]!.appended == [[0.1, 0.2], [0.3]])
    }

    @Test func appleNotReadyKeepsParakeetsText() async throws {
        apple.isReady = false
        #expect(try await run("Кит стейтас").text == "Кит стейтас")
        #expect(apple.sessions.isEmpty)
    }

    @Test func appleFailureKeepsParakeetsText() async throws {
        apple.failToStart = ["auto"]
        #expect(try await run("Кит стейтас").text == "Кит стейтас")
    }

    @Test func cancelReachesThePrimary() async throws {
        let transcriber = ScriptFallbackTranscriber(primary: parakeet, fallback: apple)
        let session = try await transcriber.makeSession(language: .automatic)
        session.cancel()
        #expect(parakeet.sessions["auto"]!.cancelled)
    }
}
