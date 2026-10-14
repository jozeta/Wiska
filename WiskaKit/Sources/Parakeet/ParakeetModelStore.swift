import Core
import FluidAudio
import Foundation
import Observation

public protocol ModelDownloader: Sendable {
    func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws
    func exists(at directory: URL) -> Bool
}

/// Downloads Parakeet TDT v3 from Hugging Face via FluidAudio. The only network access in the app:
/// FluidAudio is kept in offline mode except for the duration of this call (review C2).
public struct FluidAudioDownloader: ModelDownloader {
    public init() {}

    public func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        ModelHub.offlineMode = false
        defer { ModelHub.offlineMode = true }
        _ = try await AsrModels.download(to: directory, version: .v3,
                                         progressHandler: { progress($0.fractionCompleted) })
    }

    public func exists(at directory: URL) -> Bool {
        AsrModels.modelsExist(at: directory, version: .v3)
    }
}

@MainActor @Observable
public final class ParakeetModelStore {
    public enum Status: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    private static let log = Log.logger("Parakeet")
    /// Written after a download fully succeeds; files without it are a partial download (review I1).
    public nonisolated static let completionMarker = ".securewispr-complete"

    /// FluidAudio stores models in `<parent>/<Repo.folderName>` regardless of the directory it is
    /// given, so we use exactly that folder: the one we mark complete and delete is the one it writes.
    public nonisolated static var defaultDirectory: URL {
        AppPaths.supportDirectory
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.parakeetV3.folderName, isDirectory: true)
    }

    public private(set) var status: Status
    public let directory: URL
    @ObservationIgnored private let downloader: any ModelDownloader
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Called after `remove()`, so whoever loaded the model (~1 GB in memory) can let it go.
    @ObservationIgnored var onRemove: (@MainActor () -> Void)?
    /// Called after a download completes, so the model is loaded even when Settings is closed.
    @ObservationIgnored public var onDownloaded: (@MainActor () -> Void)?

    public var isInstalled: Bool { status == .ready }

    /// For log lines: which model this store holds.
    @ObservationIgnored private let name: String

    public init(directory: URL = ParakeetModelStore.defaultDirectory,
                downloader: any ModelDownloader = FluidAudioDownloader(), name: String = "parakeet") {
        self.name = name
        // Loading must never fall back to downloading (review C2).
        ModelHub.offlineMode = true
        self.directory = directory
        self.downloader = downloader
        let marker = directory.appendingPathComponent(Self.completionMarker)
        if downloader.exists(at: directory) && FileManager.default.fileExists(atPath: marker.path) {
            status = .ready
        } else {
            if FileManager.default.fileExists(atPath: directory.path) {
                Self.log.notice("removing partial \(name, privacy: .public) download")
                try? FileManager.default.removeItem(at: directory)
            }
            status = .notDownloaded
        }
    }

    /// Starts a download. Only ever called from the Settings "Download" button.
    public func download(revision: String? = nil) {
        switch status {
        case .ready, .downloading: return
        case .notDownloaded, .failed: break
        }
        status = .downloading(0)
        let directory = directory
        let downloader = downloader
        // Built outside the task: FluidAudio calls this on an arbitrary queue.
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                // Hops from FluidAudio's queue can arrive out of order: never move backwards.
                guard let self, case .downloading(let current) = self.status, fraction > current else { return }
                self.status = .downloading(fraction)
            }
        }
        task = Task { [weak self] in
            do {
                try await downloader.download(to: directory, progress: report)
                try Task.checkCancellation()
                guard downloader.exists(at: directory) else { throw CocoaError(.fileReadCorruptFile) }
                try Data((revision ?? "").utf8).write(to: directory.appendingPathComponent(Self.completionMarker))
                self?.status = .ready
                Self.log.notice("\(self?.name ?? "model", privacy: .public) model downloaded")
                self?.onDownloaded?()
            } catch {
                try? FileManager.default.removeItem(at: directory)
                if Task.isCancelled || error is CancellationError {
                    self?.status = .notDownloaded
                } else {
                    Self.log.error("\(self?.name ?? "model", privacy: .public) download failed: \(Log.summary(error), privacy: .public)")
                    self?.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private var markerURL: URL { directory.appendingPathComponent(Self.completionMarker) }

    /// The repo revision this model was downloaded at; nil for installs from before update checks.
    public var installedRevision: String? {
        guard isInstalled, let text = try? String(contentsOf: markerURL, encoding: .utf8) else { return nil }
        let sha = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    /// The model folder's top-level entries (the files the downloader fetched), without the marker.
    public var installedComponents: Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { $0 != Self.completionMarker && !$0.hasPrefix(".") })
    }

    /// When the model finished downloading (the marker's date).
    public var installedAt: Date? {
        guard isInstalled else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: markerURL.path))?[.modificationDate] as? Date
    }

    /// Remembers which revision the installed model is (found to be current by an update check).
    public func recordRevision(_ sha: String) {
        guard isInstalled else { return }
        try? Data(sha.utf8).write(to: markerURL)
    }

    public func cancelDownload() {
        task?.cancel()
    }

    public func remove() {
        task?.cancel()
        try? FileManager.default.removeItem(at: directory)
        status = .notDownloaded
        onRemove?()
    }
}

extension ParakeetModelStore: UpdatableModelStore {
    /// The Hugging Face repo update checks ask about.
    public nonisolated static var huggingFaceRepo: String { Repo.parakeetV3.rawValue }

    public var isDownloading: Bool {
        if case .downloading = status { true } else { false }
    }

    public func startDownload() { download() }
}
