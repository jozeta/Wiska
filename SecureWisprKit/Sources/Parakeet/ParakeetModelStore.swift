import Core
import FluidAudio
import Foundation
import Observation

public protocol ModelDownloader: Sendable {
    func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws
    func exists(at directory: URL) -> Bool
}

/// Downloads Parakeet TDT v3 from Hugging Face via FluidAudio. The only network access in the app.
public struct FluidAudioDownloader: ModelDownloader {
    public init() {}

    public func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
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

    public nonisolated static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("SecureWispr/Models/parakeet-tdt-0.6b-v3", isDirectory: true)
    }

    public private(set) var status: Status
    public let directory: URL
    @ObservationIgnored private let downloader: any ModelDownloader
    @ObservationIgnored private var task: Task<Void, Never>?

    public var isInstalled: Bool { status == .ready }

    public init(directory: URL = ParakeetModelStore.defaultDirectory,
                downloader: any ModelDownloader = FluidAudioDownloader()) {
        self.directory = directory
        self.downloader = downloader
        status = downloader.exists(at: directory) ? .ready : .notDownloaded
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
