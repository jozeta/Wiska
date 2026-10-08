/// What was in front of the user when they started dictating, and what cleanup needs to know
/// about the dictation's language.
public struct DictationContext: Sendable, Equatable {
    public var appBundleID: String?
    /// The language the transcript is in, when the engine knows it.
    public var language: Language?
    /// The user's ticked languages: their rules apply when `language` is unknown.
    public var enabledLanguages: [Language]

    public init(appBundleID: String? = nil, language: Language? = nil,
                enabledLanguages: [Language] = [.english, .swedish]) {
        self.appBundleID = appBundleID
        self.language = language
        self.enabledLanguages = enabledLanguages
    }
}
