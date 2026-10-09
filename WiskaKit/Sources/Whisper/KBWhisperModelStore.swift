import Core
import CryptoKit
import Foundation
import Observation

/// KB-Whisper Large (KBLab's quantized whisper.cpp file): downloaded on request, checked against
/// its published SHA-256, never half-installed.
@MainActor @Observable
public final class KBWhisperModelStore {
    public enum Status: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    private static let log = Log.logger("Whisper")
    public nonisolated static let fileURL = URL(string:
        "https://huggingface.co/KBLab/kb-whisper-large/resolve/d5d5984b4d8f7c4847a8ea203f1976285fb28300/ggml-model-q5_0.bin")!
    public nonisolated static let sha256 = "6d2863812d7410322bb7d8647a5c7260761300fa946714c9ed66d22bb30bcb19"
    nonisolated static let fileName = "ggml-model-q5_0.bin"
    nonisolated static let completionMarker = ".wiska-complete"
    public nonisolated static let requiredFreeBytes: Int64 = 2_000_000_000

    public nonisolated static var defaultDirectory: URL {
        AppPaths.supportDirectory.appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("kb-whisper-large", isDirectory: true)
    }

    public private(set) var status: Status
    public let directory: URL
    @ObservationIgnored private let downloader: any FileDownloader
    @ObservationIgnored private let freeSpace: @MainActor () -> Int64?
    @ObservationIgnored private let expectedSHA256: String
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Called after a download completes (the toggle is switched on).
    @ObservationIgnored public var onDownloaded: (@MainActor () -> Void)?

    public var isInstalled: Bool { status == .ready }
    public var modelFile: URL { directory.appendingPathComponent(Self.fileName) }

    public init(directory: URL = KBWhisperModelStore.defaultDirectory,
                downloader: any FileDownloader = URLSessionFileDownloader(),
                freeSpace: @escaping @MainActor () -> Int64? = KBWhisperModelStore.availableSpace,
                expectedSHA256: String = KBWhisperModelStore.sha256) {
        self.directory = directory
        self.downloader = downloader
        self.freeSpace = freeSpace
        self.expectedSHA256 = expectedSHA256
        let marker = directory.appendingPathComponent(Self.completionMarker)
        if FileManager.default.fileExists(atPath: marker.path),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent(Self.fileName).path) {
            status = .ready
        } else {
            if FileManager.default.fileExists(atPath: directory.path) {
                Self.log.notice("removing partial kb-whisper download")
                try? FileManager.default.removeItem(at: directory)
            }
            status = .notDownloaded
        }
    }

    public static func availableSpace() -> Int64? {
        let values = try? AppPaths.supportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public func download() {
        switch status {
        case .ready, .downloading: return
        case .notDownloaded, .failed: break
        }
        if let free = freeSpace(), free < Self.requiredFreeBytes {
            status = .failed("Needs about 2 GB free")
            return
        }
        status = .downloading(0)
        let directory = directory
        let downloader = downloader
        let expected = expectedSHA256
        let partial = directory.appendingPathComponent(Self.fileName + ".partial")
        let final = modelFile
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading(let current) = self.status, fraction > current else { return }
                self.status = .downloading(min(fraction, 0.999))
            }
        }
        task = Task { [weak self] in
            do {
                try await downloader.download(from: Self.fileURL, to: partial, progress: report)
                try Task.checkCancellation()
                let actual = try await Task.detached { try Self.sha256(of: partial) }.value
                guard actual == expected else { throw CocoaError(.fileReadCorruptFile) }
                try FileManager.default.moveItem(at: partial, to: final)
                try Data().write(to: directory.appendingPathComponent(Self.completionMarker))
                self?.status = .ready
                Self.log.info("kb-whisper model downloaded")
                self?.onDownloaded?()
            } catch {
                try? FileManager.default.removeItem(at: directory)
                if Task.isCancelled || error is CancellationError {
                    self?.status = .notDownloaded
                } else {
                    Self.log.error("kb-whisper download failed: \(String(describing: error), privacy: .public)")
                    self?.status = .failed("Download failed — try again")
                }
            }
        }
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 8 << 20), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
