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

    func timed(_ engine: SpeechEngine, latency: TimeInterval, transcription: TimeInterval, cleanup: TimeInterval,
               pasted: Bool = true) -> DictationRecord {
        DictationRecord(date: Self.now, appBundleID: nil, language: .english, engine: engine, rawText: "a b",
                        finalText: "a b", pasted: pasted, latency: latency, transcriptionTime: transcription,
                        cleanupTime: cleanup)
    }

    /// Speed: medians per engine over measured, pasted dictations; the busiest engine first.
    @Test func speedIsTheMedianPerEngine() {
        let result = report([
            timed(.parakeet, latency: 0.5, transcription: 0.2, cleanup: 0.1),
            timed(.parakeet, latency: 0.9, transcription: 0.4, cleanup: 0.3),
            timed(.parakeet, latency: 3.0, transcription: 2.0, cleanup: 0.5),
            timed(.apple, latency: 1.2, transcription: 0.6, cleanup: 0.4),
            timed(.apple, latency: 0, transcription: 0, cleanup: 0),            // before 1.2: not measured
            timed(.apple, latency: 9, transcription: 9, cleanup: 0, pasted: false),
        ])
        #expect(result.speed.map(\.engine) == [.parakeet, .apple])
        let parakeet = result.speed[0]
        #expect(parakeet.dictations == 3)
        #expect(parakeet.total == 0.9)
        #expect(parakeet.transcription == 0.4)
        #expect(parakeet.cleanup == 0.3)
        #expect(result.speed[1].dictations == 1)
        #expect(result.speed[1].total == 1.2)
        #expect(report([record(3)]).speed.isEmpty)
    }

    @Test func medianOfAnEvenCountIsTheMiddlePair() {
        #expect(HistoryReport.median([1, 4, 2, 3]) == 2.5)
        #expect(HistoryReport.median([]) == 0)
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

    /// Chile changes its clocks at midnight (2026-09-06): days after it must still line up.
    @Test func midnightDSTKeepsDailyBuckets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Santiago")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12))!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        let text = "one two three"
        let record = DictationRecord(date: twoDaysAgo, appBundleID: nil, language: nil, engine: .apple,
                                     rawText: text, finalText: text, pasted: true)
        let old = DictationRecord(date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: 9))!,
                                  appBundleID: nil, language: nil, engine: .apple, rawText: "x", finalText: "x", pasted: true)
        for period in [HistoryPeriod.week, .month, .all] {
            let result = HistoryReport.compute([old, record], period: period, now: now, calendar: calendar)
            #expect(result.buckets.allSatisfy { calendar.startOfDay(for: $0.start) == $0.start }, "\(period)")
            #expect(result.buckets.map(\.words).reduce(0, +) == result.words, "\(period)")
        }
    }
}
