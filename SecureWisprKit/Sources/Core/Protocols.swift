import Foundation

public enum HotkeyEvent: Sendable, Equatable {
    case pressed
    case released
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
public protocol TranscriptionSession: AnyObject {
    func append(_ chunk: AudioChunk)
    func finish() async throws -> Transcript
    func cancel()
}

@MainActor
public protocol TextCleaner {
    func clean(_ text: String, context: DictationContext) async throws -> String
}

@MainActor
public protocol TextInjector {
    func inject(_ text: String) async throws
}
