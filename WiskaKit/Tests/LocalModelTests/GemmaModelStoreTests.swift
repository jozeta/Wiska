import Foundation
import Testing
@testable import LocalModel

struct FakeRepoDownloader: RepoDownloader {
    var fails = false
    func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: directory.appendingPathComponent("config.json"))
        progress(0.5)
        if fails { throw URLError(.networkConnectionLost) }
        progress(1)
    }
}

@MainActor
struct GemmaModelStoreTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gemma-\(UUID().uuidString)")

    func waitWhileDownloading(_ store: GemmaModelStore) async {
        while case .downloading = store.status { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func downloadsMarksCompleteAndReportsReady() async {
        let store = GemmaModelStore(directory: directory, downloader: FakeRepoDownloader(), freeSpace: { 10_000_000_000 })
        let done = Box(false)
        store.onDownloaded = { done.value = true }
        #expect(store.status == .notDownloaded)
        store.download()
        await waitWhileDownloading(store)
        #expect(store.status == .ready)
        #expect(done.value)
        #expect(GemmaModelStore(directory: directory, downloader: FakeRepoDownloader(), freeSpace: { nil }).isInstalled)
    }

    @Test func failedDownloadIsRemoved() async {
        let store = GemmaModelStore(directory: directory, downloader: FakeRepoDownloader(fails: true), freeSpace: { nil })
        store.download()
        await waitWhileDownloading(store)
        #expect(store.status == .failed("Download failed — try again"))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func notEnoughDiskSpaceSaysSoFirst() {
        let store = GemmaModelStore(directory: directory, downloader: FakeRepoDownloader(), freeSpace: { 2_000_000_000 })
        store.download()
        #expect(store.status == .failed("Needs about 6 GB free"))
    }

    /// A download interrupted by quitting leaves files without the marker: removed at launch.
    @Test func partialDownloadIsRemovedAtLaunch() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: directory.appendingPathComponent("model.safetensors"))
        let store = GemmaModelStore(directory: directory, downloader: FakeRepoDownloader(), freeSpace: { nil })
        #expect(store.status == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func removeDeletesTheModel() async {
        let store = GemmaModelStore(directory: directory, downloader: FakeRepoDownloader(), freeSpace: { nil })
        store.download()
        await waitWhileDownloading(store)
        store.remove()
        #expect(store.status == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

/// `WISKA_DOWNLOAD_GEMMA=1 swift test --filter GemmaRealDownload`: fetches the real model into the
/// app's folder (5.2 GB), so the app and the real-model tests find it.
@MainActor
struct GemmaRealDownload {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_DOWNLOAD_GEMMA"] == "1"), .timeLimit(.minutes(60)))
    func downloadsGemma() async {
        let store = GemmaModelStore()
        store.download()
        while case .downloading = store.status { try? await Task.sleep(for: .seconds(1)) }
        #expect(store.status == .ready)
    }
}

@MainActor final class Box<Value> { var value: Value; init(_ value: Value) { self.value = value } }
