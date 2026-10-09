public enum DictationFailure: Equatable, Sendable {
    case noSpeech
    case secureInput
    case audio(String)
    case transcription(String)
    case injection(String)
    case editUnavailable
    case selectionTooLong
    case editFailed
    case editRefused
    case writeFailed

    /// Short text for the HUD.
    public var message: String {
        switch self {
        case .noSpeech: "No speech detected"
        case .secureInput: "Can't type here"
        case .audio: "Microphone unavailable"
        case .transcription: "Couldn't transcribe"
        case .injection: "Couldn't insert text"
        case .editUnavailable: "Command mode needs Apple Intelligence"
        case .selectionTooLong: "Selection too long"
        case .editFailed: "Couldn't edit — try again"
        case .editRefused: "Apple Intelligence won't edit this text"
        case .writeFailed: "Couldn't write — try again"
        }
    }
}
