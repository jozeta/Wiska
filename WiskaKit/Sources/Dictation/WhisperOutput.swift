import Foundation

/// Whether KB-Whisper's text may replace the first engine's: Whisper sometimes invents text
/// on near-silence ("Tack för att du tittade") or runs on.
enum WhisperOutput {
    static let hallucinations = ["tack för att du tittade", "tack för att ni tittade", "textning",
                                 "undertexter från amara.org", "prenumerera"]

    static func accept(_ whisper: String, over primary: String) -> Bool {
        let text = whisper.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let lower = text.lowercased(), heard = primary.lowercased()
        if hallucinations.contains(where: { lower.contains($0) && !heard.contains($0) }) { return false }
        return VoiceBenchmark.words(text).count <= 2 * VoiceBenchmark.words(primary).count + 4
    }
}
