import AppKit
import Core
import Observation
import Sparkle

/// Updates from GitHub releases, with Sparkle: the feed (`SUFeedURL`) and the key that signs
/// every release (`SUPublicEDKey`) are in Info.plist. An update is downloaded by Wiska itself,
/// so it opens without macOS's "Open Anyway" warning.
@MainActor @Observable
public final class AppUpdater: NSObject, SPUStandardUserDriverDelegate {
    private static let log = Log.logger("Updates")
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    /// Sparkle's own setting (kept in Wiska's defaults); Settings → General shows it.
    public var checksAutomatically = false {
        didSet {
            guard controller.updater.automaticallyChecksForUpdates != checksAutomatically else { return }
            controller.updater.automaticallyChecksForUpdates = checksAutomatically
        }
    }
    /// False while a check or an install is under way.
    public private(set) var canCheckForUpdates = false
    /// A scheduled check found this version while Wiska was in the background: the menu offers
    /// it, instead of a window that may open behind other apps ("gentle reminder").
    public private(set) var availableVersion: String?

    public override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        canCheckForUpdates = controller.updater.canCheckForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
        Self.log.notice("updates: \(self.checksAutomatically ? "checked automatically" : "checked only when asked", privacy: .public)")
    }

    /// Menu → Check for Updates…: shows Sparkle's window, also when Wiska is up to date.
    public func checkForUpdates() {
        Self.log.notice("updates: checking (asked)")
        NSApp.activate()   // a menu-bar app: bring Sparkle's window to the front
        controller.checkForUpdates(nil)
    }

    public var lastChecked: Date? { controller.updater.lastUpdateCheckDate }

    // MARK: SPUStandardUserDriverDelegate

    public nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// A scheduled check: Sparkle shows its window only when Wiska is in front; otherwise the menu says so.
    public nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    public nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let version = update.displayVersionString
        Task { @MainActor in
            Self.log.notice("updates: \(version, privacy: .public) available")
            if !handleShowingUpdate { self.availableVersion = version }
        }
    }

    public nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.availableVersion = nil }
    }

    public nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.availableVersion = nil }
    }
}
