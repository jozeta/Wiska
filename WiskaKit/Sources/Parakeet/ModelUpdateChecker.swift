import Core
import Foundation
import Observation

/// Checks whether a newer revision of the installed Parakeet model has been published.
/// Never downloads by itself: `downloadUpdate()` is only called from the Settings button.
@MainActor @Observable
public final class ModelUpdateChecker {
    public enum State: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case updateAvailable(ModelRevision)
        case failed(String)
    }

    private static let log = Log.logger("Parakeet")

    public private(set) var state: State = .idle
    @ObservationIgnored private let store: ParakeetModelStore
    @ObservationIgnored private let source: any ModelRevisionSource
    @ObservationIgnored private let interval: @MainActor () -> Int
    @ObservationIgnored private let lastCheck: @MainActor () -> Date?
    @ObservationIgnored private let setLastCheck: @MainActor (Date) -> Void
    /// The last update announced by an automatic check, so it's announced once.
    @ObservationIgnored private var announcedSha: String?

    public init(store: ParakeetModelStore, source: any ModelRevisionSource,
                interval: @escaping @MainActor () -> Int, lastCheck: @escaping @MainActor () -> Date?,
                setLastCheck: @escaping @MainActor (Date) -> Void) {
        self.store = store
        self.source = source
        self.interval = interval
        self.lastCheck = lastCheck
        self.setLastCheck = setLastCheck
    }

    /// A different sha is an update; installs from before update checks (no sha) compare dates.
    public static func isUpdate(installed: String?, installedAt: Date?, latest: ModelRevision) -> Bool {
        if let installed { return installed != latest.sha }
        guard let installedAt else { return false }
        return latest.lastModified > installedAt
    }

    /// "Check now": always checks and shows failures.
    public func checkNow(now: Date = Date()) async {
        guard store.isInstalled else { return }
        state = .checking
        do {
            try await check(now: now)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// The automatic check: only when installed, not set to Never, and the last check is older than
    /// the interval. Failures are silent and retried later. True when it found an update not yet announced.
    public func checkIfDue(now: Date = Date()) async -> Bool {
        let days = interval()
        guard store.isInstalled, days > 0 else { return false }
        if let last = lastCheck(), now.timeIntervalSince(last) < Double(days) * 86_400 { return false }
        let previous = state
        do {
            try await check(now: now)
        } catch {
            Self.log.notice("model update check failed: \(String(describing: error), privacy: .public)")
            state = previous
            return false
        }
        guard case .updateAvailable(let latest) = state, latest.sha != announcedSha else { return false }
        announcedSha = latest.sha
        return true
    }

    /// Replaces the installed model with the latest revision (Parakeet is unavailable meanwhile).
    public func downloadUpdate() {
        guard case .updateAvailable(let latest) = state else { return }
        store.remove()
        store.download(revision: latest.sha)
        state = .idle
    }

    private func check(now: Date) async throws {
        let latest = try await source.latestRevision()
        setLastCheck(now)
        let installed = store.installedRevision
        if Self.isUpdate(installed: installed, installedAt: store.installedAt, latest: latest) {
            state = .updateAvailable(latest)
        } else {
            if installed == nil { store.recordRevision(latest.sha) }
            state = .upToDate(now)
        }
    }
}
