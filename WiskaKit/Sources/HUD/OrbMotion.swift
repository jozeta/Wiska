import CoreGraphics
import Foundation

/// The orb's look at one moment, from the mood and the smoothed voice energy (0…1).
struct OrbPose: Equatable {
    /// The core's radius as a multiple of its resting size.
    var coreScale: CGFloat
    /// Glow strength 0…1.
    var glow: CGFloat
    /// How far the aura ring ripples (fraction of its radius).
    var ripple: CGFloat
    /// The processing arcs' opacity (0 = not shown).
    var spinOpacity: CGFloat
    var particleOpacity: CGFloat
    /// Particle orbit speed multiplier.
    var particleSpeed: CGFloat
    var isError: Bool
}

/// Pure timing for the orb, so its behaviour is testable without drawing.
enum OrbMotion {
    /// The core's resting radius as a share of the window side.
    static let coreShare: CGFloat = 0.16
    static let maxCoreScale: CGFloat = 1.3
    /// The glow reaches this many core radii at full strength.
    static let glowReach: CGFloat = 2.35

    static func pose(at t: Double, mood: Presence.Mood, energy: CGFloat, reduceMotion: Bool) -> OrbPose {
        let e = min(1, max(0, energy))
        let breath = reduceMotion ? 0 : CGFloat(sin(t * 1.3))
        switch mood {
        case .idle, .message:
            return OrbPose(coreScale: 1 + 0.025 * breath, glow: 0.38 + 0.06 * breath, ripple: 0,
                           spinOpacity: 0, particleOpacity: reduceMotion ? 0 : 0.3, particleSpeed: 0.4,
                           isError: false)
        case .listening(let command):
            // A gentle pulse even in silence, then the voice drives size, glow and ripple.
            let pulse = reduceMotion ? 0 : CGFloat(sin(t * 3.2)) * (0.02 + 0.03 * e)
            return OrbPose(coreScale: min(maxCoreScale, 1.04 + 0.24 * e + pulse),
                           glow: min(1, 0.5 + (command ? 0.1 : 0) + 0.45 * e),
                           ripple: reduceMotion ? 0 : 0.03 + 0.09 * e,
                           spinOpacity: 0, particleOpacity: reduceMotion ? 0 : 0.35 + 0.6 * e,
                           particleSpeed: 0.7 + 2.2 * e, isError: false)
        case .working:
            return OrbPose(coreScale: 1 + 0.03 * breath, glow: 0.55 + 0.08 * CGFloat(sin(t * 2.4)),
                           ripple: 0, spinOpacity: 0.85, particleOpacity: reduceMotion ? 0 : 0.45,
                           particleSpeed: 1.6, isError: false)
        case .success:
            return OrbPose(coreScale: 1.1, glow: 0.95, ripple: 0, spinOpacity: 0,
                           particleOpacity: reduceMotion ? 0 : 0.8, particleSpeed: 2.4, isError: false)
        case .error:
            return OrbPose(coreScale: 1, glow: 0.6, ripple: 0, spinOpacity: 0,
                           particleOpacity: 0, particleSpeed: 0, isError: true)
        }
    }

    /// How far the drawing reaches from the centre, for a window `side` points wide.
    static func outerRadius(_ pose: OrbPose, side: CGFloat) -> CGFloat {
        let core = side * coreShare * pose.coreScale
        return core * glowReach * (0.85 + 0.15 * pose.glow)
    }
}
