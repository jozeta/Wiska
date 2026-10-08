import Core
import Foundation
import Observation

/// User settings, persisted in UserDefaults. Unknown or corrupt stored values fall back to defaults.
@MainActor @Observable
public final class SettingsStore {
    private enum Key {
        static let engine = "engine"
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
    public var languageMode: LanguageMode { didSet { defaults.set(languageMode.rawValue, forKey: Key.languageMode) } }
    public var primaryLanguage: Language { didSet { defaults.set(primaryLanguage.rawValue, forKey: Key.primaryLanguage) } }
    public var toggleLanguage: Language { didSet { defaults.set(toggleLanguage.rawValue, forKey: Key.toggleLanguage) } }
    public var lastDetectedLanguage: Language {
        didSet { defaults.set(lastDetectedLanguage.rawValue, forKey: Key.lastDetectedLanguage) }
    }

    public var cleanupLevel: CleanupLevel { didSet { defaults.set(cleanupLevel.rawValue, forKey: Key.cleanupLevel) } }

    public var historyRetention: HistoryRetention {
        didSet { defaults.set(historyRetention.rawValue, forKey: Key.historyRetention) }
    }

    public var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) } }
    public var fnKeyConfirmed: Bool { didSet { defaults.set(fnKeyConfirmed, forKey: Key.fnKeyConfirmed) } }
    public var firstDictationDone: Bool { didSet { defaults.set(firstDictationDone, forKey: Key.firstDictationDone) } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        engine = Self.read(defaults, Key.engine, SpeechEngine.apple)
        languageMode = Self.read(defaults, Key.languageMode, LanguageMode.autoDetect)
        primaryLanguage = Self.read(defaults, Key.primaryLanguage, Language.english)
        toggleLanguage = Self.read(defaults, Key.toggleLanguage, Language.english)
        lastDetectedLanguage = Self.read(defaults, Key.lastDetectedLanguage, Language.english)
        cleanupLevel = Self.read(defaults, Key.cleanupLevel, CleanupLevel.polished)
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
