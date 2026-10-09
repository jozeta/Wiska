import Core
import CryptoKit
import Foundation
import Observation

/// One version of the model file: where to fetch it and the SHA-256 Hugging Face publishes for it.
public struct KBWhisperFile: Equatable, Sendable {
    public let url: URL
    public let sha256: String

    public init(url: URL, sha256: String) {
        self.url = url
        self.sha256 = sha256
    }
}

/// KB-Whisper Large (KBLab's quantized whisper.cpp file): the newest version, downloaded on request,
/// checked against its published SHA-256, never half-installed.
@MainActor @Observable
public final class KBWhisperModelStore {
    public enum Status: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    private static let log = Log.logger("Whisper")
    public nonisolated static let repo = "KBLab/kb-whisper-large"
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
    @ObservationIgnored private let latestFile: @Sendable () async throws -> KBWhisperFile
    @ObservationIgnored private let hash: @Sendable (URL) throws -> String
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Called after a download completes (the toggle is switched on).
    @ObservationIgnored public var onDownloaded: (@MainActor () -> Void)?

    public var isInstalled: Bool { status == .ready }
    public var modelFile: URL { directory.appendingPathComponent(Self.fileName) }

    public init(directory: URL = KBWhisperModelStore.defaultDirectory,
                downloader: any FileDownloader = URLSessionFileDownloader(),
                freeSpace: @escaping @MainActor () -> Int64? = KBWhisperModelStore.availableSpace,
                latestFile: @escaping @Sendable () async throws -> KBWhisperFile = { try await KBWhisperModelStore.fetchLatest() },
                hash: @escaping @Sendable (URL) throws -> String = { try KBWhisperModelStore.sha256(of: $0) }) {
        self.hash = hash
        self.directory = directory
        self.downloader = downloader
        self.freeSpace = freeSpace
        self.latestFile = latestFile
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
        let latestFile = latestFile
        let hash = hash
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
                let file = try await latestFile()
                let expected = file.sha256
                try await downloader.download(from: file.url, to: partial, progress: report)
                try Task.checkCancellation()
                let actual = try await Task.detached { try hash(partial) }.value
                try Task.checkCancellation()   // Cancel pressed while the file was being checked
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

    public nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 8 << 20), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The newest version on Hugging Face: one small request, nothing about the user is sent.
    public nonisolated static func fetchLatest() async throws -> KBWhisperFile {
        let api = URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true")!
        let (data, response) = try await URLSession.shared.data(from: api)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try decodeLatest(data)
    }

    nonisolated static func decodeLatest(_ data: Data) throws -> KBWhisperFile {
        struct Listing: Decodable {
            struct File: Decodable {
                struct LFS: Decodable { let sha256: String }
                let rfilename: String
                let lfs: LFS?
            }
            let sha: String
            let siblings: [File]
        }
        let listing = try JSONDecoder().decode(Listing.self, from: data)
        guard let file = listing.siblings.first(where: { $0.rfilename == fileName }), let sha256 = file.lfs?.sha256 else {
            throw URLError(.cannotParseResponse)
        }
        let url = URL(string: "https://huggingface.co")!.appendingPathComponent(repo)
            .appendingPathComponent("resolve").appendingPathComponent(listing.sha).appendingPathComponent(fileName)
        return KBWhisperFile(url: url, sha256: sha256)
    }

    private var markerURL: URL { directory.appendingPathComponent(Self.completionMarker) }

    /// The installed file's fingerprint, recorded by an update check; nil before the first one.
    public var installedRevision: String? {
        guard isInstalled, let text = try? String(contentsOf: markerURL, encoding: .utf8) else { return nil }
        let revision = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return revision.isEmpty ? nil : revision
    }

    public var installedAt: Date? {
        guard isInstalled else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: markerURL.path))?[.modificationDate] as? Date
    }

    /// Only the model file: other files in the repo (ONNX, PyTorch) changing isn't an update.
    public var installedComponents: Set<String> { isInstalled ? [Self.fileName] : [] }

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
