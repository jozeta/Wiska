import Core

/// The language-model call behind cleanup. Foundation Models in the app; a fake in tests.
@MainActor
public protocol TextRewriter: AnyObject, Sendable {
    var isAvailable: Bool { get }
    /// How long the pipeline waits for this model; nil = the pipeline's own budget.
    var preferredTimeout: Duration? { get }
    /// `grammar`: the Fix grammar setting, so a warmed session matches the dictation.
    func prewarm(level: CleanupLevel, grammar: Bool)
    /// The same, for the dictation's likely language and style, so a warmed session can match it exactly.
    func prewarm(level: CleanupLevel, language: Language?, style: WritingStyle, grammar: Bool)
    /// `language`: the dictation's language when known, so the model is told which one it is.
    /// `style`: how formal the wording should be. `grammar`: fix grammar mistakes too.
    func rewrite(_ text: String, level: CleanupLevel, language: Language?, style: WritingStyle,
                 grammar: Bool) async throws -> String
}

public extension TextRewriter {
    var preferredTimeout: Duration? { nil }
    func prewarm(level: CleanupLevel, language: Language?, style: WritingStyle, grammar: Bool) {
        prewarm(level: level, grammar: grammar)
    }
}
