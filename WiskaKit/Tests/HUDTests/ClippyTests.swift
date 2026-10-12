import CoreGraphics
import Testing
@testable import HUD

@MainActor
struct ClippyMotionTests {
    private func poses(_ mood: Presence.Mood, energy: CGFloat = 0, reduceMotion: Bool = false,
                       seconds: Double = 40) -> [ClippyPose] {
        stride(from: 0.0, to: seconds, by: 1.0 / 60).map {
            ClippyMotion.pose(at: $0, mood: mood, energy: energy, reduceMotion: reduceMotion)
        }
    }

    @Test func idleBlinksNowAndThenButMostlyLooksOut() {
        // Outside the tricks (a nap shuts his eyes for a while).
        let idle = stride(from: 0.0, to: 40, by: 1.0 / 60).filter {
            ClippyMotion.trick(at: $0) == nil && ClippyMotion.expression(at: $0) == nil
        }
            .map { ClippyMotion.pose(at: $0, mood: .idle, energy: 0, reduceMotion: false) }
        let closed = idle.filter { $0.eyeOpen < 0.5 }.count
        #expect(closed > 0)
        #expect(Double(closed) / Double(idle.count) < 0.08)
        #expect(idle.contains { abs($0.look.x) > 0.4 })                   // glances around now and then
        #expect(Double(idle.filter { abs($0.look.x) > 0.4 }.count) / Double(idle.count) < 0.4)
    }

    /// Between tricks he's never quite still (a sway, a breath, frequent small fidgets), but it
    /// stays small.
    @Test func idleIsLivelyButSmallBetweenTricks() {
        let samples = stride(from: 0.0, to: 600, by: 1.0 / 30).filter {
            ClippyMotion.trick(at: $0) == nil && ClippyMotion.expression(at: $0) == nil
        }
        let idle = samples.map { ClippyMotion.pose(at: $0, mood: .idle, energy: 0, reduceMotion: false) }
        #expect(idle.contains { $0.bounce < -1 })                    // hops
        #expect(idle.contains { abs($0.tilt) > 3 })                  // twists and turns
        #expect(idle.allSatisfy { $0.bounce >= -4 && abs($0.tilt) <= 8 && abs($0.squash - 1) <= 0.08 })
        let moving = idle.filter { abs($0.tilt) > 0.5 || abs($0.squash - 1) > 0.005 || $0.bounce < -0.3 }
        #expect(Double(moving.count) / Double(idle.count) > 0.6)     // more animated than before
    }

    /// The voice changes how high he bounces, never where he is in the bounce: frame to frame he
    /// moves smoothly, even with the real (huge) clock and a voice that wavers.
    @Test func listeningNeverJitters() {
        let t0 = 800_000_000.0, frame = 1.0 / 60
        var previous = ClippyMotion.pose(at: t0, mood: .listening(command: false), energy: 0.5, reduceMotion: false)
        for i in 1..<240 {
            let energy = 0.5 + 0.2 * CGFloat(sin(Double(i) * 0.7))         // a wavering voice
            let pose = ClippyMotion.pose(at: t0 + Double(i) * frame, mood: .listening(command: false), energy: energy,
                                         reduceMotion: false)
            #expect(abs(pose.bounce - previous.bounce) < 1.5)
            #expect(abs(pose.tilt - previous.tilt) < 1)
            #expect(abs(pose.shiftX - previous.shiftX) < 0.5)
            previous = pose
        }
    }

    /// Faces now and then between tricks: each kind shows up, none for long.
    @Test func idleFacesComeAndGo() {
        var seen: Set<ClippyMotion.Expression> = []
        var busy = 0
        let step = 1.0 / 10, minutes = 30.0
        for t in stride(from: 0.0, to: minutes * 60, by: step) {
            if let expression = ClippyMotion.expression(at: t) { seen.insert(expression.expression); busy += 1 }
        }
        #expect(seen == Set(ClippyMotion.Expression.allCases))
        let share = Double(busy) * step / (minutes * 60)
        #expect(share > 0.1 && share < 0.4)
    }

