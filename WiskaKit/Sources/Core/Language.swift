import Foundation

public enum Language: String, Sendable, CaseIterable, Codable {
    case english
    case swedish

    public var other: Language { self == .english ? .swedish : .english }

    public var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .swedish: Locale(identifier: "sv_SE")
        }
    }

    public var displayName: String {
        switch self {
        case .english: "English"
        case .swedish: "Svenska"
        }
    }

    public var flag: String {
        switch self {
        case .english: "🇬🇧"
        case .swedish: "🇸🇪"
        }
    }

    /// Short label for the HUD.
    public var badge: String {
        switch self {
        case .english: "EN"
        case .swedish: "SV"
        }
    }
}

/// Which language(s) one dictation should be transcribed in.
public enum LanguageChoice: Sendable, Equatable {
    case fixed(Language)
    case automatic
}

public enum LanguageMode: String, Sendable, CaseIterable, Codable {
    case autoDetect
    case toggle
    case perLanguageHotkeys

    public var displayName: String {
        switch self {
        case .autoDetect: "Auto-detect"
        case .toggle: "Toggle"
        case .perLanguageHotkeys: "Per-language hotkeys"
        }
    }
}

public enum SpeechEngine: String, Sendable, CaseIterable, Codable {
    case apple
    case parakeet

    public var displayName: String {
        switch self {
        case .apple: "Apple SpeechAnalyzer"
        case .parakeet: "Parakeet"
        }
    }

    /// For compact UI: the menu status line and per-language rows.
    public var shortName: String {
        switch self {
        case .apple: "Apple"
        case .parakeet: "Parakeet"
        }
    }
}

/// Whether one engine serves every language, or each language has its own.
public enum EngineMode: String, Sendable, CaseIterable, Codable {
    case same
    case perLanguage

    public var displayName: String {
        switch self {
        case .same: "Same for all"
        case .perLanguage: "Per language"
        }
    }
}

/// What the dictation pipeline is asked to do. Produced from hotkey events by `CommandMapper`.
public enum DictationCommand: Sendable, Equatable {
    case start(LanguageChoice)
    /// Restart the recording in progress in another language (⇧ pressed just after fn).
    case switchLanguage(LanguageChoice)
    case finish
    case cancel
}
