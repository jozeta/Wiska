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
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var engine: SpeechEngine { didSet { defaults.set(engine.rawValue, forKey: Key.engine) } }
    public var languageMode: LanguageMode { didSet { defaults.set(languageMode.rawValue, forKey: Key.languageMode) } }
    public var primaryLanguage: Language { didSet { defaults.set(primaryLanguage.rawValue, forKey: Key.primaryLanguage) } }
    public var toggleLanguage: Language { didSet { defaults.set(toggleLanguage.rawValue, forKey: Key.toggleLanguage) } }
    public var lastDetectedLanguage: Language {
        didSet { defaults.set(lastDetectedLanguage.rawValue, forKey: Key.lastDetectedLanguage) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        engine = Self.read(defaults, Key.engine, SpeechEngine.apple)
        languageMode = Self.read(defaults, Key.languageMode, LanguageMode.autoDetect)
        primaryLanguage = Self.read(defaults, Key.primaryLanguage, Language.english)
        toggleLanguage = Self.read(defaults, Key.toggleLanguage, Language.english)
        lastDetectedLanguage = Self.read(defaults, Key.lastDetectedLanguage, Language.english)
    }

    private static func read<T: RawRepresentable>(
        _ defaults: UserDefaults, _ key: String, _ fallback: T
    ) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: key) else { return fallback }
        return T(rawValue: raw) ?? fallback
    }
}
