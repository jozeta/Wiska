/// How much the cleanup step may change a transcript.
public enum CleanupLevel: String, Sendable, CaseIterable, Codable {
    case off
    case light
    case polished

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .light: "Light"
        case .polished: "Polished"
        }
    }

    public var summary: String {
        switch self {
        case .off: "Paste what was heard, uncleaned. Voice commands like “new line” still work."
        case .light: "Remove fillers and stutters, fix punctuation. Never drops other words."
        case .polished: "Light, plus resolve self-corrections (“Tuesday — no, Wednesday” → “Wednesday”)."
        }
    }
}
