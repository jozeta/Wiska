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
    /// Sideways offset in design units (a shimmy, or making room to lie down).
    var shiftX: CGFloat = 0
    /// Turning round on the spot: 1 = facing you, −1 = his back (a horizontal squeeze in between).
    var turn: CGFloat = 1
    /// Rotation in degrees around the clip's middle (a cartwheel).
    var spin: Double = 0
    /// Napping: eyes shut, a few "z"s float up.
    var sleeping = false
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
        if let pointer, !pose.sleeping {
            pose.look = pointer
            // Turn a little toward it, too (not in the middle of a trick).
            let tricking = mood == .idle && trick(at: t) != nil
            if !reduceMotion && !tricking { pose.tilt += Double(pointer.x) * 6 }
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
            if !reduceMotion {
                if let (trick, progress) = trick(at: t) {
                    var trickPose = trickPose(trick, progress: progress, at: t)
                    if !trickPose.sleeping && !trickPose.happy { trickPose.eyeOpen = pose.eyeOpen }   // still blinks
                    return trickPose
                }
                // Never quite still: a gentle sway and breath, plus frequent small fidgets.
                let fidget = fidget(at: t)
                let sway = 1.8 * sin(t * 0.8)
                pose.tilt = max(-8, min(8, sway + Double(glance.x) * 4 + fidget.tilt))
                pose.bounce = fidget.bounce
                pose.squash = fidget.squash + 0.012 * CGFloat(sin(t * 1.7))
                pose.brow = fidget.brow
            }
        case .message:
            pose.look = CGPoint(x: 0, y: 0.35)
            pose.brow = 0.4
        case .listening(let command):
            // Happy to help: looking at you, brows up, bobbing and swaying even before you speak,
            // bouncing with the voice, and a happy squint now and then.
            pose.look = CGPoint(x: 0, y: 0.35)
            pose.brow = command ? 0.95 : 0.5 + 0.4 * e
            pose.happy = isBeaming(at: t)
            if !reduceMotion {
                pose.bounce = -min(maxBounce, (2 + 9 * e) * CGFloat(abs(sin(t * (5 + 3 * Double(e))))))
                pose.squash = 1 - 0.05 * e * CGFloat(sin(t * 15))
                pose.tilt = 5 * sin(t * 2.6) + 4 * Double(e) * sin(t * 4.3)
                pose.shiftX = 2.5 * CGFloat(sin(t * 1.9))
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

    /// Listening: a happy squint for half a second in most 3-second stretches.
    static func isBeaming(at t: Double) -> Bool {
        let slot = (t / 3).rounded(.down)
        guard Seed.hash(slot + 0.13) < 0.7 else { return false }
        let at = slot * 3 + 0.4 + Seed.hash(slot + 0.29) * 2
        return t >= at && t < at + 0.5
    }

    /// The bigger idle tricks, about one a minute.
    enum Trick: CaseIterable, Hashable {
        case spin, nap, cartwheel, dance, trampoline

        var duration: Double {
            switch self {
            case .spin: 1.8
            case .nap: 6
            case .cartwheel: 1.6
            case .dance: 3.2
            case .trampoline: 2.6
            }
        }
    }

    static let trickSlot: Double = 45

    /// The trick under way at `t`, if any, and how far through it is (0…1). Each 45-second slot
    /// usually holds one, picked and placed irregularly (never in its first 8 seconds).
    static func trick(at t: Double) -> (trick: Trick, progress: Double)? {
        let slot = (t / trickSlot).rounded(.down)
        guard Seed.hash(slot + 0.17) < 0.85 else { return nil }
        let trick = Trick.allCases[Int(Seed.hash(slot + 0.71) * Double(Trick.allCases.count))]
        let start = slot * trickSlot + 8 + Seed.hash(slot + 0.37) * 25
        let local = t - start
        guard local >= 0, local < trick.duration else { return nil }
        return (trick, local / trick.duration)
    }

    /// Soft start and end.
    private static func ease(_ p: Double) -> Double { p * p * (3 - 2 * p) }

    static func trickPose(_ trick: Trick, progress p: Double, at t: Double) -> ClippyPose {
        var pose = ClippyPose(tilt: 0, bounce: 0, squash: 1, look: CGPoint(x: 0, y: 0.15), eyeOpen: 1,
                              brow: 0.3, happy: false)
        let envelope = sin(.pi * p)
        switch trick {
        case .spin:
            // A hop and a full turn on the spot: you see his back half-way.
            pose.turn = CGFloat(cos(2 * .pi * ease(p)))
            pose.bounce = -6 * CGFloat(envelope)
            pose.brow = 0.6
        case .nap:
            // Lies down on the floor, sleeps a bit, gets back up.
            let lying = p < 0.2 ? ease(p / 0.2) : p > 0.8 ? ease((1 - p) / 0.2) : 1
            pose.tilt = 88 * lying
            pose.shiftX = -48 * CGFloat(lying)
            pose.bounce = -11 * CGFloat(lying)
            pose.squash = 1 + 0.02 * CGFloat(sin(t * 2)) * CGFloat(lying)
            pose.eyeOpen = 1 - 0.92 * CGFloat(lying)
            pose.brow = 0.3 * (1 - CGFloat(lying))
            pose.sleeping = lying > 0.9
        case .cartwheel:
            pose.spin = 360 * ease(p)
            pose.bounce = -9 * CGFloat(envelope)
            pose.brow = 0.7
        case .dance:
            // A happy shimmy: side to side, leaning into it, little bounces.
            pose.shiftX = 7.5 * CGFloat(sin(4 * .pi * p) * envelope)
            pose.tilt = -8 * sin(4 * .pi * p) * envelope
            pose.bounce = -2.5 * CGFloat(abs(sin(8 * .pi * p)) * envelope)
            pose.happy = p > 0.05 && p < 0.95
            pose.brow = 0.5 + 0.3 * CGFloat(sin(8 * .pi * p))
        case .trampoline:
            // Three bouncy hops, squashing on each landing.
            let height = abs(sin(3 * .pi * p))
            pose.bounce = -10 * CGFloat(height)
            pose.squash = 1 - 0.09 * CGFloat(pow(max(0, 1 - height * 3), 2))
            pose.happy = height > 0.6
            pose.brow = 0.8
        }
        return pose
    }

    enum Fidget: CaseIterable { case hop, twist, stretch, lean, browWiggle }

    /// Idle fidgets: most 4-second slots hold one small, short movement — a double hop, a
    /// twist side to side, a stretch, a lean, a wiggle of the brows — picked and timed irregularly.
    static func fidget(at t: Double) -> (bounce: CGFloat, tilt: Double, squash: CGFloat, brow: CGFloat) {
        let rest: (bounce: CGFloat, tilt: Double, squash: CGFloat, brow: CGFloat) = (0, 0, 1, 0)
        let slot = (t / 4).rounded(.down)
        guard Seed.hash(slot + 0.31) < 0.85 else { return rest }
        let duration = 1.4
        let local = t - (slot * 4 + 0.3 + Seed.hash(slot + 0.43) * 2.2)
        guard local > 0, local < duration else { return rest }
        let p = local / duration
        let envelope = sin(.pi * p)                              // eases in and out
        let kind = Fidget.allCases[Int(Seed.hash(slot + 0.57) * Double(Fidget.allCases.count))]
        let side: Double = Seed.hash(slot + 0.69) < 0.5 ? -1 : 1
        switch kind {
        case .hop: return (-3.5 * CGFloat(abs(sin(2 * .pi * p))), 0, 1 + 0.03 * CGFloat(envelope), 0)
        case .twist: return (0, 6 * sin(2 * .pi * p) * side, 1, 0)
        case .stretch: return (-1.2 * CGFloat(envelope), 0, 1 + 0.06 * CGFloat(envelope), 0.3 * CGFloat(envelope))
        case .lean: return (0, 5 * envelope * side, 1, 0.2 * CGFloat(envelope))
        case .browWiggle: return (0, 0, 1, 0.6 * CGFloat(sin(3 * .pi * p)))
        }
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
