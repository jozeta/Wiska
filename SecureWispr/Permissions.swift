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
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
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
}
