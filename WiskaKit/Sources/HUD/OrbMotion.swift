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
    var particleOpacity: CGFloat
    /// Spark drift speed multiplier.
    var particleSpeed: CGFloat
    var isError: Bool
}

/// Pure timing for the orb, so its behaviour is testable without drawing.
enum OrbMotion {
    /// The fireball's resting radius, as a share of half the window.
    static let fireRadius: CGFloat = 0.34
    static let maxCoreScale: CGFloat = 1.3

    static func pose(at t: Double, mood: Presence.Mood, energy: CGFloat, reduceMotion: Bool) -> OrbPose {
        let e = min(1, max(0, energy))
        // A slow breath, about one every ten seconds.
        let breath = reduceMotion ? 0 : CGFloat(sin(t * 0.6))
        let moving: Double = reduceMotion ? 0 : 1
        switch mood {
        case .idle, .message:
            return OrbPose(coreScale: 1 + 0.04 * breath, glow: 0.35 + 0.08 * breath,
                           intensity: 0.3 + 0.06 * breath, flameSpeed: 0.12 * moving, ripple: 0,
                           particleOpacity: reduceMotion ? 0 : 0.3, particleSpeed: 0.25, isError: false)
        case .listening(let command):
            // The voice feeds the fire: bigger, brighter, faster, its edge pushed out per pitch band.
            return OrbPose(coreScale: min(maxCoreScale, 1.03 + 0.2 * e + 0.015 * breath),
                           glow: min(1, 0.5 + (command ? 0.1 : 0) + 0.45 * e),
                           intensity: min(1, 0.45 + (command ? 0.05 : 0) + 0.5 * e),
                           flameSpeed: moving * (0.3 + 0.7 * Double(e)), ripple: 0.08 + 0.3 * e,
                           particleOpacity: reduceMotion ? 0 : 0.35 + 0.55 * e, particleSpeed: 0.35 + 1.0 * e,
                           isError: false)
        case .working:
            // Busy: the flames roar and the glow swells, pulsing a little.
            let surge = reduceMotion ? 0 : CGFloat(sin(t * 2.2))
            return OrbPose(coreScale: 1.08 + 0.02 * surge, glow: 0.85 + 0.05 * surge,
                           intensity: 0.85 + 0.08 * surge, flameSpeed: 0.9 * moving, ripple: 0.06,
                           particleOpacity: reduceMotion ? 0 : 0.6, particleSpeed: 0.7, isError: false)
        case .success:
            return OrbPose(coreScale: 1.14, glow: 1, intensity: 1, flameSpeed: 1.1 * moving, ripple: 0.06,
                           particleOpacity: reduceMotion ? 0 : 0.85, particleSpeed: 1.2, isError: false)
        case .error:
            return OrbPose(coreScale: 1, glow: 0.6, intensity: 0.6, flameSpeed: 0.35 * moving, ripple: 0,
                           particleOpacity: 0, particleSpeed: 0, isError: true)
        }
    }

    /// The farthest the flames' ragged edge reaches, as a share of half the window (matches the shader).
    static func fireEdge(_ pose: OrbPose) -> CGFloat {
        fireRadius * pose.coreScale * (0.95 + 0.35 + pose.ripple)
    }
}
