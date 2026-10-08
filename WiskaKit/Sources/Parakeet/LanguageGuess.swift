import Core
import NaturalLanguage

/// Parakeet doesn't report the language it heard, so infer it from the text (on-device).
enum LanguageGuess {
    static func detect(_ text: String) -> Core.Language? {
        guard !text.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .swedish]
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .english?: return .english
        case .swedish?: return .swedish
        default: return nil
        }
    }
}
