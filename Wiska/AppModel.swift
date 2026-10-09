import AppKit
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
    let history: HistoryStore?
    @ObservationIgnored private var retentionTask: Task<Void, Never>?
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
        do {
            history = try HistoryStore()
        } catch {
            Self.log.error("history unavailable: \(error.localizedDescription, privacy: .public)")
            history = nil
        }
        self.settings = settings
        parakeetStore = store
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
                                     isKnownWord: { lexicon.isKnown($0) }),
            injector: PasteboardInjector(),
            contextProvider: {
                DictationContext(appBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                 enabledLanguages: settings.enabledLanguages)
            },
            handsFreeSilence: { settings.handsFreeSilence },
            showPreview: { settings.livePreview }
        )
        controller.onChange = { [weak self] state, levels in
            guard let self else { return }
            if dictationState != state { dictationState = state }
            // A hands-free dictation that ended any way but fn/Esc must not leave fn locked.
            if handsFreeLatch.update(listening: state == .listening, handsFree: controller.isHandsFree) {
                hotkey.endHandsFree()
            }
            if state != .idle { flashTask?.cancel() }
            hud.show(hudContent(for: state, levels: levels))
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
        }
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
        case .single(.parakeet): return parakeet
        case .hybrid(let appleLanguages):
            return HybridTranscriber(parakeet: parakeet, apple: apple, appleLanguages: appleLanguages,
                                     fallbackLanguage: { [settings] in settings.lastDetectedLanguage })
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
        case .preparingModel, .transcribing, .cleaning, .injecting: "ellipsis"
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
        if let command = mapped.command {
            switch command {
            case .start(let choice), .switchLanguage(let choice): badge = badgeText(for: choice)
            case .finish, .cancel, .lockHandsFree: break
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

    private func hudContent(for state: DictationController.State, levels: [Float]) -> HUDContent {
        switch state {
        case .idle: .hidden
        case .listening: .listening(levels: levels, badge: badge, preview: controller.preview,
                                    handsFree: controller.isHandsFree)
        case .preparingModel: .working("Downloading speech model…")
        case .transcribing, .cleaning, .injecting: .working("Transcribing…")
        case .failed(let failure): .error(failure.message)
        }
    }
}
