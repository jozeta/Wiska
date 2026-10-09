import Foundation

public enum Language: String, Sendable, CaseIterable, Codable {
    case english
    case swedish
    case german
    case french
    case spanish
    case italian
    case portuguese
    case danish
    case dutch

    /// The following ticked language in display order, wrapping; itself when alone.
    public func next(in languages: [Language]) -> Language {
        let all = Language.allCases
        let start = all.firstIndex(of: self)!
        for offset in 1...all.count {
            let candidate = all[(start + offset) % all.count]
            if languages.contains(candidate) { return candidate }
        }
        return self
    }

    /// Apple's SpeechTranscriber has no model for these; DictationTranscriber does.
    public var usesDictationTranscriber: Bool { [.swedish, .danish, .dutch].contains(self) }

    public var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .swedish: Locale(identifier: "sv_SE")
        case .german: Locale(identifier: "de_DE")
        case .french: Locale(identifier: "fr_FR")
        case .spanish: Locale(identifier: "es_ES")
        case .italian: Locale(identifier: "it_IT")
        case .portuguese: Locale(identifier: "pt_PT")
        case .danish: Locale(identifier: "da_DK")
        case .dutch: Locale(identifier: "nl_NL")
        }
    }

    public var displayName: String {
        switch self {
        case .english: "English"
        case .swedish: "Svenska"
        case .german: "Deutsch"
        case .french: "Français"
        case .spanish: "Español"
        case .italian: "Italiano"
        case .portuguese: "Português"
        case .danish: "Dansk"
        case .dutch: "Nederlands"
        }
    }

    public var flag: String {
        switch self {
        case .english: "🇬🇧"
        case .swedish: "🇸🇪"
        case .german: "🇩🇪"
        case .french: "🇫🇷"
        case .spanish: "🇪🇸"
        case .italian: "🇮🇹"
        case .portuguese: "🇵🇹"
        case .danish: "🇩🇰"
        case .dutch: "🇳🇱"
        }
    }

    /// Short label for the HUD.
    public var badge: String {
        switch self {
        case .english: "EN"
        case .swedish: "SV"
        case .german: "DE"
        case .french: "FR"
        case .spanish: "ES"
        case .italian: "IT"
        case .portuguese: "PT"
        case .danish: "DA"
        case .dutch: "NL"
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
    case kbWhisper

    /// What the per-language engine pickers offer: KB-Whisper is a Swedish second pass, not a choice.
    public static let selectable: [SpeechEngine] = [.apple, .parakeet]

    public var displayName: String {
        switch self {
        case .apple: "Apple SpeechAnalyzer"
        case .parakeet: "Parakeet"
        case .kbWhisper: "KB-Whisper"
        }
    }

    /// For compact UI: the menu status line and per-language rows.
    public var shortName: String {
        switch self {
        case .apple: "Apple"
        case .parakeet: "Parakeet"
        case .kbWhisper: "KB-Whisper"
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
    /// The recording in progress continues hands-free (double-tap fn).
    case lockHandsFree
    /// The recording in progress is an edit instruction for the selected text (fn+⌃).
    case makeCommand
}
