import AppKit
import Audio
import Cleanup
import Core
import Dictation
import HUD
import Hotkey
import Injection
import Observation
import SpeechToText

@MainActor @Observable
final class AppModel {
    private static let log = Log.logger("App")

    private(set) var missingPermissions: [Permission] = []
    private(set) var dictationState: DictationController.State = .idle

    @ObservationIgnored private let hud = HUDPanelController()
    @ObservationIgnored private let hotkey = FnHotkeyMonitor()
    @ObservationIgnored private let transcriber = AppleTranscriber()
    @ObservationIgnored private let controller: DictationController
    @ObservationIgnored private var hotkeyTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init() {
        controller = DictationController(
            audio: MicrophoneRecorder(),
            transcriber: transcriber,
            cleaner: PassthroughCleaner(),
            injector: PasteboardInjector(),
            contextProvider: {
                DictationContext(appBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            }
        )
        controller.onChange = { [weak self] state, levels in
            guard let self else { return }
            if dictationState != state { dictationState = state }
            hud.show(Self.hudContent(for: state, levels: levels))
        }
    }

    func start() {
        for permission in Permission.allCases where !permission.isGranted {
            permission.request()
        }
        Task { [transcriber] in try? await transcriber.prepare() }
        // TCC has no change notification; poll until everything is granted.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshPermissions()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

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
            Self.log.error("could not start fn event tap: \(String(describing: error), privacy: .public)")
            return
        }
        hotkeyTask = Task { [weak self] in
            guard let self else { return }
            for await event in hotkey.events {
                guard missingPermissions.isEmpty else { continue }
                controller.handle(event)
            }
        }
    }

    static func hudContent(for state: DictationController.State, levels: [Float]) -> HUDContent {
        switch state {
        case .idle: .hidden
        case .listening: .listening(levels: levels)
        case .preparingModel: .working("Downloading speech model…")
        case .transcribing, .cleaning, .injecting: .working("Transcribing…")
        case .failed(let failure): .message(failure.message)
        }
    }
}
