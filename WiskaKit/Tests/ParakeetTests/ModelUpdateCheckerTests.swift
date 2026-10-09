import Foundation
import Testing
@testable import Core
@testable import Parakeet

struct CheckFailed: Error {}

final class FakeRevisionSource: ModelRevisionSource, @unchecked Sendable {
    var revision = ModelRevision(sha: "repo2", lastModified: Date(timeIntervalSince1970: 2_000),
                                 files: ["Encoder.mlmodelc/weight.bin": "blob-new", "README.md": "r1"])
    var fail = false
    var delay: Duration = .zero
    private(set) var calls = 0
    func latestRevision() async throws -> ModelRevision {
        calls += 1
        if delay > .zero { try await Task.sleep(for: delay) }
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
    static let oldFiles = ModelRevision(sha: "repo1", lastModified: Date(timeIntervalSince1970: 1_000),
                                        files: ["Encoder.mlmodelc/weight.bin": "blob-old", "README.md": "r0"])

    final class Box<T> { var value: T; init(_ value: T) { self.value = value } }

    /// An installed model with an Encoder folder; `marker` is what the completion marker holds.
    func installedStore(marker: String?) throws -> ParakeetModelStore {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Encoder.mlmodelc"),
                                                withIntermediateDirectories: true)
        try Data((marker ?? "").utf8).write(to: dir.appendingPathComponent(ParakeetModelStore.completionMarker))
        return ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true))
    }

    func checker(_ store: ParakeetModelStore) -> ModelUpdateChecker {
        ModelUpdateChecker(store: store, source: source, interval: { [interval] in interval.value },
                           lastCheck: { [lastCheck] in lastCheck.value },
                           setLastCheck: { [lastCheck] in lastCheck.value = $0 })
    }

    @Test func fingerprintCoversOnlyTheInstalledFiles() {
        let readmeOnly = ModelRevision(sha: "x", lastModified: .now,
                                       files: ["Encoder.mlmodelc/weight.bin": "blob-old", "README.md": "changed"])
        let components: Set<String> = ["Encoder.mlmodelc"]
        #expect(readmeOnly.fingerprint(of: components) == Self.oldFiles.fingerprint(of: components))
        #expect(source.revision.fingerprint(of: components) != Self.oldFiles.fingerprint(of: components))
        #expect(Self.oldFiles.fingerprint(of: components).hasPrefix("files:"))
    }

    @Test func updateRule() {
        let components: Set<String> = ["Encoder.mlmodelc"]
        let latest = source.revision
        let installedOld = Self.oldFiles.fingerprint(of: components)
        #expect(ModelUpdateChecker.isUpdate(installed: installedOld, installedAt: nil, latest: latest, components: components))
        #expect(!ModelUpdateChecker.isUpdate(installed: latest.fingerprint(of: components), installedAt: nil,
                                             latest: latest, components: components))
        // Unknown (empty, or a repo sha from before fingerprints): compare dates.
        #expect(!ModelUpdateChecker.isUpdate(installed: "7dd20fe", installedAt: Date(timeIntervalSince1970: 3_000),
                                             latest: latest, components: components))
        #expect(ModelUpdateChecker.isUpdate(installed: nil, installedAt: Date(timeIntervalSince1970: 1_500),
                                            latest: latest, components: components))
    }

    @Test func onlyUnrelatedFilesChangedIsUpToDate() async throws {
        let components: Set<String> = ["Encoder.mlmodelc"]
        source.revision = ModelRevision(sha: "repo3", lastModified: .now,
                                        files: ["Encoder.mlmodelc/weight.bin": "blob-old", "README.md": "edited"])
        let checker = checker(try installedStore(marker: Self.oldFiles.fingerprint(of: components)))
        let now = Date()
        await checker.checkNow(now: now)
        #expect(checker.state == .upToDate(now))
        #expect(lastCheck.value == now)
    }

    @Test func changedModelFileIsAnUpdate() async throws {
        let checker = checker(try installedStore(marker: Self.oldFiles.fingerprint(of: ["Encoder.mlmodelc"])))
        await checker.checkNow()
        #expect(checker.state == .updateAvailable(source.revision))
    }

    @Test func legacyInstallUpToDateRecordsTheFingerprint() async throws {
        let store = try installedStore(marker: "7dd20fe")   // repo sha written before fingerprints
        source.revision = Self.oldFiles   // repo older than the install
        let checker = checker(store)
        await checker.checkNow()
        #expect(checker.state != .updateAvailable(source.revision))
        #expect(store.installedRevision == Self.oldFiles.fingerprint(of: ["Encoder.mlmodelc"]))
    }

    @Test func failureIsShownOnManualCheck() async throws {
        source.fail = true
        let checker = checker(try installedStore(marker: nil))
        await checker.checkNow()
        guard case .failed = checker.state else { Issue.record("expected failed, got \(checker.state)"); return }
        #expect(lastCheck.value == nil)
    }

    @Test func neverDoesNotCheck() async throws {
        interval.value = 0
        let found = await checker(try installedStore(marker: nil)).checkIfDue()
        #expect(!found)
        #expect(source.calls == 0)
    }

    @Test func notInstalledDoesNotCheck() async {
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        #expect(await checker(store).checkIfDue() == false)
        #expect(source.calls == 0)
    }

    @Test func recentlyCheckedIsNotDue() async throws {
        let marker = Self.oldFiles.fingerprint(of: ["Encoder.mlmodelc"])
        let now = Date()
        lastCheck.value = now.addingTimeInterval(-3 * 86_400)
        #expect(await checker(try installedStore(marker: marker)).checkIfDue(now: now) == false)
        #expect(source.calls == 0)
        lastCheck.value = now.addingTimeInterval(-8 * 86_400)
        #expect(await checker(try installedStore(marker: marker)).checkIfDue(now: now) == true)
        #expect(source.calls == 1)
    }

    @Test func failedAutomaticCheckIsRetried() async throws {
        source.fail = true
        let checker = checker(try installedStore(marker: Self.oldFiles.fingerprint(of: ["Encoder.mlmodelc"])))
        #expect(await checker.checkIfDue() == false)
        #expect(lastCheck.value == nil)
        #expect(checker.state == .idle)   // silent
        source.fail = false
        #expect(await checker.checkIfDue() == true)
    }

    /// A failing automatic check must not undo what a "Check now" found meanwhile.
    @Test func failedAutomaticCheckKeepsANewerResult() async throws {
        let store = try installedStore(marker: Self.oldFiles.fingerprint(of: ["Encoder.mlmodelc"]))
        let automatic = checker(store)
        source.fail = true
        source.delay = .milliseconds(200)
        let running = Task { await automatic.checkIfDue() }
        try await Task.sleep(for: .milliseconds(50))
        source.fail = false
        source.delay = .zero
        await automatic.checkNow()
        _ = await running.value
        #expect(automatic.state == .updateAvailable(source.revision))
    }

    @Test func announcesANewUpdateOnce() async throws {
        let checker = checker(try installedStore(marker: Self.oldFiles.fingerprint(of: ["Encoder.mlmodelc"])))
        let now = Date()
        #expect(await checker.checkIfDue(now: now) == true)
        lastCheck.value = nil   // force another check
        #expect(await checker.checkIfDue(now: now) == false)
        #expect(checker.state == .updateAvailable(source.revision))
    }

    /// The update is downloaded, then checked again: the marker ends up describing what was installed.
    @Test func downloadUpdateRecordsWhatWasDownloaded() async throws {
        let store = try installedStore(marker: Self.oldFiles.fingerprint(of: ["Encoder.mlmodelc"]))
        let checker = checker(store)
        await checker.checkNow()
        checker.downloadUpdate()
        // The fake download writes different files: the fingerprint follows what is installed.
        var expected = ""
        for _ in 0..<300 {
            expected = source.revision.fingerprint(of: store.installedComponents)
            if store.status == .ready, store.installedRevision == expected { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.status == .ready)
        #expect(store.installedRevision == expected)
        #expect(checker.state != .updateAvailable(source.revision))
    }

    /// After a relaunch the result of the last check is unknown: never claim "Up to date".
    @Test func statusTextIsHonestAfterARelaunch() {
        let checked = Date(timeIntervalSince1970: 1_000)
        let now = checked.addingTimeInterval(3 * 3_600)
        #expect(ModelUpdateChecker.statusText(.idle, lastCheck: checked, now: now).hasPrefix("Last checked"))
        #expect(ModelUpdateChecker.statusText(.idle, lastCheck: nil, now: now) == "Not checked yet")
        #expect(ModelUpdateChecker.statusText(.upToDate(checked), lastCheck: checked, now: now).hasPrefix("Up to date"))
        #expect(ModelUpdateChecker.statusText(.checking, lastCheck: nil, now: now) == "Checking…")
        #expect(ModelUpdateChecker.statusText(.updateAvailable(source.revision), lastCheck: nil, now: now) == "Update available")
        #expect(ModelUpdateChecker.statusText(.failed("offline"), lastCheck: nil, now: now) == "Couldn't check: offline")
    }

    /// The re-check after a finished update is quiet: offline, the card doesn't say "Couldn't check".
    @Test func recheckAfterAnUpdateIsQuietWhenOffline() async throws {
        let store = try installedStore(marker: Self.oldFiles.fingerprint(of: ["Encoder.mlmodelc"]))
        let checker = checker(store)
        await checker.checkNow()
        source.fail = true
        checker.downloadUpdate()
        for _ in 0..<100 where store.status != .ready { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(400))
        #expect(store.status == .ready)
        #expect(checker.state == .idle)
    }

    /// The same model files are announced once, even if the repo sha changes again (a README edit).
    @Test func sameFilesAreAnnouncedOnce() async throws {
        let checker = checker(try installedStore(marker: Self.oldFiles.fingerprint(of: ["Encoder.mlmodelc"])))
        #expect(await checker.checkIfDue() == true)
        lastCheck.value = nil
        source.revision = ModelRevision(sha: "repo9", lastModified: .now, files: source.revision.files)
        #expect(await checker.checkIfDue() == false)
    }
}
