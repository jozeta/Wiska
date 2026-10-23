import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

enum Permission: CaseIterable, Identifiable {
    case microphone
    // Before Input Monitoring: macOS judges that request through Accessibility.
    case accessibility
    case inputMonitoring

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
            // Always ask: asking is what puts Wiska in System Settings' list. macOS shows its
            // prompt only once per app; asked before and still not allowed, the list's entry is
            // stale — typically an older, differently signed Wiska, ticked but not this copy — so
            // it's cleared and Wiska asks afresh, which brings the prompt back.
            guard wasPrompted else {
                request()
                markPrompted()
                return
            }
            if resetStaleEntry() {
                request()
            } else {
                request()
                openSettings()
            }
        }
    }

    /// The TCC service `tccutil` knows this permission by.
    private var tccService: String? {
        switch self {
        case .microphone: nil
        case .inputMonitoring: "ListenEvent"
        case .accessibility: "Accessibility"
        }
    }

    /// Forgets what macOS remembers about Wiska for this permission (only called while it's not
    /// allowed, so nothing granted is lost). True when that worked.
    @MainActor private func resetStaleEntry() -> Bool {
        guard let service = tccService, let bundleID = Bundle.main.bundleIdentifier else { return false }
        let tccutil = Process()
        tccutil.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        tccutil.arguments = ["reset", service, bundleID]
        do {
            try tccutil.run()
            tccutil.waitUntilExit()
        } catch {
            return false
        }
        return tccutil.terminationStatus == 0
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

/// Screen & System Audio Recording: optional, only meeting recording needs it, so it isn't a
/// `Permission` (those are what "Setup needed" counts).
///
/// It comes in two steps: the permission itself, then, the first time Wiska captures, macOS's
/// own question whether Wiska may "bypass the private window picker". That question can't be
/// checked beforehand, only raised by capturing, so setup raises it and remembers the answer.
enum ScreenRecordingPermission {
    private static let promptedKey = "promptedScreenRecording"
    private static let confirmedKey = "screenCaptureConfirmed"

    /// Allowed, and the capture question answered (in setup or by recording a meeting).
    @MainActor static var isGranted: Bool {
        CGPreflightScreenCaptureAccess() && UserDefaults.standard.bool(forKey: confirmedKey)
    }

    /// Capturing worked: the second question has been answered.
    @MainActor static func confirm() {
        UserDefaults.standard.set(true, forKey: confirmedKey)
    }

    /// Once the permission is on: capture once, so macOS asks its second question now, in setup,
    /// rather than when the first meeting starts.
    @MainActor static func requestOrOpenSettings() {
        if CGPreflightScreenCaptureAccess() {
            Task { @MainActor in
                do {
                    _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    confirm()
                } catch {
                    // Declined, or sent to System Settings by macOS's own question: try again later.
                }
            }
            return
        }
        // Asks (which also lists Wiska in System Settings); macOS shows its prompt only once, so
        // after that open the list too.
        let asked = UserDefaults.standard.bool(forKey: promptedKey)
        _ = CGRequestScreenCaptureAccess()
        if asked {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        } else {
            UserDefaults.standard.set(true, forKey: promptedKey)
        }
    }
}
