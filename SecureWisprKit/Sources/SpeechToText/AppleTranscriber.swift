import Core
import Speech

/// Apple's on-device SpeechAnalyzer. M1: English via SpeechTranscriber.
/// (M2 adds Swedish via DictationTranscriber — SpeechTranscriber has no sv_SE.)
@MainActor
public final class AppleTranscriber: Transcriber {
    private static let english = Locale(identifier: "en_US")
    private static let log = Log.logger("SpeechToText")

    public private(set) var isReady = false
    private var preparation: Task<Void, Error>?

    public init() {}

    public func prepare() async throws {
        if isReady { return }
        if let preparation { return try await preparation.value }
        let task = Task<Void, Error> {
            try await AppleSpeechAssets.ensureInstalled(Self.makeModule(), locale: Self.english)
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
        case .fixed(.english), .automatic:
            return try await AppleTranscriptionSession.start(module: Self.makeModule(), locale: Self.english)
        case .fixed(.swedish):
            throw TranscriptionError.unsupportedLocale("sv_SE")
        }
    }

    private static func makeModule() -> SpeechTranscriber {
        SpeechTranscriber(locale: english, preset: .transcription)
    }
}
