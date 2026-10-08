import Core
import Speech

/// Apple's on-device SpeechAnalyzer: English (SpeechTranscriber), Swedish (DictationTranscriber),
/// or both in parallel for automatic detection.
@MainActor
public final class AppleTranscriber: Transcriber {
    private static let log = Log.logger("SpeechToText")

    public private(set) var isReady = false
    private var preparation: Task<Void, Error>?
    let fallbackLanguage: @MainActor () -> Language

    public init(fallbackLanguage: @escaping @MainActor () -> Language = { .english }) {
        self.fallbackLanguage = fallbackLanguage
    }

    /// Installs assets for both languages.
    public func prepare() async throws {
        if isReady { return }
        if let preparation { return try await preparation.value }
        let task = Task<Void, Error> {
            for language in Language.allCases {
                try await AppleSpeechAssets.ensureInstalled(AppleModule.make(language).module,
                                                            locale: language.locale)
            }
        }
        preparation = task
        do {
            try await task.value
            isReady = true
        } catch {
            preparation = nil
            Self.log.error("speech preparation failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        try await prepare()
        switch language {
        case .fixed(let fixed):
            return try await AppleTranscriptionSession.start(language: fixed)
        case .automatic:
            // Task 5 replaces this with AutoDetectSession.
            return try await AppleTranscriptionSession.start(language: fallbackLanguage())
        }
    }
}
