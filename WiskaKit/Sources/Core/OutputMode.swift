/// What happens to the finished text.
public enum OutputMode: String, Sendable, CaseIterable, Codable {
    /// Pasted at the cursor in the active app (the clipboard is restored afterwards).
    case insert
    /// Left on the clipboard; the user pastes it where they want.
    case clipboard

    public var displayName: String {
        switch self {
        case .insert: "Insert into the app"
        case .clipboard: "Copy to clipboard only"
        }
    }
}
