# Wiska M13 Parakeet Model Update Checks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Check the Parakeet model's Hugging Face repo for a newer revision automatically (every X days) or on demand, and offer "Download update" when one exists — never downloading by itself.

**Architecture:** The store records the downloaded revision sha in its completion marker. A `HuggingFaceRevisionSource` reads the repo's current sha/lastModified; a `ModelUpdateChecker` compares them (falling back to dates for installs from before M13), tracks its state and when it last checked (through closures the app binds to `SettingsStore`). The app runs `checkIfDue` at launch and hourly, and shows the state on the Parakeet card and in the menu.

**Tech Stack:** Swift 6.2, SwiftPM `WiskaKit` (Parakeet, Preferences), Foundation `URLSession`, Swift Testing, SwiftUI app `Wiska`.

**Spec:** `docs/superpowers/specs/2026-10-09-wiska-m13-model-updates-design.md`

## Global Constraints

- Endpoint: `https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml` (`Repo.parakeetV3.rawValue`), 15 s timeout; fields `sha`, `lastModified` (ISO 8601, fractional seconds).
- Intervals (days): 0 = Never, 1, 7 (default), 30. Keys `"modelUpdateInterval"`, `"lastModelUpdateCheck"`.
- Automatic checks: at launch and hourly; only when Parakeet is installed and the interval isn't 0; a failed automatic check is silent and doesn't move the last-check date.
- Never download automatically. Download update = remove + download in the same folder.
- Copy: "Up to date · checked <relative>", "Checking…", "Update available", "Couldn't check: <message>", "Check now", "Download update", "Check for model updates", "Speech model update available…" (menu), "Speech model update available" (notch, once per new revision).
- No test touches the network.
- Tests: `cd WiskaKit && swift test`. App build from repo root: `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build build`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**Decisions made while planning:**
- A first-time download from the card's "Download" button stores no sha (no network call before it); such installs use the date rule until the first check records the sha. Only "Download update" passes the sha it is installing.
- `ModelUpdateChecker` lives in the Parakeet module and reaches the settings through closures, so Parakeet doesn't depend on Preferences.

## Review Focus

1. An install from before M13 (empty marker) must not show "Update available" when the repo hasn't changed since the download. Pinned by `ModelUpdateCheckerTests.legacyInstallUpToDateRecordsTheSha`.
2. A network failure during an automatic check must not mark the check done (it retries next hour) and must not alarm the user. Pinned by `ModelUpdateCheckerTests.failedAutomaticCheckIsRetried`.
3. The same available update must be announced once, not every hour. Pinned by `ModelUpdateCheckerTests.announcesANewUpdateOnce`.
4. After "Download update" the marker must hold the new sha, or the next check reports the same update again. Pinned by `ModelUpdateCheckerTests.downloadUpdateRecordsTheNewSha`.
5. "Never" means no request at all. Pinned by `ModelUpdateCheckerTests.neverDoesNotCheck`.

---

### Task 1: Revision source and the store's recorded revision

**Files:**
- Create: `WiskaKit/Sources/Parakeet/ModelRevision.swift`
- Modify: `WiskaKit/Sources/Parakeet/ParakeetModelStore.swift`
- Test: `WiskaKit/Tests/ParakeetTests/ModelRevisionTests.swift`

**Interfaces:**
- Produces: `struct ModelRevision: Equatable, Sendable { sha: String; lastModified: Date }`; `protocol ModelRevisionSource: Sendable { func latestRevision() async throws -> ModelRevision }`; `struct HuggingFaceRevisionSource: ModelRevisionSource` with `init(repo: String = Repo.parakeetV3.rawValue, session: URLSession = .shared)` and `static func decode(_ data: Data) throws -> ModelRevision`; `ParakeetModelStore.download(revision: String? = nil)`, `installedRevision: String?`, `installedAt: Date?`, `recordRevision(_ sha: String)`.

