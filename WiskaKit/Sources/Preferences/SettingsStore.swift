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
        static let englishEngine = "englishEngine"
        static let swedishEngine = "swedishEngine"
        static let languageMode = "languageMode"
        static let primaryLanguage = "primaryLanguage"
        static let toggleLanguage = "toggleLanguage"
        static let lastDetectedLanguage = "lastDetectedLanguage"
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
            // First switch to Per language: start both languages from the engine in use now, and
            // save them (their didSets), so a later "Same for all" change can't move them.
            if engineMode == .perLanguage, defaults.object(forKey: Key.englishEngine) == nil {
                englishEngine = engine
                swedishEngine = engine
            }
        }
    }
    public var englishEngine: SpeechEngine { didSet { defaults.set(englishEngine.rawValue, forKey: Key.englishEngine) } }
    public var swedishEngine: SpeechEngine { didSet { defaults.set(swedishEngine.rawValue, forKey: Key.swedishEngine) } }

    /// The engine a language uses in the current mode.
    public func engine(for language: Language) -> SpeechEngine {
        guard engineMode == .perLanguage else { return engine }
        return switch language {
        case .english: englishEngine
        case .swedish: swedishEngine
        }
    }

    /// True when any language is set to Parakeet (so it should be loaded).
    public var usesParakeet: Bool {
        Language.allCases.contains { engine(for: $0) == .parakeet }
    }
    public var languageMode: LanguageMode { didSet { defaults.set(languageMode.rawValue, forKey: Key.languageMode) } }
    public var primaryLanguage: Language { didSet { defaults.set(primaryLanguage.rawValue, forKey: Key.primaryLanguage) } }
    public var toggleLanguage: Language { didSet { defaults.set(toggleLanguage.rawValue, forKey: Key.toggleLanguage) } }
    public var lastDetectedLanguage: Language {
        didSet { defaults.set(lastDetectedLanguage.rawValue, forKey: Key.lastDetectedLanguage) }
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
        // Unset per-language engines start from the engine the user already has.
        englishEngine = Self.read(defaults, Key.englishEngine, engine)
        swedishEngine = Self.read(defaults, Key.swedishEngine, engine)
        languageMode = Self.read(defaults, Key.languageMode, LanguageMode.autoDetect)
        primaryLanguage = Self.read(defaults, Key.primaryLanguage, Language.english)
        toggleLanguage = Self.read(defaults, Key.toggleLanguage, Language.english)
        lastDetectedLanguage = Self.read(defaults, Key.lastDetectedLanguage, Language.english)
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
