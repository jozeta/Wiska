# Wiska M5 — Rename, Brand, Onboarding & Stats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename SecureWispr to Wiska end-to-end (with data migration), apply the Midnight Aurora brand (icon, menu-bar mark, notch capsule HUD), add a checklist onboarding, and show weekly stats.

**Architecture:** Task 1 performs the mechanical rename (paths, project, package, bundle id) and centralises the data folder in `Core.AppPaths`. Pure, tested units carry the logic: `LegacyMigration` and `OnboardingState` (Preferences), `DictationStats`/`StatsFormatter` (History), `NotchLayout` (HUD). The app target wires them into views: a notch HUD, an onboarding window, stats tiles and a menu line.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, SwiftData, Core Graphics (icon generation script), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-08-wiska-m5-brand-onboarding-design.md`

## Global Constraints

- After Task 1: app target/scheme **Wiska**, project `Wiska.xcodeproj`, sources `Wiska/`, package `WiskaKit` (product `WiskaKit`), bundle id `com.zeta.Wiska`, log subsystem `Wiska`, data folder `~/Library/Application Support/Wiska`.
- Commands after Task 1: package `cd WiskaKit && swift test`; app `xcodebuild -project Wiska.xcodeproj -scheme Wiska -configuration Debug -derivedDataPath build -allowProvisioningUpdates build`; app bundle `build/Build/Products/Debug/Wiska.app`.
- Migration: move `Application Support/SecureWispr` → `Wiska` only if the new folder doesn't exist; copy only missing settings keys from defaults suite `com.zeta.SecureWispr`; runs once (`migratedFromSecureWispr`); never deletes the old defaults.
- Aurora: ink `#0E1116`, panel `#151A22`, teal `#3EE6C1`, violet `#8B6CFF`, danger `#FF9A9A`, textPrimary `#E8ECF2`, textSecondary `#8A93A3`; gradient teal → violet.
- Notch HUD: notched → width = max(content, notchWidth + 40), height = safeTop + content height, top flush with screen top, centred on notch, bottom corner radius 18; plain → content size, top at `visibleFrame.maxY − 6`, all corners 18; window level `mainMenuWindow + 1`; grow/shrink animation 0.18 s.
- Onboarding: auto-open when not completed or any permission missing; Finish requires the 3 permissions only; no automatic permission prompts at launch.
- Stats: last 7 days, `pasted == true` only; time saved = max(0, words ÷ 40 wpm − Σ duration); menu line hidden when no words or history Off/unavailable.
- Never log transcript/record text except `privacy: .private`.

## Review Focus

1. **Both old and new data folders exist** (e.g. Wiska launched once before migration finished) → nothing is moved or overwritten. (Test: Task 2 `keepsBothWhenBothExist`.)
2. **Migration must not run twice** — a user who later clears Wiska's data must not get old data re-imported. (Test: Task 2 `runsOnlyOnce`.)
3. **External display without a notch** → capsule hangs below the menu bar, centred on that screen. (Test: Task 5 `plainScreenHangsBelowMenuBar`.)
4. **History rows from before M5 have no duration** → stats still work (duration 0). (Test: Task 3 `entriesWithoutDurationLoadAsZero` + Task 4 `zeroDurationStillCountsWords`.)
5. **Onboarding closed early with a permission missing** → reopens at next launch; with everything granted and completed → stays closed. (Test: Task 8 `reopensWhenPermissionMissing`.)

---

## File Structure

```
(rename) SecureWispr.xcodeproj → Wiska.xcodeproj; SecureWispr/ → Wiska/; SecureWisprKit/ → WiskaKit/
WiskaKit/Sources/Core/AppPaths.swift               NEW  data folder, log subsystem constants
WiskaKit/Sources/Core/DictationRecord.swift        MOD  duration
WiskaKit/Sources/Preferences/LegacyMigration.swift NEW
WiskaKit/Sources/Preferences/OnboardingState.swift NEW
WiskaKit/Sources/Preferences/SettingsStore.swift   MOD  onboardingCompleted, fnKeyConfirmed, firstDictationDone
WiskaKit/Sources/History/HistoryEntry.swift        MOD  duration
WiskaKit/Sources/History/DictationStats.swift      NEW  stats + menu-line formatter
WiskaKit/Sources/History/HistoryStore.swift        MOD  stats(now:)
WiskaKit/Sources/Dictation/DictationController.swift MOD sample counting → duration
WiskaKit/Sources/HUD/NotchLayout.swift             NEW
WiskaKit/Sources/HUD/AuroraTheme.swift             NEW
WiskaKit/Sources/HUD/HUDView.swift, HUDPanelController.swift, WaveformView.swift  MOD notch capsule
scripts/make-icon.swift                            NEW  generates AppIcon + MenuBarIcon
Wiska/Assets.xcassets/…                            NEW  generated
Wiska/OnboardingView.swift                         NEW
Wiska/AppModel.swift, WiskaApp.swift, MenuContent.swift, HistoryView.swift, Permissions.swift, SettingsView.swift  MOD
```

---

### Task 1: Rename to Wiska

**Files:**
- Rename: `SecureWispr.xcodeproj` → `Wiska.xcodeproj`, `SecureWispr/` → `Wiska/`, `Wiska/SecureWisprApp.swift` → `Wiska/WiskaApp.swift`, `Wiska/SecureWispr.entitlements` → `Wiska/Wiska.entitlements`, `SecureWisprKit/` → `WiskaKit/`
- Modify: `Wiska.xcodeproj/project.pbxproj`, `WiskaKit/Package.swift`, `Wiska/WiskaApp.swift`, `Wiska/MenuContent.swift`, `WiskaKit/Sources/Core/Log.swift`, `WiskaKit/Sources/History/HistoryStore.swift`, `WiskaKit/Sources/Parakeet/ParakeetModelStore.swift`, `WiskaKit/Sources/Preferences/DictionaryStore.swift`
- Create: `WiskaKit/Sources/Core/AppPaths.swift`
- Test: `WiskaKit/Tests/CoreTests/AppPathsTests.swift`

**Interfaces:**
- Produces: `public enum AppPaths { static let name = "Wiska"; static var supportDirectory: URL; static func file(_ name: String) -> URL }`; `Log.subsystem == "Wiska"`.

- [ ] **Step 1: Move files with git (keeps history)**

```bash
git mv SecureWispr.xcodeproj Wiska.xcodeproj
git mv SecureWispr Wiska
git mv Wiska/SecureWisprApp.swift Wiska/WiskaApp.swift
git mv Wiska/SecureWispr.entitlements Wiska/Wiska.entitlements
git mv SecureWisprKit WiskaKit
```

- [ ] **Step 2: Rewrite names in the project and package**

```bash
sed -i '' -e 's/SecureWisprKit/WiskaKit/g' -e 's/SecureWispr/Wiska/g' Wiska.xcodeproj/project.pbxproj
sed -i '' -e 's/SecureWisprKit/WiskaKit/g' WiskaKit/Package.swift
sed -i '' -e 's/struct SecureWisprApp: App/struct WiskaApp: App/' Wiska/WiskaApp.swift
sed -i '' -e 's/Quit SecureWispr/Quit Wiska/' Wiska/MenuContent.swift
grep -c "Wiska" Wiska.xcodeproj/project.pbxproj
grep -n "com.zeta.Wiska\|Wiska listens\|CFBundleDisplayName = Wiska" Wiska.xcodeproj/project.pbxproj | head
```
Expected: counts > 0; bundle id `com.zeta.Wiska`, microphone text "Wiska listens only while you hold the fn key…", display name `Wiska`.

