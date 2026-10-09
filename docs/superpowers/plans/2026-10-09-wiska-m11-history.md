# Wiska M11 Richer History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** History gets filters, a raw-vs-cleaned view per entry, and a Stats tab with words over time, top apps and languages.

**Architecture:** Three pure, tested types in the History module — `HistoryFilter` (+ `HistoryPeriod`), `WordDiff`, `HistoryReport` — computed from the records `HistoryStore` already returns. The app's `HistoryView` becomes two tabs (Dictations | Stats) that use them; Swift Charts draws the bars.

**Tech Stack:** Swift 6.2, SwiftPM `WiskaKit` (History, Core), Swift Testing, SwiftUI + Swift Charts in app target `Wiska`.

**Spec:** `docs/superpowers/specs/2026-10-09-wiska-m11-history-design.md`

## Global Constraints

- No new storage; only pasted dictations count in stats; time saved uses `DictationStats.typingWordsPerMinute` (40 wpm) minus spoken duration, floored at 0.
- Periods: Today = since start of the current day; 7 days / 30 days = since start of the day 6 / 29 days ago; All = no limit.
- Weekly buckets when the span exceeds 60 days; weeks start on the calendar's first weekday.
- Top apps: 5, then "Other"; no app = "Unknown app".
- Copy: "No matches", "No dictations yet", "No dictations in this period", "No changes by cleanup", "History keeps <N> days — change this in Settings → History", "Clear filters".
- Clear All deletes everything regardless of filters.
- Tests: `cd WiskaKit && swift test`. App build from repo root: `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build -quiet build`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**Decisions made while planning:**
- `HistoryStore` already returns every record newest first via `items(matching: "")` (tested by `addsAndListsNewestFirst`), so no `records()` method is added; the view filters those items.
- `HistoryFilter.isDefault` ignores the search text (the search field has its own clear button); "Clear filters" resets app, language, period and pasted only.

## Review Focus

1. Midnight boundaries in the user's time zone — a dictation at 23:59 yesterday is not "Today". Pinned by `HistoryFilterTests.todayStartsAtMidnight`.
2. Punctuation and capitalisation changes ("tuesday" → "Tuesday.") must not show as changed words, or every entry looks heavily edited. Pinned by `WordDiffTests.punctuationAndCaseAreNotChanges`.
3. "All" over a long history must switch to weekly bars, not draw hundreds of daily bars. Pinned by `HistoryReportTests.longSpansUseWeeks`.
4. Not-pasted dictations must not inflate stats. Pinned by `HistoryReportTests.notPastedIsExcluded`.
5. Entries without an app or language must still be listed under "All" and not crash menus. Pinned by `HistoryFilterTests.missingAppOrLanguageMatchesOnlyAll`.

---

### Task 1: HistoryPeriod and HistoryFilter

**Files:**
- Create: `WiskaKit/Sources/History/HistoryFilter.swift`
- Test: `WiskaKit/Tests/HistoryTests/HistoryFilterTests.swift`

**Interfaces:**
- Produces: `HistoryPeriod` (`today, week, month, all`; `displayName`; `days: Int?`; `start(now:calendar:) -> Date?`), `HistoryFilter` (`query`, `app: String?`, `language: Language?`, `period`, `notPastedOnly`; `isDefault`; `cleared() -> HistoryFilter`; `matches(_:now:calendar:) -> Bool`; `static apps(in: [DictationRecord]) -> [String]`; `static languages(in: [DictationRecord]) -> [Language]`).

- [ ] **Step 1: Write the failing test**

