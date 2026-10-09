import Foundation

public enum HotkeyEvent: Sendable, Equatable {
    /// fn went down; `shifted` = ⇧ was held at that moment.
    case pressed(shifted: Bool)
    /// fn went up after the minimum hold, uninterrupted.
    case released
    /// fn went up before the minimum hold (accidental tap, or a deliberate quick tap).
    case tapped(shifted: Bool)
    /// ⇧ went down within the first `minimumHold` of an fn hold that started without it.
    case shiftAdded
    /// The second quick tap of a double-tap: the recording that press started keeps going hands-free.
    case locked
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
    /// Which engine this is (for history).
    var engine: SpeechEngine { get }
    /// True once a session for this one language can start without downloading.
    func isReady(for language: Language) -> Bool
    /// True when a dictation with this choice can start without waiting for a download.
    func isReady(for choice: LanguageChoice) -> Bool
    /// Idempotent warm-up: installs assets if needed.
    func prepare() async throws
    func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession
}

public extension Transcriber {
    var engine: SpeechEngine { .apple }
    func isReady(for language: Language) -> Bool { isReady }
    func isReady(for choice: LanguageChoice) -> Bool { isReady }
}

@MainActor
public protocol TranscriptionSession: AnyObject, Sendable {
    func append(_ chunk: AudioChunk)
    func finish() async throws -> Transcript
    func cancel()
    /// The words heard so far, while listening (for the HUD). Ends when the session does.
    /// Engines without partial results (Parakeet) report nothing.
    var preview: AsyncStream<String> { get }
}

public extension TranscriptionSession {
    var preview: AsyncStream<String> { AsyncStream { $0.finish() } }
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
