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
    /// Narrowed eyes, 0…1 (anger, suspicion, smugness): a flat upper lid comes down.
    var squint: CGFloat = 0
    /// Uneven brows: positive raises his right brow and lowers his left (a question).
    var browTilt: CGFloat = 0
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
        // Follow the pointer, except while a trick or a face has its own way of looking.
        let acting = mood == .idle && (trick(at: t) != nil || expression(at: t) != nil)
        if let pointer, !pose.sleeping, !acting {
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
            // Faces now and then: angry, happy, questioning, pondering, surprised, smug.
            if trick(at: t) == nil, let (expression, progress) = expression(at: t) {
                pose = expressionPose(expression, progress: progress, base: pose)
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
                // A steady rhythm; the voice sets only the height (a voice-driven speed would jump
                // about, since `t` is a huge number of seconds).
                pose.bounce = -min(maxBounce, (2 + 9 * e) * CGFloat(abs(sin(t * 6.5))))
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
        case spin, nap, cartwheel, dance, trampoline, peekaboo, jelly, moonwalk, dizzy, hiccup

        var duration: Double {
            switch self {
            case .spin: 1.8
            case .nap: 6
            case .cartwheel: 1.6
            case .dance: 3.2
            case .trampoline: 2.6
            case .peekaboo: 3.4
            case .jelly: 2.2
            case .moonwalk: 3.4
            case .dizzy: 3
            case .hiccup: 2.4
            }
        }
    }

    static let trickSlot: Double = 40

    /// The trick under way at `t`, if any, and how far through it is (0…1). Each 45-second slot
    /// usually holds one, picked and placed irregularly (never in its first 8 seconds).
    static func trick(at t: Double) -> (trick: Trick, progress: Double)? {
        let slot = (t / trickSlot).rounded(.down)
        guard Seed.hash(slot + 0.17) < 0.9 else { return nil }
        let trick = Trick.allCases[Int(Seed.hash(slot + 0.71) * Double(Trick.allCases.count))]
        let start = slot * trickSlot + 8 + Seed.hash(slot + 0.37) * 24
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
        case .peekaboo:
            // Sinks out of sight through the floor, peeks out looking around, pops back up.
            if p < 0.25 {
                pose.bounce = 90 * CGFloat(ease(p / 0.25))
            } else if p < 0.4 {
                pose.bounce = 90
            } else if p < 0.5 {
                pose.bounce = 90 - 35 * CGFloat(ease((p - 0.4) / 0.1))
            } else if p < 0.8 {
                pose.bounce = 55
                pose.look = CGPoint(x: 0.85 * sin(2 * .pi * (p - 0.5) / 0.3), y: 0.1)
                pose.brow = 0.7
            } else {
                let q = (p - 0.8) / 0.2
                pose.bounce = 55 * CGFloat(1 - ease(q)) - 8 * CGFloat(sin(.pi * q))
                pose.happy = q > 0.5
                pose.brow = 0.8
            }
        case .jelly:
            // Wobbles like jelly: squash, stretch, settling.
            pose.squash = 1 + 0.15 * CGFloat((1 - 0.6 * p) * sin(5 * .pi * p))
            pose.brow = 0.4
            pose.eyeOpen = 1.1
        case .moonwalk:
            // Glides back to one side, leaning back, and returns — looking where he's going.
            pose.shiftX = -24 * CGFloat(envelope)
            pose.tilt = 6 * envelope
            pose.bounce = -1.5 * CGFloat(abs(sin(10 * .pi * p)) * envelope)
            pose.look = CGPoint(x: p < 0.5 ? -0.7 : 0.7, y: 0.1)
            pose.brow = 0.5
        case .dizzy:
            // Two quick flips, then a woozy wobble with his eyes rolling round.
            if p < 0.4 {
                let q = p / 0.4
                pose.spin = 720 * ease(q)
                pose.bounce = -9 * CGFloat(sin(.pi * q))
            } else {
                let q = (p - 0.4) / 0.6
                pose.spin = 720
                pose.tilt = 10 * sin(12 * q) * (1 - q)
                pose.look = CGPoint(x: 0.8 * cos(15 * q), y: 0.8 * sin(15 * q))
                pose.squint = 0.3 * CGFloat(1 - q)
                pose.brow = -0.2
            }
        case .hiccup:
            // Three sudden little jumps, wide-eyed each time.
            pose.brow = 0.2
            for centre in [0.2, 0.5, 0.8] where abs(p - centre) < 0.1 {
                pose.eyeOpen = 1.25
                pose.brow = 1
                if abs(p - centre) < 0.04 { pose.bounce = -6 * CGFloat(sin(.pi * (p - centre + 0.04) / 0.08)) }
            }
        }
        return pose
    }

    /// Idle faces.
    enum Expression: CaseIterable, Hashable {
        case angry, happy, questioning, pondering, surprised, smug
    }

    static let expressionSlot: Double = 6
    static let expressionDuration: Double = 1.8

    /// The face being pulled at `t`, if any: most 6-second slots hold one for 1.8 s.
    static func expression(at t: Double) -> (expression: Expression, progress: Double)? {
        let slot = (t / expressionSlot).rounded(.down)
        guard Seed.hash(slot + 0.83) < 0.6 else { return nil }
        let start = slot * expressionSlot + 0.5 + Seed.hash(slot + 0.91) * 3.5
        let local = t - start
        guard local >= 0, local < expressionDuration else { return nil }
        let expression = Expression.allCases[Int(Seed.hash(slot + 0.61) * Double(Expression.allCases.count))]
        return (expression, local / expressionDuration)
    }

    /// `base` with a face pulled over it, eased in and out.
    static func expressionPose(_ expression: Expression, progress p: Double, base: ClippyPose) -> ClippyPose {
        var pose = base
        let k = CGFloat(max(0, min(1, p / 0.15, (1 - p) / 0.15)))
        func blend(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * k }
        func towards(_ look: CGPoint) -> CGPoint {
            CGPoint(x: blend(base.look.x, look.x), y: blend(base.look.y, look.y))
        }
        switch expression {
        case .angry:
            pose.squint = blend(0, 0.55)
            pose.brow = blend(base.brow, -0.85)
            pose.look = towards(CGPoint(x: 0, y: 0.2))
        case .happy:
            pose.happy = k > 0.5
            pose.brow = blend(base.brow, 0.5)
        case .questioning:
            pose.browTilt = blend(0, 0.85)
            pose.brow = blend(base.brow, 0.3)
            pose.tilt = base.tilt + 6 * Double(k)
            pose.look = towards(CGPoint(x: 0.3, y: -0.1))
        case .pondering:
            pose.look = towards(CGPoint(x: -0.6, y: -0.65))
            pose.browTilt = blend(0, -0.5)
            pose.squint = blend(0, 0.25)
            pose.tilt = base.tilt - 4 * Double(k)
        case .surprised:
            pose.eyeOpen = blend(base.eyeOpen, 1.25)
            pose.brow = blend(base.brow, 1)
        case .smug:
            pose.squint = blend(0, 0.45)
            pose.browTilt = blend(0, 0.6)
            pose.brow = blend(base.brow, 0.1)
            pose.look = towards(CGPoint(x: 0.5, y: 0.1))
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
