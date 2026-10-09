import Core
import Observation
import Speech

/// Apple's on-device SpeechAnalyzer for the ticked languages (SpeechTranscriber, or
/// DictationTranscriber for Svenska, Dansk and Nederlands), in parallel for automatic detection.
/// Observable so Settings can show a language whose assets failed (e.g. Apple's 5-locale limit).
@MainActor @Observable
public final class AppleTranscriber: Transcriber {
    private static let log = Log.logger("SpeechToText")

    private var installed: Set<Language> = []
    /// Why a ticked language's assets couldn't be installed, until a later attempt succeeds.
    public private(set) var installErrors: [Language: String] = [:]
    @ObservationIgnored private var installing: [Language: Task<Void, Error>] = [:]
    @ObservationIgnored private let installer: @MainActor (Language) async throws -> Void
    @ObservationIgnored let fallbackLanguage: @MainActor () -> Language
    /// The ticked languages: only these get assets (Apple reserves at most 5 per app).
    @ObservationIgnored private let languages: @MainActor () -> [Language]
    @ObservationIgnored private let vocabulary: @MainActor () -> [String]
    /// Ask Apple for in-progress results so the HUD can show the words as they're heard.
    @ObservationIgnored private let livePreview: @MainActor () -> Bool

    /// True once assets for every ticked language are installed (drives the "Downloading…" HUD state).
    public var isReady: Bool { Set(languages()).isSubset(of: installed) }

    public func isReady(for language: Language) -> Bool { installed.contains(language) }

    /// Ready for this dictation: its language is installed, or (automatic) at least one ticked
    /// language is — a language still downloading doesn't hold the others up.
    public func isReady(for choice: LanguageChoice) -> Bool {
        switch choice {
        case .fixed(let language): installed.contains(language)
        case .automatic: !installed.isDisjoint(with: languages())
        }
    }

    public init(languages: @escaping @MainActor () -> [Language] = { [.english, .swedish] },
                fallbackLanguage: @escaping @MainActor () -> Language = { .english },
                vocabulary: @escaping @MainActor () -> [String] = { [] },
                livePreview: @escaping @MainActor () -> Bool = { false },
                installer: @escaping @MainActor (Language) async throws -> Void = AppleTranscriber.installAssets) {
        self.languages = languages
        self.fallbackLanguage = fallbackLanguage
        self.vocabulary = vocabulary
        self.livePreview = livePreview
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
            installErrors[language] = nil
        } catch {
            Self.log.error("speech assets for \(language.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            installErrors[language] = error.localizedDescription
            throw error
        }
    }

    /// Gives back Apple's reservations for languages that are no longer ticked, so the
    /// 5-locale limit leaves room for the ones that are.
    public func releaseUnticked() async {
        let reserved = await AssetInventory.reservedLocales
        // Read the ticked set after the await: it may have changed meanwhile.
        let ticked = Set(languages().map { $0.locale.identifier(.bcp47) })
        for locale in reserved where !ticked.contains(locale.identifier(.bcp47)) {
            _ = await AssetInventory.release(reservedLocale: locale)
        }
        installed.formIntersection(languages())
        installErrors = installErrors.filter { languages().contains($0.key) }
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
            return try await AppleTranscriptionSession.start(language: fixed, vocabulary: words,
                                                             volatile: livePreview())
        case .automatic:
            // A language that can't start is left out rather than failing the dictation:
            // with one language left, that language is used as-is.
            // Languages still downloading join once installed; until then auto-detect uses the
            // installed ones instead of waiting (unless none is installed yet).
            let ticked = languages()
            let ready = ticked.filter(installed.contains)
            for missing in ticked where !ready.isEmpty && !installed.contains(missing) {
                Task { try? await self.prepare(missing) }
            }
            // Only the session the HUD previews asks for in-progress results.
            let preferred = fallbackLanguage()
            let candidates = ready.isEmpty ? ticked : ready
            let previewed = candidates.contains(preferred) ? preferred : candidates.first
            var sessions: [any TranscriptionSession] = []
            var started: [Language] = []
            var firstError: Error?
            for language in candidates {
                do {
                    try await prepare(language)
                    sessions.append(try await AppleTranscriptionSession.start(
                        language: language, vocabulary: words, volatile: livePreview() && language == previewed))
                    started.append(language)
                } catch {
                    Self.log.error("auto-detect without \(language.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    firstError = firstError ?? error
                }
            }
            if let only = sessions.first, sessions.count == 1 { return only }
            guard !sessions.isEmpty else { throw firstError ?? TranscriptionError.noCompatibleAudioFormat }
            return AutoDetectSession(sessions: sessions, fallback: preferred,
                                     previewIndex: previewed.flatMap(started.firstIndex(of:)) ?? 0)
        }
    }
}
