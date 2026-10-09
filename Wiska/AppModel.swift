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
import Observation
import Parakeet
import Preferences
import SpeechToText

@MainActor @Observable
final class AppModel {
    private static let log = Log.logger("App")

    let settings: SettingsStore
    let parakeetStore: ParakeetModelStore
    let dictionaryStore: DictionaryStore
    let snippetStore: SnippetStore
    let history: HistoryStore?
    @ObservationIgnored private var retentionTask: Task<Void, Never>?
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var holdHideUntil = Date.distantPast
    /// Checks whether a newer Parakeet model has been published (Settings → Speech).
    let modelUpdates: ModelUpdateChecker
    private(set) var missingPermissions: [Permission] = []
    private(set) var dictationState: DictationController.State = .idle

    @ObservationIgnored private let hud = HUDPanelController()
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
    @ObservationIgnored private var handsFreeLatch = HandsFreeLatch()

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
        do {
            history = try HistoryStore()
        } catch {
            Self.log.error("history unavailable: \(error.localizedDescription, privacy: .public)")
            history = nil
        }
        self.settings = settings
        parakeetStore = store
        modelUpdates = ModelUpdateChecker(store: store, source: HuggingFaceRevisionSource(),
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
        controller = DictationController(
            audio: MicrophoneRecorder(),
            transcriber: { [weak self] choice in self?.transcriber(for: choice) ?? AppleTranscriber() },
            cleaner: CleanupPipeline(level: { settings.cleanupLevel }, rewriter: rewriter,
                                     dictionary: { dictionaryStore.dictionary },
                                     isKnownWord: { lexicon.isKnown($0) },
                                     style: { settings.style(for: $0) },
                                     snippets: { snippetStore.snippets }),
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
            editor: FoundationModelsEditor(),
            isSecureInput: { IsSecureEventInputEnabled() }
        )
        controller.onChange = { [weak self] state, audio in
            guard let self else { return }
            let finishedCopy = state == .idle && dictationState == .injecting && settings.outputMode == .clipboard
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
            if !record.finalText.isEmpty, let app = record.appBundleID, app != Bundle.main.bundleIdentifier {
                settings.noteRecentApp(app)
            }
        }
        // Load Parakeet after any download (also when Settings is closed).
        parakeetStore.onDownloaded = { [weak self] in self?.parakeetModelBecameReady() }
        applyHighlight()
    }

    /// Pushes the chosen colour to the capsule; called at launch and when Settings changes it.
    func applyHighlight() {
        hud.highlight = settings.highlight
    }

    func start() {
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
        // Parakeet model updates: at launch, then hourly; only when due, never downloads.
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, await modelUpdates.checkIfDue() {
                    flash("Speech model update available", for: .seconds(2))
                }
                try? await Task.sleep(for: .seconds(3_600))
            }
        }
    }

    var modelUpdateAvailable: Bool {
        if case .updateAvailable = modelUpdates.state { true } else { false }
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
        settings.cleanupLevel != .off && !rewriter.isAvailable
    }

    private func plan(for choice: LanguageChoice) -> EnginePlan {
        EngineRouter.plan(choice: choice, languages: settings.enabledLanguages, engines: { self.settings.engine(for: $0) },
                          parakeetReady: parakeet.isReady)
    }

    private func transcriber(for choice: LanguageChoice) -> any Transcriber {
        if settings.usesParakeet && !parakeet.isReady { warmUpParakeetIfSelected() }
        switch plan(for: choice) {
        case .single(.apple): return apple
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
        guard settings.engineMode == .perLanguage else { return usable(settings.engine).shortName }
        return settings.enabledLanguages
            .map { "\($0.flag) \(usable(settings.engine(for: $0)).shortName)" }
            .joined(separator: " · ")
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
        case .preparingModel, .transcribing, .cleaning, .editing, .injecting: "ellipsis"
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
        case .failed(let failure): failure.message
        }
    }

    // MARK: Hotkey

    private func refreshPermissions() {
        let missing = Permission.allCases.filter { !$0.isGranted }
        if missing != missingPermissions { missingPermissions = missing }
        if !missing.contains(.inputMonitoring) && !hotkey.isRunning {
            startHotkey()
        }
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
        // A quick tap may be the first half of a double-tap: keep the capsule up meanwhile.
        if case .tapped = event { holdHideUntil = Date().addingTimeInterval(0.45) }
        if let command = mapped.command {
            switch command {
            case .start(let choice), .switchLanguage(let choice): badge = badgeText(for: choice)
            case .finish, .cancel, .lockHandsFree, .makeCommand: break
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
        case .listening: .listening(audio: audio, badge: controller.isCommand ? "⌃ Edit" : badge,
                                    preview: controller.preview, handsFree: controller.isHandsFree)
        case .editing: .working("Editing…")
        case .preparingModel: .working("Downloading speech model…")
        case .transcribing, .cleaning, .injecting: .working("Transcribing…")
        case .failed(let failure): .error(failure.message)
        }
    }
}