    @Test func eachFaceReads() {
        func face(_ expression: ClippyMotion.Expression) -> ClippyPose {
            ClippyMotion.expressionPose(expression, progress: 0.5, base: ClippyMotion.pose(at: 1000, mood: .idle,
                                                                                          energy: 0, reduceMotion: true))
        }
        #expect(face(.angry).squint >= 0.4 && face(.angry).brow < -0.5)
        #expect(face(.happy).happy)
        #expect(abs(face(.questioning).browTilt) >= 0.6)
        #expect(face(.pondering).look.y < -0.3 && abs(face(.pondering).browTilt) > 0.3)
        #expect(face(.surprised).eyeOpen > 1.1 && face(.surprised).brow > 0.8)
        #expect(face(.smug).squint > 0.3 && abs(face(.smug).browTilt) > 0.3)
    }

    /// Tricks and faces still happen while his eyes follow the pointer; between them, the eyes
    /// go back to the pointer.
    @Test func tricksAndFacesHappenWhileFollowingThePointer() {
        let pointer = CGPoint(x: 0.7, y: -0.2)
        let trickTime = stride(from: 0.0, to: 600, by: 0.1).first { ClippyMotion.trick(at: $0)?.trick == .cartwheel }!
        let tracked = ClippyMotion.pose(at: trickTime + 0.5, mood: .idle, energy: 0, reduceMotion: false, pointer: pointer)
        let plain = ClippyMotion.pose(at: trickTime + 0.5, mood: .idle, energy: 0, reduceMotion: false)
        #expect(tracked.spin == plain.spin && tracked.spin > 0)
        let faceTime = stride(from: 0.0, to: 600, by: 0.1).first {
            ClippyMotion.expression(at: $0)?.expression == .surprised && ClippyMotion.trick(at: $0) == nil
        }!
        let face = ClippyMotion.pose(at: faceTime + 0.3, mood: .idle, energy: 0, reduceMotion: false, pointer: pointer)
        #expect(face.eyeOpen > 1.05)
        let calm = stride(from: 0.0, to: 600, by: 0.1).first {
            ClippyMotion.expression(at: $0) == nil && ClippyMotion.trick(at: $0) == nil && !ClippyMotion.isBlinking(at: $0)
        }!
        #expect(ClippyMotion.pose(at: calm, mood: .idle, energy: 0, reduceMotion: false, pointer: pointer).look == pointer)
    }

    /// Five bigger tricks, each now and then: roughly one a minute, never more than one at a time.
    @Test func idleTricksAreFunButSeldom() {
        var seen: Set<ClippyMotion.Trick> = []
        var starts = 0, busy = 0, previous: ClippyMotion.Trick?
        let step = 1.0 / 10, minutes = 30.0
        for t in stride(from: 0.0, to: minutes * 60, by: step) {
            let trick = ClippyMotion.trick(at: t)?.trick
            if let trick { seen.insert(trick); busy += 1 }
            if trick != nil && previous == nil { starts += 1 }
            previous = trick
        }
        #expect(seen == Set(ClippyMotion.Trick.allCases))
        #expect(Double(starts) / minutes >= 0.7 && Double(starts) / minutes <= 1.8)
        #expect(Double(busy) * step / (minutes * 60) < 0.12)
    }

    @Test func eachTrickDoesItsThing() {
        func run(_ trick: ClippyMotion.Trick) -> [ClippyPose] {
            stride(from: 0.0, through: 1, by: 0.01).map { ClippyMotion.trickPose(trick, progress: $0, at: 100) }
        }
        #expect(run(.spin).contains { $0.turn < -0.9 })                                  // shows his back
        let nap = run(.nap)
        #expect(nap.contains { abs($0.tilt) >= 80 && $0.eyeOpen < 0.2 && $0.sleeping })  // lying down, asleep
        #expect(nap.first!.tilt == 0 && nap.last!.tilt == 0)                            // and back up
        #expect(run(.cartwheel).map(\.spin).max()! >= 359)
        let dance = run(.dance)
        #expect(dance.contains { $0.shiftX > 5 } && dance.contains { $0.shiftX < -5 } && dance.contains { $0.happy })
        let peek = run(.peekaboo)
        #expect(peek.contains { $0.bounce >= 80 })                                      // gone below the floor
        #expect(peek.contains { $0.bounce > 40 && $0.bounce < 70 && abs($0.look.x) > 0.5 })   // peeking out, looking around
        #expect(run(.jelly).contains { $0.squash > 1.1 } && run(.jelly).contains { $0.squash < 0.9 })
        #expect(run(.moonwalk).map { abs($0.shiftX) }.max()! >= 20)
        let dizzy = run(.dizzy)
        #expect(dizzy.map(\.spin).max()! >= 719 && dizzy.contains { abs($0.tilt) > 6 && $0.spin == 720 })
        let hiccups = run(.hiccup)
        var jumps = 0
        for i in 1..<hiccups.count where hiccups[i].bounce < -3 && hiccups[i - 1].bounce >= -3 { jumps += 1 }
        #expect(jumps == 3 && hiccups.contains { $0.eyeOpen > 1.1 })
        let hops = run(.trampoline)
        var landings = 0
        for i in 1..<hops.count where hops[i].bounce > -0.5 && hops[i - 1].bounce <= -0.5 { landings += 1 }
        #expect(landings >= 2 && hops.contains { $0.bounce <= -8 } && hops.contains { $0.squash < 0.95 })
        for trick in ClippyMotion.Trick.allCases {
            let poses = run(trick)
            #expect(poses.allSatisfy { $0.bounce >= -ClippyMotion.maxBounce && $0.squash <= 1.16 })
            #expect(poses.first!.turn == 1 && abs(poses.last!.spin.truncatingRemainder(dividingBy: 360)) < 0.001)
            #expect(abs(poses.first!.bounce) < 0.001 && abs(poses.last!.bounce) < 0.001)   // starts and ends standing
        }
    }

