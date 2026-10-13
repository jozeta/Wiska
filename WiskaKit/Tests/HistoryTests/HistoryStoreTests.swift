import Core
import Foundation
import Testing
@testable import History

@MainActor
struct HistoryStoreTests {
    let store = try! HistoryStore(inMemory: true)
    let now = Date()

    func record(_ text: String, ageDays: Double = 0, pasted: Bool = true) -> DictationRecord {
        DictationRecord(date: now.addingTimeInterval(-ageDays * 86_400), appBundleID: "com.apple.TextEdit",
                        language: .swedish, engine: .apple, rawText: "öh \(text)", finalText: text, pasted: pasted)
    }

    @Test func addsAndListsNewestFirst() {
        store.add(record("first", ageDays: 2), retention: .forever)
        store.add(record("second", ageDays: 1), retention: .forever)
        #expect(store.items(matching: "").map(\.record.finalText) == ["second", "first"])
    }

    @Test func latestIsTheNewestDictation() {
        #expect(store.latest() == nil)
        store.add(record("second", ageDays: 1), retention: .forever)
        store.add(record("first", ageDays: 2), retention: .forever)
        #expect(store.latest()?.finalText == "second")
    }

    /// Speed stats survive a save and reload.
    @Test func timingsRoundTrip() {
        var timed = record("timed")
        timed.latency = 0.8
        timed.transcriptionTime = 0.3
        timed.cleanupTime = 0.2
        store.add(timed, retention: .forever)
        #expect(store.latest() == timed)
    }

    @Test func searchMatchesRawOrFinalTextCaseInsensitively() {
        store.add(record("Skicka rapporten"), retention: .forever)
        store.add(record("Something else"), retention: .forever)
        #expect(store.items(matching: "RAPPORT").map(\.record.finalText) == ["Skicka rapporten"])
        #expect(store.items(matching: "öh").count == 2)
    }

    @Test func roundTripsAllFields() {
        let original = record("hej", pasted: false)
        store.add(original, retention: .forever)
        let stored = store.items(matching: "").first?.record
        #expect(stored?.language == .swedish)
        #expect(stored?.engine == .apple)
        #expect(stored?.pasted == false)
        #expect(stored?.appBundleID == "com.apple.TextEdit")
        #expect(stored?.rawText == "öh hej")
    }

    @Test func recordIsIgnoredWhenRetentionIsOff() {
        store.add(record("secret"), retention: .off)
        #expect(store.items(matching: "").isEmpty)
    }

    @Test func applyingShorterRetentionPurgesImmediately() {
        store.add(record("old", ageDays: 10), retention: .forever)
        store.add(record("recent", ageDays: 0.5), retention: .forever)
        store.apply(retention: .day, now: now)
        #expect(store.items(matching: "").map(\.record.finalText) == ["recent"])
    }

    @Test func retentionOffDeletesEverything() {
        store.add(record("a"), retention: .forever)
        store.apply(retention: .off, now: now)
        #expect(store.items(matching: "").isEmpty)
    }

    @Test func deleteOneAndDeleteAll() {
        store.add(record("a"), retention: .forever)
        store.add(record("b"), retention: .forever)
        let first = store.items(matching: "")[0]
        store.delete(first.id)
        #expect(store.items(matching: "").count == 1)
        store.deleteAll()
        #expect(store.items(matching: "").isEmpty)
    }

    @Test func deletingAnEntryThatRetentionAlreadyRemovedIsHarmless() {
        store.add(record("a"), retention: .forever)
        let id = store.items(matching: "")[0].id
        store.apply(retention: .off, now: now)
        store.delete(id)
        #expect(store.items(matching: "").isEmpty)
    }

    @Test func retentionWithNothingToDeleteLeavesRevisionAlone() {
        store.add(record("fresh"), retention: .forever)
        let start = store.revision
        store.apply(retention: .week, now: now)
        #expect(store.revision == start)
    }

    @Test func statsOnlyReadTheWindow() {
        store.add(record("old words here", ageDays: 30), retention: .forever)
        store.add(record("new", ageDays: 1), retention: .forever)
        #expect(store.stats(now: now).words == 1)
    }

    @Test func revisionChangesOnEveryMutation() {
        let start = store.revision
        store.add(record("a"), retention: .forever)
        store.deleteAll()
        #expect(store.revision == start + 2)
    }

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

    @Test func storeComputesStats() {
        var r = record("ett två tre fyra")
        r.duration = 1
        store.add(r, retention: .forever)
        #expect(store.stats(now: now).words == 4)
    }

    /// "This week" in the menu matches the Stats tab's 7 days: today and the 6 calendar days before.
    @Test func weeklyStatsUseCalendarDays() {
        let calendar = HistoryFilterTests.calendar
        let now = HistoryFilterTests.now   // Thursday 12:00
        let sevenDaysAgoAfternoon = calendar.date(byAdding: .day, value: -7, to: now)!.addingTimeInterval(2 * 3_600)
        let sixDaysAgoMorning = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
            .addingTimeInterval(3_600)
        for (date, text) in [(sevenDaysAgoAfternoon, "old words"), (sixDaysAgoMorning, "kept")] {
            store.add(DictationRecord(date: date, appBundleID: nil, language: .english, engine: .apple,
                                      rawText: text, finalText: text, pasted: true), retention: .forever)
        }
        #expect(store.stats(now: now, calendar: calendar).words == 1)
    }
}
