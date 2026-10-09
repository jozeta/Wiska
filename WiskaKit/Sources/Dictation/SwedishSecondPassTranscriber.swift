import Core
import Foundation

/// KB-Whisper as a Swedish second pass: the chosen engine transcribes (and previews) as always;
/// when its text is Swedish, KB-Whisper re-transcribes the same recording and its text is used —
/// unless it fails, is too slow, or returns junk.
@MainActor
public final class SwedishSecondPassTranscriber: Transcriber {
    private let primary: any Transcriber
    private let recognizer: any BatchRecognizer
    private let isEnabled: @MainActor () -> Bool

    public init(primary: any Transcriber, recognizer: any BatchRecognizer, isEnabled: @escaping @MainActor () -> Bool) {
        self.primary = primary
        self.recognizer = recognizer
        self.isEnabled = isEnabled
    }

    public var isReady: Bool { primary.isReady }
    public var engine: SpeechEngine { primary.engine }
    public func isReady(for language: Language) -> Bool { primary.isReady(for: language) }
    public func isReady(for choice: LanguageChoice) -> Bool { primary.isReady(for: choice) }
    public func prepare() async throws { try await primary.prepare() }

    static func mayBeSwedish(_ choice: LanguageChoice) -> Bool {
        switch choice {
        case .automatic: true
        case .fixed(let language): language == .swedish
        }
    }

    public func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        // Only a dictation that may be Swedish can use it: no load, no kept audio otherwise.
        let usable = isEnabled() && Self.mayBeSwedish(language)
        if usable { recognizer.prepare() }   // load while the user speaks
        return SecondPassSession(primary: try await primary.makeSession(language: language),
                                 recognizer: recognizer, isEnabled: isEnabled,
                                 keepsAudio: usable && recognizer.isReady)
    }
}

@MainActor
final class SecondPassSession: TranscriptionSession {
    private static let log = Log.logger("Dictation")
    private let primary: any TranscriptionSession
    private let recognizer: any BatchRecognizer
    private let isEnabled: @MainActor () -> Bool
    private var samples: [Float] = []
    /// The recording is copied only when the second pass may run (up to ~7.7 MB for 2 minutes).
    let keepsAudio: Bool

    init(primary: any TranscriptionSession, recognizer: any BatchRecognizer, isEnabled: @escaping @MainActor () -> Bool,
         keepsAudio: Bool = true) {
        self.primary = primary
        self.recognizer = recognizer
        self.isEnabled = isEnabled
        self.keepsAudio = keepsAudio
    }

    var preview: AsyncStream<String> { primary.preview }

    func append(_ chunk: AudioChunk) {
        if keepsAudio { samples += chunk.samples }
        primary.append(chunk)
    }

    /// 3 s, or a quarter of the recording for long dictations.
    static func budget(forSamples count: Int) -> Duration {
        .milliseconds(max(3_000, Int(Double(count) / AudioChunk.sampleRate * 250)))
    }

    func finish() async throws -> Transcript {
        let transcript = try await primary.finish()
        guard keepsAudio, transcript.language == .swedish, isEnabled(), recognizer.isReady,
              !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return transcript }
        let samples = samples
        let recognizer = recognizer
        let start = ContinuousClock.now
        do {
            let text = try await Self.race(within: Self.budget(forSamples: samples.count)) {
                try await recognizer.transcribe(samples, language: .swedish)
            }
            guard WhisperOutput.accept(text, over: transcript.text) else {
                Self.log.notice("kb-whisper output rejected")
                return transcript
            }
            Self.log.info("kb-whisper in \((ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds])), privacy: .public)")
            var result = transcript
            result.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            result.engine = .kbWhisper
            return result
        } catch {
            Self.log.notice("kb-whisper skipped: \(String(describing: type(of: error)), privacy: .public)")
            return transcript
        }
    }

    func cancel() {
        samples = []
        primary.cancel()
    }

    struct Timeout: Error {}

    /// Whichever finishes first wins; never waits for the model to stop.
    static func race(within limit: Duration, _ work: @escaping @MainActor () async throws -> String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let task = Task { @MainActor in
                do { once.resume(.success(try await work())) } catch { once.resume(.failure(error)) }
            }
            let timer = Task {
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                once.resume(.failure(Timeout()))
                task.cancel()
            }
            Task { @MainActor in
                _ = await task.result
                timer.cancel()   // the work won: no timer left running for up to 30 s
            }
        }
    }
}