- [ ] **Step 1: Write the failing test**

```swift
// WiskaKit/Tests/ParakeetTests/ModelRevisionTests.swift
import Foundation
import Testing
@testable import Parakeet

@MainActor
struct ModelRevisionTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pkrev-\(UUID().uuidString)")

    @Test func decodesTheHuggingFaceResponse() throws {
        let json = #"{"_id":"x","id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","sha":"7dd20fe6","lastModified":"2026-08-19T20:10:29.000Z","private":false}"#
        let revision = try HuggingFaceRevisionSource.decode(Data(json.utf8))
        #expect(revision.sha == "7dd20fe6")
        #expect(revision.lastModified == Date(timeIntervalSince1970: 1_787_170_229))
    }

    @Test func decodesDatesWithoutFractionalSeconds() throws {
        let json = #"{"sha":"a","lastModified":"2026-08-19T20:10:29Z"}"#
        #expect(try HuggingFaceRevisionSource.decode(Data(json.utf8)).sha == "a")
    }

    @Test func missingFieldsAreAnError() {
        #expect(throws: (any Error).self) { try HuggingFaceRevisionSource.decode(Data(#"{"sha":"a"}"#.utf8)) }
    }

    @Test func downloadRecordsTheRevision() async throws {
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        store.download(revision: "abc123")
        for _ in 0..<200 { if case .downloading = store.status { try await Task.sleep(for: .milliseconds(10)) } }
        #expect(store.status == .ready)
        #expect(store.installedRevision == "abc123")
        #expect(store.installedAt != nil)
    }

    @Test func plainDownloadHasNoRevisionUntilRecorded() async throws {
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        store.download()
        for _ in 0..<200 { if case .downloading = store.status { try await Task.sleep(for: .milliseconds(10)) } }
        #expect(store.installedRevision == nil)
        store.recordRevision("def456")
        #expect(store.installedRevision == "def456")
        // A recorded revision survives a relaunch.
        #expect(ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true)).installedRevision == "def456")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WiskaKit && swift test --filter ModelRevisionTests`
Expected: FAIL — `HuggingFaceRevisionSource` not found.

- [ ] **Step 3: Implement**

```swift
// WiskaKit/Sources/Parakeet/ModelRevision.swift
import FluidAudio
import Foundation

/// One published state of the model repo on Hugging Face.
public struct ModelRevision: Equatable, Sendable {
    public let sha: String
    public let lastModified: Date

    public init(sha: String, lastModified: Date) {
        self.sha = sha
        self.lastModified = lastModified
    }
}

public protocol ModelRevisionSource: Sendable {
    func latestRevision() async throws -> ModelRevision
}

/// Asks Hugging Face which revision of the model repo is current. One small request; nothing
/// about the user is sent. Used only for update checks, never to download.
public struct HuggingFaceRevisionSource: ModelRevisionSource {
    struct BadResponse: Error {}
    private struct Body: Decodable {
        let sha: String
        let lastModified: String
    }

    private let url: URL
    private let session: URLSession

    public init(repo: String = Repo.parakeetV3.rawValue, session: URLSession = .shared) {
        self.url = URL(string: "https://huggingface.co/api/models/\(repo)")!
        self.session = session
    }

    public func latestRevision() async throws -> ModelRevision {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BadResponse()
        }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> ModelRevision {
        let body = try JSONDecoder().decode(Body.self, from: data)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = fractional.date(from: body.lastModified) ?? plain.date(from: body.lastModified) else {
            throw BadResponse()
        }
        return ModelRevision(sha: body.sha, lastModified: date)
    }
}
```

`ParakeetModelStore.swift`:
- `public func download()` becomes `public func download(revision: String? = nil)`; in the task, replace `try Data().write(to: directory.appendingPathComponent(Self.completionMarker))` with `try Data((revision ?? "").utf8).write(to: directory.appendingPathComponent(Self.completionMarker))`.
- Add:

