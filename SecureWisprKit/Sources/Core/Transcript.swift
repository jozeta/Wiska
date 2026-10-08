import Foundation

/// Which language a dictation should be transcribed in. M2 adds Swedish and auto-detect.
public enum LanguageChoice: Sendable, Equatable {
    case english
}

public struct Transcript: Sendable, Equatable {
    public var text: String
    public var locale: Locale
    public var confidence: Double?

    public init(text: String, locale: Locale, confidence: Double? = nil) {
        self.text = text
        self.locale = locale
        self.confidence = confidence
    }
}
