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
