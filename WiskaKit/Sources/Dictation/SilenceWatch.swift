import Foundation

/// Decides when a hands-free dictation has been quiet long enough to finish.
/// Fed the microphone's 0…1 levels with their times; speech resets the clock.
struct SilenceWatch {
    /// ≈ −35 dBFS on `Levels.normalized`: quieter than speech, louder than a quiet room.
    static let speechThreshold: Float = 0.3

    private let timeout: TimeInterval
    private var quietSince: TimeInterval?
    private var reported = false

    /// `timeout` ≤ 0 means never.
    init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    /// True exactly once: when the level has stayed below the threshold for `timeout`.
    mutating func feed(level: Float, time: TimeInterval) -> Bool {
        guard timeout > 0, !reported else { return false }
        guard level < Self.speechThreshold else {
            quietSince = nil
            return false
        }
        let since = quietSince ?? time
        quietSince = since
        guard time - since >= timeout else { return false }
        reported = true
        return true
    }
}