- [ ] **Step 3: Write the failing test**

`WiskaKit/Tests/CoreTests/AppPathsTests.swift`:
```swift
import Foundation
import Testing
@testable import Core

struct AppPathsTests {
    @Test func dataLivesInWiskaFolder() {
        #expect(AppPaths.supportDirectory.lastPathComponent == "Wiska")
        #expect(AppPaths.file("dictionary.json").path.hasSuffix("Application Support/Wiska/dictionary.json"))
    }

    @Test func logSubsystemIsWiska() {
        #expect(Log.subsystem == "Wiska")
    }
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `cd WiskaKit && swift test --filter AppPathsTests`
Expected: compile FAIL — `AppPaths`, `Log.subsystem` not found.

- [ ] **Step 5: Implement and use AppPaths**

`WiskaKit/Sources/Core/AppPaths.swift`:
```swift
import Foundation

/// Where Wiska keeps its data. One place, so a rename never scatters paths again.
public enum AppPaths {
    public static let name = "Wiska"

    public static var supportDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent(name, isDirectory: true)
    }

    public static func file(_ name: String) -> URL {
        supportDirectory.appendingPathComponent(name)
    }
}
```

Replace `WiskaKit/Sources/Core/Log.swift` with:
```swift
import os

public enum Log {
    public static let subsystem = "Wiska"

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
```

In `WiskaKit/Sources/History/HistoryStore.swift` replace the `defaultURL` body with `AppPaths.file("History.store")`.
In `WiskaKit/Sources/Preferences/DictionaryStore.swift` replace the `defaultURL` body with `AppPaths.file("dictionary.json")`.
In `WiskaKit/Sources/Parakeet/ParakeetModelStore.swift` replace
```swift
        URL.applicationSupportDirectory
            .appendingPathComponent("SecureWispr/Models", isDirectory: true)
```
with
```swift
        AppPaths.supportDirectory
            .appendingPathComponent("Models", isDirectory: true)
```

- [ ] **Step 6: Run tests and build**

Run: `cd WiskaKit && swift test 2>&1 | grep -E "error:|✘|Test run with"`
Expected: no `✘`; AppPathsTests 2/2.

Run: `xcodebuild -project Wiska.xcodeproj -scheme Wiska -configuration Debug -derivedDataPath build -allowProvisioningUpdates build 2>&1 | grep -E "error:|\*\* BUILD"`
Expected: `** BUILD SUCCEEDED **`; `codesign -dv build/Build/Products/Debug/Wiska.app 2>&1 | grep Identifier` shows `com.zeta.Wiska`.

- [ ] **Step 7: Commit**

```bash
git add -A Wiska Wiska.xcodeproj WiskaKit SecureWispr SecureWispr.xcodeproj SecureWisprKit
git commit -m "chore: rename SecureWispr to Wiska (project, package, bundle id, paths)"
```

---

### Task 2: Legacy migration

**Files:**
- Create: `WiskaKit/Sources/Preferences/LegacyMigration.swift`
- Test: `WiskaKit/Tests/PreferencesTests/LegacyMigrationTests.swift`

**Interfaces:**
- Produces: `public enum LegacyMigration { static let legacySuite = "com.zeta.SecureWispr"; static let settingsKeys: [String]; struct Outcome: Equatable { movedData: Bool; copiedKeys: [String] }; @discardableResult static func run(applicationSupport: URL = URL.applicationSupportDirectory, defaults: UserDefaults = .standard, legacyDefaults: UserDefaults? = UserDefaults(suiteName: legacySuite)) -> Outcome }`

- [ ] **Step 1: Write the failing tests**

`WiskaKit/Tests/PreferencesTests/LegacyMigrationTests.swift`:
```swift
import Foundation
import Testing
@testable import Preferences

struct LegacyMigrationTests {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent("mig-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: "WiskaMigTests-\(UUID().uuidString)")!
    let legacy = UserDefaults(suiteName: "WiskaMigLegacy-\(UUID().uuidString)")!
    var old: URL { support.appendingPathComponent("SecureWispr") }
    var new: URL { support.appendingPathComponent("Wiska") }

    func makeOld() throws {
        try FileManager.default.createDirectory(at: old.appendingPathComponent("Models"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: old.appendingPathComponent("dictionary.json"))
    }

    func run() -> LegacyMigration.Outcome {
        LegacyMigration.run(applicationSupport: support, defaults: defaults, legacyDefaults: legacy)
    }

    @Test func movesOldDataFolder() throws {
        try makeOld()
        #expect(run().movedData)
        #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("dictionary.json").path))
        #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("Models").path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func keepsBothWhenBothExist() throws {
        try makeOld()
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        #expect(!run().movedData)
        #expect(FileManager.default.fileExists(atPath: old.appendingPathComponent("dictionary.json").path))
        #expect(!FileManager.default.fileExists(atPath: new.appendingPathComponent("dictionary.json").path))
    }

    @Test func copiesOnlyMissingSettings() {
        legacy.set("parakeet", forKey: "engine")
        legacy.set("light", forKey: "cleanupLevel")
        defaults.set("polished", forKey: "cleanupLevel")
        let outcome = run()
        #expect(outcome.copiedKeys == ["engine"])
        #expect(defaults.string(forKey: "engine") == "parakeet")
        #expect(defaults.string(forKey: "cleanupLevel") == "polished")
        #expect(legacy.string(forKey: "engine") == "parakeet")   // never deleted
    }

    @Test func runsOnlyOnce() throws {
        try makeOld()
        _ = run()
        try FileManager.default.removeItem(at: new)                  // user cleared Wiska data
        try makeOld()                                                // old folder reappears
        #expect(run() == LegacyMigration.Outcome(movedData: false, copiedKeys: []))
        #expect(!FileManager.default.fileExists(atPath: new.path))
    }

    @Test func nothingToMigrateIsFine() {
        #expect(run() == LegacyMigration.Outcome(movedData: false, copiedKeys: []))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter LegacyMigrationTests`
Expected: compile FAIL — `LegacyMigration` not found.

- [ ] **Step 3: Implement**

`WiskaKit/Sources/Preferences/LegacyMigration.swift`:
```swift
import Core
import Foundation

/// One-time import of SecureWispr's data and settings into Wiska.
public enum LegacyMigration {
    public static let legacySuite = "com.zeta.SecureWispr"
    public static let legacyFolder = "SecureWispr"
    public static let settingsKeys = [
        "engine", "languageMode", "primaryLanguage", "toggleLanguage",
        "lastDetectedLanguage", "cleanupLevel", "historyRetention",
    ]
    static let doneKey = "migratedFromSecureWispr"
    private static let log = Log.logger("Migration")

    public struct Outcome: Equatable {
        public var movedData: Bool
        public var copiedKeys: [String]
    }

    @discardableResult
    public static func run(applicationSupport: URL = URL.applicationSupportDirectory,
                           defaults: UserDefaults = .standard,
                           legacyDefaults: UserDefaults? = UserDefaults(suiteName: legacySuite)) -> Outcome {
        guard !defaults.bool(forKey: doneKey) else { return Outcome(movedData: false, copiedKeys: []) }
        defer { defaults.set(true, forKey: doneKey) }

        let old = applicationSupport.appendingPathComponent(legacyFolder, isDirectory: true)
        let new = applicationSupport.appendingPathComponent(AppPaths.name, isDirectory: true)
        let fm = FileManager.default
        var moved = false
        if fm.fileExists(atPath: old.path) {
            if fm.fileExists(atPath: new.path) {
                log.notice("both SecureWispr and Wiska data folders exist; leaving both untouched")
            } else {
                do {
                    try fm.moveItem(at: old, to: new)   // a rename: the 469 MB model isn't copied
                    moved = true
                } catch {
                    log.error("could not move SecureWispr data: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        var copied: [String] = []
        if let legacyDefaults {
            for key in settingsKeys where defaults.object(forKey: key) == nil {
                if let value = legacyDefaults.object(forKey: key) {
                    defaults.set(value, forKey: key)
                    copied.append(key)
                }
            }
        }
        log.info("migration: movedData=\(moved, privacy: .public) copiedKeys=\(copied.count, privacy: .public)")
        return Outcome(movedData: moved, copiedKeys: copied)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd WiskaKit && swift test --filter LegacyMigrationTests`
Expected: 5/5 PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(preferences): one-time migration of SecureWispr data and settings"
```

---

### Task 3: Dictation duration

**Files:**
- Modify: `WiskaKit/Sources/Core/DictationRecord.swift`, `WiskaKit/Sources/Dictation/DictationController.swift`, `WiskaKit/Sources/History/HistoryEntry.swift`
- Test: `WiskaKit/Tests/DictationTests/DictationControllerTests.swift`, `WiskaKit/Tests/HistoryTests/HistoryStoreTests.swift`

**Interfaces:**
- Produces: `DictationRecord.duration: TimeInterval` (init parameter `duration: TimeInterval = 0`, last).

- [ ] **Step 1: Write the failing tests**

Append inside `DictationControllerTests`:
```swift
    @Test func recordCarriesSpokenDuration() async {
        let controller = makeController()
        let records = recording(controller)
        controller.handle(en)
        audio.emit(Array(repeating: 0, count: 16_000))
        audio.emit(Array(repeating: 0, count: 8_000))
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(records.value.first?.duration == 1.5)
    }
```

Append inside `HistoryStoreTests`:
```swift
    @Test func durationRoundTrips() {
        var r = record("timed")
        r.duration = 4.25
        store.add(r, retention: .forever)
        #expect(store.items(matching: "").first?.record.duration == 4.25)
    }

    @Test func entriesWithoutDurationLoadAsZero() {
        store.add(record("old"), retention: .forever)          // record() leaves duration at default
        #expect(store.items(matching: "").first?.record.duration == 0)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter "recordCarriesSpokenDuration|durationRoundTrips"`
Expected: compile FAIL — `duration` not a member.

- [ ] **Step 3: Implement**

In `WiskaKit/Sources/Core/DictationRecord.swift`, add the property and init parameter:
```swift
    /// Seconds of audio captured for this dictation.
    public var duration: TimeInterval
```
change the initializer signature to end with `pasted: Bool, duration: TimeInterval = 0)` and add `self.duration = duration` to its body.

In `WiskaKit/Sources/History/HistoryEntry.swift`:
- add `var duration: Double = 0`
- in `init(_ record:)` add `duration = record.duration`
- in `var record` pass `pasted: pasted, duration: duration`

In `WiskaKit/Sources/Dictation/DictationController.swift`:
- add `private var capturedSamples = 0` next to `context`
- in `startListening`, right after `state = .listening`, add `capturedSamples = 0`
- in the session task loop replace `for await chunk in capture.chunks { session.append(chunk) }` with
```swift
            for await chunk in capture.chunks {
                session.append(chunk)
                self?.capturedSamples += chunk.samples.count
            }
```
- in `record(_:_:pasted:)` add the argument `duration: Double(capturedSamples) / AudioChunk.sampleRate`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd WiskaKit && swift test --filter "DictationControllerTests|HistoryStoreTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat: record spoken duration with each dictation"
```

---

### Task 4: Stats

**Files:**
- Create: `WiskaKit/Sources/History/DictationStats.swift`
- Modify: `WiskaKit/Sources/History/HistoryStore.swift`
- Test: `WiskaKit/Tests/HistoryTests/DictationStatsTests.swift`

**Interfaces:**
- Produces:
  - `public struct DictationStats: Equatable, Sendable { words: Int; timeSaved: TimeInterval; swedishShare: Double; englishShare: Double; static let typingWordsPerMinute = 40.0; static func compute(_ records: [DictationRecord], now: Date, window: TimeInterval = 7 * 86_400) -> DictationStats }`
  - `public enum StatsFormatter { static func menuLine(_ stats: DictationStats, locale: Locale = .current) -> String?; static func savedText(_ seconds: TimeInterval) -> String }`
  - `HistoryStore.stats(now: Date = Date()) -> DictationStats`

- [ ] **Step 1: Write the failing tests**

`WiskaKit/Tests/HistoryTests/DictationStatsTests.swift`:
```swift
import Core
import Foundation
import Testing
@testable import History

struct DictationStatsTests {
    let now = Date(timeIntervalSince1970: 2_000_000)

    func r(_ words: Int, _ language: Language?, ageDays: Double = 0, duration: TimeInterval = 0,
           pasted: Bool = true) -> DictationRecord {
        DictationRecord(date: now.addingTimeInterval(-ageDays * 86_400), appBundleID: nil, language: language,
                        engine: .apple, rawText: "", finalText: Array(repeating: "ord", count: words).joined(separator: " "),
                        pasted: pasted, duration: duration)
    }

    @Test func countsWordsAndTimeSaved() {
        // 80 words = 2 min to type; spoken in 30 s → 90 s saved.
        let stats = DictationStats.compute([r(80, .english, duration: 30)], now: now)
        #expect(stats.words == 80)
        #expect(stats.timeSaved == 90)
    }

    @Test func timeSavedNeverNegative() {
        #expect(DictationStats.compute([r(4, .english, duration: 60)], now: now).timeSaved == 0)
    }

    @Test func zeroDurationStillCountsWords() {
        #expect(DictationStats.compute([r(40, nil)], now: now).timeSaved == 60)
    }

    @Test func languageShares() {
        let stats = DictationStats.compute([r(60, .swedish), r(40, .english), r(50, nil)], now: now)
        #expect(stats.swedishShare == 0.6)
        #expect(stats.englishShare == 0.4)
    }

    @Test func onlyLastSevenDaysAndPastedCount() {
        let stats = DictationStats.compute([r(10, .english), r(20, .english, ageDays: 8),
                                            r(30, .english, pasted: false)], now: now)
        #expect(stats.words == 10)
    }

    @Test func menuLineFormatting() {
        let stats = DictationStats(words: 2_340, timeSaved: 48 * 60 + 10, swedishShare: 0.6, englishShare: 0.4)
        #expect(StatsFormatter.menuLine(stats, locale: Locale(identifier: "en_US"))
                == "This week: 2,340 words · 48 min saved")
        #expect(StatsFormatter.savedText(30) == "< 1 min")
    }

    @Test func menuLineHiddenWhenNoWords() {
        #expect(StatsFormatter.menuLine(DictationStats(words: 0, timeSaved: 0, swedishShare: 0, englishShare: 0)) == nil)
    }
}
```

Append inside `HistoryStoreTests`:
```swift
    @Test func storeComputesStats() {
        var r = record("ett två tre fyra")
        r.duration = 1
        store.add(r, retention: .forever)
        #expect(store.stats(now: now).words == 4)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter "DictationStatsTests|storeComputesStats"`
Expected: compile FAIL — `DictationStats` not found.

- [ ] **Step 3: Implement**

`WiskaKit/Sources/History/DictationStats.swift`:
```swift
import Core
import Foundation

/// Weekly numbers computed from history; nothing extra is stored.
public struct DictationStats: Equatable, Sendable {
    public static let typingWordsPerMinute = 40.0

    public var words: Int
    public var timeSaved: TimeInterval
    public var swedishShare: Double
    public var englishShare: Double

    public init(words: Int, timeSaved: TimeInterval, swedishShare: Double, englishShare: Double) {
        self.words = words
        self.timeSaved = timeSaved
        self.swedishShare = swedishShare
        self.englishShare = englishShare
    }

    public static func compute(_ records: [DictationRecord], now: Date,
                               window: TimeInterval = 7 * 86_400) -> DictationStats {
        let recent = records.filter { $0.pasted && $0.date >= now.addingTimeInterval(-window) }
        func count(_ r: DictationRecord) -> Int { r.finalText.split(whereSeparator: \.isWhitespace).count }
        let words = recent.reduce(0) { $0 + count($1) }
        let spoken = recent.reduce(0) { $0 + $1.duration }
        let typing = Double(words) / typingWordsPerMinute * 60
        let swedish = recent.filter { $0.language == .swedish }.reduce(0) { $0 + count($1) }
        let english = recent.filter { $0.language == .english }.reduce(0) { $0 + count($1) }
        let known = swedish + english
        return DictationStats(words: words, timeSaved: max(0, typing - spoken),
                              swedishShare: known == 0 ? 0 : Double(swedish) / Double(known),
                              englishShare: known == 0 ? 0 : Double(english) / Double(known))
    }
}

public enum StatsFormatter {
    /// "This week: 2,340 words · 48 min saved", or nil when there's nothing to show.
    public static func menuLine(_ stats: DictationStats, locale: Locale = .current) -> String? {
        guard stats.words > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let words = formatter.string(from: NSNumber(value: stats.words)) ?? "\(stats.words)"
        return "This week: \(words) words · \(savedText(stats.timeSaved)) saved"
    }

    public static func savedText(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "< 1 min" : "\(Int((seconds / 60).rounded())) min"
    }
}
```

In `WiskaKit/Sources/History/HistoryStore.swift` add:
```swift
    public func stats(now: Date = Date()) -> DictationStats {
        DictationStats.compute(items(matching: "").map(\.record), now: now)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd WiskaKit && swift test --filter "DictationStatsTests|HistoryStoreTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(history): weekly dictation stats and menu-line formatting"
```

---

### Task 5: Notch layout

**Files:**
- Create: `WiskaKit/Sources/HUD/NotchLayout.swift`
- Modify: `WiskaKit/Package.swift` (add `HUDTests`)
- Test: `WiskaKit/Tests/HUDTests/NotchLayoutTests.swift`

**Interfaces:**
- Produces: `public enum NotchLayout { struct Screen { frame, visibleFrame: CGRect; safeTop: CGFloat; auxLeft, auxRight: CGRect? }; struct Placement: Equatable { frame: CGRect; contentInsetTop: CGFloat; hasNotch: Bool }; static let notchPadding: CGFloat = 40; static let menuBarGap: CGFloat = 6; static func placement(on: Screen, content: CGSize) -> Placement }`

- [ ] **Step 1: Add the test target**

In `WiskaKit/Package.swift` add:
```swift
        .testTarget(name: "HUDTests", dependencies: ["HUD"]),
```

- [ ] **Step 2: Write the failing tests**

`WiskaKit/Tests/HUDTests/NotchLayoutTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import HUD

struct NotchLayoutTests {
    // Measured on the dev MacBook (2026-10-08).
    let macBook = NotchLayout.Screen(
        frame: CGRect(x: 0, y: 0, width: 2704, height: 1756),
        visibleFrame: CGRect(x: 0, y: 0, width: 2704, height: 1698),
        safeTop: 57,
        auxLeft: CGRect(x: 0, y: 1699, width: 1186.5, height: 57),
        auxRight: CGRect(x: 1517.5, y: 1699, width: 1186.5, height: 57))

    let external = NotchLayout.Screen(
        frame: CGRect(x: 2704, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 2704, y: 0, width: 1920, height: 1055),
        safeTop: 0, auxLeft: nil, auxRight: nil)

    @Test func notchedScreenGrowsOutOfTheNotch() {
        let p = NotchLayout.placement(on: macBook, content: CGSize(width: 240, height: 44))
        #expect(p.hasNotch)
        #expect(p.frame.width == 371)                 // notch 331 + 40 > content 240
        #expect(p.frame.height == 101)                // 57 + 44
        #expect(p.frame.maxY == 1756)                 // flush with the top edge
        #expect(p.frame.midX == 1352)                 // centred on the notch
        #expect(p.contentInsetTop == 57)
    }

    @Test func wideContentWidensTheCapsule() {
        let p = NotchLayout.placement(on: macBook, content: CGSize(width: 420, height: 44))
        #expect(p.frame.width == 420)
    }

    @Test func plainScreenHangsBelowMenuBar() {
        let p = NotchLayout.placement(on: external, content: CGSize(width: 240, height: 44))
        #expect(!p.hasNotch)
        #expect(p.frame == CGRect(x: 2704 + 840, y: 1055 - 6 - 44, width: 240, height: 44))
        #expect(p.contentInsetTop == 0)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter NotchLayoutTests`
Expected: compile FAIL — `NotchLayout` not found.

- [ ] **Step 4: Implement**

`WiskaKit/Sources/HUD/NotchLayout.swift`:
```swift
import CoreGraphics

/// Where the capsule goes: out of the notch when there is one, under the menu bar otherwise.
public enum NotchLayout {
    public static let notchPadding: CGFloat = 40
    public static let menuBarGap: CGFloat = 6

    public struct Screen {
        public var frame: CGRect
        public var visibleFrame: CGRect
        public var safeTop: CGFloat
        public var auxLeft: CGRect?
        public var auxRight: CGRect?

        public init(frame: CGRect, visibleFrame: CGRect, safeTop: CGFloat, auxLeft: CGRect?, auxRight: CGRect?) {
            self.frame = frame
            self.visibleFrame = visibleFrame
            self.safeTop = safeTop
            self.auxLeft = auxLeft
            self.auxRight = auxRight
        }
    }

    public struct Placement: Equatable {
        public var frame: CGRect
        /// Height reserved at the top for the notch itself.
        public var contentInsetTop: CGFloat
        public var hasNotch: Bool
    }

    public static func placement(on screen: Screen, content: CGSize) -> Placement {
        if screen.safeTop > 0, let left = screen.auxLeft, let right = screen.auxRight, right.minX > left.maxX {
            let notchWidth = right.minX - left.maxX
            let width = max(content.width, notchWidth + notchPadding)
            let height = screen.safeTop + content.height
            let midX = (left.maxX + right.minX) / 2
            return Placement(frame: CGRect(x: midX - width / 2, y: screen.frame.maxY - height,
                                           width: width, height: height),
                             contentInsetTop: screen.safeTop, hasNotch: true)
        }
        let frame = CGRect(x: screen.frame.midX - content.width / 2,
                           y: screen.visibleFrame.maxY - menuBarGap - content.height,
                           width: content.width, height: content.height)
        return Placement(frame: frame, contentInsetTop: 0, hasNotch: false)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd WiskaKit && swift test --filter NotchLayoutTests`
Expected: 3/3 PASS.

- [ ] **Step 6: Commit**

```bash
git add WiskaKit
git commit -m "feat(hud): notch capsule placement"
```

---

### Task 6: Aurora theme + notch capsule HUD

**Files:**
- Create: `WiskaKit/Sources/HUD/AuroraTheme.swift`
- Modify: `WiskaKit/Sources/HUD/HUDView.swift`, `WiskaKit/Sources/HUD/WaveformView.swift`, `WiskaKit/Sources/HUD/HUDPanelController.swift`

**Interfaces:**
- Consumes: `NotchLayout`, `HUDContent`.
- Produces: `public enum AuroraTheme { static let ink, panel, teal, violet, danger, textPrimary, textSecondary: Color; static var gradient: LinearGradient }`; `HUDPanelController` public API unchanged (`init()`, `show(_:)`).

- [ ] **Step 1: Theme**

`WiskaKit/Sources/HUD/AuroraTheme.swift`:
```swift
import SwiftUI

/// Wiska's Midnight Aurora palette.
public enum AuroraTheme {
    public static let ink = Color(hex: 0x0E1116)
    public static let panel = Color(hex: 0x151A22)
    public static let teal = Color(hex: 0x3EE6C1)
    public static let violet = Color(hex: 0x8B6CFF)
    public static let danger = Color(hex: 0xFF9A9A)
    public static let textPrimary = Color(hex: 0xE8ECF2)
    public static let textSecondary = Color(hex: 0x8A93A3)

    public static var gradient: LinearGradient {
        LinearGradient(colors: [teal, violet], startPoint: .leading, endPoint: .trailing)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
```

- [ ] **Step 2: Gradient waveform**

Replace `WiskaKit/Sources/HUD/WaveformView.swift` with:
```swift
import SwiftUI

/// Bars for the most recent loudness samples; newest on the right, coloured teal → violet.
struct WaveformView: View {
    static let barCount = 20
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(color(at: index))
                    .frame(width: 3, height: 4 + CGFloat(level(at: index)) * 20)
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.08), value: levels)
    }

    private func level(at index: Int) -> Float {
        let offset = Self.barCount - levels.count
        return index >= offset ? levels[index - offset] : 0
    }

    private func color(at index: Int) -> Color {
        let t = Double(index) / Double(Self.barCount - 1)
        return Color(red: (0x3E + (0x8B - 0x3E) * t) / 255,
                     green: (0xE6 + (0x6C - 0xE6) * t) / 255,
                     blue: (0xC1 + (0xFF - 0xC1) * t) / 255)
    }
}
```

- [ ] **Step 3: Capsule view**

Replace `WiskaKit/Sources/HUD/HUDView.swift` with:
```swift
import SwiftUI

struct HUDView: View {
    let model: HUDModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.insetTop)       // the notch itself
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black, in: UnevenRoundedRectangle(
            topLeadingRadius: model.hasNotch ? 0 : 18, bottomLeadingRadius: 18,
            bottomTrailingRadius: 18, topTrailingRadius: model.hasNotch ? 0 : 18))
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AuroraTheme.textPrimary)
    }

    @ViewBuilder private var content: some View {
        switch model.content {
        case .hidden:
            EmptyView()
        case .listening(let levels, let badge):
            HStack(spacing: 10) {
                Text(badge)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .foregroundStyle(AuroraTheme.teal)
                    .background(AuroraTheme.teal.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
                WaveformView(levels: levels)
            }
        case .working(let text):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(AuroraTheme.teal)
                Text(text)
            }
        case .message(let text):
            Text(text).foregroundStyle(model.isError ? AuroraTheme.danger : AuroraTheme.textPrimary)
        }
    }
}
```

In `WiskaKit/Sources/HUD/HUDContent.swift` replace the `HUDModel` class with:
```swift
@MainActor @Observable
final class HUDModel {
    var content: HUDContent = .hidden
    var insetTop: CGFloat = 0
    var hasNotch = false
    /// Messages that are failures render in the danger colour.
    var isError = false
}
```
and add `import CoreGraphics` at the top of that file.

- [ ] **Step 4: Panel controller**

Replace `WiskaKit/Sources/HUD/HUDPanelController.swift` with:
```swift
import AppKit
import SwiftUI

/// The notch capsule: a click-through panel above the menu bar that never takes focus.
@MainActor
public final class HUDPanelController {
    static let contentSize = CGSize(width: 260, height: 44)
    static let animation: TimeInterval = 0.18
    /// Failure texts shown in the danger colour (matches DictationFailure messages).
    static let errorMessages: Set<String> = [
        "No speech detected", "Can't type here", "Microphone unavailable",
        "Couldn't transcribe", "Couldn't insert text",
    ]

    private let model = HUDModel()
    private let panel: NSPanel
    private var placement: NotchLayout.Placement?

    public init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
    }

    public func show(_ content: HUDContent) {
        guard model.content != content else { return }
        let wasHidden = model.content == .hidden
        if content == .hidden {
            collapse()
            return
        }
        if case .message(let text) = content { model.isError = Self.errorMessages.contains(text) }
        else { model.isError = false }
        model.content = content
        if wasHidden { expand() }
    }

    private func expand() {
        guard let screen = activeScreen() else { return }
        let placement = NotchLayout.placement(on: NotchLayout.Screen(
            frame: screen.frame, visibleFrame: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
            auxLeft: screen.auxiliaryTopLeftArea, auxRight: screen.auxiliaryTopRightArea),
            content: Self.contentSize)
        self.placement = placement
        model.insetTop = placement.contentInsetTop
        model.hasNotch = placement.hasNotch
        var start = placement.frame
        start.origin.y = placement.frame.maxY - placement.contentInsetTop - 1
        start.size.height = placement.contentInsetTop + 1
        panel.setFrame(start, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animation
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(placement.frame, display: true)
        }
    }

    private func collapse() {
        guard let placement else {
            model.content = .hidden
            panel.orderOut(nil)
            return
        }
        var end = placement.frame
        end.origin.y = placement.frame.maxY - placement.contentInsetTop - 1
        end.size.height = placement.contentInsetTop + 1
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.animation
            panel.animator().setFrame(end, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.content == .hidden else { return }
                self.panel.orderOut(nil)
            }
        })
        model.content = .hidden
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
```

- [ ] **Step 5: Build and test**

Run: `cd WiskaKit && swift build 2>&1 | grep -E "error|Build complete" && swift test 2>&1 | grep -E "error:|✘|Test run with"`
Expected: `Build complete!`; no `✘`.

- [ ] **Step 6: Commit**

```bash
git add WiskaKit
git commit -m "feat(hud): Midnight Aurora notch capsule"
```

---

### Task 7: App icon and menu-bar mark

**Files:**
- Create: `scripts/make-icon.swift`, generated `Wiska/Assets.xcassets/**`
- Modify: `Wiska.xcodeproj/project.pbxproj` (AppIcon build setting), `Wiska/WiskaApp.swift` (menu-bar image)

**Interfaces:**
- Produces: asset `AppIcon` (app icon), image `MenuBarIcon` (template).

- [ ] **Step 1: Icon generator**

`scripts/make-icon.swift`:
```swift
// Generates Wiska's app icon and menu-bar mark (Midnight Aurora).
// Usage: swift scripts/make-icon.swift Wiska/Assets.xcassets
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let teal = CGColor(srgbRed: 0x3E / 255, green: 0xE6 / 255, blue: 0xC1 / 255, alpha: 1)
let violet = CGColor(srgbRed: 0x8B / 255, green: 0x6C / 255, blue: 0xFF / 255, alpha: 1)
let bars: [CGFloat] = [10, 26, 42, 22, 8]          // heights in a 50-unit box

func png(_ size: Int, to url: URL, draw: (CGContext, CGFloat) -> Void) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx, CGFloat(size))
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

func drawBars(_ ctx: CGContext, in rect: CGRect, gradient: Bool, color: CGColor = .black) {
    let unit = rect.width / 50
    let width = 6 * unit, gap = (rect.width - 5 * width) / 6
    for (i, h) in bars.enumerated() {
        let height = h * unit
        let bar = CGRect(x: rect.minX + gap + CGFloat(i) * (width + gap), y: rect.midY - height / 2,
                         width: width, height: height)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
        ctx.clip()
        if gradient {
            let g = CGGradient(colorsSpace: nil, colors: [teal, violet] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
        } else {
            ctx.setFillColor(color)
            ctx.fill(bar)
        }
        ctx.restoreGState()
    }
}

func appIcon(_ ctx: CGContext, _ s: CGFloat) {
    let body = CGRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let path = CGPath(roundedRect: body, cornerWidth: body.width * 0.2237, cornerHeight: body.width * 0.2237, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [CGColor(srgbRed: 0x1E / 255, green: 0x26 / 255, blue: 0x33 / 255, alpha: 1),
                                                   CGColor(srgbRed: 0x0B / 255, green: 0x0E / 255, blue: 0x13 / 255, alpha: 1)] as CFArray,
                        locations: [0, 1])!
    ctx.drawRadialGradient(bg, startCenter: CGPoint(x: body.minX + body.width * 0.3, y: body.maxY - body.height * 0.2),
                           startRadius: 0, endCenter: CGPoint(x: body.midX, y: body.midY), endRadius: body.width * 0.75,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    drawBars(ctx, in: body.insetBy(dx: body.width * 0.18, dy: body.height * 0.18), gradient: true)
}

// AppIcon.appiconset
let iconSet = out.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        png(points * scale, to: iconSet.appendingPathComponent(name), draw: appIcon)
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
try JSONSerialization.data(withJSONObject: ["images": images, "info": ["version": 1, "author": "xcode"]],
                           options: [.prettyPrinted]).write(to: iconSet.appendingPathComponent("Contents.json"))

// MenuBarIcon.imageset (template)
let menuSet = out.appendingPathComponent("MenuBarIcon.imageset")
try FileManager.default.createDirectory(at: menuSet, withIntermediateDirectories: true)
for scale in [1, 2] {
    png(18 * scale, to: menuSet.appendingPathComponent("menubar@\(scale)x.png")) { ctx, s in
        drawBars(ctx, in: CGRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.05, dy: s * 0.05), gradient: false)
    }
}
try JSONSerialization.data(withJSONObject: [
    "images": [["idiom": "universal", "scale": "1x", "filename": "menubar@1x.png"],
               ["idiom": "universal", "scale": "2x", "filename": "menubar@2x.png"]],
    "info": ["version": 1, "author": "xcode"],
    "properties": ["template-rendering-intent": "template"],
], options: [.prettyPrinted]).write(to: menuSet.appendingPathComponent("Contents.json"))

try JSONSerialization.data(withJSONObject: ["info": ["version": 1, "author": "xcode"]], options: [.prettyPrinted])
    .write(to: out.appendingPathComponent("Contents.json"))
print("wrote \(out.path)")
```

- [ ] **Step 2: Generate assets**

Run: `swift scripts/make-icon.swift Wiska/Assets.xcassets && ls Wiska/Assets.xcassets/AppIcon.appiconset | wc -l`
Expected: `wrote …/Wiska/Assets.xcassets`; 11 files (10 PNGs + Contents.json).

- [ ] **Step 3: Point the target at the icon**

```bash
sed -i '' 's/CODE_SIGN_STYLE = Automatic; CODE_SIGN_ENTITLEMENTS/ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; CODE_SIGN_STYLE = Automatic; CODE_SIGN_ENTITLEMENTS/g' Wiska.xcodeproj/project.pbxproj
grep -c "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon" Wiska.xcodeproj/project.pbxproj
```
Expected: `2` (Debug and Release target configurations).

- [ ] **Step 4: Menu-bar mark**

In `Wiska/WiskaApp.swift` replace the MenuBarExtra label
```swift
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
```
with
```swift
        } label: {
            if model.menuBarSymbol == "waveform" {
                Image("MenuBarIcon")
            } else {
                Image(systemName: model.menuBarSymbol)
            }
        }
```

- [ ] **Step 5: Build and verify the icon is bundled**

Run: `xcodebuild -project Wiska.xcodeproj -scheme Wiska -configuration Debug -derivedDataPath build -allowProvisioningUpdates build 2>&1 | grep -E "error:|\*\* BUILD" && ls build/Build/Products/Debug/Wiska.app/Contents/Resources | grep -E "AppIcon|Assets.car"`
Expected: `** BUILD SUCCEEDED **`; `AppIcon.icns` and `Assets.car` listed.

- [ ] **Step 6: Commit**

```bash
git add scripts Wiska Wiska.xcodeproj
git commit -m "feat(brand): Midnight Aurora app icon and menu-bar mark"
```

---

### Task 8: Onboarding state + flags

**Files:**
- Create: `WiskaKit/Sources/Preferences/OnboardingState.swift`
- Modify: `WiskaKit/Sources/Preferences/SettingsStore.swift`
- Test: `WiskaKit/Tests/PreferencesTests/OnboardingStateTests.swift`, `WiskaKit/Tests/PreferencesTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces:
  - `public enum OnboardingStep: String, CaseIterable, Identifiable { case microphone, inputMonitoring, accessibility, fnKey, tryIt; var title: String; var reason: String; var isRequired: Bool }`
  - `public struct OnboardingState: Equatable { microphone, inputMonitoring, accessibility, fnKeyConfirmed, firstDictationDone: Bool; func isDone(_ step: OnboardingStep) -> Bool; var canFinish: Bool; func shouldOpenAtLaunch(completed: Bool) -> Bool }`
  - `SettingsStore.onboardingCompleted`, `.fnKeyConfirmed`, `.firstDictationDone: Bool` (default false; keys of the same names)

- [ ] **Step 1: Write the failing tests**

`WiskaKit/Tests/PreferencesTests/OnboardingStateTests.swift`:
```swift
import Testing
@testable import Preferences

struct OnboardingStateTests {
    let allGranted = OnboardingState(microphone: true, inputMonitoring: true, accessibility: true,
                                     fnKeyConfirmed: false, firstDictationDone: false)

    @Test func finishNeedsOnlyThePermissions() {
        #expect(allGranted.canFinish)
        var missing = allGranted
        missing.accessibility = false
        #expect(!missing.canFinish)
    }

    @Test func stepStatuses() {
        var state = allGranted
        state.fnKeyConfirmed = true
        #expect(state.isDone(.microphone))
        #expect(state.isDone(.fnKey))
        #expect(!state.isDone(.tryIt))
        #expect(!OnboardingStep.tryIt.isRequired && OnboardingStep.accessibility.isRequired)
    }

    @Test func opensOnFirstLaunch() {
        #expect(allGranted.shouldOpenAtLaunch(completed: false))
    }

    @Test func reopensWhenPermissionMissing() {
        var state = allGranted
        state.inputMonitoring = false
        #expect(state.shouldOpenAtLaunch(completed: true))
        #expect(!allGranted.shouldOpenAtLaunch(completed: true))
    }
}
```

Append inside `SettingsStoreTests`:
```swift
    @Test func onboardingFlagsDefaultFalseAndPersist() {
        let store = SettingsStore(defaults: defaults)
        #expect(!store.onboardingCompleted && !store.fnKeyConfirmed && !store.firstDictationDone)
        store.onboardingCompleted = true
        store.fnKeyConfirmed = true
        store.firstDictationDone = true
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.onboardingCompleted && reloaded.fnKeyConfirmed && reloaded.firstDictationDone)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter "OnboardingStateTests|onboardingFlags"`
Expected: compile FAIL — `OnboardingState` / flags not found.

- [ ] **Step 3: Implement**

`WiskaKit/Sources/Preferences/OnboardingState.swift`:
```swift
/// The first-run checklist.
public enum OnboardingStep: String, CaseIterable, Identifiable, Sendable {
    case microphone, inputMonitoring, accessibility, fnKey, tryIt

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .microphone: "Microphone"
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        case .fnKey: "🌐 key → “Do Nothing”"
        case .tryIt: "Try it"
        }
    }

    public var reason: String {
        switch self {
        case .microphone: "to hear you — only while you hold fn"
        case .inputMonitoring: "to notice the fn key"
        case .accessibility: "to paste where you type"
        case .fnKey: "so holding fn doesn't open emoji or switch input"
        case .tryIt: "hold fn, say hi, release"
        }
    }

    public var isRequired: Bool {
        switch self {
        case .microphone, .inputMonitoring, .accessibility: true
        case .fnKey, .tryIt: false
        }
    }
}

public struct OnboardingState: Equatable, Sendable {
    public var microphone: Bool
    public var inputMonitoring: Bool
    public var accessibility: Bool
    public var fnKeyConfirmed: Bool
    public var firstDictationDone: Bool

    public init(microphone: Bool, inputMonitoring: Bool, accessibility: Bool,
                fnKeyConfirmed: Bool, firstDictationDone: Bool) {
        self.microphone = microphone
        self.inputMonitoring = inputMonitoring
        self.accessibility = accessibility
        self.fnKeyConfirmed = fnKeyConfirmed
        self.firstDictationDone = firstDictationDone
    }

    public func isDone(_ step: OnboardingStep) -> Bool {
        switch step {
        case .microphone: microphone
        case .inputMonitoring: inputMonitoring
        case .accessibility: accessibility
        case .fnKey: fnKeyConfirmed
        case .tryIt: firstDictationDone
        }
    }

    /// The three permissions are required; the 🌐 key and test dictation are recommended.
    public var canFinish: Bool {
        OnboardingStep.allCases.filter(\.isRequired).allSatisfy(isDone)
    }

    public func shouldOpenAtLaunch(completed: Bool) -> Bool {
        !completed || !canFinish
    }
}
```

In `WiskaKit/Sources/Preferences/SettingsStore.swift`:
- `Key`: add `static let onboardingCompleted = "onboardingCompleted"`, `static let fnKeyConfirmed = "fnKeyConfirmed"`, `static let firstDictationDone = "firstDictationDone"`
- properties:
```swift
    public var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) } }
    public var fnKeyConfirmed: Bool { didSet { defaults.set(fnKeyConfirmed, forKey: Key.fnKeyConfirmed) } }
    public var firstDictationDone: Bool { didSet { defaults.set(firstDictationDone, forKey: Key.firstDictationDone) } }
```
- `init`:
```swift
        onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted)
        fnKeyConfirmed = defaults.bool(forKey: Key.fnKeyConfirmed)
        firstDictationDone = defaults.bool(forKey: Key.firstDictationDone)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd WiskaKit && swift test --filter "OnboardingStateTests|SettingsStoreTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(preferences): onboarding checklist state and flags"
