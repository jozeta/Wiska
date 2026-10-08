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
