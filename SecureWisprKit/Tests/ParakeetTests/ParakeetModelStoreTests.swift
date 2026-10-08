import Core
import FluidAudio
import Foundation
import Testing
@testable import Parakeet

struct DownloadFailed: Error {}

final class FakeDownloader: ModelDownloader, @unchecked Sendable {
    var installed: Bool
    var fail = false
    var delay: Duration = .zero
    init(installed: Bool) { self.installed = installed }

    func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: directory.appendingPathComponent("part.bin"))
        progress(0.5)
        if delay > .zero { try await Task.sleep(for: delay) }
        if fail { throw DownloadFailed() }
        installed = true
        progress(1)
    }

    func exists(at directory: URL) -> Bool { installed }
}

@MainActor
struct ParakeetModelStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pk-\(UUID().uuidString)")

    private func waitWhileDownloading(_ store: ParakeetModelStore) async throws {
        for _ in 0..<200 {
            if case .downloading = store.status { try await Task.sleep(for: .milliseconds(10)) } else { return }
        }
    }

    private func markComplete() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent(ParakeetModelStore.completionMarker))
    }

    @Test func startsReadyWhenModelExists() throws {
        try markComplete()
        #expect(ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true)).status == .ready)
    }

    @Test func defaultDirectoryIsWhereFluidAudioActuallyStoresTheModel() {
        // Review C1: FluidAudio writes to <parent>/<repo folder>, not to the directory passed in,
        // unless that directory already *is* the repo folder.
        #expect(ParakeetModelStore.defaultDirectory.lastPathComponent == "parakeet-tdt-0.6b-v3-coreml")
    }

    @Test func storeLocksFluidAudioOffline() {
        // Review C2: loading must never fall back to downloading.
        ModelHub.offlineMode = false
        _ = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        #expect(ModelHub.offlineMode == true)
    }

    @Test func filesWithoutCompletionMarkerAreTreatedAsPartialAndDeleted() throws {
        // Review I1: app quit mid-download can leave files that FluidAudio considers present.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true))
        #expect(store.status == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func successfulDownloadWritesCompletionMarker() async throws {
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        store.download()
        try await waitWhileDownloading(store)
        #expect(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(ParakeetModelStore.completionMarker).path))
    }

    @Test func partialFilesAreNotInstalled() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: dir.appendingPathComponent("x.bin"))
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        #expect(store.status == .notDownloaded)
        #expect(!store.isInstalled)
    }

    @Test func successfulDownloadBecomesReady() async throws {
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        store.download()
        try await waitWhileDownloading(store)
        #expect(store.status == .ready)
        #expect(store.isInstalled)
    }

    @Test func failedDownloadCleansUpAndReportsFailure() async throws {
        let downloader = FakeDownloader(installed: false)
        downloader.fail = true
        let store = ParakeetModelStore(directory: dir, downloader: downloader)
        store.download()
        try await waitWhileDownloading(store)
        guard case .failed = store.status else {
            Issue.record("expected failed, got \(store.status)")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func cancelledDownloadReturnsToNotDownloaded() async throws {
        let downloader = FakeDownloader(installed: false)
        downloader.delay = .seconds(5)
        let store = ParakeetModelStore(directory: dir, downloader: downloader)
        store.download()
        try await Task.sleep(for: .milliseconds(50))
        store.cancelDownload()
        try await waitWhileDownloading(store)
        #expect(store.status == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func removeDeletesTheModel() throws {
        try markComplete()
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true))
        store.remove()
        #expect(store.status == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }
}