    @Test func blinksAreNotEvenlySpaced() {
        let idle = poses(.idle)
        var starts: [Int] = []
        for i in 1..<idle.count where idle[i].eyeOpen < 0.5 && idle[i - 1].eyeOpen >= 0.5 { starts.append(i) }
        let gaps = zip(starts.dropFirst(), starts).map { $0 - $1 }
        #expect(Set(gaps).count > 1)
    }

    @Test func listeningMovesMoreWithALouderVoice() {
        let quiet = poses(.listening(command: false), energy: 0.3, seconds: 4).map { abs($0.bounce) }.max()!
        let loud = poses(.listening(command: false), energy: 1, seconds: 4).map { abs($0.bounce) }.max()!
        let silent = poses(.listening(command: false), energy: 0, seconds: 4).map { abs($0.bounce) }.max()!
        #expect(quiet > silent + 1)
        #expect(loud > quiet)
        #expect(loud <= ClippyMotion.maxBounce)
    }

    /// Listening, he's cheerful: moving even before you speak, flashing a happy face now and then.
    @Test func listeningIsHappyAndLively() {
        let silent = poses(.listening(command: false), energy: 0, seconds: 20)
        #expect(silent.contains { $0.bounce < -1.5 })
        #expect(silent.map { abs($0.tilt) }.max()! >= 4)
        let happy = silent.filter(\.happy).count
        #expect(happy > 0 && Double(happy) / Double(silent.count) < 0.3)
        #expect(silent.allSatisfy { $0.brow >= 0.45 })
    }

    @Test func eachStateHasItsOwnExpression() {
        let listening = poses(.listening(command: false), seconds: 2).filter { !$0.happy }
        let command = poses(.listening(command: true), seconds: 2)
        #expect(command.allSatisfy { $0.brow > 0.8 })                        // eyebrows up: an instruction
        #expect(listening.allSatisfy { $0.brow > 0.2 && $0.brow < 0.8 })     // attentive
        #expect(poses(.working(.editing), seconds: 2).allSatisfy { $0.look.y > 0.3 && $0.brow < 0 }) // reading, focused
        #expect(poses(.working(.transcribing), seconds: 2).contains { $0.look.y < -0.3 })            // thinking: eyes up
        #expect(poses(.success, seconds: 1).allSatisfy { $0.happy })
        #expect(poses(.error, seconds: 1).allSatisfy { $0.brow < -0.6 && !$0.happy })
    }

    @Test func reducedMotionHoldsStill() {
        for mood in [Presence.Mood.idle, .listening(command: false), .working(.transcribing), .error] {
            let still = poses(mood, energy: 1, reduceMotion: true, seconds: 5)
            #expect(still.allSatisfy { $0.bounce == 0 && $0.tilt == 0 && $0.squash == 1 && $0.shiftX == 0
                && $0.turn == 1 && $0.spin == 0 && !$0.sleeping })
        }
    }
}

