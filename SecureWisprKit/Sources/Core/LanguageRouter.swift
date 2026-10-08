/// Decides which language a dictation uses, from the mode and whether ⇧ was held with fn.
public enum LanguageRouter {
    public static func choice(mode: LanguageMode, shifted: Bool,
                              primary: Language, toggle: Language) -> LanguageChoice {
        switch mode {
        case .autoDetect: .automatic
        case .toggle: .fixed(toggle)
        case .perLanguageHotkeys: .fixed(shifted ? primary.other : primary)
        }
    }
}
