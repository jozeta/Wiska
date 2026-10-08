import Core
import Foundation

/// Weekly numbers computed from history; nothing extra is stored.
public struct DictationStats: Equatable, Sendable {
    public static let typingWordsPerMinute = 40.0
    public static let window: TimeInterval = 7 * 86_400

    public var words: Int
    public var timeSaved: TimeInterval
    /// Each language's share of the words whose language is known (0…1). Absent = none.
    public var shares: [Language: Double]

    public init(words: Int, timeSaved: TimeInterval, shares: [Language: Double]) {
        self.words = words
        self.timeSaved = timeSaved
        self.shares = shares
    }

    public static func compute(_ records: [DictationRecord], now: Date,
                               window: TimeInterval = DictationStats.window) -> DictationStats {
        let recent = records.filter { $0.pasted && $0.date >= now.addingTimeInterval(-window) }
        func count(_ r: DictationRecord) -> Int { r.finalText.split(whereSeparator: \.isWhitespace).count }
        let words = recent.reduce(0) { $0 + count($1) }
        let spoken = recent.reduce(0) { $0 + $1.duration }
        let typing = Double(words) / typingWordsPerMinute * 60
        var perLanguage: [Language: Int] = [:]
        for record in recent {
            if let language = record.language { perLanguage[language, default: 0] += count(record) }
        }
        let known = perLanguage.values.reduce(0, +)
        let shares = known == 0 ? [:] : perLanguage.filter { $0.value > 0 }.mapValues { Double($0) / Double(known) }
        return DictationStats(words: words, timeSaved: max(0, typing - spoken), shares: shares)
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

    /// Whole percentages that add up to 100 (largest remainders get the leftover points), largest
    /// first, without languages that round to 0%. Empty when no dictation had a known language.
    public static func languagePercents(_ stats: DictationStats) -> [(language: Language, percent: Int)] {
        let entries = Language.allCases.compactMap { language in stats.shares[language].map { (language, $0 * 100) } }
        guard !entries.isEmpty else { return [] }
        var percents = entries.map { (language: $0.0, percent: Int($0.1.rounded(.down)), remainder: $0.1 - $0.1.rounded(.down)) }
        var leftover = 100 - percents.reduce(0) { $0 + $1.percent }
        for index in percents.indices.sorted(by: { percents[$0].remainder > percents[$1].remainder }) where leftover > 0 {
            percents[index].percent += 1
            leftover -= 1
        }
        // Ties keep display order (`percents` is built in `Language.allCases` order).
        return percents.enumerated().filter { $0.element.percent > 0 }
            .sorted { $0.element.percent != $1.element.percent ? $0.element.percent > $1.element.percent
                                                               : $0.offset < $1.offset }
            .map { (language: $0.element.language, percent: $0.element.percent) }
    }

    public static func savedText(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "< 1 min" : "\(Int((seconds / 60).rounded())) min"
    }
}
