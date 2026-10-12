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
        let idle = poses(.idle)
        let closed = idle.filter { $0.eyeOpen < 0.5 }.count
        #expect(closed > 0)
        #expect(Double(closed) / Double(idle.count) < 0.08)
        #expect(idle.allSatisfy { abs($0.bounce) < 0.5 })                // no hopping about
        #expect(idle.contains { abs($0.look.x) > 0.4 })                   // glances around now and then
        #expect(Double(idle.filter { abs($0.look.x) > 0.4 }.count) / Double(idle.count) < 0.4)
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

    @Test func eachStateHasItsOwnExpression() {
        let listening = poses(.listening(command: false), seconds: 2)
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
            #expect(still.allSatisfy { $0.bounce == 0 && $0.tilt == 0 && $0.squash == 1 })
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
