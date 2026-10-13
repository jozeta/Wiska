import Foundation

/// How long dictation history is kept.
public enum HistoryRetention: String, Sendable, CaseIterable, Codable {
    case off
    case day
    case week
    case month
    case forever

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .day: "1 day"
        case .week: "7 days"
        case .month: "30 days"
        case .forever: "Forever"
        }
    }

    /// Entries older than this are deleted; nil keeps everything.
    public func cutoff(now: Date) -> Date? {
        switch self {
        case .off: now
        case .day: now.addingTimeInterval(-86_400)
        case .week: now.addingTimeInterval(-7 * 86_400)
        case .month: now.addingTimeInterval(-30 * 86_400)
        case .forever: nil
        }
    }
}

/// One finished dictation, as kept in history.
public struct DictationRecord: Sendable, Equatable {
    public var date: Date
    public var appBundleID: String?
    public var language: Language?
    public var engine: SpeechEngine
    public var rawText: String
    public var finalText: String
    /// False when pasting failed — kept so the text can be rescued.
    public var pasted: Bool
    /// Seconds of audio captured for this dictation.
    public var duration: TimeInterval
    /// Seconds from releasing fn to the text being pasted (0: not measured, or not pasted).
    public var latency: TimeInterval
    /// Seconds spent turning the audio into words, after fn was released (0: not measured).
    public var transcriptionTime: TimeInterval
    /// Seconds spent cleaning up the words (0: not measured).
    public var cleanupTime: TimeInterval

    public init(date: Date, appBundleID: String?, language: Language?, engine: SpeechEngine,
                rawText: String, finalText: String, pasted: Bool, duration: TimeInterval = 0,
                latency: TimeInterval = 0, transcriptionTime: TimeInterval = 0, cleanupTime: TimeInterval = 0) {
        self.date = date
        self.appBundleID = appBundleID
        self.language = language
        self.engine = engine
        self.rawText = rawText
        self.finalText = finalText
        self.pasted = pasted
        self.duration = duration
        self.latency = latency
        self.transcriptionTime = transcriptionTime
        self.cleanupTime = cleanupTime
    }
}
