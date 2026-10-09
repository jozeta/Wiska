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
