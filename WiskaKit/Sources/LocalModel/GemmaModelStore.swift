import Core
import Foundation
import Observation

/// The Gemma 4 E4B model files: downloaded only when the user asks, removable, never half-loaded.
@MainActor @Observable
public final class GemmaModelStore {
    public enum Status: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    private static let log = Log.logger("LocalModel")
    public nonisolated static let repo = "mlx-community/gemma-4-e4b-it-4bit"
    public nonisolated static let requiredFreeBytes: Int64 = 6_000_000_000
    /// Written after a download fully succeeds; files without it are a partial download.
    nonisolated static let completionMarker = ".wiska-complete"

    public nonisolated static var defaultDirectory: URL {
        AppPaths.supportDirectory.appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("gemma-4-e4b-it-4bit", isDirectory: true)
    }

    public private(set) var status: Status
    public let directory: URL
    @ObservationIgnored private let downloader: any RepoDownloader
    @ObservationIgnored private let freeSpace: @MainActor () -> Int64?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Called after a download completes (Gemma becomes the chosen model).
    @ObservationIgnored public var onDownloaded: (@MainActor () -> Void)?
    /// Called whenever a download attempt ends — finished, failed, cancelled or refused for disk
    /// space — so the app can switch back to Apple when Gemma still isn't installed.
    @ObservationIgnored public var onDownloadEnded: (@MainActor () -> Void)?

    public var isInstalled: Bool { status == .ready }

    public init(directory: URL = GemmaModelStore.defaultDirectory,
                downloader: any RepoDownloader = HuggingFaceRepoDownloader(repo: GemmaModelStore.repo),
                freeSpace: @escaping @MainActor () -> Int64? = GemmaModelStore.availableSpace) {
        self.directory = directory
        self.downloader = downloader
        self.freeSpace = freeSpace
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(Self.completionMarker).path) {
            status = .ready
        } else {
            if FileManager.default.fileExists(atPath: directory.path) {
                Self.log.notice("removing partial gemma download")
                try? FileManager.default.removeItem(at: directory)
            }
            status = .notDownloaded
        }
    }

    public static func availableSpace() -> Int64? {
        let values = try? AppPaths.supportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Starts a download (Settings → Cleanup). Checks the disk first.
    public func download() {
        switch status {
        case .ready, .downloading: return
        case .notDownloaded, .failed: break
        }
        if let free = freeSpace(), free < Self.requiredFreeBytes {
            status = .failed("Needs about 6 GB free")
            onDownloadEnded?()
            return
        }
        status = .downloading(0)
        let directory = directory
        let downloader = downloader
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading(let current) = self.status, fraction > current else { return }
                self.status = .downloading(min(fraction, 0.999))
            }
        }
        task = Task { [weak self] in
            do {
                try await downloader.download(to: directory, progress: report)
                try Task.checkCancellation()
                try Data().write(to: directory.appendingPathComponent(Self.completionMarker))
                self?.status = .ready
                Self.log.info("gemma model downloaded")
                self?.onDownloaded?()
                self?.onDownloadEnded?()
            } catch {
                try? FileManager.default.removeItem(at: directory)
                if Task.isCancelled || error is CancellationError {
                    self?.status = .notDownloaded
                } else {
                    Self.log.error("gemma download failed: \(String(describing: error), privacy: .public)")
                    self?.status = .failed("Download failed — try again")
                }
                self?.onDownloadEnded?()
            }
        }
    }

    private var markerURL: URL { directory.appendingPathComponent(Self.completionMarker) }

    /// The installed files' fingerprint, recorded by an update check; nil before the first one.
    public var installedRevision: String? {
        guard isInstalled, let text = try? String(contentsOf: markerURL, encoding: .utf8) else { return nil }
        let revision = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return revision.isEmpty ? nil : revision
    }

    /// When the model finished downloading (the marker's date).
    public var installedAt: Date? {
        guard isInstalled else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: markerURL.path))?[.modificationDate] as? Date
    }

    /// The model folder's files (what an update check compares), without the marker.
    public var installedComponents: Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { $0 != Self.completionMarker && !$0.hasPrefix(".") })
    }

    /// Remembers which version is installed (found current by an update check).
    public func recordRevision(_ revision: String) {
        guard isInstalled else { return }
        try? Data(revision.utf8).write(to: markerURL)
    }

    public func cancelDownload() {
        task?.cancel()
    }

    public func remove() {
        task?.cancel()
        try? FileManager.default.removeItem(at: directory)
        status = .notDownloaded
    }
}
