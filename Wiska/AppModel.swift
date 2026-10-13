import AppKit
import Carbon.HIToolbox
import Audio
import Cleanup
import Core
import Dictation
import HUD
import History
import Hotkey
import Injection
import KBWhisper
import LocalModel
import Observation
import Parakeet
import Preferences
import SpeechToText
import Updates

@MainActor @Observable
final class AppModel {
    private static let log = Log.logger("App")

    let settings: SettingsStore
    let parakeetStore: ParakeetModelStore
    let dictionaryStore: DictionaryStore
    let snippetStore: SnippetStore
    let commandStore: CommandStore
    /// Speaker diarization models (~14 MB): tell the voices on a call apart. Downloaded on request.
    let speakerModel = ParakeetModelStore(directory: SpeakerDiarizer.modelDirectory, downloader: DiarizerDownloader(),
                                          name: "speaker")
    /// Records calls and meetings (the Mac's audio and the microphone) for a transcript.
    @ObservationIgnored let meetingRecorder = MeetingRecorder()
    /// Which tab the Transcribe window opens on (menu: Transcribe Audio File… or Record Meeting…).
    var transcribeMode = TranscribeMode.file
    enum TranscribeMode: Hashable { case file, meeting }
    /// Words the user fixed after a dictation, offered in the Dictionary tab.
    let corrections = CorrectionSuggestions()
    @ObservationIgnored private let correctionWatcher = CorrectionWatcher()
    @ObservationIgnored private var lexicon: SpellCheckerLexicon!
    let history: HistoryStore?
    @ObservationIgnored private var retentionTask: Task<Void, Never>?
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var holdHideUntil = Date.distantPast
    /// Checks whether a newer Parakeet model has been published (Settings → Speech).
    let modelUpdates: ModelUpdateChecker
    let gemmaStore: GemmaModelStore
    let gemma: GemmaModel
    /// Checks whether a newer Gemma has been published (Settings → Cleanup); never downloads by itself.
    let gemmaUpdates: ModelUpdateChecker
    let kbWhisperStore: KBWhisperModelStore
    let kbWhisper: KBWhisperRecognizer
    /// Checks whether a newer KB-Whisper has been published (Settings → Models).
    let kbWhisperUpdates: ModelUpdateChecker
    /// Wiska's own updates (Sparkle, from GitHub releases).
    let updater = AppUpdater()
    @ObservationIgnored private var cleanupRewriter: SwitchingRewriter!
    @ObservationIgnored private var appleEditor: FoundationModelsEditor!
    @ObservationIgnored private var localRewriter: LocalRewriter!
    @ObservationIgnored private var localEditor: LocalEditor!
    /// Cleans transcribed recordings: the same models and dictionary as dictation, a minute per
    /// paragraph instead of a second, and Light when cleanup is set to Off (the user asked for it).
    @ObservationIgnored private var fileCleaner: CleanupPipeline!
    private(set) var missingPermissions: [Permission] = []
    private(set) var dictationState: DictationController.State = .idle

    /// Shows dictation in the chosen theme (Settings ▸ Appearance); the controller never knows which.
    @ObservationIgnored private let hud = DictationThemeController(theme: .notchDropdown)
    @ObservationIgnored private let hotkey = FnHotkeyMonitor()
    @ObservationIgnored private let apple: AppleTranscriber
    @ObservationIgnored private let parakeet: ParakeetTranscriber
    @ObservationIgnored private let rewriter: FoundationModelsRewriter
    @ObservationIgnored private var controller: DictationController!
    @ObservationIgnored private var hotkeyTask: Task<Void, Never>?
    @ObservationIgnored private var appleSyncTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var hotkeyFailureLogged = false
    @ObservationIgnored private var badge = "AUTO"
    /// fn+⌃: "Edit" with a selection, "Write" without, "Command" when the app doesn't say.
    @ObservationIgnored private var commandBadge = "Command"
    @ObservationIgnored private var handsFreeLatch = HandsFreeLatch()
    /// Offers a restart once Microphone and Accessibility are on (the fn listener follows then).
    @ObservationIgnored private var restartOffer = RestartOffer()
    /// The last dictation's text, kept for "Paste last dictation" (also when history is off).
    @ObservationIgnored private var lastDictationText: String?
    @ObservationIgnored private lazy var pasteLastShortcut = GlobalShortcut { [weak self] in self?.pasteLastDictation() }
    @ObservationIgnored private let lastPaster = PasteboardInjector()

