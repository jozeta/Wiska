import Core

/// Auto-detect with mixed engines: Parakeet hears everything, and an Apple session runs for each
/// language assigned to Apple. The language of Parakeet's text decides whose result is used.
@MainActor
public final class HybridTranscriber: Transcriber {
    private static let log = Log.logger("Dictation")
    private let parakeet: any Transcriber
    private let apple: any Transcriber
    private let appleLanguages: Set<Language>
    private let fallbackLanguage: @MainActor () -> Language

    public init(parakeet: any Transcriber, apple: any Transcriber, appleLanguages: Set<Language>,
                fallbackLanguage: @escaping @MainActor () -> Language) {
        self.parakeet = parakeet
        self.apple = apple
        self.appleLanguages = appleLanguages
        self.fallbackLanguage = fallbackLanguage
    }

    /// Only the Apple languages this hybrid uses need their assets.
    public var isReady: Bool {
        parakeet.isReady && appleLanguages.allSatisfy { apple.isReady(for: $0) }
    }
    public var engine: SpeechEngine { .parakeet }

    public func prepare() async throws {
        try await parakeet.prepare()
        try await apple.prepare()
    }

    /// Always automatic: a fixed language never gets a hybrid (see `EngineRouter`).
    public func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        // Every engine starts at once: a short dictation waits for the slowest, not for each in turn.
        let apple = apple
        let appleStarts = Language.allCases.filter(appleLanguages.contains).map { language in
            (language, Task { try await apple.makeSession(language: .fixed(language)) })
        }
        let parakeetSession: any TranscriptionSession
        do {
            parakeetSession = try await parakeet.makeSession(language: .automatic)
        } catch {
            Self.log.error("hybrid: parakeet can't start (\(String(describing: type(of: error)), privacy: .public)); using apple auto-detect")
            for (_, start) in appleStarts { (try? await start.value)?.cancel() }
            return LabeledSession(try await apple.makeSession(language: .automatic), engine: .apple)
        }
        var appleSessions: [Language: any TranscriptionSession] = [:]
        for (language, start) in appleStarts {
            do {
                appleSessions[language] = try await start.value
            } catch {
                Self.log.error("hybrid: apple \(language.rawValue, privacy: .public) can't start; parakeet only")
            }
        }
        return HybridSession(parakeet: parakeetSession, apple: appleSessions, fallbackLanguage: fallbackLanguage())
    }
}

@MainActor
final class HybridSession: TranscriptionSession {
    private let parakeet: any TranscriptionSession
    private let apple: [Language: any TranscriptionSession]
    private let fallbackLanguage: Language

    init(parakeet: any TranscriptionSession, apple: [Language: any TranscriptionSession], fallbackLanguage: Language) {
        self.parakeet = parakeet
        self.apple = apple
        self.fallbackLanguage = fallbackLanguage
    }

    func append(_ chunk: AudioChunk) {
        parakeet.append(chunk)
        for session in apple.values { session.append(chunk) }
    }

    func finish() async throws -> Transcript {
        // Apple sessions start finishing now, in parallel with Parakeet, so Swedish waits less.
        let appleResults = apple.mapValues { session in Task { try await session.finish() } }

        let heard: Transcript
        do {
            heard = try await parakeet.finish()
        } catch {
            return try await bestApple(appleResults, parakeetError: error)
        }
        var fromParakeet = heard
        fromParakeet.engine = .parakeet
        // No guess (short or empty text): assume the language of the last dictation.
        let language = heard.language ?? fallbackLanguage
        guard let chosen = appleResults[language] else {
            cancelApple(appleResults)
            fromParakeet.language = language   // the fallback, so History and the flash have one
            return fromParakeet
        }
        cancelApple(appleResults.filter { $0.key != language })
        guard var fromApple = try? await chosen.value, !fromApple.text.isEmpty else { return fromParakeet }
        fromApple.engine = .apple
        fromApple.language = language
        return fromApple
    }

    func cancel() {
        parakeet.cancel()
        for session in apple.values { session.cancel() }
    }

    /// Parakeet has no partial results: preview the Apple session for the expected language.
    var preview: AsyncStream<String> {
        let source = apple[fallbackLanguage] ?? Language.allCases.lazy.compactMap { self.apple[$0] }.first
        return source?.preview ?? parakeet.preview
    }

    private func cancelApple(_ results: [Language: Task<Transcript, Error>]) {
        for (language, task) in results {
            task.cancel()
            apple[language]?.cancel()
        }
    }

    /// Parakeet failed: the most confident Apple result, like Apple's own auto-detect.
    private func bestApple(_ results: [Language: Task<Transcript, Error>],
                           parakeetError: Error) async throws -> Transcript {
        var transcripts: [Transcript] = []
        for (language, task) in results {
            guard var transcript = try? await task.value else { continue }
            transcript.engine = .apple
            transcript.language = transcript.language ?? language
            transcripts.append(transcript)
        }
        guard !transcripts.isEmpty else { throw parakeetError }
        return LanguagePicker.pick(transcripts, fallback: fallbackLanguage)
    }
}

/// Stamps the engine on a session's transcripts, so History doesn't fall back to the
/// hybrid's own label (Parakeet) when only Apple ran.
@MainActor
final class LabeledSession: TranscriptionSession {
    private let inner: any TranscriptionSession
    private let engine: SpeechEngine

    init(_ inner: any TranscriptionSession, engine: SpeechEngine) {
        self.inner = inner
        self.engine = engine
    }

    func append(_ chunk: AudioChunk) { inner.append(chunk) }

    func finish() async throws -> Transcript {
        var transcript = try await inner.finish()
        transcript.engine = transcript.engine ?? engine
        return transcript
    }

    func cancel() { inner.cancel() }

    var preview: AsyncStream<String> { inner.preview }
}
