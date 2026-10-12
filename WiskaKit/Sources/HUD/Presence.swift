import Foundation

/// The mood a character-like theme (the orb, Clippy) shows, read from the same `HUDContent`
/// every theme gets — not a state machine of its own. The one thing it adds is memory of the
/// previous content: work that ends (working → hidden) is a success, shown briefly.
@MainActor
final class Presence {
    enum Mood: Equatable {
        case idle
        case listening(command: Bool)
        case working(WorkActivity)
        case success
        case error
        case message
    }

    static let successDuration: TimeInterval = 0.9

    private(set) var content: HUDContent = .hidden
    private var successUntil = Date.distantPast

    func update(_ content: HUDContent, at now: Date = Date()) {
        if case .working = self.content, content == .hidden { successUntil = now + Self.successDuration }
        if content != .hidden { successUntil = .distantPast }
        self.content = content
    }

    func mood(at now: Date = Date()) -> Mood {
        switch content {
        case .hidden: now < successUntil ? .success : .idle
        case .listening(_, _, _, _, let isCommand): .listening(command: isCommand)
        case .working(_, let activity): .working(activity)
        case .message: .message
        case .error: .error
        }
    }

    /// The microphone loudness to animate with (silent unless listening).
    var level: Float {
        if case .listening(let audio, _, _, _, _) = content { return audio.level }
        return 0
    }
}
