import Observation

public enum HUDContent: Equatable, Sendable {
    case hidden
    case listening(levels: [Float])
    case working(String)
    case message(String)
}

@MainActor @Observable
final class HUDModel {
    var content: HUDContent = .hidden
}
