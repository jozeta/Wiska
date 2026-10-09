import Foundation
import Observation

/// What the update checker needs from a downloadable model (Parakeet, Gemma).
@MainActor
public protocol UpdatableModelStore: AnyObject {
    var isInstalled: Bool { get }
    var isDownloading: Bool { get }
    /// The installed files' fingerprint (or an older repo sha); nil when not recorded.
    var installedRevision: String? { get }
    /// When the installed model finished downloading.
    var installedAt: Date? { get }
    /// The installed model folder's top-level entries (what the fingerprint covers).
    var installedComponents: Set<String> { get }
    func recordRevision(_ fingerprint: String)
    /// Deletes the installed model (and lets go of it in memory).
    func remove()
    func startDownload()
}

/// Checks whether a newer revision of an installed model has been published.
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

    private static let log = Log.logger("Models")

    public private(set) var state: State = .idle
    @ObservationIgnored private let store: any UpdatableModelStore
    @ObservationIgnored private let source: any ModelRevisionSource
    @ObservationIgnored private let interval: @MainActor () -> Int
    @ObservationIgnored private let lastCheck: @MainActor () -> Date?
    @ObservationIgnored private let setLastCheck: @MainActor (Date) -> Void
    /// The last update announced by an automatic check, so it's announced once.
    @ObservationIgnored private var announcedSha: String?

    public init(store: any UpdatableModelStore, source: any ModelRevisionSource,
                interval: @escaping @MainActor () -> Int, lastCheck: @escaping @MainActor () -> Date?,
                setLastCheck: @escaping @MainActor (Date) -> Void) {
        self.store = store
        self.source = source
        self.interval = interval
        self.lastCheck = lastCheck
        self.setLastCheck = setLastCheck
    }

    /// A different fingerprint of the installed files is an update. Without one (an empty marker, or
    /// a repo sha from before fingerprints), the repo changing after the install counts.
    public static func isUpdate(installed: String?, installedAt: Date?, latest: ModelRevision,
                                components: Set<String>) -> Bool {
        if let installed, installed.hasPrefix(ModelRevision.fingerprintPrefix), !components.isEmpty {
            return installed != latest.fingerprint(of: components)
        }
        guard let installedAt else { return false }
        return latest.lastModified > installedAt
    }

    /// The card's status line. `.idle` means this run hasn't checked yet, so the last check's
    /// result is unknown: it says when, never "Up to date".
    public static func statusText(_ state: State, lastCheck: Date?, now: Date = Date()) -> String {
        func ago(_ date: Date) -> String { date.formatted(.relative(presentation: .named, unitsStyle: .wide)) }
        return switch state {
        case .checking: "Checking…"
        case .updateAvailable: "Update available"
        case .failed(let message): "Couldn't check: \(message)"
        case .upToDate(let date): "Up to date · checked \(ago(date))"
        case .idle: lastCheck.map { "Last checked \(ago($0))" } ?? "Not checked yet"
        }
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
        do {
            // A failed check changes nothing, so a "Check now" result from meanwhile stays.
            try await check(now: now)
        } catch {
            Self.log.notice("model update check failed: \(String(describing: error), privacy: .public)")
            return false
        }
        // Announce each set of model files once (a README edit changes the sha, not the files).
        guard case .updateAvailable(let latest) = state else { return false }
        let fingerprint = latest.fingerprint(of: store.installedComponents)
        guard fingerprint != announcedSha else { return false }
        announcedSha = fingerprint
        return true
    }

    /// Replaces the installed model (Parakeet is unavailable meanwhile), then checks again: the
    /// download fetches whatever is current, and the check records exactly that.
    public func downloadUpdate() {
        guard case .updateAvailable = state else { return }
        store.remove()
        store.startDownload()
        state = .idle
        Task { [weak self] in
            guard let self else { return }
            while store.isDownloading { try? await Task.sleep(for: .milliseconds(200)) }
            // Quietly: offline right after a successful download isn't worth an error on the card.
            guard store.isInstalled else { return }
            do { try await check(now: Date()) } catch {
                Self.log.notice("re-check after the update failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func check(now: Date) async throws {
        let latest = try await source.latestRevision()
        setLastCheck(now)
        let installed = store.installedRevision
        let components = store.installedComponents
        if Self.isUpdate(installed: installed, installedAt: store.installedAt, latest: latest, components: components) {
            state = .updateAvailable(latest)
        } else {
            let fingerprint = latest.fingerprint(of: components)
            if installed != fingerprint, !components.isEmpty { store.recordRevision(fingerprint) }
            state = .upToDate(now)
        }
    }
}
