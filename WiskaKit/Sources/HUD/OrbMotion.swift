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
    var isError: Bool
}

/// Pure timing for the orb, so its behaviour is testable without drawing.
enum OrbMotion {
    /// The fireball's resting radius, as a share of half the window.
    static let fireRadius: CGFloat = 0.28
    /// How far the flame tongues lick past the fire's edge (share of its radius, as in the shader).
    static let tongueReach: CGFloat = 0.15
    static let maxCoreScale: CGFloat = 1.4

    static func pose(at t: Double, mood: Presence.Mood, energy: CGFloat, reduceMotion: Bool) -> OrbPose {
        let e = min(1, max(0, energy))
        // A calm breath, about one every five seconds.
        let breath = reduceMotion ? 0 : CGFloat(sin(t * 1.2))
        let moving: Double = reduceMotion ? 0 : 1
        switch mood {
        case .idle, .message:
            return OrbPose(coreScale: 1 + 0.1 * breath, glow: 0.35 + 0.15 * breath,
                           intensity: 0.3 + 0.12 * breath, flameSpeed: 0.25 * moving, ripple: 0, isError: false)
        case .listening(let command):
            // The voice feeds the fire hard: much bigger, brighter and livelier, its edge pushed out
            // per pitch band.
            return OrbPose(coreScale: min(maxCoreScale, 1.03 + 0.33 * e),
                           glow: min(1, 0.45 + (command ? 0.1 : 0) + 0.55 * e),
                           intensity: min(1, 0.4 + (command ? 0.05 : 0) + 0.6 * e),
                           flameSpeed: moving * (0.25 + 0.45 * Double(e)), ripple: 0.1 + 0.35 * e, isError: false)
        case .working:
            // Busy: the flames roar and the glow swells, pulsing a little.
            let surge = reduceMotion ? 0 : CGFloat(sin(t * 2.2))
            return OrbPose(coreScale: 1.08 + 0.03 * surge, glow: 0.85 + 0.05 * surge,
                           intensity: 0.85 + 0.08 * surge, flameSpeed: 0.65 * moving, ripple: 0.06, isError: false)
        case .success:
            return OrbPose(coreScale: 1.14, glow: 1, intensity: 1, flameSpeed: 0.7 * moving, ripple: 0.06,
                           isError: false)
        case .error:
            return OrbPose(coreScale: 1, glow: 0.6, intensity: 0.6, flameSpeed: 0.25 * moving, ripple: 0,
                           isError: true)
        }
    }

    /// The farthest the flames' ragged edge reaches, as a share of half the window (matches the shader).
    static func fireEdge(_ pose: OrbPose) -> CGFloat {
        fireRadius * pose.coreScale * (0.95 + 0.35 + tongueReach + pose.ripple)
    }
}
