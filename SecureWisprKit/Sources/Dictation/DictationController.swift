import Core
import Foundation

/// Runs one dictation at a time: start → audio → transcription → cleanup → injection.
/// Only this type mutates pipeline state; UI observes it through `onChange`.
@MainActor
public final class DictationController {
    public enum State: Equatable, Sendable {
        case idle
        case listening
        case preparingModel
        case transcribing
        case cleaning
        case injecting
        case failed(DictationFailure)
    }

    public static let levelHistory = 24
    private static let log = Log.logger("Dictation")

    public private(set) var state: State = .idle { didSet { notify() } }
    public private(set) var levels: [Float] = [] { didSet { notify() } }
    public private(set) var lastLatency: Duration?
    public private(set) var currentTask: Task<Void, Never>?
    public private(set) var currentChoice: LanguageChoice?
    public var onChange: (@MainActor (State, [Float]) -> Void)?
    public var onLanguageDetected: (@MainActor (Language) -> Void)?

    private let audio: any AudioSource
    private let transcriberProvider: @MainActor () -> any Transcriber
    private let cleaner: any TextCleaner
    private let injector: any TextInjector
    private let contextProvider: @MainActor () -> DictationContext
    private let maxDuration: Duration
    private let noticeDuration: Duration
    private let releaseTail: Duration

    private var activeTranscriber: (any Transcriber)?
    private var context = DictationContext()
    private var sessionTask: Task<any TranscriptionSession, Error>?
    private var levelTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?

    public init(
        audio: any AudioSource,
        transcriber: @escaping @MainActor () -> any Transcriber,
        cleaner: any TextCleaner,
        injector: any TextInjector,
        contextProvider: @escaping @MainActor () -> DictationContext = { DictationContext() },
        maxDuration: Duration = .seconds(300),
        noticeDuration: Duration = .milliseconds(1_500),
        releaseTail: Duration = .milliseconds(150)
    ) {
        self.audio = audio
        self.transcriberProvider = transcriber
        self.cleaner = cleaner
        self.injector = injector
        self.contextProvider = contextProvider
        self.maxDuration = maxDuration
        self.noticeDuration = noticeDuration
        self.releaseTail = releaseTail
    }

    public func handle(_ command: DictationCommand) {
        switch command {
        case .start(let choice):
            guard canStart else { return }
            startListening(choice)
        case .finish:
            guard state == .listening else { return }
            // Leave .listening synchronously so a stray cancel/start arriving while
            // the pipeline runs can't cancel or restart it.
            state = (activeTranscriber?.isReady ?? true) ? .transcribing : .preparingModel
            currentTask = Task { await finishDictation() }
        case .cancel:
            guard state == .listening else { return }
            cancelListening()
        }
    }

    private var canStart: Bool {
        switch state {
        case .idle, .failed: true
        default: false
        }
    }

    private func startListening(_ choice: LanguageChoice) {
        resetTask?.cancel()
        context = contextProvider()
        let capture: AudioCapture
        do {
            capture = try audio.start()
        } catch {
            fail(.audio(String(describing: error)))
            return
        }
        currentChoice = choice
        // Chosen once per dictation: changing engine in Settings mid-hold affects the next one.
        let transcriber = transcriberProvider()
        activeTranscriber = transcriber
        state = .listening

        // The chunk stream buffers while the session is being created, so audio
        // captured before the transcriber is ready is still delivered, in order.
        sessionTask = Task { [weak self] in
            let session = try await transcriber.makeSession(language: choice)
            for await chunk in capture.chunks { session.append(chunk) }
            // Stream ended while still listening: the recorder stopped on its own
            // (e.g. audio device change). Transcribe what we have.
            if self?.state == .listening {
                Self.log.notice("audio capture ended unexpectedly; finishing dictation")
                self?.handle(.finish)
            }
            return session
        }
        levelTask = Task { [weak self] in
            for await level in capture.levels { self?.pushLevel(level) }
        }
        timeoutTask = Task { [weak self, maxDuration] in
            try? await Task.sleep(for: maxDuration)
            guard !Task.isCancelled else { return }
            Self.log.notice("max dictation length reached; auto-finishing")
            self?.handle(.finish)
        }
    }

    private func finishDictation() async {
        let releasedAt = ContinuousClock.now
        timeoutTask?.cancel()
        // Keep recording briefly: people release fn on the last syllable (minor b).
        if releaseTail > .zero { try? await Task.sleep(for: releaseTail) }
        stopCapture()
        guard let sessionTask else { return }
        self.sessionTask = nil

        let transcript: Transcript
        do {
            let session = try await sessionTask.value
            state = .transcribing
            transcript = try await session.finish()
        } catch {
            fail(.transcription(String(describing: error)))
            return
        }
        guard !transcript.text.isEmpty else {
            fail(.noSpeech)
            return
        }
        Self.log.debug("transcript: \(transcript.text, privacy: .private)")

        do {
            state = .cleaning
            let cleaned = try await cleaner.clean(transcript.text, context: context)
            state = .injecting
            try await injector.inject(cleaned)
        } catch InjectionError.secureInputActive {
            fail(.secureInput)
            return
        } catch {
            fail(.injection(String(describing: error)))
            return
        }
        let latency = ContinuousClock.now - releasedAt
        lastLatency = latency
        Self.log.info("release→inject \(latency.formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        state = .idle
        if currentChoice == .automatic, let language = transcript.language {
            onLanguageDetected?(language)
        }
    }

    private func cancelListening() {
        stopCapture()
        let pending = sessionTask
        sessionTask = nil
        pending?.cancel()
        state = .idle
        currentTask = Task {
            if let session = try? await pending?.value { session.cancel() }
        }
    }

    private func stopCapture() {
        timeoutTask?.cancel()
        timeoutTask = nil
        audio.stop()
        levelTask?.cancel()
        levelTask = nil
        levels = []
    }

    private func pushLevel(_ level: Float) {
        var next = levels
        next.append(level)
        if next.count > Self.levelHistory { next.removeFirst(next.count - Self.levelHistory) }
        levels = next
    }

    private func fail(_ failure: DictationFailure) {
        Self.log.error("dictation failed: \(String(describing: failure), privacy: .public)")
        state = .failed(failure)
        resetTask = Task { [weak self, noticeDuration] in
            try? await Task.sleep(for: noticeDuration)
            guard !Task.isCancelled, let self, case .failed = self.state else { return }
            self.state = .idle
        }
    }

    private func notify() {
        onChange?(state, levels)
    }
}