    init() {
        LegacyMigration.run()   // before any store touches the data folder
        // Build dependencies as locals first: reading self.* before every stored
        // property is initialized is a compile error.
        let settings = SettingsStore()
        let store = ParakeetModelStore()
        let lexicon = SpellCheckerLexicon(languages: { settings.enabledLanguages })
        let dictionaryStore = DictionaryStore()
        self.dictionaryStore = dictionaryStore
        let snippetStore = SnippetStore()
        self.snippetStore = snippetStore
        let commandStore = CommandStore()
        self.commandStore = commandStore
        do {
            history = try HistoryStore()
        } catch {
            Self.log.error("history unavailable: \(error.localizedDescription, privacy: .public)")
            history = nil
        }
        self.settings = settings
        parakeetStore = store
        modelUpdates = ModelUpdateChecker(store: store, source: HuggingFaceRevisionSource(repo: ParakeetModelStore.huggingFaceRepo),
                                          interval: { settings.modelUpdateInterval },
                                          lastCheck: { settings.lastModelUpdateCheck },
                                          setLastCheck: { settings.lastModelUpdateCheck = $0 })
        apple = AppleTranscriber(languages: { settings.enabledLanguages },
                                 fallbackLanguage: { settings.lastDetectedLanguage },
                                 vocabulary: { dictionaryStore.dictionary.words },
                                 livePreview: { settings.livePreview })
        parakeet = ParakeetTranscriber(store: store, languages: { settings.enabledLanguages })
        let rewriter = FoundationModelsRewriter()
        self.rewriter = rewriter
        let gemmaStore = GemmaModelStore()
        self.gemmaStore = gemmaStore
        let gemma = GemmaModel(store: gemmaStore)
        self.gemma = gemma
        gemmaUpdates = ModelUpdateChecker(store: gemma, source: HuggingFaceRevisionSource(repo: GemmaModelStore.repo),
                                          interval: { settings.modelUpdateInterval },
                                          lastCheck: { settings.lastGemmaUpdateCheck },
                                          setLastCheck: { settings.lastGemmaUpdateCheck = $0 })
        let kbWhisperStore = KBWhisperModelStore()
        self.kbWhisperStore = kbWhisperStore
        let kbWhisper = KBWhisperRecognizer(store: kbWhisperStore)
        self.kbWhisper = kbWhisper
        kbWhisperUpdates = ModelUpdateChecker(store: kbWhisper,
                                              source: HuggingFaceRevisionSource(repo: KBWhisperModelStore.repo),
                                              interval: { settings.modelUpdateInterval },
                                              lastCheck: { settings.lastKBWhisperUpdateCheck },
                                              setLastCheck: { settings.lastKBWhisperUpdateCheck = $0 })
        let localRewriter = LocalRewriter(generator: gemma)
        let cleanupRewriter = SwitchingRewriter(choice: { settings.languageModel }, apple: rewriter, local: localRewriter)
        let appleEditor = FoundationModelsEditor()
        let localEditor = LocalEditor(generator: gemma)
        controller = DictationController(
            audio: MicrophoneRecorder(),
            transcriber: { [weak self] choice in self?.transcriber(for: choice) ?? AppleTranscriber() },
            cleaner: CleanupPipeline(level: { settings.cleanupLevel }, rewriter: cleanupRewriter,
                                     dictionary: { dictionaryStore.dictionary },
                                     isKnownWord: { lexicon.isKnown($0) },
                                     style: { settings.style(for: $0) },
                                     snippets: { snippetStore.snippets },
                                     grammar: { settings.fixGrammar }),
            injector: SwitchingInjector(mode: { settings.outputMode }, insert: PasteboardInjector(),
                                        copy: ClipboardCopier()),
            contextProvider: {
                let bundleID = FrontApp.bundleID()
                return DictationContext(appBundleID: bundleID, enabledLanguages: settings.enabledLanguages,
                                        category: AppCatalog.category(for: bundleID, overrides: settings.appCategories))
            },
            handsFreeSilence: { settings.handsFreeSilence },
            showPreview: { settings.livePreview },
            selection: AXSelectionReader(),
            editor: SwitchingEditor(choice: { settings.languageModel }, apple: appleEditor, local: localEditor,
                                    appleAvailable: { rewriter.isAvailable }, localAvailable: { gemma.isAvailable }),
            commands: { commandStore.commands },
            isSecureInput: { IsSecureEventInputEnabled() }
        )
        self.cleanupRewriter = cleanupRewriter
        self.lexicon = lexicon
        fileCleaner = CleanupPipeline(level: { settings.cleanupLevel == .off ? .light : settings.cleanupLevel },
                                      rewriter: cleanupRewriter,
                                      dictionary: { dictionaryStore.dictionary },
                                      isKnownWord: { lexicon.isKnown($0) },
                                      grammar: { settings.fixGrammar },
                                      timeout: .seconds(60))
        self.appleEditor = appleEditor
        self.localRewriter = localRewriter
        self.localEditor = localEditor
        // A finished download is what the user asked for: use it, and load it now.
        kbWhisperStore.onDownloaded = { [weak self] in
            self?.settings.useKBWhisper = true
            self?.kbWhisper.prepare()
        }
        // A download that failed, was cancelled or had no room: Gemma isn't there, so back to Apple.
        gemmaStore.onDownloadEnded = { [weak self] in
            guard let self, !gemmaStore.isInstalled, settings.languageModel == .gemma else { return }
            settings.languageModel = .apple
        }
        gemmaStore.onDownloaded = { [weak self] in
            self?.settings.languageModel = .gemma
            self?.gemma.prepare()
        }
        controller.onChange = { [weak self] state, audio in
            guard let self else { return }
            let finishedCopy = state == .idle && dictationState == .injecting && settings.outputMode == .clipboard
            // A new dictation: the last one's correction watch ends now.
            if state == .listening && dictationState != .listening { correctionWatcher.finish() }
            if dictationState != state { dictationState = state }
            // A hands-free dictation that ended any way but fn/Esc must not leave fn locked.
            if handsFreeLatch.update(listening: state == .listening, handsFree: controller.isHandsFree) {
                hotkey.endHandsFree()
            }
            if state != .idle { flashTask?.cancel() }
            hud.show(hudContent(for: state, audio: audio),
                     hideAfter: Date() < holdHideUntil ? .milliseconds(450) : .zero)
            // Copy-only: nothing appeared in the app, so say where the text went.
            if finishedCopy { flash("Copied — press ⌘V to paste", for: .milliseconds(1_500)) }
        }
        controller.onLanguageDetected = { [weak self] language in
            guard let self else { return }
            settings.lastDetectedLanguage = language
            flash("\(language.flag) \(language.displayName)", for: .milliseconds(800))
        }
        controller.onDictationFinished = { [weak self] record in
            guard let self else { return }
            if record.pasted && !settings.firstDictationDone { settings.firstDictationDone = true }
            history?.add(record, retention: settings.historyRetention)
            if !record.finalText.isEmpty { lastDictationText = record.finalText }
            if record.pasted && settings.outputMode == .insert && settings.learnFromCorrections {
                watchForCorrections(of: record.finalText)
            }
            if !record.finalText.isEmpty, let app = record.appBundleID, app != Bundle.main.bundleIdentifier {
                settings.noteRecentApp(app)
            }
        }
        // Load Parakeet after any download (also when Settings is closed).
        parakeetStore.onDownloaded = { [weak self] in self?.parakeetModelBecameReady() }
        hud.savedOrigin = { [weak settings] theme in
            switch theme {
            case .orb: settings?.orbOrigin
            case .clippy: settings?.clippyOrigin
            case .notchDropdown, .expandedNotch: nil
            }
        }
        hud.onMoved = { [weak self] theme, origin in
            guard let self else { return }
            switch theme {
            case .orb: settings.orbOrigin = origin
            case .clippy: settings.clippyOrigin = origin
            case .notchDropdown, .expandedNotch: break
            }
        }
        applyAppearance()
    }

