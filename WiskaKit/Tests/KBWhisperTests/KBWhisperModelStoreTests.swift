import CryptoKit
import Foundation
import Testing
@testable import KBWhisper

struct FakeFileDownloader: FileDownloader {
    var contents = Data("ggml".utf8)
    var fails = false
    func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: destination)
        progress(0.5)
        if fails { throw URLError(.networkConnectionLost) }
    }
}

@MainActor
struct KBWhisperModelStoreTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kb-\(UUID().uuidString)")
    let sha = SHA256.hash(data: Data("ggml".utf8)).map { String(format: "%02x", $0) }.joined()

    func store(_ downloader: FakeFileDownloader = FakeFileDownloader(), free: Int64? = nil, sha: String? = nil) -> KBWhisperModelStore {
        KBWhisperModelStore(directory: directory, downloader: downloader, freeSpace: { free }, expectedSHA256: sha ?? self.sha)
    }

    func waitWhileDownloading(_ store: KBWhisperModelStore) async {
        while case .downloading = store.status { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func downloadsVerifiesAndIsReady() async {
        let store = store()
        let done = Box(false)
        store.onDownloaded = { done.value = true }
        store.download()
        await waitWhileDownloading(store)
        #expect(store.status == .ready)
        #expect(done.value)
        #expect(FileManager.default.fileExists(atPath: store.modelFile.path))
        #expect(self.store().isInstalled)
    }

    @Test func checksumMismatchIsRemoved() async {
        let store = store(sha: String(repeating: "0", count: 64))
        store.download()
        await waitWhileDownloading(store)
        #expect(store.status == .failed("Download failed — try again"))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func networkFailureIsRemoved() async {
        let store = store(FakeFileDownloader(fails: true))
        store.download()
        await waitWhileDownloading(store)
        #expect(store.status == .failed("Download failed — try again"))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func notEnoughDiskSpace() {
        let store = store(free: 500_000_000)
        store.download()
        #expect(store.status == .failed("Needs about 2 GB free"))
    }

    @Test func partialDownloadIsRemovedAtLaunch() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: directory.appendingPathComponent("ggml-model-q5_0.bin.partial"))
        #expect(store().status == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func removeDeletesTheModel() async {
        let store = store()
        store.download()
        await waitWhileDownloading(store)
        store.remove()
        #expect(store.status == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// Cancel while the 1.1 GB file is being checked: nothing is installed.
    @Test func cancelDuringTheChecksumInstallsNothing() async throws {
        let store = KBWhisperModelStore(directory: directory, downloader: FakeFileDownloader(), freeSpace: { nil },
                                        expectedSHA256: sha, hash: { url in
            Thread.sleep(forTimeInterval: 0.3)
            return try KBWhisperModelStore.sha256(of: url)
        })
        store.download()
        try await Task.sleep(for: .milliseconds(100))
        store.cancelDownload()
        await waitWhileDownloading(store)
        #expect(store.status == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func pinnedModelFile() {
        #expect(KBWhisperModelStore.fileURL.absoluteString
                == "https://huggingface.co/KBLab/kb-whisper-large/resolve/d5d5984b4d8f7c4847a8ea203f1976285fb28300/ggml-model-q5_0.bin")
        #expect(KBWhisperModelStore.sha256 == "6d2863812d7410322bb7d8647a5c7260761300fa946714c9ed66d22bb30bcb19")
    }
}

/// `WISKA_DOWNLOAD_KB=1 swift test --filter KBWhisperRealDownload`: fetches KB-Whisper Large
/// (1.08 GB) into the app's folder, checked against its SHA-256.
@MainActor
struct KBWhisperRealDownload {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_DOWNLOAD_KB"] == "1"), .timeLimit(.minutes(30)))
    func downloadsKBWhisper() async {
        let store = KBWhisperModelStore()
        store.download()
        while case .downloading = store.status { try? await Task.sleep(for: .seconds(1)) }
        #expect(store.status == .ready)
    }
}

@MainActor final class Box<Value> { var value: Value; init(_ value: Value) { self.value = value } }
