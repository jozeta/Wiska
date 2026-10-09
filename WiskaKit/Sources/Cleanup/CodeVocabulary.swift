import Foundation

/// Words speech engines mishear in a terminal. Only used in the Code category, so prose like
/// "get status updates" elsewhere is never touched.
enum CodeVocabulary {
    static let gitCommands = ["status", "commit", "push", "pull", "add", "diff", "log", "checkout", "branch",
                              "merge", "rebase", "stash", "clone", "fetch", "init", "switch", "restore", "reset"]
    /// "get status" / "kit status" → "git status": "git" is heard as a common word.
    private static let misheardGit = try! NSRegularExpression(
        pattern: "\\b(?:get|kit)\\s+(\(gitCommands.joined(separator: "|")))\\b", options: [.caseInsensitive])

    static func apply(_ text: String) -> String {
        misheardGit.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                             withTemplate: "git $1")
    }
}
