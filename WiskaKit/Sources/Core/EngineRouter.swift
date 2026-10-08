/// Which engine(s) transcribe one dictation.
public enum EnginePlan: Equatable, Sendable {
    case single(SpeechEngine)
    /// Auto-detect with mixed engines: Parakeet plus an Apple session for each of these languages.
    case hybrid(apple: Set<Language>)
}

/// Turns the per-language engine settings into a plan for one dictation. Pure.
public enum EngineRouter {
    /// `languages`: the ticked languages (automatic chooses among these only).
    public static func plan(choice: LanguageChoice, languages: [Language] = [.english, .swedish],
                            engines: (Language) -> SpeechEngine, parakeetReady: Bool) -> EnginePlan {
        func usable(_ engine: SpeechEngine) -> SpeechEngine {
            engine == .parakeet && !parakeetReady ? .apple : engine
        }
        switch choice {
        case .fixed(let language):
            return .single(usable(engines(language)))
        case .automatic:
            let chosen = languages.map { usable(engines($0)) }
            if let first = chosen.first, chosen.allSatisfy({ $0 == first }) { return .single(first) }
            return .hybrid(apple: Set(languages.filter { usable(engines($0)) == .apple }))
        }
    }

    /// False when every fixed language ends up on Parakeet, which picks the language itself:
    /// then switching the Toggle language changes nothing.
    public static func languageChoiceMatters(languages: [Language] = [.english, .swedish],
                                             engines: (Language) -> SpeechEngine, parakeetReady: Bool) -> Bool {
        languages.contains {
            plan(choice: .fixed($0), engines: engines, parakeetReady: parakeetReady) != .single(.parakeet)
        }
    }
}
