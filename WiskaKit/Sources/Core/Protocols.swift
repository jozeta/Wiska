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
    /// ⌃ went down while fn was held: the recording is an edit instruction for the selected text.
    case commandAdded
    /// Another key went down while fn was held (fn+arrow etc.).
    case cancelled
}

/// Live output of one recording. Both streams finish when the source is stopped.
public struct AudioCapture: Sendable {
    public let chunks: AsyncStream<AudioChunk>
    /// One analysis frame every 16 ms: loudness plus pitch bands, for the waveform and silence stop.
    public let levels: AsyncStream<AudioLevel>

    public init(chunks: AsyncStream<AudioChunk>, levels: AsyncStream<AudioLevel>) {
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
    /// The same, knowing where the dictation goes and, if fixed, its language: a warmed model
    /// session can then match the dictation exactly.
    func prewarm(for context: DictationContext)
}

public extension TextCleaner {
    func prewarm() {}
    func prewarm(for context: DictationContext) { prewarm() }
}

@MainActor
public protocol TextInjector {
    func inject(_ text: String) async throws
}

/// Reads the text selected in the frontmost app.
@MainActor
public protocol SelectionReader {
    /// The selection, or nil when nothing (or only whitespace) is selected.
    func selectedText() async -> String?
    /// The text around the cursor (`CursorContext.window`), or nil when the app doesn't expose it.
    func surroundingText() async -> String?
}

public extension SelectionReader {
    func surroundingText() async -> String? { nil }
}

public enum EditError: Error, Equatable, Sendable {
    /// No on-device model (Apple Intelligence off or unsupported).
    case unavailable
    /// The selection is longer than the model can take.
    case tooLong
    /// Apple Intelligence declined (safety guardrails): retrying won't help.
    case refused
    /// Timeout, error or empty output.
    case failed
}

/// Rewrites text following a spoken instruction ("make this more formal").
@MainActor
public protocol TextEditor {
    func edit(_ text: String, instruction: String, language: Language?) async throws -> String
    /// New text for the cursor; `context` is the text around it (`CursorContext.window`), if any.
    func write(instruction: String, context: String?, language: Language?) async throws -> String
}