```swift
// WiskaKit/Tests/HistoryTests/HistoryFilterTests.swift
import Core
import Foundation
import Testing
@testable import History

struct HistoryFilterTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        calendar.firstWeekday = 2
        return calendar
    }()
    /// Thursday 2026-10-08 12:00 in Stockholm.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!

    func record(_ text: String = "hello there", at date: Date = now, app: String? = "com.apple.mail",
                language: Language? = .english, pasted: Bool = true, raw: String? = nil) -> DictationRecord {
        DictationRecord(date: date, appBundleID: app, language: language, engine: .apple,
                        rawText: raw ?? text, finalText: text, pasted: pasted)
    }

    func matches(_ filter: HistoryFilter, _ record: DictationRecord) -> Bool {
        filter.matches(record, now: Self.now, calendar: Self.calendar)
    }

    @Test func defaultMatchesEverything() {
        #expect(HistoryFilter().isDefault)
        #expect(matches(HistoryFilter(), record(app: nil, language: nil, pasted: false)))
    }

    @Test func queryMatchesFinalOrRawText() {
        let filter = HistoryFilter(query: "RAPPORT")
        #expect(matches(filter, record("skicka rapporten")))
        #expect(matches(filter, record("send it", raw: "öh skicka rapporten")))
        #expect(!matches(filter, record("something else")))
        #expect(filter.isDefault)   // the search text isn't a filter
    }

    @Test func appAndLanguage() {
        #expect(matches(HistoryFilter(app: "com.apple.mail"), record()))
        #expect(!matches(HistoryFilter(app: "com.tinyspeck.slackmacgap"), record()))
        #expect(matches(HistoryFilter(language: .english), record()))
        #expect(!matches(HistoryFilter(language: .swedish), record()))
        #expect(!HistoryFilter(language: .swedish).isDefault)
    }

    @Test func missingAppOrLanguageMatchesOnlyAll() {
        let bare = record(app: nil, language: nil)
        #expect(matches(HistoryFilter(), bare))
        #expect(!matches(HistoryFilter(app: "com.apple.mail"), bare))
        #expect(!matches(HistoryFilter(language: .english), bare))
    }

    @Test func todayStartsAtMidnight() {
        let today = HistoryFilter(period: .today)
        let midnight = Self.calendar.startOfDay(for: Self.now)
        #expect(matches(today, record(at: midnight)))
        #expect(!matches(today, record(at: midnight.addingTimeInterval(-60))))
    }

    @Test func sevenDaysIncludesTodayAndSixDaysBefore() {
        let week = HistoryFilter(period: .week)
        let firstDay = Self.calendar.date(byAdding: .day, value: -6, to: Self.calendar.startOfDay(for: Self.now))!
        #expect(matches(week, record(at: firstDay)))
        #expect(!matches(week, record(at: firstDay.addingTimeInterval(-1))))
        #expect(HistoryPeriod.all.start(now: Self.now, calendar: Self.calendar) == nil)
    }

    @Test func notPastedOnly() {
        let filter = HistoryFilter(notPastedOnly: true)
        #expect(matches(filter, record(pasted: false)))
        #expect(!matches(filter, record(pasted: true)))
    }

    @Test func clearedKeepsTheSearch() {
        let filter = HistoryFilter(query: "x", app: "a", language: .danish, period: .month, notPastedOnly: true)
        #expect(filter.cleared() == HistoryFilter(query: "x"))
    }

    @Test func menuChoicesComeFromHistory() {
        let records = [record(app: "b"), record(app: "a"), record(app: "b"), record(app: nil, language: .swedish)]
        #expect(HistoryFilter.apps(in: records) == ["b", "a"])
        #expect(HistoryFilter.languages(in: records) == [.english, .swedish])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WiskaKit && swift test --filter HistoryFilterTests`
Expected: FAIL — compile error, `HistoryFilter` not found.

- [ ] **Step 3: Implement**

