import CoreGraphics
import Foundation

/// Clippy's pose at one moment (design units: the paperclip is 60 × 100).
struct ClippyPose: Equatable {
    /// Lean in degrees, pivoting on the bottom of the clip.
    var tilt: Double
    /// Vertical offset; negative = up.
    var bounce: CGFloat
    /// Vertical stretch (1 = none), for flexing with speech.
    var squash: CGFloat
    /// Where the pupils point, −1…1 each way (y down).
    var look: CGPoint
    /// 1 = eyes open, 0 = closed (blink).
    var eyeOpen: CGFloat
    /// Eyebrows: 1 = raised high, 0 = neutral, −1 = knitted (frown).
    var brow: CGFloat
    /// Smiling eyes (^ ^).
    var happy: Bool
}

/// Pure timing for Clippy, so its behaviour is testable without drawing. Idle movement is
/// sparse and irregular (seeded, not random per frame): a blink every few seconds, a glance
/// now and then; dictation brings the voice-driven movement.
enum ClippyMotion {
    static let maxBounce: CGFloat = 11

    /// `pointer`: where the eyes should look instead (following the mouse), from `look(toward:from:)`.
    static func pose(at t: Double, mood: Presence.Mood, energy: CGFloat, reduceMotion: Bool,
                     pointer: CGPoint? = nil) -> ClippyPose {
        var pose = moodPose(at: t, mood: mood, energy: energy, reduceMotion: reduceMotion)
        if let pointer {
            pose.look = pointer
            // Turn a little toward it, too.
            if !reduceMotion { pose.tilt += Double(pointer.x) * 6 }
        }
        return pose
    }

    /// Pupil direction (−1…1, y down) for a pointer at `pointer`, seen from the eyes at `eyes`
    /// (screen coordinates, y up). Full turn beyond `reach` points; less when it's close by.
    static func look(toward pointer: CGPoint, from eyes: CGPoint, reach: CGFloat = 120) -> CGPoint {
        let dx = pointer.x - eyes.x, dy = pointer.y - eyes.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > 0.5 else { return .zero }
        let strength = min(1, distance / reach)
        return CGPoint(x: dx / distance * strength, y: -dy / distance * strength)
    }

    private static func moodPose(at t: Double, mood: Presence.Mood, energy: CGFloat, reduceMotion: Bool) -> ClippyPose {
        let e = min(1, max(0, energy))
        let blinking = isBlinking(at: t)
        var pose = ClippyPose(tilt: 0, bounce: 0, squash: 1, look: CGPoint(x: 0, y: 0.15),
                              eyeOpen: blinking ? 0.08 : 1, brow: 0, happy: false)
        switch mood {
        case .idle:
            let glance = glance(at: t)
            pose.look = glance
            pose.tilt = reduceMotion ? 0 : Double(glance.x) * 4
        case .message:
            pose.look = CGPoint(x: 0, y: 0.35)
            pose.brow = 0.4
        case .listening(let command):
            // Attentive: looking at you, brows up, bobbing and flexing with the voice.
            pose.look = CGPoint(x: 0, y: 0.35)
            pose.brow = command ? 0.95 : 0.35 + 0.35 * e
            if !reduceMotion {
                pose.bounce = -min(maxBounce, (2.5 + 8.5 * CGFloat(abs(sin(t * 7.5)))) * e)
                pose.squash = 1 - 0.05 * e * CGFloat(sin(t * 15))
                pose.tilt = 4 * Double(e) * sin(t * 4.3)
            }
        case .working(let activity):
            if activity == .editing {
                // Reading the text: eyes down, sweeping along a line, brows knitted.
                pose.look = CGPoint(x: reduceMotion ? 0 : 0.7 * sin(t * 1.6), y: 0.65)
                pose.brow = -0.3
                pose.tilt = reduceMotion ? 0 : -4
            } else {
                // Thinking: eyes rolling up and around.
                pose.look = reduceMotion ? CGPoint(x: 0.5, y: -0.6)
                    : CGPoint(x: 0.75 * cos(t * 2.4), y: -0.4 - 0.4 * abs(sin(t * 2.4)))
                pose.brow = 0.15
                if !reduceMotion { pose.tilt = 5 * sin(t * 1.7) }
            }
        case .success:
            pose.happy = true
            pose.eyeOpen = 1
            pose.brow = 0.6
            if !reduceMotion { pose.bounce = -7 * CGFloat(abs(sin(t * 6))) }
        case .error:
            pose.brow = -0.9
            pose.look = CGPoint(x: 0, y: 0.2)
            if !reduceMotion { pose.tilt = 3 * sin(t * 16) }
        }
        return pose
    }

    static func hash(_ n: Double) -> Double { Seed.hash(n) }

    /// One blink in every 4-second slot, somewhere in its first 2.6 s.
    static func isBlinking(at t: Double) -> Bool {
        let slot = (t / 4).rounded(.down)
        let at = slot * 4 + hash(slot) * 2.6
        return t >= at && t < at + 0.13
    }

    /// Every 9-second slot may hold one 1.6 s glance to a side, eased in and out.
    static func glance(at t: Double) -> CGPoint {
        let slot = (t / 9).rounded(.down)
        let pick = hash(slot + 0.5)
        guard pick < 0.75 else { return CGPoint(x: 0, y: 0.15) }
        let start = slot * 9 + 2 + hash(slot + 0.25) * 5
        let local = t - start
        guard local > 0, local < 1.6 else { return CGPoint(x: 0, y: 0.15) }
        let ease = min(1, local / 0.25, (1.6 - local) / 0.25)
        let side: CGFloat = pick < 0.375 ? -0.8 : 0.8
        return CGPoint(x: side * CGFloat(ease), y: 0.15 - 0.25 * CGFloat(ease) * CGFloat(hash(slot)))
    }
}

/// Where Clippy's speech bubble goes: above the character when there's room, else below;
/// slid sideways to stay on screen, its tail still pointing at the character.
enum BubblePlacement {
    static let gap: CGFloat = 2
    /// The tail never sits closer than this to the bubble's side.
    static let tailInset: CGFloat = 22

    struct Result: Equatable {
        var frame: CGRect
        var above: Bool
        /// The tail's x inside the bubble.
        var tailX: CGFloat
    }

    static func place(bubble: CGSize, character: CGRect, screen: CGRect) -> Result {
        let aboveY = character.maxY + gap
        let belowY = character.minY - gap - bubble.height
        let above = aboveY + bubble.height <= screen.maxY || belowY < screen.minY
        var y = above ? aboveY : belowY
        y = max(screen.minY, min(y, screen.maxY - bubble.height))
        var x = character.midX - bubble.width / 2
        x = max(screen.minX, min(x, screen.maxX - bubble.width))
        let tail = max(tailInset, min(character.midX - x, bubble.width - tailInset))
        return Result(frame: CGRect(x: x, y: y, width: bubble.width, height: bubble.height), above: above, tailX: tail)
    }
}
