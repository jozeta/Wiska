import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics

enum Permission: CaseIterable, Identifiable {
    case microphone
    case inputMonitoring
    case accessibility

    var id: Self { self }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        }
    }

    /// Why we need it, shown in the menu.
    var reason: String {
        switch self {
        case .microphone: "to hear you while fn is held"
        case .inputMonitoring: "to notice the fn key"
        case .accessibility: "to paste text where your cursor is"
        }
    }

    private var settingsAnchor: String {
        switch self {
        case .microphone: "Privacy_Microphone"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .accessibility: "Privacy_Accessibility"
        }
    }

    @MainActor var isGranted: Bool {
        switch self {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .inputMonitoring: CGPreflightListenEventAccess()
        case .accessibility: AXIsProcessTrusted()
        }
    }

    /// Shows the system prompt (first time only; afterwards macOS requires System Settings).
    @MainActor func request() {
        switch self {
        case .microphone:
            // Async form: the completion-handler form calls back on a background queue, and a
            // closure written here would inherit @MainActor and trap under Swift 6.
            Task { _ = await AVCaptureDevice.requestAccess(for: .audio) }
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    @MainActor func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)")!
        NSWorkspace.shared.open(url)
    }

    /// Prompt the first time; afterwards (or when the prompt can't show) open the right pane.
    /// Never both at once: the prompt and System Settings would cover each other.
    @MainActor func requestOrOpenSettings() {
        switch self {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { request() } else { openSettings() }
        case .inputMonitoring, .accessibility:
            // macOS shows these prompts only once per app and can't tell us whether it did,
            // so remember our own first request.
            if wasPrompted {
                openSettings()
            } else {
                markPrompted()
                request()
            }
        }
    }

    private static let promptedKey = "promptedPermissions"

    @MainActor private var wasPrompted: Bool {
        UserDefaults.standard.stringArray(forKey: Self.promptedKey)?.contains(settingsAnchor) ?? false
    }

    @MainActor private func markPrompted() {
        let prompted = UserDefaults.standard.stringArray(forKey: Self.promptedKey) ?? []
        UserDefaults.standard.set(prompted + [settingsAnchor], forKey: Self.promptedKey)
    }
}
