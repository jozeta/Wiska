import CoreGraphics
import Foundation

/// The orb's look at one moment, from the mood and the smoothed voice energy (0…1).
struct OrbPose: Equatable {
    /// The fireball's size as a multiple of its resting size.
    var coreScale: CGFloat
    /// The soft light around it, 0…1.
    var glow: CGFloat
    /// How fiercely the flames burn, 0…1.
    var intensity: CGFloat
    /// How fast the flames churn (shader time per second; 0 = still).
    var flameSpeed: Double
    /// How far the voice's pitch bands push the fire's edge (share of its radius).
    var ripple: CGFloat
    /// Wavy borders floating round the fire: how many, how far they undulate (share of their
    /// radius) and how fast (wave time per second).
    var waveCount: Int
    var waveAmplitude: CGFloat
    var waveSpeed: Double
    var isError: Bool
}

/// Pure timing for the orb, so its behaviour is testable without drawing.
enum OrbMotion {
    /// The fireball's resting radius, as a share of half the window.
    static let fireRadius: CGFloat = 0.26
    /// Where the shader starts fading the fire out (share of half the window); nothing passes 1.
    static let fadeStart: CGFloat = 0.82
    /// The wavy borders' radii, in fire radii.
    static func waveRadius(_ index: Int) -> CGFloat { 1.35 + 0.22 * CGFloat(index) }
    /// How far the flame tongues lick past the fire's edge (share of its radius, as in the shader).
    static let tongueReach: CGFloat = 0.15
    static let maxCoreScale: CGFloat = 1.45

    static func pose(at t: Double, mood: Presence.Mood, energy: CGFloat, reduceMotion: Bool) -> OrbPose {
        let e = min(1, max(0, energy))
        // A calm breath, about one every five seconds.
        let breath = reduceMotion ? 0 : CGFloat(sin(t * 1.2))
        let moving: Double = reduceMotion ? 0 : 1
        let waves = reduceMotion ? 0.0 : 1.0
        switch mood {
        case .idle, .message:
            return OrbPose(coreScale: 1 + 0.13 * breath, glow: 0.35 + 0.18 * breath,
                           intensity: 0.28 + 0.15 * breath, flameSpeed: 0.25 * moving, ripple: 0,
                           waveCount: 3, waveAmplitude: 0.06, waveSpeed: 0.3 * waves, isError: false)
        case .listening(let command):
            // The voice feeds the fire hard: much bigger and brighter, its tongues flaring and its
            // edge pushed out per pitch band; the wavy borders swell and quicken with it.
            return OrbPose(coreScale: min(maxCoreScale, 1.03 + 0.42 * e),
                           glow: min(1, 0.45 + (command ? 0.1 : 0) + 0.55 * e),
                           intensity: min(1, 0.35 + (command ? 0.05 : 0) + 0.65 * e),
                           flameSpeed: moving * (0.25 + 0.5 * Double(e)), ripple: 0.1 + 0.4 * e,
                           waveCount: 3, waveAmplitude: 0.06 + 0.22 * e, waveSpeed: waves * (0.3 + 0.9 * Double(e)),
                           isError: false)
        case .working:
            // Busy: the flames roar and the glow swells, pulsing a little.
            let surge = reduceMotion ? 0 : CGFloat(sin(t * 2.2))
            return OrbPose(coreScale: 1.08 + 0.03 * surge, glow: 0.85 + 0.05 * surge,
                           intensity: 0.85 + 0.08 * surge, flameSpeed: 0.65 * moving, ripple: 0.06,
                           waveCount: 3, waveAmplitude: 0.08, waveSpeed: 0.5 * waves, isError: false)
        case .success:
            return OrbPose(coreScale: 1.14, glow: 1, intensity: 1, flameSpeed: 0.7 * moving, ripple: 0.06,
                           waveCount: 3, waveAmplitude: 0.12, waveSpeed: 0.6 * waves, isError: false)
        case .error:
            return OrbPose(coreScale: 1, glow: 0.6, intensity: 0.6, flameSpeed: 0.25 * moving, ripple: 0,
                           waveCount: 2, waveAmplitude: 0.04, waveSpeed: 0.2 * waves, isError: true)
        }
    }

    /// The farthest the flames' ragged edge reaches, as a share of half the window (matches the shader).
    static func fireEdge(_ pose: OrbPose) -> CGFloat {
        fireRadius * pose.coreScale * (0.95 + 0.35 + tongueReach * (1 + 2 * pose.ripple) + pose.ripple)
    }

    /// How far the outermost wavy border reaches, as a share of half the window.
    static func waveReach(_ pose: OrbPose) -> CGFloat {
        guard pose.waveCount > 0 else { return 0 }
        return fireRadius * pose.coreScale * waveRadius(pose.waveCount - 1) * (1 + pose.waveAmplitude)
    }
}