    /// Pushes the theme, its options and the colour to the dictation UI; called at launch and
    /// whenever Settings ▸ Appearance changes them. A theme switch mid-dictation only moves
    /// what's on screen: recording, recognition and insertion carry on.
    func applyAppearance() {
        hud.highlight = settings.highlight
        hud.options = ThemeOptions(orbSize: settings.orbSize, orbBehavior: settings.orbWindowBehavior,
                                   clippySize: settings.clippySize, clippyBehavior: settings.clippyWindowBehavior,
                                   clippyFollowsPointer: settings.clippyFollowsPointer)
        let theme = settings.dictationTheme
        if hud.theme != theme {
            Self.log.notice("dictation theme: \(theme.rawValue, privacy: .public)")
            hud.theme = theme
        }
    }

    func start() {
        logLaunch()
        applyModelMemory()
        applyPasteLastShortcut()
        refreshPermissions()
        syncAppleLanguages()   // also frees slots leaked by an earlier run
        warmUpParakeetIfSelected()
        // TCC has no change notification, so keep polling (cheap) to notice grants and revocations.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshPermissions()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        applyRetention()
        // Every minute, so expired entries leave History promptly; a no-op costs one small query.
        retentionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.applyRetention()
            }
        }
        // Parakeet and Gemma updates: at launch, then hourly; only when due, never downloads.
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, await modelUpdates.checkIfDue() {
                    flash("Speech model update available", for: .seconds(2))
                }
                if let self, await gemmaUpdates.checkIfDue() {
                    flash("Gemma update available", for: .seconds(2))
                }
                if let self, await kbWhisperUpdates.checkIfDue() {
                    flash("KB-Whisper update available", for: .seconds(2))
                }
                try? await Task.sleep(for: .seconds(3_600))
            }
        }
    }

    var modelUpdateAvailable: Bool {
        if case .updateAvailable = modelUpdates.state { true } else { false }
    }

    /// After a paste: a word the user then fixes in that text becomes a dictionary suggestion.
    private func watchForCorrections(of pasted: String) {
        correctionWatcher.watch { [weak self] before, after in
            guard let self else { return }
            let dictionary = dictionaryStore.dictionary
            let found = CorrectionFinder.corrections(before: before, after: after, pasted: pasted,
                                                     isKnownWord: { [lexicon] in lexicon!.isKnown($0) })
                .filter { correction in
                    !dictionary.replacements.contains { $0.heard.caseInsensitiveCompare(correction.heard) == .orderedSame }
                }
            guard !found.isEmpty else { return }
            Self.log.notice("corrections: \(found.count) noticed")
            let new = found.filter { corrections.note($0) }
            if let first = new.first {
                flash("“\(first.heard)” → “\(first.written)”? Add it in Settings → Dictionary", for: .seconds(3))
            }
        }
    }

    /// A suggestion accepted in the Dictionary tab: the misheard form becomes a replacement, and a
    /// single unknown word also a dictionary word (it helps recognition).
    func acceptCorrection(_ correction: Correction) {
        dictionaryStore.addReplacement(heard: correction.heard, written: correction.written)
        if !correction.written.contains(" "), !lexicon.isKnown(correction.written) {
            dictionaryStore.addWord(correction.written)
        }
        corrections.accept(correction)
    }

    /// The menu bar menu was shown: when a click seems to do nothing, the log tells whether
    /// Wiska got it at all.
    func menuOpened() {
        Self.log.notice("menu opened")
    }

    /// Settings → General → "Paste last dictation": registers the chosen shortcut (or none).
    func applyPasteLastShortcut() {
        let shortcut = settings.pasteLastShortcut
        if !pasteLastShortcut.register(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers) {
            flash("\(shortcut.displayName) is taken by another app", for: .seconds(2))
        }
    }

    /// The last dictation, or the newest in History after a relaunch.
    var lastDictation: String? {
        lastDictationText ?? history?.latest()?.finalText
    }

    /// Pastes the last dictation again at the cursor (menu, or the global shortcut).
    func pasteLastDictation(after delay: Duration = .zero) {
        guard let text = lastDictation, !text.isEmpty else {
            Self.log.notice("paste last: nothing dictated yet")
            flash("Nothing dictated yet", for: .milliseconds(1_200))
            return
        }
        Task { [weak self] in
            // From the menu: let it close, so the app underneath has focus again.
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let self else { return }
            do {
                try await lastPaster.inject(text)
                Self.log.notice("paste last: pasted \(Log.words(text)) words")
            } catch InjectionError.secureInputActive {
                Self.log.notice("paste last: blocked by a password field")
                flash("Can't paste into a password field", for: .milliseconds(1_500))
            } catch {
                Self.log.error("paste last failed: \(Log.summary(error), privacy: .public)")
                flash("Couldn't paste", for: .milliseconds(1_500))
            }
        }
    }

    /// Menu → Transcribe Audio File…: the recording in pieces, with the engine a dictation in
    /// `language` would use. `progress` runs on the main actor, 0…1.
    enum FileStep { case transcribing, cleaningUp, identifyingSpeakers, writingNotes }

    /// A transcribed meeting: who said what (names are given in the window), and notes.
    struct MeetingResult {
        var segments: [MeetingSegment]
        var notes: String?
    }

    /// The model that writes meeting notes: the chosen one when it's there, else the other.
    var notesGenerator: MeetingNotes.Generate? {
        let gemmaReady = gemma.isAvailable
        if settings.languageModel == .gemma && gemmaReady {
            return { [gemma] system, prompt in try await gemma.generate(system: system, prompt: prompt, maxTokens: 1_024) }
        }
        if MeetingNotes.appleAvailable { return MeetingNotes.apple }
        if gemmaReady {
            return { [gemma] system, prompt in try await gemma.generate(system: system, prompt: prompt, maxTokens: 1_024) }
        }
        return nil
    }

    func transcribeFile(_ url: URL, language: LanguageChoice, cleanUp: Bool = false,
                        progress: @escaping @MainActor (FileStep, Double) -> Void) async throws -> FileTranscription.Result {
        let samples = try await runBlocking { try AudioFileLoader.samples(from: url) }
        let minutes = Double(samples.count) / AudioChunk.sampleRate / 60
        Self.log.notice("file: \(String(format: "%.1f", minutes), privacy: .public) min of audio, \(String(describing: language), privacy: .public)")
        let start = ContinuousClock.now
        do {
            if cleanUp { fileCleaner.prewarm() }   // load the model while the audio is transcribed
            let result = try await FileTranscription.run(samples, session: { [weak self] in
                guard let self else { throw CancellationError() }
                return try await transcriber(for: language).makeSession(language: language)
            }, progress: { progress(.transcribing, $0) })
            Self.log.notice("file: \(Log.words(result.text)) words in \(Log.ms(ContinuousClock.now - start), privacy: .public)")
            guard cleanUp, !result.text.isEmpty else { return result }
            return FileTranscription.Result(text: try await cleanTranscript(result.text, language: result.language,
                                                                             progress: { progress(.cleaningUp, $0) }),
                                            language: result.language)
        } catch {
            Self.log.error("file transcription failed: \(Log.summary(error), privacy: .public)")
            throw error
        }
    }

    /// Stops the meeting recording and turns it into a "[0:05] You: …" transcript. The audio is
    /// deleted afterwards: only the text is kept, and only if the user copies or saves it.
    func finishMeeting(language: LanguageChoice, cleanUp: Bool, identifySpeakers: Bool, writeNotes: Bool,
                       progress: @escaping @MainActor (FileStep, Double) -> Void) async throws -> MeetingResult {
        guard let recording = try await meetingRecorder.stop() else { return MeetingResult(segments: []) }
        defer { try? FileManager.default.removeItem(at: recording.folder) }
        let you = (try? await runBlocking { try AudioFileLoader.samples(from: recording.you) }) ?? []
        let others = (try? await runBlocking { try AudioFileLoader.samples(from: recording.others) }) ?? []
        Self.log.notice("meeting: \(String(format: "%.1f", Double(max(you.count, others.count)) / AudioChunk.sampleRate / 60), privacy: .public) min recorded")
        if cleanUp { fileCleaner.prewarm() }
        var turns: [MeetingTurn]?
        if identifySpeakers && speakerModel.isInstalled && !others.isEmpty {
            progress(.identifyingSpeakers, 0)
            do {
                let start = ContinuousClock.now
                let voices = try await SpeakerDiarizer.segments(in: others)
                    .map { VoiceSegment(speaker: $0.speaker, start: $0.start, end: $0.end) }
                turns = MeetingTranscription.turns(from: voices, sampleCount: others.count)
                Self.log.notice("meeting: \(Set(voices.map(\.speaker)).count) voices on the call, \(turns?.count ?? 0) turns, in \(Log.ms(ContinuousClock.now - start), privacy: .public)")
                if turns?.isEmpty == true { turns = nil }   // nothing found: the call as one speaker
            } catch {
                Self.log.error("meeting: speakers not told apart: \(Log.summary(error), privacy: .public)")
            }
            progress(.identifyingSpeakers, 1)
        }
        var segments = try await MeetingTranscription.run(you: you, others: others, othersTurns: turns, session: { [weak self] _ in
            guard let self else { throw CancellationError() }
            return try await transcriber(for: language).makeSession(language: language)
        }, progress: { progress(.transcribing, $0) })
        if cleanUp {
            for index in segments.indices {
                segments[index].text = try await cleanTranscript(segments[index].text, language: nil, progress: { _ in })
                progress(.cleaningUp, Double(index + 1) / Double(segments.count))
            }
        }
        Self.log.notice("meeting: \(segments.count) segments")
        var notes: String?
        if writeNotes, !segments.isEmpty, let generate = notesGenerator {
            let start = ContinuousClock.now
            let heard: Language? = if case .fixed(let fixed) = language { fixed } else { nil }
            do {
                notes = try await MeetingNotes.write(MeetingTranscription.transcript(segments), language: heard,
                                                     generate: generate, progress: { progress(.writingNotes, $0) })
                Self.log.notice("meeting: notes written in \(Log.ms(ContinuousClock.now - start), privacy: .public)")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Self.log.error("meeting: notes failed: \(Log.summary(error), privacy: .public)")
            }
        }
        return MeetingResult(segments: segments, notes: notes)
    }

    /// Throws away a recording in progress.
    func discardMeeting() async {
        if let recording = try? await meetingRecorder.stop() {
            try? FileManager.default.removeItem(at: recording.folder)
        }
    }

    /// A recording's transcript, tidied like a dictation but word for word: no voice commands.
    func cleanTranscript(_ text: String, language: Language?,
                         progress: @escaping @MainActor (Double) -> Void) async throws -> String {
        var context = DictationContext(language: language, enabledLanguages: settings.enabledLanguages)
        context.isRecording = true
        let start = ContinuousClock.now
        let cleaned = try await FileTranscription.cleanUp(text, clean: { [fileCleaner] chunk in
            try await fileCleaner!.clean(chunk, context: context)
        }, progress: progress)
        Self.log.notice("file: cleaned \(Log.words(text)) → \(Log.words(cleaned)) words in \(Log.ms(ContinuousClock.now - start), privacy: .public)")
        return cleaned
    }

    /// Settings → Models → "Free memory after": how long Gemma and KB-Whisper stay loaded unused.
    func applyModelMemory() {
        gemma.setIdleLimit(settings.modelIdleLimit)
        kbWhisper.setIdleLimit(settings.modelIdleLimit)
    }

    /// One line per launch with the version and the settings that shape a dictation, so a log
    /// excerpt says what the app was set up to do.
    private func logLaunch() {
        Self.log.notice("\(self.versionLine, privacy: .public)")
        Self.log.notice("\(self.settingsLine, privacy: .public)")
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        return "Wiska \(version) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }

    private var settingsLine: String {
        let languages = settings.enabledLanguages.map(\.rawValue).joined(separator: ",")
        return "settings: engine \(settings.engine.rawValue) (\(settings.engineMode)), languages \(languages), mode \(settings.languageMode.rawValue), model \(settings.languageModel), cleanup \(settings.cleanupLevel), grammar \(settings.fixGrammar), KB-Whisper \(settings.useKBWhisper), output \(settings.outputMode), theme \(settings.dictationTheme.rawValue), model memory \(settings.modelIdleMinutes) min"
    }

    /// Settings → Help → Copy diagnostics: the version, the settings now, and Wiska's log since it
    /// started, on the clipboard. False when the log couldn't be read.
    func copyDiagnostics() async -> Bool {
        let missing = missingPermissions.isEmpty ? "none" : missingPermissions.map { "\($0)" }.joined(separator: ", ")
        let header = [versionLine, settingsLine, "missing permissions: \(missing)"].joined(separator: "\n")
        do {
            let text = try await runBlocking { try Diagnostics.collect(header: header) }
            AXSelectionReader.clipboardWillBeWrittenByWiska(.general)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return true
        } catch {
            Self.log.error("diagnostics: log not readable: \(Log.summary(error), privacy: .public)")
            return false
        }
    }

    func applyRetention() {
        history?.apply(retention: settings.historyRetention)
    }

    var onboarding: OnboardingState {
        OnboardingState(microphone: !missingPermissions.contains(.microphone),
                        inputMonitoring: !missingPermissions.contains(.inputMonitoring),
                        accessibility: !missingPermissions.contains(.accessibility),
                        fnKeyConfirmed: settings.fnKeyConfirmed,
                        firstDictationDone: settings.firstDictationDone)
    }

    @ObservationIgnored private var onboardingOffered = false

    /// True at most once per launch: SwiftUI may rebuild the menu-bar label (and re-run its
    /// onAppear) at any time, and the checklist must not pop up again each time.
    func takeOnboardingLaunchOffer() -> Bool {
        guard !onboardingOffered else { return false }
        onboardingOffered = true
        return onboarding.shouldOpenAtLaunch(completed: settings.onboardingCompleted)
    }

    /// "This week: … words · … saved", nil when there's nothing to show.
    var statsLine: String? {
        guard settings.historyRetention != .off, let history else { return nil }
        _ = history.revision
        return StatsFormatter.menuLine(history.stats())
    }

    // MARK: Engines

    /// True when some language is set to Parakeet but it can't be used right now.
    var parakeetUnavailable: Bool {
        settings.usesParakeet && !parakeet.isReady
    }

    /// False when every language is on Parakeet, which picks the language itself.
    var toggleLanguageMatters: Bool {
        EngineRouter.languageChoiceMatters(languages: settings.enabledLanguages, engines: { settings.engine(for: $0) },
                                           parakeetReady: parakeet.isReady)
    }

    /// True when AI cleanup is selected but Apple Intelligence isn't available.
    var cleanupUnavailable: Bool {
        settings.cleanupLevel != .off && !cleanupRewriter.isAvailable
    }

    /// The models Compare can run: Apple Intelligence and Gemma, each when available.
    func benchmarkEngines() -> [(name: String, rewriter: any TextRewriter, editor: any Core.TextEditor)] {
        var engines: [(name: String, rewriter: any TextRewriter, editor: any Core.TextEditor)] = []
        if rewriter.isAvailable { engines.append(("Apple", rewriter, appleEditor)) }
        if gemma.isAvailable { engines.append(("Gemma", localRewriter, localEditor)) }
        return engines
    }

    /// Settings → Models → Remove: the model goes, and every choice of it goes back to Apple.
    func removeParakeet() {
        parakeetStore.remove()
        settings.stopUsingParakeet()
    }

    func removeGemma() {
        gemma.remove()
        if settings.languageModel == .gemma { settings.languageModel = .apple }
    }

    func removeKBWhisper() {
        kbWhisper.remove()
        settings.useKBWhisper = false
    }

    /// The Cleanup tab's model picker (only downloaded models are offered).
    func chooseLanguageModel(_ choice: LanguageModelChoice) {
        settings.languageModel = choice
        if choice == .gemma { gemma.prepare() } else { gemma.unload() }   // ~5 GB back when not in use
    }

    private func plan(for choice: LanguageChoice) -> EnginePlan {
        EngineRouter.plan(choice: choice, languages: settings.enabledLanguages, engines: { self.settings.engine(for: $0) },
                          parakeetReady: parakeet.isReady)
    }

    private func transcriber(for choice: LanguageChoice) -> any Transcriber {
        // Swedish second pass: on only when wanted, Swedish ticked, and the model installed.
        SwedishSecondPassTranscriber(primary: baseTranscriber(for: choice), recognizer: kbWhisper,
                                     isEnabled: { [settings] in settings.useKBWhisper && settings.enabledLanguages.contains(.swedish) })
    }

    /// The engines Compare on my voice can run on a recording, each when installed.
    func voiceEngines() -> [(name: String, transcribe: @MainActor ([Float]) async throws -> String)] {
        var engines: [(name: String, transcribe: @MainActor ([Float]) async throws -> String)] = []
        func viaSession(_ transcriber: any Transcriber) -> @MainActor ([Float]) async throws -> String {
            { samples in
                let session = try await transcriber.makeSession(language: .fixed(.swedish))
                for start in stride(from: 0, to: samples.count, by: 1_600) {
                    session.append(AudioChunk(samples: Array(samples[start..<min(start + 1_600, samples.count)])))
                }
                return try await session.finish().text
            }
        }
        if apple.isReady(for: .swedish) { engines.append(("Apple", viaSession(apple))) }
        if parakeet.isReady { engines.append(("Parakeet", viaSession(parakeet))) }
        if kbWhisper.isReady { engines.append(("KB-Whisper", { [kbWhisper] in try await kbWhisper.transcribe($0, language: .swedish) })) }
        return engines
    }

    private func baseTranscriber(for choice: LanguageChoice) -> any Transcriber {
        if settings.usesParakeet && !parakeet.isReady { warmUpParakeetIfSelected() }
        switch plan(for: choice) {
        // KB-Whisper is never a primary engine (a Swedish second pass), so a stray setting means Apple.
        case .single(.apple), .single(.kbWhisper): return apple
        // Parakeet sometimes hears a short phrase in another alphabet ("Кит статус"): Apple retries.
        case .single(.parakeet): return ScriptFallbackTranscriber(primary: parakeet, fallback: apple)
        case .hybrid(let appleLanguages):
            return ScriptFallbackTranscriber(
                primary: HybridTranscriber(parakeet: parakeet, apple: apple, appleLanguages: appleLanguages,
                                           fallbackLanguage: { [settings] in settings.lastDetectedLanguage }),
                fallback: apple)
        }
    }

    /// The ticked set changed: give back Apple's slots for unticked languages, then fetch
    /// assets for newly ticked ones in the background.
    func tickedLanguagesChanged() {
        if !settings.enabledLanguages.contains(.swedish) { kbWhisper.unload() }   // no Swedish: free ~1.5 GB
        warmUpParakeetIfSelected()
        syncAppleLanguages()
    }

    /// Releases unticked languages' Apple slots, then installs the ticked ones. Runs one at a
    /// time: overlapping runs could release a language another run just reserved.
    private func syncAppleLanguages() {
        let previous = appleSyncTask
        appleSyncTask = Task { [apple] in
            await previous?.value
            await apple.releaseUnticked()
            try? await apple.prepare()   // failures are shown per language in Settings
        }
    }

    /// Why a ticked language can't use Apple's engine yet, if it can't.
    func appleInstallError(for language: Language) -> String? {
        apple.installErrors[language]
    }

    /// A fresh download replaces whatever failed to load before.
    func parakeetModelBecameReady() {
        parakeet.forgetLoadFailure()
        warmUpParakeetIfSelected()
    }

    func warmUpParakeetIfSelected() {
        // A failed load is remembered: retrying (and logging) on every key press can't help.
        // A fresh download clears it (parakeetModelBecameReady).
        guard settings.usesParakeet, parakeetStore.isInstalled, !parakeet.isReady, !parakeet.hasLoadFailure else { return }
        Task { [parakeet] in
            do { try await parakeet.prepare() } catch {
                Self.log.error("parakeet load failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: Language

    func switchToggleLanguage() {
        settings.toggleLanguage = settings.toggleLanguage.next(in: settings.enabledLanguages)
        flash("\(settings.toggleLanguage.flag) \(settings.toggleLanguage.displayName)", for: .seconds(1))
    }

    var languageStatus: String {
        let mode = switch settings.languageMode {
        case .autoDetect: "Auto-detect"
        case .toggle: "Toggle: \(settings.toggleLanguage.displayName)"
        case .perLanguageHotkeys:
            "fn: \(settings.primaryLanguage.displayName) · fn+⇧: \(settings.secondaryLanguage.displayName)"
        }
        return "\(mode) · \(engineSummary)"
    }

    /// What will actually run: "Parakeet", or "🇬🇧 Parakeet · 🇸🇪 Apple" per language.
    private var engineSummary: String {
        func usable(_ engine: SpeechEngine) -> SpeechEngine {
            engine == .parakeet && !parakeet.isReady ? .apple : engine
        }
        let base = settings.engineMode == .perLanguage
            ? settings.enabledLanguages.map { "\($0.flag) \(usable(settings.engine(for: $0)).shortName)" }
                .joined(separator: " · ")
            : usable(settings.engine).shortName
        // Swedish dictations are re-transcribed by KB-Whisper when it's on and installed.
        let kbActive = settings.useKBWhisper && settings.enabledLanguages.contains(.swedish) && kbWhisper.isReady
        return kbActive ? "\(base) · 🇸🇪 + KB-Whisper" : base
    }

    private func badgeText(for choice: LanguageChoice) -> String {
        if case .single(.parakeet) = plan(for: choice) { return "AUTO" }   // Parakeet picks the language itself
        return switch choice {
        case .automatic: "AUTO"
        case .fixed(let language): language.badge
        }
    }

    // MARK: Menu bar

    var menuBarSymbol: String {
        if !missingPermissions.isEmpty { return "exclamationmark.triangle" }
        return switch dictationState {
        case .listening: "mic.fill"
        case .preparingModel, .transcribing, .cleaning, .editing, .writing, .injecting: "ellipsis"
        case .idle, .failed: "waveform"
        }
    }

    var statusLine: String {
        if !missingPermissions.isEmpty { return "Setup needed" }
        return switch dictationState {
        case .idle: "Ready — hold fn to dictate"
        case .listening: "Listening…"
        case .preparingModel: "Downloading speech model…"
        case .transcribing, .cleaning, .injecting: "Transcribing…"
        case .editing: "Editing…"
        case .writing: "Writing…"
        case .failed(let failure): failure.message
        }
    }

    // MARK: Hotkey

    private func refreshPermissions() {
        let missing = Permission.allCases.filter { !$0.isGranted }
        if missing != missingPermissions {
            let names = missing.isEmpty ? "none" : missing.map { String(describing: $0) }.joined(separator: ", ")
            Self.log.notice("missing permissions: \(names, privacy: .public)")
            missingPermissions = missing
        }
        if !missing.contains(.inputMonitoring) && !hotkey.isRunning {
            startHotkey()
        }
        let now = RestartOffer.Permissions(microphone: !missing.contains(.microphone),
                                           accessibility: !missing.contains(.accessibility),
                                           inputMonitoring: !missing.contains(.inputMonitoring))
        if restartOffer.update(now) {
            // After this poll returns: the alert runs its own event loop.
            DispatchQueue.main.async { [weak self] in self?.offerRestart() }
        }
    }

    /// "Restart Wiska?" once Microphone and Accessibility are allowed: macOS lets Wiska listen to
    /// the fn key only from its next launch.
    private func offerRestart() {
        Self.log.notice("setup: offering a restart")
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Restart Wiska?"
        alert.informativeText = "Microphone and Accessibility are allowed. Wiska needs to restart to apply them and start listening for the fn key."
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            relaunch()
        } else {
            Self.log.notice("setup: restart postponed")
        }
    }

    /// Quits and opens Wiska again (a helper waits for this copy to quit first).
    func relaunch() {
        Self.log.notice("setup: restarting")
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
                            Bundle.main.bundlePath, String(ProcessInfo.processInfo.processIdentifier)]
        do {
            try helper.run()
        } catch {
            Self.log.error("setup: restart failed: \(Log.summary(error), privacy: .public)")
            return
        }
        NSApp.terminate(nil)
    }

    private func startHotkey() {
        do {
            try hotkey.start()
        } catch {
            if !hotkeyFailureLogged {   // minor e: once per launch
                hotkeyFailureLogged = true
                Self.log.error("could not start fn event tap: \(String(describing: error), privacy: .public)")
            }
            return
        }
        hotkeyTask = Task { [weak self] in
            guard let self else { return }
            for await event in hotkey.events { handle(event) }
        }
    }

    private func handle(_ event: HotkeyEvent) {
        let context = HotkeyContext(
            mode: settings.languageMode, primary: settings.primaryLanguage, secondary: settings.secondaryLanguage,
            toggle: settings.toggleLanguage, enabled: settings.enabledLanguages,
            canStart: missingPermissions.isEmpty   // minor d
        )
        let mapped = CommandMapper.map(event, context: context)
        if !context.canStart, case .pressed = event {
            Self.log.notice("fn pressed, but dictation is blocked by missing permissions")
        }
        // A quick tap may be the first half of a double-tap: keep the capsule up meanwhile.
        if case .tapped = event { holdHideUntil = Date().addingTimeInterval(0.45) }
        if let command = mapped.command {
            switch command {
            case .start(let choice), .switchLanguage(let choice): badge = badgeText(for: choice)
            case .finish, .cancel, .lockHandsFree, .makeCommand: break
            }
            if command == .makeCommand {
                commandBadge = CommandBadge.text(selectedText: AXSelectionReader.focusedSelection(),
                                                 rangeIsEmpty: AXSelectionReader.focusedSelectionIsEmpty())
                // Cleanup set to Off doesn't load Gemma at fn press: commands load it here.
                if settings.languageModel == .gemma { gemma.prepare() }
            }
            controller.handle(command)
            // A lock that didn't take (no dictation running) must not swallow the next fn press.
            if command == .lockHandsFree, !controller.isHandsFree { hotkey.endHandsFree() }
        }
        if mapped.newToggleLanguage != nil { switchToggleLanguage() }
    }

    // MARK: HUD

    private func flash(_ text: String, for duration: Duration) {
        flashTask?.cancel()
        hud.show(.message(text))
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, dictationState == .idle else { return }
            hud.show(.hidden)
        }
    }

    private func hudContent(for state: DictationController.State, audio: AudioLevel) -> HUDContent {
        switch state {
        case .idle: .hidden
        case .listening: .listening(audio: audio, badge: controller.isCommand ? commandBadge : badge,
                                    preview: controller.preview, handsFree: controller.isHandsFree,
                                    isCommand: controller.isCommand)
        case .editing: .working("Editing…", activity: .editing)
        case .writing: .working("Writing…", activity: .writing)
        case .preparingModel: .working("Downloading speech model…", activity: .preparing)
        case .transcribing, .cleaning, .injecting: .working("Transcribing…")
        case .failed(let failure): .error(failure.message)
        }
    }
}
