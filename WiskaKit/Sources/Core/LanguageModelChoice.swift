/// Which language model cleans up dictations and runs command mode.
public enum LanguageModelChoice: String, CaseIterable, Codable, Sendable {
    case apple
    case gemma

    public var displayName: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .gemma: "Gemma 4 E4B (on this Mac)"
        }
    }
}
