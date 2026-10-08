import Core
import CoreGraphics
import Observation

public enum HUDContent: Equatable, Sendable {
    case hidden
    case listening(levels: [Float], badge: String)
    case working(String)
    case message(String)
    /// A failure, shown in the danger colour.
    case error(String)
}

@MainActor @Observable
final class HUDModel {
    var content: HUDContent = .hidden
    var insetTop: CGFloat = 0
    var hasNotch = false
    var highlight: Highlight = .aurora
    /// 0 = tucked into the notch, 1 = fully down. Animated by the panel controller.
    var reveal: CGFloat = 0
}
