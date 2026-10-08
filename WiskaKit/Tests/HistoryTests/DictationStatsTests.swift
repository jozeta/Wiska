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

    @Test func languagePercentsAlwaysAddUpTo100() {
        let stats = DictationStats(words: 3, timeSaved: 0, swedishShare: 0.335, englishShare: 0.665)
        let split = StatsFormatter.languagePercents(stats)
        #expect(split?.swedish == 34)
        #expect(split?.english == 66)
    }

    @Test func noLanguagePercentsWhenNoLanguageIsKnown() {
        #expect(StatsFormatter.languagePercents(DictationStats(words: 5, timeSaved: 0,
                                                               swedishShare: 0, englishShare: 0)) == nil)
    }
}