struct BubblePlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
    let bubble = CGSize(width: 250, height: 170)

    @Test func sitsAboveTheCharacterWithItsTailOnIt() {
        let character = CGRect(x: 600, y: 100, width: 96, height: 140)
        let placed = BubblePlacement.place(bubble: bubble, character: character, screen: screen)
        #expect(placed.above)
        #expect(placed.frame.minY == character.maxY + BubblePlacement.gap)
        #expect(placed.frame.midX == character.midX)
        #expect(placed.tailX == bubble.width / 2)
    }

    @Test func flipsBelowNearTheTop() {
        let character = CGRect(x: 600, y: 780, width: 96, height: 140)
        let placed = BubblePlacement.place(bubble: bubble, character: character, screen: screen)
        #expect(!placed.above)
        #expect(placed.frame.maxY == character.minY - BubblePlacement.gap)
        #expect(screen.contains(placed.frame))
    }

    @Test func shiftsInsideAtTheSidesAndTheTailStillPoints() {
        let character = CGRect(x: 1430, y: 100, width: 80, height: 140)
        let placed = BubblePlacement.place(bubble: bubble, character: character, screen: screen)
        #expect(placed.frame.maxX == screen.maxX)
        #expect(placed.tailX > bubble.width / 2)
        #expect(placed.tailX <= bubble.width - BubblePlacement.tailInset)
        let left = BubblePlacement.place(bubble: bubble, character: CGRect(x: 0, y: 100, width: 80, height: 140),
                                         screen: screen)
        #expect(left.frame.minX == screen.minX)
        #expect(left.tailX >= BubblePlacement.tailInset)
    }

    @Test func aScreenTooShortForEitherSideKeepsItOnScreen() {
        let short = CGRect(x: 0, y: 0, width: 800, height: 260)
        let placed = BubblePlacement.place(bubble: bubble, character: CGRect(x: 300, y: 60, width: 96, height: 140),
                                           screen: short)
        #expect(short.contains(placed.frame))
    }
}

struct ClippyBubbleTailTests {
    /// The tail's tip sits exactly at `tailX`, with an even base either side.
    @Test func theTailIsSymmetricAroundItsTip() {
        let rect = CGRect(x: 0, y: 0, width: 238, height: 80)
        for down in [true, false] {
            let tail = BubbleShape.tail(at: 119, in: rect, down: down).boundingRect
            #expect(abs(tail.midX - 119) < 0.001)
        }
    }

    /// The bubble view insets its shape for the shadow; the tail still points at the panel's `tailX`.
    @Test func theInsetIsTakenOffTheTailPosition() {
        #expect(ClippyBubbleView.shapeTailX(panelTailX: 125) == 125 - ClippyBubbleView.sideInset)
    }
}

@MainActor
struct ClippyPointerTests {
    let eyes = CGPoint(x: 500, y: 500)

    @Test func eyesTurnTowardThePointer() {
        let right = ClippyMotion.look(toward: CGPoint(x: 1200, y: 500), from: eyes)
        #expect(right.x > 0.9 && abs(right.y) < 0.01)
        let above = ClippyMotion.look(toward: CGPoint(x: 500, y: 1200), from: eyes)
        #expect(above.y < -0.9)                          // screen y goes up, the pupils' y goes down
        let belowLeft = ClippyMotion.look(toward: CGPoint(x: 0, y: 0), from: eyes)
        #expect(belowLeft.x < -0.6 && belowLeft.y > 0.6)
    }

    @Test func aNearbyPointerTurnsTheEyesLess() {
        let near = ClippyMotion.look(toward: CGPoint(x: 520, y: 500), from: eyes)
        #expect(near.x > 0 && near.x < 0.5)
        #expect(ClippyMotion.look(toward: eyes, from: eyes) == .zero)
    }

    @Test func followingThePointerWinsOverTheMoodsOwnGaze() {
        let target = CGPoint(x: -0.8, y: -0.5)
        for mood in [Presence.Mood.idle, .listening(command: false), .working(.editing), .working(.transcribing), .error] {
            let pose = ClippyMotion.pose(at: 1.7, mood: mood, energy: 0.5, reduceMotion: false, pointer: target)
            #expect(pose.look == target)
        }
        let leaning = ClippyMotion.pose(at: 1.7, mood: .idle, energy: 0, reduceMotion: false, pointer: target)
        #expect(leaning.tilt < 0)                        // turns toward it a little
        let still = ClippyMotion.pose(at: 1.7, mood: .idle, energy: 0, reduceMotion: true, pointer: target)
        #expect(still.tilt == 0)
    }

    @Test func clippysWindowIsSquareAtEverySize() {
        for height: CGFloat in [80, 128, 240] {
            let size = ClippyController.characterSize(height: height)
            #expect(size.height == height)
            #expect(size.width == size.height)          // square: room to lie down and cartwheel
        }
    }
}
