import Foundation

/// A local model's raw answer without chat-template leftovers: a thinking block
/// (`<|channel>thought … <channel|>`) and special tokens like `<turn|>` are never pasted.
enum LocalOutput {
    static func clean(_ raw: String) -> String {
        raw.replacing(/(?s)<\|channel>.*?<channel\|>/, with: "")
            .replacing(/<\|[a-z_"]*>|<[a-z_"]*\|>/, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