```swift
// WiskaKit/Sources/History/HistoryFilter.swift
import Core
import Foundation

/// A span of calendar days ending today.
public enum HistoryPeriod: String, CaseIterable, Sendable {
    case today, week, month, all

    public var displayName: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        case .all: "All"
        }
    }

    /// Calendar days covered, today included; nil for all.
    public var days: Int? {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        case .all: nil
        }
    }

    /// Midnight of the first day in the period (nil: no limit).
    public func start(now: Date, calendar: Calendar) -> Date? {
        guard let days else { return nil }
        return calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))
    }
}

/// What the Dictations tab shows: search text plus app, language, period and pasted filters.
public struct HistoryFilter: Equatable, Sendable {
    public var query: String
    public var app: String?
    public var language: Language?
    public var period: HistoryPeriod
    public var notPastedOnly: Bool

    public init(query: String = "", app: String? = nil, language: Language? = nil,
                period: HistoryPeriod = .all, notPastedOnly: Bool = false) {
        self.query = query
        self.app = app
        self.language = language
        self.period = period
        self.notPastedOnly = notPastedOnly
    }

    /// True when no filter narrows the list (the search text has its own clear button).
    public var isDefault: Bool { app == nil && language == nil && period == .all && !notPastedOnly }

    /// The filters reset, the search kept.
    public func cleared() -> HistoryFilter { HistoryFilter(query: query) }

    public func matches(_ record: DictationRecord, now: Date, calendar: Calendar = .current) -> Bool {
        if let app, record.appBundleID != app { return false }
        if let language, record.language != language { return false }
        if notPastedOnly && record.pasted { return false }
        if let start = period.start(now: now, calendar: calendar), record.date < start { return false }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || record.finalText.localizedCaseInsensitiveContains(trimmed)
            || record.rawText.localizedCaseInsensitiveContains(trimmed)
    }

    /// Apps found in history, most entries first (ties: alphabetical by bundle ID).
    public static func apps(in records: [DictationRecord]) -> [String] {
        var counts: [String: Int] = [:]
        for record in records { if let app = record.appBundleID { counts[app, default: 0] += 1 } }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// Languages found in history, in the app's language order.
    public static func languages(in records: [DictationRecord]) -> [Language] {
        let present = Set(records.compactMap(\.language))
        return Language.allCases.filter(present.contains)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WiskaKit && swift test --filter HistoryFilterTests`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(history): filters by app, language, period and pasted"
```

---

### Task 2: WordDiff

**Files:**
- Create: `WiskaKit/Sources/History/WordDiff.swift`
- Test: `WiskaKit/Tests/HistoryTests/WordDiffTests.swift`

**Interfaces:**
- Produces: `struct DiffToken: Equatable, Sendable { let text: String; let changed: Bool }`; `WordDiff.diff(raw: String, final: String) -> (heard: [DiffToken], pasted: [DiffToken])`.

- [ ] **Step 1: Write the failing test**

```swift
// WiskaKit/Tests/HistoryTests/WordDiffTests.swift
import Testing
@testable import History

struct WordDiffTests {
    func changed(_ tokens: [DiffToken]) -> [String] { tokens.filter(\.changed).map(\.text) }

    @Test func identicalTextsHaveNoChanges() {
        let diff = WordDiff.diff(raw: "see you soon", final: "see you soon")
        #expect(changed(diff.heard).isEmpty)
        #expect(changed(diff.pasted).isEmpty)
        #expect(diff.pasted.map(\.text) == ["see", "you", "soon"])
    }

    @Test func removedFillersAreChangedInHeard() {
        let diff = WordDiff.diff(raw: "um I think uh so", final: "I think so")
        #expect(changed(diff.heard) == ["um", "uh"])
        #expect(changed(diff.pasted).isEmpty)
    }

    @Test func punctuationAndCaseAreNotChanges() {
        let diff = WordDiff.diff(raw: "hi anna see you tuesday", final: "Hi Anna, see you Tuesday.")
        #expect(changed(diff.heard).isEmpty)
        #expect(changed(diff.pasted).isEmpty)
        #expect(diff.pasted.map(\.text) == ["Hi", "Anna,", "see", "you", "Tuesday."])
    }

    @Test func selfCorrectionKeepsOnlyTheCorrection() {
        let diff = WordDiff.diff(raw: "tuesday no wait wednesday", final: "Wednesday.")
        #expect(changed(diff.heard) == ["tuesday", "no", "wait"])
        #expect(changed(diff.pasted).isEmpty)
    }

    @Test func rewordedSentence() {
        let diff = WordDiff.diff(raw: "send it asap", final: "please send it soon")
        #expect(changed(diff.heard) == ["asap"])
        #expect(changed(diff.pasted) == ["please", "soon"])
    }

