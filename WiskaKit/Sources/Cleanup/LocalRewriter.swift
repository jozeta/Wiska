import Core

/// Cleanup with a local model (Gemma): the same instructions as Apple Intelligence.
@MainActor
public final class LocalRewriter: TextRewriter {
    private let generator: any LocalGenerator

    public init(generator: any LocalGenerator) {
        self.generator = generator
    }

    public var isAvailable: Bool { generator.isAvailable }
    /// A bigger model than Apple's: more time before the pipeline falls back to rule cleanup.
    public var preferredTimeout: Duration? { .milliseconds(2_500) }

    public func prewarm(level: CleanupLevel, grammar: Bool) { generator.prepare() }

    public func rewrite(_ text: String, level: CleanupLevel, language: Language?, style: WritingStyle,
                        grammar: Bool) async throws -> String {
        let words = text.split(whereSeparator: \.isWhitespace).count
        let raw = try await generator.generate(
            system: CleanupPrompts.instructions(for: level, language: language, style: style, grammar: grammar),
            prompt: text, maxTokens: words * 3 + 64)
        return LocalOutput.clean(raw)
    }
}
