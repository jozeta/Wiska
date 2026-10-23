import Core
import Foundation
import Testing
@testable import Dictation

/// Returns a fresh FakeSession per language choice, so each engine/language is observable.
@MainActor
final class SessionsTranscriber: Transcriber {
    var isReady = true
    var unreadyLanguages: Set<Language> = []
    var failToStart: Set<String> = []
    private(set) var sessions: [String: FakeSession] = [:]
    let name: SpeechEngine
    init(_ name: SpeechEngine) { self.name = name }
    var engine: SpeechEngine { name }
    func prepare() async throws {}
    func isReady(for language: Language) -> Bool { isReady && !unreadyLanguages.contains(language) }

    static func key(_ choice: LanguageChoice) -> String {
        switch choice {
        case .automatic: "auto"
        case .fixed(let language): language.rawValue
        }
    }

    func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        let key = Self.key(language)
        if failToStart.contains(key) { throw FakeError() }
        let session = FakeSession()
        sessions[key] = session
        return session
    }
}

@MainActor
struct HybridTranscriberTests {
    let parakeet = SessionsTranscriber(.parakeet)
    let apple = SessionsTranscriber(.apple)

    func hybrid(last: Language = .english) -> HybridTranscriber {
        HybridTranscriber(parakeet: parakeet, apple: apple, appleLanguages: [.swedish],
                          fallbackLanguage: { last })
    }

    func run(_ transcriber: HybridTranscriber, parakeetSays text: String, language: Language?,
             appleSays appleText: String = "Apple svenska") async throws -> Transcript {
        let session = try await transcriber.makeSession(language: .automatic)
        session.append(AudioChunk(samples: [0.1]))
        parakeet.sessions["auto"]?.result = .success(text)
        parakeet.sessions["auto"]?.language = language
        apple.sessions["swedish"]?.result = .success(appleText)
        apple.sessions["swedish"]?.language = .swedish
        return try await session.finish()
    }

    @Test func audioReachesEverySession() async throws {
        let session = try await hybrid().makeSession(language: .automatic)
        session.append(AudioChunk(samples: [0.5]))
        #expect(parakeet.sessions["auto"]?.appended == [[0.5]])
        #expect(apple.sessions["swedish"]?.appended == [[0.5]])
        #expect(apple.sessions["english"] == nil)
    }

    @Test func englishUsesParakeetAndCancelsApple() async throws {
        let transcript = try await run(hybrid(), parakeetSays: "Hello there", language: .english)
        #expect(transcript.text == "Hello there")
        #expect(transcript.engine == .parakeet)
        #expect(apple.sessions["swedish"]?.cancelled == true)
    }

    @Test func swedishUsesApple() async throws {
        let transcript = try await run(hybrid(), parakeetSays: "Hej gicker", language: .swedish)
        #expect(transcript.text == "Apple svenska")
        #expect(transcript.engine == .apple)
        #expect(transcript.language == .swedish)
    }

    @Test func noLanguageGuessUsesLastLanguage() async throws {
        let transcript = try await run(hybrid(last: .swedish), parakeetSays: "ok", language: nil)
        #expect(transcript.engine == .apple)
        #expect(transcript.text == "Apple svenska")
    }

    @Test func emptyParakeetUsesFallbackLanguageEngine() async throws {
        let toEnglish = try await run(hybrid(last: .english), parakeetSays: "", language: nil)
        #expect(toEnglish.text.isEmpty)
        #expect(toEnglish.engine == .parakeet)
    }

    @Test func appleFailingFallsBackToParakeet() async throws {
        let transcriber = hybrid()
        let session = try await transcriber.makeSession(language: .automatic)
        parakeet.sessions["auto"]?.result = .success("Hej gicker")
        parakeet.sessions["auto"]?.language = .swedish
        apple.sessions["swedish"]?.result = .failure(FakeError())
        let transcript = try await session.finish()
        #expect(transcript.text == "Hej gicker")
        #expect(transcript.engine == .parakeet)
    }

    @Test func appleEmptyFallsBackToParakeet() async throws {
        let transcript = try await run(hybrid(), parakeetSays: "Hej gicker", language: .swedish, appleSays: "")
        #expect(transcript.text == "Hej gicker")
        #expect(transcript.engine == .parakeet)
    }

    @Test func parakeetFailingUsesApple() async throws {
        let transcriber = hybrid()
        let session = try await transcriber.makeSession(language: .automatic)
        parakeet.sessions["auto"]?.result = .failure(FakeError())
        apple.sessions["swedish"]?.result = .success("Apple svenska")
        apple.sessions["swedish"]?.language = .swedish
        let transcript = try await session.finish()
        #expect(transcript.text == "Apple svenska")
        #expect(transcript.engine == .apple)
    }

    @Test func everythingFailingThrows() async throws {
        let session = try await hybrid().makeSession(language: .automatic)
        parakeet.sessions["auto"]?.result = .failure(FakeError())
        apple.sessions["swedish"]?.result = .failure(FakeError())
        await #expect(throws: (any Error).self) { _ = try await session.finish() }
    }

    @Test func appleThatCannotStartLeavesParakeet() async throws {
        apple.failToStart = ["swedish"]
        let transcript = try await run(hybrid(), parakeetSays: "Hej gicker", language: .swedish)
        #expect(transcript.text == "Hej gicker")
        #expect(transcript.engine == .parakeet)
    }

    @Test func parakeetThatCannotStartUsesAppleAutoDetect() async throws {
        parakeet.failToStart = ["auto"]
        let session = try await hybrid().makeSession(language: .automatic)
        #expect(apple.sessions["auto"] != nil)
        // Started alongside Parakeet, then let go: it's never used.
        #expect(apple.sessions["swedish"]?.cancelled ?? true)
        // History must say Apple, not the hybrid's own (Parakeet) label.
        #expect(try await session.finish().engine == .apple)
    }

    @Test func cancelCancelsEverySession() async throws {
        let session = try await hybrid().makeSession(language: .automatic)
        session.cancel()
        #expect(parakeet.sessions["auto"]?.cancelled == true)
        #expect(apple.sessions["swedish"]?.cancelled == true)
    }

    @Test func readyOnlyWhenBothEnginesAre() {
        apple.isReady = false
        #expect(!hybrid().isReady)
    }

    @Test func readyIgnoresAppleLanguagesTheHybridDoesNotUse() {
        apple.unreadyLanguages = [.english]   // hybrid only uses Apple for Swedish
        #expect(hybrid().isReady)
        apple.unreadyLanguages = [.swedish]
        #expect(!hybrid().isReady)
    }

    @Test func fallbackLanguageIsRecordedWhenParakeetHasNoGuess() async throws {
        let transcript = try await run(hybrid(last: .english), parakeetSays: "ok", language: nil)
        #expect(transcript.engine == .parakeet)
        #expect(transcript.language == .english)
    }

    @Test func hybridPreviewFollowsTheFallbackAppleSession() async {
        let parakeet = FakeSession()
        let english = PreviewSession()
        let swedish = PreviewSession()
        let session = HybridSession(parakeet: parakeet, apple: [.english: english, .swedish: swedish],
                                    fallbackLanguage: .swedish)
        swedish.previewInput.yield("hej")
        swedish.previewInput.finish()
        var seen: [String] = []
        for await text in session.preview { seen.append(text) }
        #expect(seen == ["hej"])
    }
}
