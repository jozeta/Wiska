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
    /// Chance (0…1) that each lightning bolt shows in a given flicker.
    var boltChance: Double
    /// How many bolts can crackle at once.
    var maxBolts: Int
    /// The tilted rings' opacity and turning speed (radians per second; 0 = still).
    var ringOpacity: CGFloat
    var ringSpeed: Double
    var isError: Bool
}

/// Pure timing for the orb, so its behaviour is testable without drawing.
enum OrbMotion {
    /// The core's resting radius as a share of the window side.
    static let coreShare: CGFloat = 0.16
    static let maxCoreScale: CGFloat = 1.3
    /// The glow reaches this many core radii at full strength.
    static let glowReach: CGFloat = 2.35
    /// The aura's resting radius, in core radii.
    static let auraRadius: CGFloat = 1.32
    /// The tilted rings' radius, in core radii.
    static let ringRadius: CGFloat = 1.5
    /// Lightning reaches at most this many core radii (bolt end plus its jitter).
    static let boltReach: CGFloat = 2.1

    static func pose(at t: Double, mood: Presence.Mood, energy: CGFloat, reduceMotion: Bool) -> OrbPose {
        let e = min(1, max(0, energy))
        // A slow breath, about one every ten seconds.
        let breath = reduceMotion ? 0 : CGFloat(sin(t * 0.6))
        let calm: Double = reduceMotion ? 0 : 1
        switch mood {
        case .idle, .message:
            return OrbPose(coreScale: 1 + 0.04 * breath, glow: 0.38 + 0.08 * breath, ripple: reduceMotion ? 0 : 0.025,
                           spinOpacity: 0, particleOpacity: reduceMotion ? 0 : 0.28, particleSpeed: 0.25,
                           boltChance: 0, maxBolts: 0, ringOpacity: 0.35, ringSpeed: 0.25 * calm, isError: false)
        case .listening(let command):
            // The voice drives size, glow, the aura's shape (per pitch band), sparks and lightning.
            let pulse = reduceMotion ? 0 : CGFloat(sin(t * 1.6)) * 0.02
            return OrbPose(coreScale: min(maxCoreScale, 1.04 + 0.24 * e + pulse),
                           glow: min(1, 0.5 + (command ? 0.1 : 0) + 0.45 * e),
                           ripple: reduceMotion ? 0 : 0.04 + 0.24 * e,
                           spinOpacity: 0, particleOpacity: reduceMotion ? 0 : 0.35 + 0.6 * e,
                           particleSpeed: 0.35 + 1.0 * e,
                           boltChance: calm * (0.08 + 0.5 * Double(e)), maxBolts: 1 + Int((2 * e).rounded()),
                           ringOpacity: 0.45 + 0.5 * e, ringSpeed: calm * (0.4 + 1.2 * Double(e)), isError: false)
        case .working:
            return OrbPose(coreScale: 1 + 0.03 * breath, glow: 0.55 + 0.06 * CGFloat(sin(t * 1.2)),
                           ripple: reduceMotion ? 0 : 0.04, spinOpacity: 0.85,
                           particleOpacity: reduceMotion ? 0 : 0.45, particleSpeed: 0.6,
                           boltChance: 0.08 * calm, maxBolts: 1, ringOpacity: 0.6, ringSpeed: 0.8 * calm,
                           isError: false)
        case .success:
            return OrbPose(coreScale: 1.1, glow: 0.95, ripple: reduceMotion ? 0 : 0.06, spinOpacity: 0,
                           particleOpacity: reduceMotion ? 0 : 0.8, particleSpeed: 1.2,
                           boltChance: 0.6 * calm, maxBolts: 3, ringOpacity: 0.9, ringSpeed: 1.5 * calm,
                           isError: false)
        case .error:
            return OrbPose(coreScale: 1, glow: 0.6, ripple: 0, spinOpacity: 0,
                           particleOpacity: 0, particleSpeed: 0, boltChance: 0, maxBolts: 0,
                           ringOpacity: 0.3, ringSpeed: 0, isError: true)
        }
    }

    /// How far the glow reaches from the centre, for a window `side` points wide.
    static func outerRadius(_ pose: OrbPose, side: CGFloat) -> CGFloat {
        let core = side * coreShare * pose.coreScale
        return core * glowReach * (0.85 + 0.15 * pose.glow)
    }

    /// The farthest anything is drawn (glow, rippling aura, rings, lightning).
    static func maxReach(_ pose: OrbPose, side: CGFloat) -> CGFloat {
        let core = side * coreShare * pose.coreScale
        return max(outerRadius(pose, side: side), core * auraRadius * (1 + pose.ripple), core * ringRadius,
                   pose.maxBolts > 0 ? core * boltReach : 0)
    }
}