```swift
    private var markerURL: URL { directory.appendingPathComponent(Self.completionMarker) }

    /// The repo revision this model was downloaded at; nil for installs from before update checks.
    public var installedRevision: String? {
        guard isInstalled, let text = try? String(contentsOf: markerURL, encoding: .utf8) else { return nil }
        let sha = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WiskaKit && swift test --filter "ModelRevisionTests|ParakeetModelStoreTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(parakeet): read the model repo's revision; the store records which revision it downloaded"
```

---

### Task 2: ModelUpdateChecker

**Files:**
- Create: `WiskaKit/Sources/Parakeet/ModelUpdateChecker.swift`
- Test: `WiskaKit/Tests/ParakeetTests/ModelUpdateCheckerTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces: `ModelUpdateChecker` (`@MainActor @Observable`) with `init(store:source:interval:lastCheck:setLastCheck:)`, `enum State: Equatable { idle, checking, upToDate(Date), updateAvailable(ModelRevision), failed(String) }`, `state`, `checkNow(now: Date = Date()) async`, `checkIfDue(now: Date = Date()) async -> Bool`, `downloadUpdate()`, `static isUpdate(installed:installedAt:latest:) -> Bool`.

- [ ] **Step 1: Write the failing test**

```swift
// WiskaKit/Tests/ParakeetTests/ModelUpdateCheckerTests.swift
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
```

Note: `FakeDownloader(installed: true)` reports the model as present even after `remove()`; for `downloadUpdateRecordsTheNewSha` that is fine because `download(revision:)` writes the marker after the fake download.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WiskaKit && swift test --filter ModelUpdateCheckerTests`
Expected: FAIL — `ModelUpdateChecker` not found.

- [ ] **Step 3: Implement**

```swift
// WiskaKit/Sources/Parakeet/ModelUpdateChecker.swift
import Core
import Foundation
import Observation

/// Checks whether a newer revision of the installed Parakeet model has been published.
/// Never downloads by itself: `downloadUpdate()` is only called from the Settings button.
@MainActor @Observable
public final class ModelUpdateChecker {
    public enum State: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case updateAvailable(ModelRevision)
        case failed(String)
    }

    private static let log = Log.logger("Parakeet")

    public private(set) var state: State = .idle
    @ObservationIgnored private let store: ParakeetModelStore
    @ObservationIgnored private let source: any ModelRevisionSource
    @ObservationIgnored private let interval: @MainActor () -> Int
    @ObservationIgnored private let lastCheck: @MainActor () -> Date?
    @ObservationIgnored private let setLastCheck: @MainActor (Date) -> Void
    /// The last update announced by an automatic check, so it's announced once.
    @ObservationIgnored private var announcedSha: String?

    public init(store: ParakeetModelStore, source: any ModelRevisionSource,
                interval: @escaping @MainActor () -> Int, lastCheck: @escaping @MainActor () -> Date?,
                setLastCheck: @escaping @MainActor (Date) -> Void) {
        self.store = store
        self.source = source
        self.interval = interval
        self.lastCheck = lastCheck
        self.setLastCheck = setLastCheck
    }

    /// A different sha is an update; installs from before update checks (no sha) compare dates.
    public static func isUpdate(installed: String?, installedAt: Date?, latest: ModelRevision) -> Bool {
        if let installed { return installed != latest.sha }
        guard let installedAt else { return false }
        return latest.lastModified > installedAt
    }

    /// "Check now": always checks and shows failures.
    public func checkNow(now: Date = Date()) async {
        guard store.isInstalled else { return }
        state = .checking
        do {
            try await check(now: now)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// The automatic check: only when installed, not set to Never, and the last check is older than
    /// the interval. Failures are silent and retried later. True when it found an update not yet announced.
    public func checkIfDue(now: Date = Date()) async -> Bool {
        let days = interval()
        guard store.isInstalled, days > 0 else { return false }
        if let last = lastCheck(), now.timeIntervalSince(last) < Double(days) * 86_400 { return false }
        let previous = state
        do {
            try await check(now: now)
        } catch {
            Self.log.notice("model update check failed: \(String(describing: error), privacy: .public)")
            state = previous
            return false
        }
        guard case .updateAvailable(let latest) = state, latest.sha != announcedSha else { return false }
        announcedSha = latest.sha
        return true
    }

    /// Replaces the installed model with the latest revision (Parakeet is unavailable meanwhile).
    public func downloadUpdate() {
        guard case .updateAvailable(let latest) = state else { return }
        store.remove()
        store.download(revision: latest.sha)
        state = .idle
    }

    private func check(now: Date) async throws {
        let latest = try await source.latestRevision()
        setLastCheck(now)
        let installed = store.installedRevision
        if Self.isUpdate(installed: installed, installedAt: store.installedAt, latest: latest) {
            state = .updateAvailable(latest)
        } else {
            if installed == nil { store.recordRevision(latest.sha) }
            state = .upToDate(now)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WiskaKit && swift test --filter "ModelUpdateCheckerTests|ModelRevisionTests|ParakeetModelStoreTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(parakeet): model update checker — on demand or when due, never downloads by itself"
```

