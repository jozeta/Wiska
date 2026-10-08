/// Chooses the best transcript among per-language attempts of the same audio.
public enum LanguagePicker {
    public static let minimumMargin: Double = 0.15

    public static func pick(_ candidates: [Transcript], fallback: Language) -> Transcript {
        let spoken = candidates.filter { !$0.text.isEmpty }
        guard !spoken.isEmpty else {
            return candidates.first ?? Transcript(text: "", locale: fallback.locale, language: fallback)
        }
        let ranked = spoken.sorted { ($0.confidence ?? -1) > ($1.confidence ?? -1) }
        guard ranked.count > 1 else { return ranked[0] }
        let margin = (ranked[0].confidence ?? -1) - (ranked[1].confidence ?? -1)
        if margin >= minimumMargin { return ranked[0] }
        return ranked.first { $0.language == fallback } ?? ranked[0]
    }
}
