import CoreGraphics
import Observation

public enum HUDContent: Equatable, Sendable {
    case hidden
    case listening(levels: [Float], badge: String)
    case working(String)
    case message(String)
}

@MainActor @Observable
final class HUDModel {
    var content: HUDContent = .hidden
    var insetTop: CGFloat = 0
    var hasNotch = false
    /// Messages that are failures render in the danger colour.
    var isError = false
}
