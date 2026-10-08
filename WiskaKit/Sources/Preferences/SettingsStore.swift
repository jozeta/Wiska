import Core
import Foundation
import Observation

/// User settings, persisted in UserDefaults. Unknown or corrupt stored values fall back to defaults.
@MainActor @Observable
public final class SettingsStore {
    private enum Key {
        static let engine = "engine"
        static let engineMode = "engineMode"
        static let highlight = "highlight"
        static let languageMode = "languageMode"
        static let primaryLanguage = "primaryLanguage"
        static let toggleLanguage = "toggleLanguage"
        static let lastDetectedLanguage = "lastDetectedLanguage"
        static let languages = "languages"
        static let secondaryLanguage = "secondaryLanguage"
        static let cleanupLevel = "cleanupLevel"
        static let historyRetention = "historyRetention"
        static let onboardingCompleted = "onboardingCompleted"
        static let fnKeyConfirmed = "fnKeyConfirmed"
        static let firstDictationDone = "firstDictationDone"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var engine: SpeechEngine { didSet { defaults.set(engine.rawValue, forKey: Key.engine) } }
    public var engineMode: EngineMode {
        didSet {
            defaults.set(engineMode.rawValue, forKey: Key.engineMode)
            // First switch to Per language: start every language from the engine in use now, and
            // save them, so a later "Same for all" change can't move them.
            if engineMode == .perLanguage {
                for language in Language.allCases where languageEngines[language] == nil {
                    setEngine(engine, for: language)
                }
            }
        }
    }
    /// Engines chosen per language (Per language mode). Missing entries use `engine`.
    public private(set) var languageEngines: [Language: SpeechEngine]

    /// `englishEngine` / `swedishEngine` are the keys earlier versions used, so choices carry over.
    private static func engineKey(_ language: Language) -> String { "\(language.rawValue)Engine" }

    public func setEngine(_ engine: SpeechEngine, for language: Language) {
        languageEngines[language] = engine
        defaults.set(engine.rawValue, forKey: Self.engineKey(language))
    }

    /// The engine a language uses in the current mode.
    public func engine(for language: Language) -> SpeechEngine {
        guard engineMode == .perLanguage else { return engine }
        return languageEngines[language] ?? engine
    }

    /// True when any language is set to Parakeet (so it should be loaded).
    public var usesParakeet: Bool {
        enabledLanguages.contains { engine(for: $0) == .parakeet }
    }
    public var languageMode: LanguageMode { didSet { defaults.set(languageMode.rawValue, forKey: Key.languageMode) } }
    /// Apple reserves speech models for at most 5 locales per app.
    public static let maxLanguages = 5

    private var storedLanguages: [Language]
    private var storedPrimary: Language
    private var storedSecondary: Language?
    private var storedToggle: Language
    private var storedLastDetected: Language

    /// The ticked languages, in display order: 1 to `maxLanguages` of them. Other sets are ignored.
    public var enabledLanguages: [Language] {
        get { storedLanguages }
        set {
            let ordered = Language.allCases.filter(newValue.contains)
            guard (1...Self.maxLanguages).contains(ordered.count) else { return }
            storedLanguages = ordered
            defaults.set(ordered.map(\.rawValue), forKey: Key.languages)
        }
    }

    /// A language that isn't ticked reads as the first ticked one.
    private func ticked(_ language: Language) -> Language {
        storedLanguages.contains(language) ? language : storedLanguages[0]
    }

    public var primaryLanguage: Language {
        get { ticked(storedPrimary) }
        set { storedPrimary = newValue; defaults.set(newValue.rawValue, forKey: Key.primaryLanguage) }
    }

    /// fn+⇧ language in Per-language hotkeys mode: ticked and never the primary (when possible).
    public var secondaryLanguage: Language {
        get {
            let primary = primaryLanguage
            if let stored = storedSecondary, stored != primary, storedLanguages.contains(stored) { return stored }
            return storedLanguages.first { $0 != primary } ?? primary
        }
        set { storedSecondary = newValue; defaults.set(newValue.rawValue, forKey: Key.secondaryLanguage) }
    }

    public var toggleLanguage: Language {
        get { ticked(storedToggle) }
        set { storedToggle = newValue; defaults.set(newValue.rawValue, forKey: Key.toggleLanguage) }
    }

    public var lastDetectedLanguage: Language {
        get { ticked(storedLastDetected) }
        set { storedLastDetected = newValue; defaults.set(newValue.rawValue, forKey: Key.lastDetectedLanguage) }
    }

    public var highlight: Highlight { didSet { defaults.set(highlight.rawValue, forKey: Key.highlight) } }

    public var cleanupLevel: CleanupLevel { didSet { defaults.set(cleanupLevel.rawValue, forKey: Key.cleanupLevel) } }

    public var historyRetention: HistoryRetention {
        didSet { defaults.set(historyRetention.rawValue, forKey: Key.historyRetention) }
    }

    public var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) } }
    public var fnKeyConfirmed: Bool { didSet { defaults.set(fnKeyConfirmed, forKey: Key.fnKeyConfirmed) } }
    public var firstDictationDone: Bool { didSet { defaults.set(firstDictationDone, forKey: Key.firstDictationDone) } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let engine = Self.read(defaults, Key.engine, SpeechEngine.apple)
        self.engine = engine
        engineMode = Self.read(defaults, Key.engineMode, EngineMode.same)
        languageEngines = Dictionary(uniqueKeysWithValues: Language.allCases.compactMap { language in
            defaults.string(forKey: Self.engineKey(language)).flatMap(SpeechEngine.init(rawValue:)).map { (language, $0) }
        })
        languageMode = Self.read(defaults, Key.languageMode, LanguageMode.autoDetect)
        let stored = (defaults.stringArray(forKey: Key.languages) ?? []).compactMap(Language.init(rawValue:))
        let ticked = Language.allCases.filter(stored.contains)
        storedLanguages = (1...Self.maxLanguages).contains(ticked.count) ? ticked : [.english, .swedish]
        storedPrimary = Self.read(defaults, Key.primaryLanguage, Language.english)
        storedSecondary = defaults.string(forKey: Key.secondaryLanguage).flatMap(Language.init(rawValue:))
        storedToggle = Self.read(defaults, Key.toggleLanguage, Language.english)
        storedLastDetected = Self.read(defaults, Key.lastDetectedLanguage, Language.english)
        cleanupLevel = Self.read(defaults, Key.cleanupLevel, CleanupLevel.polished)
        highlight = Self.read(defaults, Key.highlight, Highlight.aurora)
        historyRetention = Self.read(defaults, Key.historyRetention, HistoryRetention.week)
        onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted)
        fnKeyConfirmed = defaults.bool(forKey: Key.fnKeyConfirmed)
        firstDictationDone = defaults.bool(forKey: Key.firstDictationDone)
    }

    private static func read<T: RawRepresentable>(
        _ defaults: UserDefaults, _ key: String, _ fallback: T
    ) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: key) else { return fallback }
        return T(rawValue: raw) ?? fallback
    }
}