---

### Task 3: Settings

**Files:**
- Modify: `WiskaKit/Sources/Preferences/SettingsStore.swift`
- Test: `WiskaKit/Tests/PreferencesTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces: `SettingsStore.modelUpdateInterval: Int` (default 7), `SettingsStore.lastModelUpdateCheck: Date?`, `static let modelUpdateIntervals = [0, 1, 7, 30]`.

- [ ] **Step 1: Write the failing test** (append inside `SettingsStoreTests`)

```swift
    @Test func modelUpdateSettings() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.modelUpdateInterval == 7)
        #expect(store.lastModelUpdateCheck == nil)
        let date = Date(timeIntervalSince1970: 1_000_000)
        store.modelUpdateInterval = 30
        store.lastModelUpdateCheck = date
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.modelUpdateInterval == 30)
        #expect(reloaded.lastModelUpdateCheck == date)
        #expect(SettingsStore.modelUpdateIntervals == [0, 1, 7, 30])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WiskaKit && swift test --filter SettingsStoreTests`
Expected: FAIL — `modelUpdateInterval` not found.

- [ ] **Step 3: Implement**

Keys: `static let modelUpdateInterval = "modelUpdateInterval"`, `static let lastModelUpdateCheck = "lastModelUpdateCheck"`. Properties (near `outputMode`):

```swift
    public static let modelUpdateIntervals = [0, 1, 7, 30]
    /// Days between automatic checks for a newer Parakeet model; 0 = never.
    public var modelUpdateInterval: Int {
        didSet { defaults.set(modelUpdateInterval, forKey: Key.modelUpdateInterval) }
    }
    public var lastModelUpdateCheck: Date? {
        didSet { defaults.set(lastModelUpdateCheck, forKey: Key.lastModelUpdateCheck) }
    }
```

In `init`:

```swift
        modelUpdateInterval = defaults.object(forKey: Key.modelUpdateInterval) as? Int ?? 7
        lastModelUpdateCheck = defaults.object(forKey: Key.lastModelUpdateCheck) as? Date
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WiskaKit && swift test --filter SettingsStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(settings): model update interval and last check"
```

---

### Task 4: App — Parakeet card, automatic checks, menu, README

**Files:**
- Modify: `Wiska/AppModel.swift`, `Wiska/Settings/SpeechTab.swift`, `Wiska/MenuContent.swift`, `README.md`

**Interfaces:**
- Consumes: Tasks 1–3.

- [ ] **Step 1: AppModel**

Add a property `let modelUpdates: ModelUpdateChecker` and `@ObservationIgnored private var updateTask: Task<Void, Never>?`. In `init`, after `parakeetStore = store` (and once `settings` exists):

