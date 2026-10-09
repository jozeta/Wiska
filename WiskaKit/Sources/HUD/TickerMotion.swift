import CoreGraphics

/// How far the live-preview line has scrolled, stepped every frame.
/// The line chases its target at a speed proportional to how far behind it is (so words
/// arriving at a steady pace scroll at an even speed), and the change in speed per second
/// is capped — the dampener that keeps it from jerking, lurching or stopping abruptly.
struct TickerMotion {
    /// Seconds to cover the remaining distance at the current pace: higher = calmer.
    static let timeConstant: CGFloat = 1.0
    static let maxSpeed: CGFloat = 220
    /// ≥ maxSpeed / timeConstant, so it can always slow down in time and never overshoots.
    static let maxAcceleration: CGFloat = 240

    private(set) var position: CGFloat = 0
    private(set) var velocity: CGFloat = 0

    func isSettled(at target: CGFloat) -> Bool {
        position == target && velocity == 0
    }

    /// Below this distance the line crawls in gently instead of creeping forever.
    static let crawlSpeed: CGFloat = 8

    mutating func step(toward target: CGFloat, dt: CGFloat) {
        guard dt > 0 else { return }
        let distance = target - position
        if abs(distance) < 0.25 && abs(velocity) < 1 {
            position = target
            velocity = 0
            return
        }
        let pace = max(abs(distance) / Self.timeConstant, min(Self.crawlSpeed, abs(distance) * 10))
        let desired = min(Self.maxSpeed, pace) * (distance < 0 ? -1 : 1)
        let maxChange = Self.maxAcceleration * dt
        velocity += max(-maxChange, min(maxChange, desired - velocity))
        let next = position + velocity * dt
        // Never pass the target: hold there while the (small) remaining speed fades.
        position = (target - next) * distance <= 0 ? target : next
    }

    /// Jump straight to a position (a new dictation starts at rest).
    mutating func reset(to value: CGFloat = 0) {
        position = value
        velocity = 0
    }
}
