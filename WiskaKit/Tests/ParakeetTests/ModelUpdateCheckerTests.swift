import Foundation
import Testing
@testable import Parakeet

struct CheckFailed: Error {}

final class FakeRevisionSource: ModelRevisionSource, @unchecked Sendable {
    var revision = ModelRevision(sha: "new", lastModified: Date(timeIntervalSince1970: 2_000))
    var fail = false
    private(set) var calls = 0
    func latestRevision() async throws -> ModelRevision {
        calls += 1
        if fail { throw CheckFailed() }
        return revision
    }
}

@MainActor
struct ModelUpdateCheckerTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pkupd-\(UUID().uuidString)")
    let source = FakeRevisionSource()
    let lastCheck = Box<Date?>(nil)
    let interval = Box(7)

    final class Box<T> { var value: T; init(_ value: T) { self.value = value } }

    func installedStore(revision: String?) throws -> ParakeetModelStore {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data((revision ?? "").utf8).write(to: dir.appendingPathComponent(ParakeetModelStore.completionMarker))
        return ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true))
    }

    func checker(_ store: ParakeetModelStore) -> ModelUpdateChecker {
        ModelUpdateChecker(store: store, source: source, interval: { [interval] in interval.value },
                           lastCheck: { [lastCheck] in lastCheck.value },
                           setLastCheck: { [lastCheck] in lastCheck.value = $0 })
    }

    @Test func updateRule() {
        let latest = ModelRevision(sha: "b", lastModified: Date(timeIntervalSince1970: 100))
        #expect(!ModelUpdateChecker.isUpdate(installed: "b", installedAt: nil, latest: latest))
        #expect(ModelUpdateChecker.isUpdate(installed: "a", installedAt: nil, latest: latest))
        #expect(!ModelUpdateChecker.isUpdate(installed: nil, installedAt: Date(timeIntervalSince1970: 200), latest: latest))
        #expect(ModelUpdateChecker.isUpdate(installed: nil, installedAt: Date(timeIntervalSince1970: 50), latest: latest))
    }

    @Test func sameShaIsUpToDate() async throws {
        source.revision = ModelRevision(sha: "same", lastModified: .now)
        let checker = checker(try installedStore(revision: "same"))
        let now = Date()
        await checker.checkNow(now: now)
        #expect(checker.state == .upToDate(now))
        #expect(lastCheck.value == now)
    }

    @Test func newShaIsAnUpdate() async throws {
        let checker = checker(try installedStore(revision: "old"))
        await checker.checkNow()
        #expect(checker.state == .updateAvailable(source.revision))
    }

    @Test func legacyInstallUpToDateRecordsTheSha() async throws {
        let store = try installedStore(revision: nil)   // marker written just now
        source.revision = ModelRevision(sha: "current", lastModified: Date(timeIntervalSince1970: 1_000))
        let checker = checker(store)
        await checker.checkNow()
        #expect(checker.state != .updateAvailable(source.revision))
        #expect(store.installedRevision == "current")
    }

    @Test func failureIsShownOnManualCheck() async throws {
        source.fail = true
        let checker = checker(try installedStore(revision: "a"))
        await checker.checkNow()
        guard case .failed = checker.state else { Issue.record("expected failed, got \(checker.state)"); return }
        #expect(lastCheck.value == nil)
    }

    @Test func neverDoesNotCheck() async throws {
        interval.value = 0
        let found = await checker(try installedStore(revision: "old")).checkIfDue()
        #expect(!found)
        #expect(source.calls == 0)
    }

    @Test func notInstalledDoesNotCheck() async {
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        #expect(await checker(store).checkIfDue() == false)
        #expect(source.calls == 0)
    }

    @Test func recentlyCheckedIsNotDue() async throws {
        let now = Date()
        lastCheck.value = now.addingTimeInterval(-3 * 86_400)
        #expect(await checker(try installedStore(revision: "old")).checkIfDue(now: now) == false)
        #expect(source.calls == 0)
        lastCheck.value = now.addingTimeInterval(-8 * 86_400)
        #expect(await checker(try installedStore(revision: "old")).checkIfDue(now: now) == true)
        #expect(source.calls == 1)
    }

    @Test func failedAutomaticCheckIsRetried() async throws {
        source.fail = true
        let checker = checker(try installedStore(revision: "old"))
        #expect(await checker.checkIfDue() == false)
        #expect(lastCheck.value == nil)
        #expect(checker.state == .idle)   // silent
        source.fail = false
        #expect(await checker.checkIfDue() == true)
    }

    @Test func announcesANewUpdateOnce() async throws {
        let checker = checker(try installedStore(revision: "old"))
        let now = Date()
        #expect(await checker.checkIfDue(now: now) == true)
        lastCheck.value = nil   // force another check
        #expect(await checker.checkIfDue(now: now) == false)
        #expect(checker.state == .updateAvailable(source.revision))
    }

    @Test func downloadUpdateRecordsTheNewSha() async throws {
        let store = try installedStore(revision: "old")
        let checker = checker(store)
        await checker.checkNow()
        checker.downloadUpdate()
        for _ in 0..<200 {
            if store.status == .ready, store.installedRevision == "new" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.status == .ready)
        #expect(store.installedRevision == "new")
        #expect(checker.state == .idle)
    }
}
