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
        case editing
        case writing
        case injecting
        case failed(DictationFailure)
    }

    private static let log = Log.logger("Dictation")

    public private(set) var state: State = .idle { didSet { notify() } }
    /// The microphone's latest analysis frame, for the waveform (silent when not listening).
    public private(set) var audioLevel = AudioLevel.silent { didSet { notify() } }
    public private(set) var lastLatency: Duration?
    public private(set) var currentTask: Task<Void, Never>?
    public private(set) var currentChoice: LanguageChoice?
    /// The dictation in progress was locked with a double-tap (no fn to hold).
    public private(set) var isHandsFree = false { didSet { if oldValue != isHandsFree { notify() } } }
    /// The words heard so far in this dictation (empty when the preview is off or not available).
    public private(set) var preview = "" { didSet { if oldValue != preview { notify() } } }
    /// The recording in progress is an instruction (fn+⌃): edit the selection, or write at the cursor.
    public private(set) var isCommand = false { didSet { if oldValue != isCommand { notify() } } }
    public var onChange: (@MainActor (State, AudioLevel) -> Void)?
    public var onLanguageDetected: (@MainActor (Language) -> Void)?
    /// A finished dictation (pasted, or paste failed) for history. Never for secure input.
    public var onDictationFinished: (@MainActor (DictationRecord) -> Void)?

    private let audio: any AudioSource
    private let transcriberProvider: @MainActor (LanguageChoice) -> any Transcriber
    private let cleaner: any TextCleaner
    private let injector: any TextInjector
    private let contextProvider: @MainActor () -> DictationContext
    /// Seconds of silence after which a hands-free dictation finishes (0 = never).
    private let handsFreeSilence: @MainActor () -> TimeInterval
    private let showPreview: @MainActor () -> Bool
    private let selection: (any SelectionReader)?
    private let editor: (any TextEditor)?
    private let commands: @MainActor () -> [SavedCommand]
    /// A password field has focus: nothing may be read or pasted there.
    private let isSecureInput: @MainActor () -> Bool
    private let maxDuration: Duration
    private let noticeDuration: Duration
    private let releaseTail: Duration

    private var activeTranscriber: (any Transcriber)?
    private var context = DictationContext()
    private var capturedSamples = 0
    private var sessionTask: Task<any TranscriptionSession, Error>?
    private var levelTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?
    private var silence: SilenceWatch?
    private var previewTask: Task<Void, Never>?

    public init(
        audio: any AudioSource,
        transcriber: @escaping @MainActor (LanguageChoice) -> any Transcriber,
        cleaner: any TextCleaner,
        injector: any TextInjector,
        contextProvider: @escaping @MainActor () -> DictationContext = { DictationContext() },
        handsFreeSilence: @escaping @MainActor () -> TimeInterval = { 30 },
        showPreview: @escaping @MainActor () -> Bool = { true },
        selection: (any SelectionReader)? = nil,
        editor: (any TextEditor)? = nil,
        commands: @escaping @MainActor () -> [SavedCommand] = { [] },
        isSecureInput: @escaping @MainActor () -> Bool = { false },
        maxDuration: Duration = .seconds(300),
        noticeDuration: Duration = .milliseconds(1_500),
        releaseTail: Duration = .milliseconds(150)
    ) {
        self.audio = audio
        self.transcriberProvider = transcriber
        self.cleaner = cleaner
        self.injector = injector
        self.contextProvider = contextProvider
        self.handsFreeSilence = handsFreeSilence
        self.showPreview = showPreview
        self.selection = selection
        self.editor = editor
        self.commands = commands
        self.isSecureInput = isSecureInput
        self.maxDuration = maxDuration
        self.noticeDuration = noticeDuration
        self.releaseTail = releaseTail
    }

    public func handle(_ command: DictationCommand) {
        switch command {
        case .start(let choice):
            guard canStart else { return }
            isCommand = false
            startListening(choice)
        case .finish:
            guard state == .listening else { return }
            // Leave .listening synchronously so a stray cancel/start arriving while
            // the pipeline runs can't cancel or restart it.
            // Judged for this dictation's language: another ticked language downloading doesn't count.
            let ready = activeTranscriber.map { transcriber in
                currentChoice.map { transcriber.isReady(for: $0) } ?? transcriber.isReady
            } ?? true
            endHandsFree()
            // The preview vanishes the moment listening ends (capture stops after the release tail).
            endPreview()
            state = ready ? .transcribing : .preparingModel
            currentTask = Task { await finishDictation() }
        case .cancel:
            guard state == .listening else { return }
            Self.log.notice("cancelled after \(self.audioSeconds) s of audio")
            cancelListening()
            isCommand = false
        case .lockHandsFree:
            guard state == .listening, !isHandsFree else { return }
            silence = SilenceWatch(timeout: handsFreeSilence())
            isHandsFree = true
            Self.log.notice("hands-free on")
        case .makeCommand:
            guard state == .listening else { return }
            if !isCommand { Self.log.notice("command mode on") }
            isCommand = true
        case .switchLanguage(let choice):
            guard state == .listening, choice != currentChoice else { return }
            Self.log.notice("language switched to \(String(describing: choice), privacy: .public)")
            // Stay in .listening throughout so the HUD doesn't collapse and reopen.
            cancelListening(endState: .listening)
            startListening(choice)
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
        endHandsFree()
        endPreview()
        context = contextProvider()
        let capture: AudioCapture
        do {
            capture = try audio.start()
        } catch {
            Self.log.error("microphone did not start: \(Log.summary(error), privacy: .public)")
            fail(.audio(String(describing: error)))
            return
        }
        currentChoice = choice
        // Chosen once per dictation, for its language: changing engines mid-hold affects the next one.
        let transcriber = transcriberProvider(choice)
        activeTranscriber = transcriber
        Self.log.notice("listening: \(String(describing: choice), privacy: .public), \(transcriber.engine.rawValue, privacy: .public)\(transcriber.isReady ? "" : " (model not ready)", privacy: .public), in \(self.context.appBundleID ?? "unknown app", privacy: .public)")
        state = .listening
        capturedSamples = 0
        // Load the cleanup model while the user is still talking.
        cleaner.prewarm()

        // The chunk stream buffers while the session is being created, so audio
        // captured before the transcriber is ready is still delivered, in order.
        sessionTask = Task { [weak self] in
            let session = try await transcriber.makeSession(language: choice)
            if let self, self.showPreview(), !Task.isCancelled {
                self.previewTask = Task { [weak self] in
                    for await text in session.preview {
                        guard !Task.isCancelled, let self, self.state == .listening else { return }
                        self.preview = text
                    }
                }
            }
            for await chunk in capture.chunks {
                session.append(chunk)
                self?.capturedSamples += chunk.samples.count
            }
            // Stream ended while still listening: the recorder stopped on its own
            // (e.g. audio device change). Transcribe what we have. A cancelled task's
            // stream ended because we stopped it, and .listening may be a newer recording.
            if !Task.isCancelled, self?.state == .listening {
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
        let transcribeStart = ContinuousClock.now
        do {
            let session = try await sessionTask.value
            state = .transcribing
            transcript = try await session.finish()
        } catch {
            Self.log.error("transcription failed after \(self.audioSeconds) s of audio: \(Log.summary(error), privacy: .public)")
            fail(.transcription(String(describing: error)))
            return
        }
        guard !transcript.text.isEmpty else {
            Self.log.notice("no words heard in \(self.audioSeconds) s of audio")
            fail(.noSpeech)
            return
        }
        Self.log.notice("transcribed \(Log.words(transcript.text)) words (\(self.audioSeconds) s of audio) by \((transcript.engine ?? self.activeTranscriber?.engine)?.rawValue ?? "?", privacy: .public), \(transcript.language?.rawValue ?? "language unknown", privacy: .public), in \(Log.ms(ContinuousClock.now - transcribeStart), privacy: .public)")
        Self.log.debug("transcript: \(transcript.text, privacy: .private)")
        if isCommand {
            await runCommand(transcript)
            return
        }

        var finalText = ""
        do {
            state = .cleaning
            var context = self.context
            context.language = transcript.language
            let cleanStart = ContinuousClock.now
            finalText = try await cleaner.clean(transcript.text, context: context)
            Self.log.notice("cleaned \(Log.words(transcript.text)) → \(Log.words(finalText)) words in \(Log.ms(ContinuousClock.now - cleanStart), privacy: .public)")
            // Voice commands can remove everything ("scratch that" alone): nothing to paste.
            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Self.log.notice("nothing left to paste after voice commands")
                fail(.noSpeech)
                return
            }
            state = .injecting
            try await injector.inject(finalText)
        } catch InjectionError.secureInputActive {
            fail(.secureInput)
            return
        } catch {
            Self.log.error("paste failed: \(Log.summary(error), privacy: .public)")
            if !finalText.isEmpty { record(transcript, finalText, pasted: false) }
            fail(.injection(String(describing: error)))
            return
        }
        let latency = ContinuousClock.now - releasedAt
        lastLatency = latency
        record(transcript, finalText, pasted: true)   // after measuring: saving isn't latency
        Self.log.notice("pasted; release→inject \(latency.formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        state = .idle
        if currentChoice == .automatic, let language = transcript.language {
            onLanguageDetected?(language)
        }
    }

    /// fn+⌃: the transcript (or the saved command it starts with) is an instruction. With text
    /// selected, the selection is edited and pasted over itself; with nothing selected, new text is
    /// written at the cursor, with the text around it as context. Never cleaned or recorded.
    private func runCommand(_ transcript: Transcript) async {
        isCommand = false
        // Checked first: in a password field nothing may be read.
        guard !isSecureInput() else {
            fail(.secureInput)
            return
        }
        guard let selection, let editor else {
            fail(.editUnavailable)
            return
        }
        let instruction = CommandResolver.resolve(transcript.text, commands: commands())
        let saved = instruction != transcript.text ? ", saved command" : ""
        let selected = await selection.selectedText()
        let writing = selected == nil
        let start = ContinuousClock.now
        do {
            let output: String
            if let selected {
                state = .editing
                Self.log.notice("command: edit \(Log.words(selected)) selected words\(saved, privacy: .public)")
                output = try await editor.edit(selected, instruction: instruction, language: transcript.language)
            } else {
                state = .writing
                let context = await selection.surroundingText()
                Self.log.notice("command: write at the cursor, \(context == nil ? "no text around it" : "\(Log.words(context)) words around it", privacy: .public)\(saved, privacy: .public)")
                output = try await editor.write(instruction: instruction, context: context, language: transcript.language)
            }
            state = .injecting
            try await injector.inject(output)
            Self.log.notice("command pasted \(Log.words(output)) words after \(Log.ms(ContinuousClock.now - start), privacy: .public)")
        } catch EditError.unavailable {
            fail(.editUnavailable); return
        } catch EditError.tooLong {
            fail(writing ? .writeFailed : .selectionTooLong); return
        } catch EditError.failed {
            fail(writing ? .writeFailed : .editFailed); return
        } catch EditError.refused {
            fail(.editRefused); return
        } catch InjectionError.secureInputActive {
            fail(.secureInput); return
        } catch {
            fail(.injection(String(describing: error))); return
        }
        state = .idle
    }

    /// Seconds of audio captured so far in this dictation, for log lines.
    private var audioSeconds: String {
        String(format: "%.1f", Double(capturedSamples) / AudioChunk.sampleRate)
    }

    private func record(_ transcript: Transcript, _ finalText: String, pasted: Bool) {
        onDictationFinished?(DictationRecord(
            date: Date(), appBundleID: context.appBundleID, language: transcript.language,
            engine: transcript.engine ?? activeTranscriber?.engine ?? .apple, rawText: transcript.text,
            finalText: finalText, pasted: pasted,
            duration: Double(capturedSamples) / AudioChunk.sampleRate))
    }

    private func cancelListening(endState: State = .idle) {
        endHandsFree()
        stopCapture()
        let pending = sessionTask
        sessionTask = nil
        pending?.cancel()
        state = endState
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
        endPreview()
        audioLevel = .silent
    }

    private func pushLevel(_ frame: AudioLevel) {
        audioLevel = frame
        let level = frame.level
        if silence?.feed(level: level, time: ProcessInfo.processInfo.systemUptime) == true {
            Self.log.notice("hands-free: silence; auto-finishing")
            handle(.finish)
        }
    }

    private func endPreview() {
        previewTask?.cancel()
        previewTask = nil
        preview = ""
    }

    private func endHandsFree() {
        silence = nil
        isHandsFree = false
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
        onChange?(state, audioLevel)
    }
}