```

---

### Task 9: App wiring — migration, onboarding window, stats, theme

**Files:**
- Create: `Wiska/OnboardingView.swift`
- Modify: `Wiska/AppModel.swift`, `Wiska/WiskaApp.swift`, `Wiska/MenuContent.swift`, `Wiska/HistoryView.swift`, `Wiska/Permissions.swift`, `Wiska/SpellCheckerLexicon.swift`

**Interfaces:**
- Consumes: `LegacyMigration.run()`, `OnboardingState`, `OnboardingStep`, `SettingsStore` flags, `HistoryStore.stats`, `StatsFormatter`, `DictationStats`, `AuroraTheme`.
- Produces: `AppModel.onboarding: OnboardingState`, `AppModel.statsLine: String?`, windows `onboarding` / `history`.

- [ ] **Step 1: Permissions — one action per row**

Append inside `enum Permission` in `Wiska/Permissions.swift`:
```swift
    /// Prompt the first time; afterwards (or when the prompt can't show) open the right pane.
    @MainActor func requestOrOpenSettings() {
        switch self {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { request() } else { openSettings() }
        case .inputMonitoring:
            if !CGRequestListenEventAccess() { openSettings() }
        case .accessibility:
            request()
            openSettings()
        }
    }
```

- [ ] **Step 2: AppModel**

In `Wiska/AppModel.swift`:
- as the **first line of `init`** add:
```swift
        LegacyMigration.run()   // before any store touches the data folder
