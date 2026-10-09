import Core

/// The language-model call behind cleanup. Foundation Models in the app; a fake in tests.
@MainActor
public protocol TextRewriter: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func prewarm(level: CleanupLevel)
    /// `language`: the dictation's language when known, so the model is told which one it is.
    /// `style`: how formal the wording should be.
    func rewrite(_ text: String, level: CleanupLevel, language: Language?, style: WritingStyle) async throws -> String
}
