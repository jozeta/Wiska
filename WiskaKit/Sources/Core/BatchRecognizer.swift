/// A model that transcribes a whole recording at once (KB-Whisper), used after a dictation.
@MainActor
public protocol BatchRecognizer: AnyObject {
    /// Installed and not known to be broken.
    var isReady: Bool { get }
    /// Starts loading in the background (fn press), so the second pass doesn't wait for it.
    func prepare()
    /// The text of `samples` (16 kHz mono) in `language`.
    func transcribe(_ samples: [Float], language: Language) async throws -> String
}
