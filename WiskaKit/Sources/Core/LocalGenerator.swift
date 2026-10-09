/// A language model running in Wiska itself (Gemma via MLX), as opposed to Apple Intelligence.
@MainActor
public protocol LocalGenerator: AnyObject {
    /// Downloaded and not known to be broken (it may still need loading).
    var isAvailable: Bool { get }
    /// Starts loading in the background, so the first answer doesn't wait for it.
    func prepare()
    /// One answer with fresh chat state: `system` as the instructions, `prompt` as the user's turn.
    func generate(system: String, prompt: String, maxTokens: Int) async throws -> String
}