```
- in `start()`, **delete** the loop
```swift
        for permission in Permission.allCases where !permission.isGranted {
            permission.request()
        }
```
  and insert `refreshPermissions()` as the first line of `start()` (so launch-time decisions see real permission state).
- in the `controller.onDictationFinished` closure add, before storing:
```swift
            if record.pasted && !settings.firstDictationDone { settings.firstDictationDone = true }
```
- add:
```swift
    var onboarding: OnboardingState {
        OnboardingState(microphone: !missingPermissions.contains(.microphone),
                        inputMonitoring: !missingPermissions.contains(.inputMonitoring),
                        accessibility: !missingPermissions.contains(.accessibility),
                        fnKeyConfirmed: settings.fnKeyConfirmed,
                        firstDictationDone: settings.firstDictationDone)
    }

    var shouldShowOnboardingAtLaunch: Bool {
        onboarding.shouldOpenAtLaunch(completed: settings.onboardingCompleted)
    }

    /// "This week: … words · … saved", nil when there's nothing to show.
    var statsLine: String? {
        guard settings.historyRetention != .off, let history else { return nil }
        _ = history.revision
        return StatsFormatter.menuLine(history.stats())
    }
```

- [ ] **Step 3: Onboarding window**

`Wiska/OnboardingView.swift`:
```swift
import AppKit
import HUD
import Preferences
import SwiftUI

