import Core
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
    /// The mood last reported by `takeMoodChange`, i.e. the one the view last drew.
    private var reported: Mood = .idle

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

    /// True once each time the mood differs from the last one reported — including a celebration
    /// that ran out on its own. Views redraw (and pick their frame rate) only when this says so.
    func takeMoodChange(at now: Date = Date()) -> Bool {
        let mood = mood(at: now)
        guard mood != reported else { return false }
        reported = mood
        return true
    }

    /// The microphone frame to animate with (silent unless listening).
    var audio: AudioLevel {
        if case .listening(let audio, _, _, _, _) = content { return audio }
        return .silent
    }

    var level: Float { audio.level }
}
