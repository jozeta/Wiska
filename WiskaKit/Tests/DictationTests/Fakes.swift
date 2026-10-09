import Core
import Foundation
@testable import Dictation

/// Records distinct consecutive states (a class, so @MainActor closures can mutate it under Swift 6).
@MainActor
final class StateRecorder {
    private(set) var states: [DictationController.State] = []
    func record(_ state: DictationController.State) {
        if states.last != state { states.append(state) }
    }
}

@MainActor
final class FakeAudio: AudioSource {
    var startCount = 0
    var failOnStart = false
    private var chunks: AsyncStream<AudioChunk>.Continuation?
    private var levels: AsyncStream<AudioLevel>.Continuation?

    func start() throws -> AudioCapture {
        startCount += 1
        if failOnStart { throw AudioError.noInputDevice }
        let (c, cc) = AsyncStream.makeStream(of: AudioChunk.self)
        let (l, lc) = AsyncStream.makeStream(of: AudioLevel.self)
        chunks = cc
        levels = lc
        return AudioCapture(chunks: c, levels: l)
    }

    func emit(_ samples: [Float]) { chunks?.yield(AudioChunk(samples: samples)) }
    func emitLevel(_ level: Float) { levels?.yield(AudioLevel(level: level)) }
    func emit(level: AudioLevel) { levels?.yield(level) }

    func stop() {
        chunks?.finish()
        levels?.finish()
    }
}

struct FakeError: Error {}

@MainActor
final class FakeSession: TranscriptionSession {
    var result: Result<String, FakeError> = .success("hello world")
    var language: Language? = .english
    var finishDelay: Duration = .zero
    var engine: SpeechEngine?
    private(set) var appended: [[Float]] = []
    private(set) var cancelled = false

    func append(_ chunk: AudioChunk) { appended.append(chunk.samples) }

    func finish() async throws -> Transcript {
        if finishDelay > .zero { try await Task.sleep(for: finishDelay) }
        return Transcript(text: try result.get(), locale: Locale(identifier: "en_US"), language: language,
                          engine: engine)
    }

    func cancel() { cancelled = true }
}

@MainActor
final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@MainActor
final class FakeTranscriber: Transcriber {
    let session = FakeSession()
    var sessionOverride: (any TranscriptionSession)?
    var isReady = true
    /// Choices that are ready even when `isReady` (everything) is false.
    var readyChoices: [LanguageChoice] = []
    var makeDelay: Duration = .zero
    private(set) var languages: [LanguageChoice] = []

    func prepare() async throws {}
    func isReady(for choice: LanguageChoice) -> Bool { isReady || readyChoices.contains(choice) }

    func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        languages.append(language)
        if makeDelay > .zero { try await Task.sleep(for: makeDelay) }
        return sessionOverride ?? session
    }
}

@MainActor
final class FakeCleaner: TextCleaner {
    private(set) var contexts: [DictationContext] = []
    private(set) var prewarmCount = 0
    func prewarm() { prewarmCount += 1 }

    var output: String?

    func clean(_ text: String, context: DictationContext) async throws -> String {
        contexts.append(context)
        if let output { return output }
        return "cleaned: \(text)"
    }
}

@MainActor
final class FakeInjector: TextInjector {
    var error: InjectionError?
    private(set) var injected: [String] = []

    func inject(_ text: String) async throws {
        if let error { throw error }
        injected.append(text)
    }
}

/// A session whose preview the test drives.
@MainActor
final class PreviewSession: TranscriptionSession {
    let preview: AsyncStream<String>
    let previewInput: AsyncStream<String>.Continuation
    var text = "hello world"
    init() { (preview, previewInput) = AsyncStream.makeStream(of: String.self) }
    func append(_ chunk: AudioChunk) {}
    func finish() async throws -> Transcript {
        Transcript(text: text, locale: Locale(identifier: "en_US"), language: .english)
    }
    func cancel() { previewInput.finish() }
}

@MainActor
final class FakeSelection: SelectionReader {
    var text: String? = "hey can u send it"
    private(set) var reads = 0
    func selectedText() async -> String? { reads += 1; return text }
}

@MainActor
final class FakeEditor: TextEditor {
    var error: EditError?
    private(set) var calls: [(text: String, instruction: String)] = []
    private(set) var writes: [(instruction: String, context: String?)] = []
    func edit(_ text: String, instruction: String, language: Language?) async throws -> String {
        calls.append((text, instruction))
        if let error { throw error }
        return "edited: \(text)"
    }
    func write(instruction: String, context: String?, language: Language?) async throws -> String {
        writes.append((instruction, context))
        if let error { throw error }
        return "written: \(instruction)"
    }
}