struct OnboardingView: View {
    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var settings = model.settings
        let state = model.onboarding
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text("Wiska").foregroundStyle(AuroraTheme.gradient)
                Text("setup")
            }
            .font(.system(size: 26, weight: .bold))
            Text("A few quick steps. Your voice never leaves this Mac.")
                .foregroundStyle(.secondary)

            ForEach(OnboardingStep.allCases) { step in
                HStack(spacing: 12) {
                    Image(systemName: state.isDone(step) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(state.isDone(step) ? AuroraTheme.teal : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).fontWeight(.semibold)
                        Text(step.reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    action(for: step, done: state.isDone(step), settings: settings)
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Text(state.canFinish ? "You're ready — hold fn anywhere to dictate."
                                     : "Microphone, Input Monitoring and Accessibility are required.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Finish") {
                    settings.onboardingCompleted = true
                    dismissWindow(id: OnboardingWindow.id)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canFinish)
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    @ViewBuilder
    private func action(for step: OnboardingStep, done: Bool, settings: SettingsStore) -> some View {
        switch step {
        case .microphone, .inputMonitoring, .accessibility:
            if !done {
                Button("Allow…") { permission(for: step).requestOrOpenSettings() }
            }
        case .fnKey:
            HStack {
                Button("Open Keyboard Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                }
                Toggle("Done", isOn: Binding(get: { settings.fnKeyConfirmed },
                                             set: { settings.fnKeyConfirmed = $0 }))
                    .toggleStyle(.checkbox)
            }
        case .tryIt:
            EmptyView()
        }
    }

    private func permission(for step: OnboardingStep) -> Permission {
        switch step {
        case .inputMonitoring: .inputMonitoring
        case .accessibility: .accessibility
        default: .microphone
        }
    }
}
```

In `Wiska/SpellCheckerLexicon.swift` add after `enum HistoryWindow { … }`:
```swift
/// The first-run checklist window, opened in front like Settings and History.
@MainActor
enum OnboardingWindow {
    static let id = "onboarding"
    static let title = "Welcome to Wiska"

    static func open(_ openWindow: OpenWindowAction) {
        NSApp.activate()
        openWindow(id: id)
        DispatchQueue.main.async {
            NSApp.windows.first { $0.title == title }?.orderFrontRegardless()
        }
    }
}
```

- [ ] **Step 4: Scenes and menu**

In `Wiska/WiskaApp.swift`:
- add a scene after the History window:
```swift
        Window(OnboardingWindow.title, id: OnboardingWindow.id) {
            OnboardingView(model: model)
        }
        .windowResizability(.contentSize)
```
- open it at launch from the menu-bar label (the label exists from launch and has the environment): wrap the label content so it reads
```swift
        } label: {
            MenuBarLabel(model: model)
        }
```
and add at the end of the file:
```swift
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.menuBarSymbol == "waveform" {
                Image("MenuBarIcon")
            } else {
                Image(systemName: model.menuBarSymbol)
            }
        }
        .onAppear {
            if model.shouldShowOnboardingAtLaunch { OnboardingWindow.open(openWindow) }
        }
    }
}
```

In `Wiska/MenuContent.swift`:
- under `Text(model.languageStatus)` add:
```swift
        if let stats = model.statsLine {
            Text(stats)
        }
