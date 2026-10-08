import Foundation

public enum HotkeyEvent: Sendable, Equatable {
    /// fn went down; `shifted` = ⇧ was held at that moment.
    case pressed(shifted: Bool)
    /// fn went up after the minimum hold, uninterrupted.
    case released
    /// fn went up before the minimum hold (accidental tap, or a deliberate quick tap).
    case tapped(shifted: Bool)
    /// Another key went down while fn was held (fn+arrow etc.).
    case cancelled
}

/// Live output of one recording. Both streams finish when the source is stopped.
public struct AudioCapture: Sendable {
    public let chunks: AsyncStream<AudioChunk>
    public let levels: AsyncStream<Float>

    public init(chunks: AsyncStream<AudioChunk>, levels: AsyncStream<Float>) {
        self.chunks = chunks
        self.levels = levels
    }
}

@MainActor
public protocol AudioSource: AnyObject {
    func start() throws -> AudioCapture
    func stop()
}

@MainActor
public protocol Transcriber: AnyObject {
    /// True once models/assets are installed and a session can start without downloading.
    var isReady: Bool { get }
    /// Idempotent warm-up: installs assets if needed.
    func prepare() async throws
    func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession
}

@MainActor
public protocol TranscriptionSession: AnyObject, Sendable {
    func append(_ chunk: AudioChunk)
    func finish() async throws -> Transcript
    func cancel()
}

@MainActor
public protocol TextCleaner {
    func clean(_ text: String, context: DictationContext) async throws -> String
    /// Called when a dictation starts so slow resources (a language model) can load while
    /// the user speaks.
    func prewarm()
}

public extension TextCleaner {
    func prewarm() {}
}

@MainActor
public protocol TextInjector {
    func inject(_ text: String) async throws
}
