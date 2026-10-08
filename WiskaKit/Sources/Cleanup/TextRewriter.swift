import Core

/// The language-model call behind cleanup. Foundation Models in the app; a fake in tests.
@MainActor
public protocol TextRewriter: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func prewarm(level: CleanupLevel)
    func rewrite(_ text: String, level: CleanupLevel) async throws -> String
}