```
- before `Button("History…")` add:
```swift
        Button("Setup…") {
            OnboardingWindow.open(openWindow)
        }
```

- [ ] **Step 5: Stats header in History**

In `Wiska/HistoryView.swift`, add `import HUD` and replace `return List(items) { item in` with:
```swift
        let stats = store.stats()
        return VStack(spacing: 0) {
            if stats.words > 0 {
                StatsHeader(stats: stats).padding([.horizontal, .top], 12)
            }
            List(items) { item in
```
then close the extra `VStack` by changing the end of the `List` builder from
```swift
            .padding(.vertical, 2)
        }
```
to
```swift
            .padding(.vertical, 2)
        }
        }
```
and append at the end of the file:
```swift
private struct StatsHeader: View {
    let stats: DictationStats

    var body: some View {
        HStack(spacing: 10) {
            tile(stats.words.formatted(), "words this week")
            tile(StatsFormatter.savedText(stats.timeSaved), "time saved")
            VStack(alignment: .leading, spacing: 6) {
                Text("🇸🇪 \(Int((stats.swedishShare * 100).rounded()))%  ·  🇬🇧 \(Int((stats.englishShare * 100).rounded()))%")
                    .font(.headline)
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        AuroraTheme.teal.frame(width: proxy.size.width * stats.swedishShare)
                        AuroraTheme.violet.frame(width: proxy.size.width * stats.englishShare)
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold()).foregroundStyle(AuroraTheme.gradient)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
```

- [ ] **Step 6: Build, test, relaunch**

Run: `xcodebuild -project Wiska.xcodeproj -scheme Wiska -configuration Debug -derivedDataPath build -allowProvisioningUpdates build 2>&1 | grep -E "error:|\*\* BUILD"`
Expected: `** BUILD SUCCEEDED **`

Run: `cd WiskaKit && swift test 2>&1 | grep -E "error:|✘|Test run with"`
Expected: no `✘`.

Run: `pkill -x SecureWispr; pkill -x Wiska; open build/Build/Products/Debug/Wiska.app`
Expected: Wiska launches; data folder now `~/Library/Application Support/Wiska` (contains dictionary.json, History.store, Models/); onboarding window opens in front (permissions must be re-granted for the new bundle id).

- [ ] **Step 7: Commit**

```bash
git add Wiska WiskaKit
git commit -m "feat(app): Wiska onboarding checklist, weekly stats, migration on launch"
```

---

### Task 10: GitHub rename + acceptance (with the user)

- [ ] **Step 1: Rename the repository** (user-approved; keeps PR, history, tags, redirects)

```bash
gh repo rename Wiska --repo jozeta/SecureWispr --yes
git remote set-url origin https://github.com/jozeta/Wiska.git
git remote -v
```
Expected: `origin https://github.com/jozeta/Wiska.git`.

- [ ] **Step 2: Acceptance (manual)**
  - Icon in Finder/Dock/Settings and menu-bar mark look right in light and dark menu bars.
  - Notch capsule: listening (badge + gradient waveform), transcribing, language flash, an error (password field) — on the built-in display; on an external display if available.
  - Onboarding: opens in front at first Wiska launch; each "Allow…" works; ✓ appear live; 🌐 row confirmable; "Try it" ticks after a dictation; Finish closes; next launch doesn't reopen.
  - Data carried over: dictionary entries, history, Settings choices, Parakeet shows Ready without download.
  - Stats tiles in History and the menu line match recent dictations.

- [ ] **Step 3: Commit / tag**

```bash
git commit --allow-empty -m "chore: M5 acceptance passed"
git tag v0.5-m5
```
