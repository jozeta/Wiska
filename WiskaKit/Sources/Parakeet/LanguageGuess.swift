import Core
import NaturalLanguage

/// Parakeet doesn't report the language it heard, so infer it from the text (on-device).
enum LanguageGuess {
    static func detect(_ text: String, among languages: [Core.Language] = Core.Language.allCases) -> Core.Language? {
        guard !text.isEmpty, !languages.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = languages.map(\.nlLanguage)
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        return languages.first { $0.nlLanguage == dominant }
    }
}

extension Core.Language {
    var nlLanguage: NLLanguage {
        switch self {
        case .english: .english
        case .swedish: .swedish
        case .german: .german
        case .french: .french
        case .spanish: .spanish
        case .italian: .italian
        case .portuguese: .portuguese
        case .danish: .danish
        case .dutch: .dutch
        }
    }
}
