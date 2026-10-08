import Core
import Speech

/// Apple's on-device SpeechAnalyzer: English (SpeechTranscriber), Swedish (DictationTranscriber),
/// or both in parallel for automatic detection.
@MainActor
public final class AppleTranscriber: Transcriber {
    private static let log = Log.logger("SpeechToText")

    private var installed: Set<Language> = []
    private var installing: [Language: Task<Void, Error>] = [:]
    private let installer: @MainActor (Language) async throws -> Void
    let fallbackLanguage: @MainActor () -> Language

    /// True once assets for *both* languages are installed (drives the "Downloading…" HUD state).
    public var isReady: Bool { installed.count == Language.allCases.count }

    public init(fallbackLanguage: @escaping @MainActor () -> Language = { .english },
                installer: @escaping @MainActor (Language) async throws -> Void = AppleTranscriber.installAssets) {
        self.fallbackLanguage = fallbackLanguage
        self.installer = installer
    }

    public static func installAssets(for language: Language) async throws {
        try await AppleSpeechAssets.ensureInstalled(AppleModule.make(language).module, locale: language.locale)
    }

    /// Warm-up: installs assets for both languages. Failures are per language, so a failed
    /// Swedish install never blocks English (review I3).
    public func prepare() async throws {
        var firstError: Error?
        for language in Language.allCases {
            do { try await prepare(language) } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    private func prepare(_ language: Language) async throws {
        if installed.contains(language) { return }
        if let running = installing[language] { return try await running.value }
        let installer = installer
        let task = Task<Void, Error> { try await installer(language) }
        installing[language] = task
        defer { installing[language] = nil }
        do {
            try await task.value
            installed.insert(language)
        } catch {
            Self.log.error("speech assets for \(language.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        switch language {
        case .fixed(let fixed):
            try await prepare(fixed)
            return try await AppleTranscriptionSession.start(language: fixed)
        case .automatic:
            try await prepare(.english)
            try await prepare(.swedish)
            let english = try await AppleTranscriptionSession.start(language: .english)
            let swedish: AppleTranscriptionSession
            do {
                swedish = try await AppleTranscriptionSession.start(language: .swedish)
            } catch {
                english.cancel()
                throw error
            }
            return AutoDetectSession(sessions: [english, swedish], fallback: fallbackLanguage())
        }
    }
}
