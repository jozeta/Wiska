/// The listening badge while fn+⌃ is held: what the command will do, when the app says.
public enum CommandBadge {
    public static func text(selectedText: String?, rangeIsEmpty: Bool) -> String {
        if let selectedText, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Edit" }
        return rangeIsEmpty ? "Write" : "Command"
    }
}
