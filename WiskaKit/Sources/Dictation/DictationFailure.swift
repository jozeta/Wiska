public enum DictationFailure: Equatable, Sendable {
    case noSpeech
    case secureInput
    case audio(String)
    case transcription(String)
    case injection(String)

    /// Short text for the HUD.
    public var message: String {
        switch self {
        case .noSpeech: "No speech detected"
        case .secureInput: "Can't type here"
        case .audio: "Microphone unavailable"
        case .transcription: "Couldn't transcribe"
        case .injection: "Couldn't insert text"
        }
    }
}
