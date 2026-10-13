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

    /// How fast one speech engine has been, as medians in seconds (typical, not thrown by one slow load).
    public struct EngineSpeed: Equatable, Sendable {
        public let engine: SpeechEngine
        public let dictations: Int
        /// Release of fn → text pasted.
        public let total: TimeInterval
        public let transcription: TimeInterval
        public let cleanup: TimeInterval
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
    /// Engines used in the period, most dictations first; only dictations whose speed was measured (1.2 and later).
    public var speed: [EngineSpeed] = []

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
            // Re-snap every step: where clocks change at midnight, adding a day lands on 01:00.
            guard let next = calendar.date(byAdding: report.bucketIsWeek ? .weekOfYear : .day, value: 1, to: cursor)
            else { break }
            cursor = bucketStart(next)
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

        let measured = Dictionary(grouping: included.filter { $0.latency > 0 }, by: \.engine)
        report.speed = measured.map { engine, records in
            EngineSpeed(engine: engine, dictations: records.count, total: median(records.map(\.latency)),
                        transcription: median(records.map(\.transcriptionTime)), cleanup: median(records.map(\.cleanupTime)))
        }
        .sorted { $0.dictations != $1.dictations ? $0.dictations > $1.dictations : $0.engine.rawValue < $1.engine.rawValue }
        return report
    }

    /// The middle value (the mean of the middle two for an even count); 0 when empty.
    static func median(_ values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
