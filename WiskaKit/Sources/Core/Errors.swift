public enum AudioError: Error, Equatable {
    case noInputDevice
    case unsupportedFormat
    case engineFailed(String)
}

public enum TranscriptionError: Error, Equatable {
    case unsupportedLocale(String)
    case noCompatibleAudioFormat
}

public enum InjectionError: Error, Equatable {
    case secureInputActive
    case eventCreationFailed
}
