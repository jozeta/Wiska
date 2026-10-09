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

    /// A filter for an app or language no longer in history resets, instead of leaving a blank menu.
    @Test func vanishedChoicesReset() {
        let filter = HistoryFilter(query: "x", app: "gone", language: .danish, period: .week)
        let valid = filter.validated(apps: ["com.apple.mail"], languages: [.english])
        #expect(valid == HistoryFilter(query: "x", period: .week))
        let kept = HistoryFilter(app: "com.apple.mail", language: .english)
        #expect(kept.validated(apps: ["com.apple.mail"], languages: [.english]) == kept)
    }
}
