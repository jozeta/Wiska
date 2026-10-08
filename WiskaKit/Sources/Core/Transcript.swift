import Foundation

public struct Transcript: Sendable, Equatable {
    public var text: String
    public var locale: Locale
    public var confidence: Double?
    public var language: Language?
    /// Which engine produced the text, when the session knows (hybrid sessions set it).
    public var engine: SpeechEngine?

    public init(text: String, locale: Locale, confidence: Double? = nil, language: Language? = nil,
                engine: SpeechEngine? = nil) {
        self.text = text
        self.locale = locale
        self.confidence = confidence
        self.language = language
        self.engine = engine
    }
}