    @Test func emptyInputs() {
        #expect(WordDiff.diff(raw: "", final: "Hi").pasted == [DiffToken(text: "Hi", changed: true)])
        #expect(WordDiff.diff(raw: "um", final: "").heard == [DiffToken(text: "um", changed: true)])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WiskaKit && swift test --filter WordDiffTests`
Expected: FAIL — `WordDiff` not found.

- [ ] **Step 3: Implement**

```swift
// WiskaKit/Sources/History/WordDiff.swift
import Foundation

public struct DiffToken: Equatable, Sendable {
    public let text: String
    /// Removed (in the heard text) or added/changed (in the pasted text).
    public let changed: Bool

    public init(text: String, changed: Bool) {
        self.text = text
        self.changed = changed
    }
}

/// What cleanup changed, word by word: the longest common subsequence of words, compared
/// without case and surrounding punctuation ("tuesday" = "Tuesday."), is unchanged.
public enum WordDiff {
    public static func diff(raw: String, final: String) -> (heard: [DiffToken], pasted: [DiffToken]) {
        let a = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = final.split(whereSeparator: \.isWhitespace).map(String.init)
        let ka = a.map(key), kb = b.map(key)
        // lcs[i][j] = length of the LCS of ka[i...] and kb[j...].
        var lcs = Array(repeating: Array(repeating: 0, count: kb.count + 1), count: ka.count + 1)
        for i in stride(from: ka.count - 1, through: 0, by: -1) {
            for j in stride(from: kb.count - 1, through: 0, by: -1) {
                lcs[i][j] = ka[i] == kb[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var keptA = Set<Int>(), keptB = Set<Int>()
        var i = 0, j = 0
        while i < ka.count && j < kb.count {
            if ka[i] == kb[j] {
                keptA.insert(i); keptB.insert(j); i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return (a.indices.map { DiffToken(text: a[$0], changed: !keptA.contains($0)) },
                b.indices.map { DiffToken(text: b[$0], changed: !keptB.contains($0)) })
    }

    private static func key(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WiskaKit && swift test --filter WordDiffTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(history): word diff between what was heard and what was pasted"
```

---

### Task 3: HistoryReport

**Files:**
- Create: `WiskaKit/Sources/History/HistoryReport.swift`
- Test: `WiskaKit/Tests/HistoryTests/HistoryReportTests.swift`

**Interfaces:**
- Consumes: `HistoryPeriod` (Task 1); `DictationStats.typingWordsPerMinute`.
- Produces: `HistoryReport { words, dictations, averageWords: Int; timeSaved: TimeInterval; buckets: [Bucket]; bucketIsWeek: Bool; topApps: [AppWords]; shares: [Language: Double] }`, `HistoryReport.Bucket { start: Date; words: Int }`, `HistoryReport.AppWords { app: String?; words: Int; isOther: Bool }`, `static maxApps = 5`, `static weeklyAfterDays = 60`, `static compute(_:period:now:calendar:) -> HistoryReport`.

- [ ] **Step 1: Write the failing test**

```swift
// WiskaKit/Tests/HistoryTests/HistoryReportTests.swift
import Core
import Foundation
import Testing
@testable import History

struct HistoryReportTests {
    static let calendar = HistoryFilterTests.calendar
    static let now = HistoryFilterTests.now

    func record(_ words: Int, daysAgo: Int = 0, app: String? = "com.apple.mail", language: Language? = .english,
                pasted: Bool = true, duration: TimeInterval = 0) -> DictationRecord {
        let date = Self.calendar.date(byAdding: .day, value: -daysAgo, to: Self.now)!
        let text = Array(repeating: "word", count: words).joined(separator: " ")
        return DictationRecord(date: date, appBundleID: app, language: language, engine: .apple,
                               rawText: text, finalText: text, pasted: pasted, duration: duration)
    }

    func report(_ records: [DictationRecord], _ period: HistoryPeriod = .week) -> HistoryReport {
        HistoryReport.compute(records, period: period, now: Self.now, calendar: Self.calendar)
    }

    @Test func totals() {
        let result = report([record(30, duration: 10), record(10, daysAgo: 1, duration: 5)])
        #expect(result.words == 40)
        #expect(result.dictations == 2)
        #expect(result.averageWords == 20)
        #expect(result.timeSaved == 40.0 / 40 * 60 - 15)
    }

    @Test func emptyDaysAreZero() {
        let result = report([record(5, daysAgo: 2)])
        #expect(result.buckets.count == 7)
        #expect(!result.bucketIsWeek)
        #expect(result.buckets.map(\.words) == [0, 0, 0, 0, 5, 0, 0])
        #expect(result.buckets.first?.start == HistoryPeriod.week.start(now: Self.now, calendar: Self.calendar))
    }

    @Test func longSpansUseWeeks() {
        let result = report([record(5, daysAgo: 100), record(7)], .all)
        #expect(result.bucketIsWeek)
        #expect(result.buckets.count >= 14 && result.buckets.count <= 16)
        #expect(result.buckets.map(\.words).reduce(0, +) == 12)
        #expect(result.buckets.last?.words == 7)
    }

    @Test func shortAllSpanStaysDaily() {
        let result = report([record(5, daysAgo: 3), record(7)], .all)
        #expect(!result.bucketIsWeek)
        #expect(result.buckets.count == 4)
    }

    @Test func notPastedIsExcluded() {
        let result = report([record(50, pasted: false), record(5)])
        #expect(result.words == 5)
        #expect(result.dictations == 1)
    }

    @Test func periodCutOff() {
        let result = report([record(5, daysAgo: 7), record(3, daysAgo: 6)])
        #expect(result.words == 3)
    }

    @Test func topFiveAppsThenOther() {
        let apps = ["a", "b", "c", "d", "e", "f", "g"]
        let records = apps.enumerated().map { record(10 - $0.offset, app: $0.element) } + [record(1, app: nil)]
        let top = report(records).topApps
        #expect(top.map(\.app) == ["a", "b", "c", "d", "e", nil])
        #expect(top.last?.isOther == true)
        #expect(top.last?.words == 5 + 4 + 1)
    }

    @Test func unknownAppIsItsOwnEntry() {
        let top = report([record(9, app: nil), record(3)]).topApps
        #expect(top.first == HistoryReport.AppWords(app: nil, words: 9, isOther: false))
    }

    @Test func languageShares() {
        let shares = report([record(30, language: .english), record(10, language: .swedish), record(5, language: nil)]).shares
        #expect(shares[.english] == 0.75)
        #expect(shares[.swedish] == 0.25)
    }

    @Test func emptyInput() {
        let result = report([])
        #expect(result.dictations == 0)
        #expect(result.averageWords == 0)
        #expect(result.topApps.isEmpty)
        #expect(report([], .all).buckets.count == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WiskaKit && swift test --filter HistoryReportTests`
Expected: FAIL — `HistoryReport` not found.

- [ ] **Step 3: Implement**

```swift
// WiskaKit/Sources/History/HistoryReport.swift
import Core
import Foundation

/// The Stats tab's numbers for one period, computed from history (only pasted dictations count).
public struct HistoryReport: Equatable, Sendable {
    public struct Bucket: Equatable, Sendable {
        public let start: Date
        public let words: Int
    }

    public struct AppWords: Equatable, Sendable {
        /// nil with `isOther == false`: dictations whose app is unknown.
        public let app: String?
        public let words: Int
        /// The sum of every app after the top five.
        public let isOther: Bool

        public init(app: String?, words: Int, isOther: Bool) {
            self.app = app
            self.words = words
            self.isOther = isOther
        }
    }

    public static let maxApps = 5
    /// Longer spans get one bar per week.
    public static let weeklyAfterDays = 60

    public var words = 0
    public var dictations = 0
    public var averageWords = 0
    public var timeSaved: TimeInterval = 0
    public var buckets: [Bucket] = []
    public var bucketIsWeek = false
    public var topApps: [AppWords] = []
    public var shares: [Language: Double] = [:]

    public static func compute(_ records: [DictationRecord], period: HistoryPeriod, now: Date,
                               calendar: Calendar = .current) -> HistoryReport {
        let today = calendar.startOfDay(for: now)
        let pasted = records.filter { $0.pasted && $0.date <= now }
        let earliest = pasted.map(\.date).min().map { calendar.startOfDay(for: $0) } ?? today
        let start = period.start(now: now, calendar: calendar) ?? earliest
        let included = pasted.filter { $0.date >= start }
        func count(_ record: DictationRecord) -> Int { record.finalText.split(whereSeparator: \.isWhitespace).count }

        var report = HistoryReport()
        report.dictations = included.count
        report.words = included.reduce(0) { $0 + count($1) }
        report.averageWords = included.isEmpty ? 0 : Int((Double(report.words) / Double(included.count)).rounded())
        let typing = Double(report.words) / DictationStats.typingWordsPerMinute * 60
        report.timeSaved = max(0, typing - included.reduce(0) { $0 + $1.duration })

        // Buckets: one per day, or per week when the span is long.
        let spanDays = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1
        report.bucketIsWeek = spanDays > weeklyAfterDays
        func bucketStart(_ date: Date) -> Date {
            report.bucketIsWeek ? (calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date))
                                : calendar.startOfDay(for: date)
        }
        var wordsPerBucket: [Date: Int] = [:]
        for record in included { wordsPerBucket[bucketStart(record.date), default: 0] += count(record) }
        var cursor = bucketStart(start)
        let last = bucketStart(today)
        while cursor <= last {
            report.buckets.append(Bucket(start: cursor, words: wordsPerBucket[cursor] ?? 0))
            cursor = calendar.date(byAdding: report.bucketIsWeek ? .weekOfYear : .day, value: 1, to: cursor) ?? last.addingTimeInterval(1)
        }

        // Top apps, then everything else as "Other".
        var perApp: [String?: Int] = [:]
        for record in included { perApp[record.appBundleID, default: 0] += count(record) }
        let ranked = perApp.sorted { $0.value != $1.value ? $0.value > $1.value : ($0.key ?? "") < ($1.key ?? "") }
        report.topApps = ranked.prefix(maxApps).map { AppWords(app: $0.key, words: $0.value, isOther: false) }
        let rest = ranked.dropFirst(maxApps).reduce(0) { $0 + $1.value }
        if rest > 0 { report.topApps.append(AppWords(app: nil, words: rest, isOther: true)) }

        // Each language's share of the words whose language is known.
        var perLanguage: [Language: Int] = [:]
        for record in included { if let language = record.language { perLanguage[language, default: 0] += count(record) } }
        let known = perLanguage.values.reduce(0, +)
        if known > 0 { report.shares = perLanguage.filter { $0.value > 0 }.mapValues { Double($0) / Double(known) } }
        return report
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WiskaKit && swift test --filter "HistoryReportTests|HistoryFilterTests|WordDiffTests|HistoryStoreTests|DictationStatsTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(history): report for the Stats tab — totals, words over time, top apps, languages"
```

---

### Task 4: History window — Dictations and Stats tabs

**Files:**
- Modify (rewrite): `Wiska/HistoryView.swift`

**Interfaces:**
- Consumes: Tasks 1–3; `HistoryStore.items(matching:)`, `delete`, `deleteAll`, `revision`; `SettingsStore.highlight`, `historyRetention`; `AuroraTheme`; `StatsFormatter.savedText`, `StatsFormatter.languagePercents`.

- [ ] **Step 1: Replace `Wiska/HistoryView.swift`**

```swift
import AppKit
import Charts
import Core
import History
import HUD
import Preferences
import SwiftData
import SwiftUI

struct HistoryView: View {
    let store: HistoryStore?
    let settings: SettingsStore
    @State private var tab = Tab.dictations

    enum Tab: String, CaseIterable {
        case dictations = "Dictations"
        case stats = "Stats"
    }

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ContentUnavailableView("History unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text("The history database could not be opened."))
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func content(_ store: HistoryStore) -> some View {
        let _ = store.revision   // re-query when the store changes
        let items = store.items(matching: "")
        return VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .padding(.vertical, 8)
            switch tab {
            case .dictations:
                DictationsList(store: store, items: items, highlight: settings.highlight)
            case .stats:
                StatsPane(records: items.map(\.record), retention: settings.historyRetention,
                          highlight: settings.highlight)
            }
        }
    }
}

// MARK: Dictations

private struct DictationsList: View {
    let store: HistoryStore
    let items: [HistoryItem]
    let highlight: Highlight
    @State private var filter = HistoryFilter()
    @State private var expanded: PersistentIdentifier?
    @State private var confirmClear = false

    var body: some View {
        let records = items.map(\.record)
        let now = Date()
        let shown = items.filter { filter.matches($0.record, now: now) }
        List(shown) { item in
            DictationRow(item: item, expanded: expanded == item.id, highlight: highlight, store: store)
                .contentShape(Rectangle())
                .onTapGesture { expanded = expanded == item.id ? nil : item.id }
        }
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView(items.isEmpty ? "No dictations yet" : "No matches",
                                       systemImage: "clock.arrow.circlepath")
            }
        }
        .searchable(text: $filter.query, prompt: "Search history")
        .toolbar {
            ToolbarItemGroup {
                Picker("App", selection: $filter.app) {
                    Text("All apps").tag(String?.none)
                    ForEach(HistoryFilter.apps(in: records), id: \.self) { app in
                        Text(AppInfo.name(app)).tag(String?.some(app))
                    }
                }
                Picker("Language", selection: $filter.language) {
                    Text("All languages").tag(Language?.none)
                    ForEach(HistoryFilter.languages(in: records), id: \.self) { language in
                        Text("\(language.flag) \(language.displayName)").tag(Language?.some(language))
                    }
                }
                Picker("Period", selection: $filter.period) {
                    ForEach(HistoryPeriod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Pasted", selection: $filter.notPastedOnly) {
                    Text("All").tag(false)
                    Text("Not pasted only").tag(true)
                }
                if !filter.isDefault {
                    Button("Clear filters") { filter = filter.cleared() }
                }
                Button("Clear All", role: .destructive) { confirmClear = true }
                    .disabled(items.isEmpty)
            }
        }
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { store.deleteAll() }
        }
    }
}

private struct DictationRow: View {
    let item: HistoryItem
    let expanded: Bool
    let highlight: Highlight
    let store: HistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.record.date, style: .time).font(.caption).foregroundStyle(.secondary)
                        Text(item.record.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        if let language = item.record.language { Text(language.flag).font(.caption) }
                        if let app = item.record.appBundleID {
                            Text(AppInfo.name(app)).font(.caption).foregroundStyle(.secondary)
                        }
                        if !item.record.pasted {
                            Label("not pasted", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Text(item.record.finalText).lineLimit(expanded ? nil : 2).textSelection(.enabled)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.record.finalText, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help("Copy")
                Button(role: .destructive) { store.delete(item.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Delete")
            }
            if expanded { CleanupDiff(record: item.record, highlight: highlight) }
        }
        .padding(.vertical, 2)
    }
}

/// What was heard next to what was pasted, with cleanup's changes marked.
private struct CleanupDiff: View {
    let record: DictationRecord
    let highlight: Highlight

    var body: some View {
        let diff = WordDiff.diff(raw: record.rawText, final: record.finalText)
        VStack(alignment: .leading, spacing: 6) {
            if record.rawText == record.finalText {
                Text("No changes by cleanup").font(.caption).foregroundStyle(.secondary)
            } else {
                block("Heard", diff.heard.reduce(Text("")) { text, token in
                    text + (token.changed ? Text(token.text).foregroundColor(.red).strikethrough()
                                          : Text(token.text)) + Text(" ")
                })
                block("Pasted", diff.pasted.reduce(Text("")) { text, token in
                    text + (token.changed ? Text(token.text).foregroundColor(AuroraTheme.start(highlight)).bold()
                                          : Text(token.text)) + Text(" ")
                })
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func block(_ title: String, _ text: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            text.textSelection(.enabled)
        }
    }
}

// MARK: Stats

private struct StatsPane: View {
    let records: [DictationRecord]
    let retention: HistoryRetention
    let highlight: Highlight
    @State private var period = HistoryPeriod.week

    var body: some View {
        let report = HistoryReport.compute(records, period: period, now: Date())
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Period", selection: $period) {
                    ForEach([HistoryPeriod.week, .month, .all], id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                if let note = retentionNote {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if report.dictations == 0 {
                    ContentUnavailableView("No dictations in this period", systemImage: "chart.bar")
                } else {
                    HStack(spacing: 10) {
                        tile(report.words.formatted(), "words")
                        tile(StatsFormatter.savedText(report.timeSaved), "time saved")
                        tile(report.dictations.formatted(), "dictations")
                        tile(report.averageWords.formatted(), "words per dictation")
                    }
                    section(report.bucketIsWeek ? "Words per week" : "Words per day") {
                        Chart(report.buckets, id: \.start) { bucket in
                            BarMark(x: .value("Date", bucket.start, unit: report.bucketIsWeek ? .weekOfYear : .day),
                                    y: .value("Words", bucket.words))
                            .foregroundStyle(AuroraTheme.gradient(highlight))
                        }
                        .frame(height: 160)
                    }
                    section("Top apps") { TopApps(apps: report.topApps, highlight: highlight) }
                    let split = StatsFormatter.languagePercents(DictationStats(words: report.words,
                                                                               timeSaved: report.timeSaved,
                                                                               shares: report.shares))
                    if !split.isEmpty {
                        section("Languages") {
                            Text(split.map { "\($0.language.flag) \($0.percent)%" }.joined(separator: "  ·  "))
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    /// Shown when History keeps fewer days than the chosen period.
    private var retentionNote: String? {
        let kept: Int? = switch retention {
        case .day: 1
        case .week: 7
        case .month: 30
        case .off, .forever: nil
        }
        guard let kept, kept < (period.days ?? .max) else { return nil }
        return "History keeps \(kept) \(kept == 1 ? "day" : "days") — change this in Settings → History"
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold()).foregroundStyle(AuroraTheme.gradient(highlight))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }
}

private struct TopApps: View {
    let apps: [HistoryReport.AppWords]
    let highlight: Highlight

    var body: some View {
        let most = apps.map(\.words).max() ?? 1
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(apps.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 8) {
                    if let app = entry.app, let icon = AppInfo.icon(app) {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: entry.isOther ? "ellipsis.circle" : "questionmark.app")
                            .frame(width: 16, height: 16)
                    }
                    Text(entry.isOther ? "Other" : entry.app.map(AppInfo.name) ?? "Unknown app")
                        .frame(width: 140, alignment: .leading).lineLimit(1)
                    GeometryReader { proxy in
                        Capsule().fill(AuroraTheme.gradient(highlight))
                            .frame(width: max(4, proxy.size.width * Double(entry.words) / Double(most)))
                    }
                    .frame(height: 8)
                    Text(entry.words.formatted()).font(.caption).foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
    }
}

/// An app's display name and icon from its bundle ID (the bundle ID when it's not installed).
private enum AppInfo {
    static func name(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
```

- [ ] **Step 2: Build and run the full suite**

Run: `cd WiskaKit && swift test`, then from the repo root `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build -quiet build`
Expected: all tests pass (1 known Parakeet Danish issue); the app builds.

- [ ] **Step 3: Manual check**

Relaunch (`pkill -x Wiska; open build/Build/Products/Debug/Wiska.app`), open History: the Dictations tab filters by app / language / period / not pasted and "Clear filters" resets them; clicking a row shows Heard / Pasted with removed words struck through; the Stats tab shows tiles, the words chart, top apps and languages, and the retention note for 30 days when History keeps 7.

- [ ] **Step 4: Commit**

```bash
git add Wiska/HistoryView.swift
git commit -m "feat(app): History gets filters, a raw-vs-cleaned view and a Stats tab"
```
