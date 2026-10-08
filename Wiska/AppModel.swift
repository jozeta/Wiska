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
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var hotkeyFailureLogged = false
    @ObservationIgnored private var badge = "AUTO"

    init() {
        LegacyMigration.run()   // before any store touches the data folder
        // Build dependencies as locals first: reading self.* before every stored
        // property is initialized is a compile error.
        let settings = SettingsStore()
        let store = ParakeetModelStore()
        let lexicon = SpellCheckerLexicon()
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
        apple = AppleTranscriber(fallbackLanguage: { settings.lastDetectedLanguage },
                                 vocabulary: { dictionaryStore.dictionary.words })
        parakeet = ParakeetTranscriber(store: store)
        let rewriter = FoundationModelsRewriter()
        self.rewriter = rewriter
        controller = DictationController(
            audio: MicrophoneRecorder(),
            transcriber: { [weak self] in self?.activeTranscriber() ?? AppleTranscriber() },
            cleaner: CleanupPipeline(level: { settings.cleanupLevel }, rewriter: rewriter,
                                     dictionary: { dictionaryStore.dictionary },
                                     isKnownWord: { lexicon.isKnown($0) }),
            injector: PasteboardInjector(),
            contextProvider: {
                DictationContext(appBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            }
        )
        controller.onChange = { [weak self] state, levels in
            guard let self else { return }
            if dictationState != state { dictationState = state }
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
    }

    func start() {
        refreshPermissions()
        Task { [apple] in try? await apple.prepare() }
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

    var shouldShowOnboardingAtLaunch: Bool {
        onboarding.shouldOpenAtLaunch(completed: settings.onboardingCompleted)
    }

    /// "This week: … words · … saved", nil when there's nothing to show.
    var statsLine: String? {
        guard settings.historyRetention != .off, let history else { return nil }
        _ = history.revision
        return StatsFormatter.menuLine(history.stats())
    }

    // MARK: Engines

    /// True when Parakeet is selected but can't be used right now.
    var parakeetUnavailable: Bool {
        settings.engine == .parakeet && !parakeet.isReady
    }

    /// True when AI cleanup is selected but Apple Intelligence isn't available.
    var cleanupUnavailable: Bool {
        settings.cleanupLevel != .off && !rewriter.isAvailable
    }

    private func activeTranscriber() -> any Transcriber {
        guard settings.engine == .parakeet else { return apple }
        if parakeet.isReady { return parakeet }
        warmUpParakeetIfSelected()
        return apple
    }

    /// A fresh download replaces whatever failed to load before.
    func parakeetModelBecameReady() {
        parakeet.forgetLoadFailure()
        warmUpParakeetIfSelected()
    }

    func warmUpParakeetIfSelected() {
        guard settings.engine == .parakeet, parakeetStore.isInstalled, !parakeet.isReady else { return }
        Task { [parakeet] in
            do { try await parakeet.prepare() } catch {
                Self.log.error("parakeet load failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: Language

    func switchToggleLanguage() {
        settings.toggleLanguage = settings.toggleLanguage.other
        flash("\(settings.toggleLanguage.flag) \(settings.toggleLanguage.displayName)", for: .seconds(1))
    }

    var languageStatus: String {
        if settings.engine == .parakeet && parakeet.isReady { return "Parakeet · automatic language" }
        return switch settings.languageMode {
        case .autoDetect: "Auto-detect (English / Svenska)"
        case .toggle: "Toggle: \(settings.toggleLanguage.displayName)"
        case .perLanguageHotkeys:
            "fn: \(settings.primaryLanguage.displayName) · fn+⇧: \(settings.primaryLanguage.other.displayName)"
        }
    }

    private func badgeText(for choice: LanguageChoice) -> String {
        if settings.engine == .parakeet && parakeet.isReady { return "AUTO" }
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
            mode: settings.languageMode, primary: settings.primaryLanguage,
            toggle: settings.toggleLanguage, canStart: missingPermissions.isEmpty   // minor d
        )
        let mapped = CommandMapper.map(event, context: context)
        if let command = mapped.command {
            switch command {
            case .start(let choice), .switchLanguage(let choice): badge = badgeText(for: choice)
            case .finish, .cancel: break
            }
            controller.handle(command)
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
        case .listening: .listening(levels: levels, badge: badge)
        case .preparingModel: .working("Downloading speech model…")
        case .transcribing, .cleaning, .injecting: .working("Transcribing…")
        case .failed(let failure): .message(failure.message)
        }
    }
}
