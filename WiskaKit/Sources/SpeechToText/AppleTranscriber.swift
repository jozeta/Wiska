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
    /// The ticked languages: only these get assets (Apple reserves at most 5 per app).
    private let languages: @MainActor () -> [Language]
    private let vocabulary: @MainActor () -> [String]

    /// True once assets for every ticked language are installed (drives the "Downloading…" HUD state).
    public var isReady: Bool { Set(languages()).isSubset(of: installed) }

    public func isReady(for language: Language) -> Bool { installed.contains(language) }

    public init(languages: @escaping @MainActor () -> [Language] = { [.english, .swedish] },
                fallbackLanguage: @escaping @MainActor () -> Language = { .english },
                vocabulary: @escaping @MainActor () -> [String] = { [] },
                installer: @escaping @MainActor (Language) async throws -> Void = AppleTranscriber.installAssets) {
        self.languages = languages
        self.fallbackLanguage = fallbackLanguage
        self.vocabulary = vocabulary
        self.installer = installer
    }

    public static func installAssets(for language: Language) async throws {
        try await AppleSpeechAssets.ensureInstalled(AppleModule.make(language).module, locale: language.locale)
    }

    /// Warm-up: installs assets for the ticked languages. Failures are per language, so a failed
    /// Swedish install never blocks English (review I3).
    public func prepare() async throws {
        var firstError: Error?
        for language in languages() {
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

    /// Gives back Apple's reservations for languages that are no longer ticked, so the
    /// 5-locale limit leaves room for the ones that are.
    public func releaseUnticked() async {
        let ticked = Set(languages().map { $0.locale.identifier(.bcp47) })
        for locale in await AssetInventory.reservedLocales where !ticked.contains(locale.identifier(.bcp47)) {
            _ = await AssetInventory.release(reservedLocale: locale)
        }
        installed.formIntersection(languages())
    }

    /// Releases specific languages' reservations (tests use it to stay under Apple's limit).
    public static func release(_ languages: [Language]) async {
        for language in languages { _ = await AssetInventory.release(reservedLocale: language.locale) }
    }

    public func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        let words = vocabulary()
        switch language {
        case .fixed(let fixed):
            try await prepare(fixed)
            return try await AppleTranscriptionSession.start(language: fixed, vocabulary: words)
        case .automatic:
            // A language that can't start is left out rather than failing the dictation:
            // with one language left, that language is used as-is.
            var sessions: [any TranscriptionSession] = []
            var firstError: Error?
            for language in languages() {
                do {
                    try await prepare(language)
                    sessions.append(try await AppleTranscriptionSession.start(language: language, vocabulary: words))
                } catch {
                    Self.log.error("auto-detect without \(language.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    firstError = firstError ?? error
                }
            }
            if let only = sessions.first, sessions.count == 1 { return only }
            guard !sessions.isEmpty else { throw firstError ?? TranscriptionError.noCompatibleAudioFormat }
            return AutoDetectSession(sessions: sessions, fallback: fallbackLanguage())
        }
    }
}
