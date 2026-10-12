import Core
import CoreGraphics
import Observation

/// What the dictation UI shows right now; every theme presents the same value.
public enum HUDContent: Equatable, Sendable {
    case hidden
    /// `isCommand`: an fn+⌃ instruction (the badge then says Edit / Write / Command).
    case listening(audio: AudioLevel, badge: String, preview: String, handsFree: Bool, isCommand: Bool = false)
    case working(String, activity: WorkActivity = .transcribing)
    case message(String)
    /// A failure, shown in the danger colour.
    case error(String)
}

/// What a `.working` dictation is busy with.
public enum WorkActivity: Sendable, Equatable {
    case transcribing, editing, writing, preparing
}

@MainActor @Observable
final class HUDModel {
    var content: HUDContent = .hidden
    var insetTop: CGFloat = 0
    var hasNotch = false
    var highlight: Highlight = .aurora
    /// 0 = tucked into the notch, 1 = fully down. Animated by the panel controller.
    var reveal: CGFloat = 0
    /// The preview row is showing (from the first words until the capsule hides).
    var expanded = false
}
