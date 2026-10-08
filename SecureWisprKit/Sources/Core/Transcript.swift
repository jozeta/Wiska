import Foundation

public struct Transcript: Sendable, Equatable {
    public var text: String
    public var locale: Locale
    public var confidence: Double?
    public var language: Language?

    public init(text: String, locale: Locale, confidence: Double? = nil, language: Language? = nil) {
        self.text = text
        self.locale = locale
        self.confidence = confidence
        self.language = language
    }
}
