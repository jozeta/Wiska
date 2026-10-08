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
        URL.applicationSupportDirectory
            .appendingPathComponent("SecureWispr/Models", isDirectory: true)
            .appendingPathComponent(Repo.parakeetV3.folderName, isDirectory: true)
    }

    public private(set) var status: Status
    public let directory: URL
    @ObservationIgnored private let downloader: any ModelDownloader
    @ObservationIgnored private var task: Task<Void, Never>?

    public var isInstalled: Bool { status == .ready }

    public init(directory: URL = ParakeetModelStore.defaultDirectory,
                downloader: any ModelDownloader = FluidAudioDownloader()) {
        // Loading must never fall back to downloading (review C2).
        ModelHub.offlineMode = true
        self.directory = directory
        self.downloader = downloader
        let marker = directory.appendingPathComponent(Self.completionMarker)
        if downloader.exists(at: directory) && FileManager.default.fileExists(atPath: marker.path) {
            status = .ready
        } else {
            if FileManager.default.fileExists(atPath: directory.path) {
                Self.log.notice("removing partial parakeet download")
                try? FileManager.default.removeItem(at: directory)
            }
            status = .notDownloaded
        }
    }

    /// Starts a download. Only ever called from the Settings "Download" button.
    public func download() {
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
                guard let self, case .downloading = self.status else { return }
                self.status = .downloading(fraction)
            }
        }
        task = Task { [weak self] in
            do {
                try await downloader.download(to: directory, progress: report)
                try Task.checkCancellation()
                guard downloader.exists(at: directory) else { throw CocoaError(.fileReadCorruptFile) }
                try Data().write(to: directory.appendingPathComponent(Self.completionMarker))
                self?.status = .ready
                Self.log.info("parakeet model downloaded")
            } catch {
                try? FileManager.default.removeItem(at: directory)
                if Task.isCancelled || error is CancellationError {
                    self?.status = .notDownloaded
                } else {
                    Self.log.error("parakeet download failed: \(String(describing: error), privacy: .public)")
                    self?.status = .failed(error.localizedDescription)
                }
            }
        }
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
