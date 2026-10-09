public enum DictationFailure: Equatable, Sendable {
    case noSpeech
    case secureInput
    case audio(String)
    case transcription(String)
    case injection(String)
    case noSelection
    case editUnavailable
    case selectionTooLong
    case editFailed

    /// Short text for the HUD.
    public var message: String {
        switch self {
        case .noSpeech: "No speech detected"
        case .secureInput: "Can't type here"
        case .audio: "Microphone unavailable"
        case .transcription: "Couldn't transcribe"
        case .injection: "Couldn't insert text"
        case .noSelection: "Select text first"
        case .editUnavailable: "Command mode needs Apple Intelligence"
        case .selectionTooLong: "Selection too long"
        case .editFailed: "Couldn't edit — try again"
        }
    }
}
