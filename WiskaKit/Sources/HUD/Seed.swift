import Foundation

/// Irregular but repeatable numbers for animation timing (a blink, a lightning flicker):
/// the same input always gives the same fraction, so nothing is random per frame.
enum Seed {
    /// A fraction 0…1.
    static func hash(_ n: Double) -> Double {
        let x = sin(n * 12.9898 + 78.233) * 43_758.5453
        return x - x.rounded(.down)
    }
}