```swift
        modelUpdates = ModelUpdateChecker(store: store, source: HuggingFaceRevisionSource(),
                                          interval: { settings.modelUpdateInterval },
                                          lastCheck: { settings.lastModelUpdateCheck },
                                          setLastCheck: { settings.lastModelUpdateCheck = $0 })
```

In `start()`, after the retention task:

```swift
        // Parakeet model updates: at launch, then hourly; only when due, never downloads.
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, await modelUpdates.checkIfDue() {
                    flash("Speech model update available", for: .seconds(2))
                }
                try? await Task.sleep(for: .seconds(3_600))
            }
        }
```

Add a computed property for the menu: `var modelUpdateAvailable: Bool { if case .updateAvailable = modelUpdates.state { true } else { false } }`.

- [ ] **Step 2: Parakeet card**

`SpeechTab`: pass the model: `ParakeetCard(store: model.parakeetStore, updates: model.modelUpdates, settings: model.settings) { model.parakeetModelBecameReady() }`. In `ParakeetCard` add `let updates: ModelUpdateChecker` and `let settings: SettingsStore`, wrap the existing `HStack` in a `VStack(alignment: .leading, spacing: 8)`, and below it, only when `store.status == .ready`:

```swift
            if store.status == .ready {
                @Bindable var settings = settings
                HStack {
                    Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if case .updateAvailable = updates.state {
                        Button("Download update") { updates.downloadUpdate() }
                    }
                    Button("Check now") { Task { await updates.checkNow() } }
                        .disabled(updates.state == .checking)
                }
                Picker("Check for model updates", selection: $settings.modelUpdateInterval) {
                    ForEach(SettingsStore.modelUpdateIntervals, id: \.self) { days in
                        Text(Self.intervalLabel(days)).tag(days)
                    }
                }
            }
```

with

```swift
    private var updateStatus: String {
        switch updates.state {
        case .checking: "Checking…"
        case .updateAvailable: "Update available"
        case .failed(let message): "Couldn't check: \(message)"
        case .upToDate(let date): "Up to date · checked \(date.formatted(.relative(presentation: .named)))"
        case .idle:
            settings.lastModelUpdateCheck.map { "Up to date · checked \($0.formatted(.relative(presentation: .named)))" }
                ?? "Not checked yet"
        }
    }

    static func intervalLabel(_ days: Int) -> String {
        switch days {
        case 0: "Never"
        case 1: "Every day"
        default: "Every \(days) days"
        }
    }
```

(`SpeechTab.swift` needs `import Preferences` and `import Parakeet` if not already imported.)

- [ ] **Step 3: Menu**

In `MenuContent`, after the `parakeetUnavailable` text:

```swift
        if model.modelUpdateAvailable {
            Button("Speech model update available…") { showSettings() }
        }
```

and move the body of the existing "Settings…" button into `private func showSettings()` used by both buttons.

- [ ] **Step 4: README**

Replace the Privacy paragraph's second sentence with: "Wiska makes no network requests except downloading speech models when you ask for them (Apple's language assets, or the Parakeet model from Hugging Face) and, if Parakeet is installed, a small check every few days whether a newer Parakeet model exists — turn it off with Settings → Speech → Check for model updates → Never."

- [ ] **Step 5: Build, full suite, manual check, commit**

Run: `cd WiskaKit && swift test`, then from the repo root `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build build`
Expected: all tests pass (1 known Parakeet Danish issue); `** BUILD SUCCEEDED **`.

Manual: relaunch; Settings → Speech → Parakeet card shows "Up to date · checked …" (the launch check runs because `lastModelUpdateCheck` is nil), "Check now" works, the picker changes the interval.

```bash
git add Wiska README.md
git commit -m "feat(app): Parakeet update status, Check now and Download update; automatic checks; menu item"
```
