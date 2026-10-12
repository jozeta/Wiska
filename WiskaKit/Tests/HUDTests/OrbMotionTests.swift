import CoreGraphics
import Metal
import Testing
@testable import HUD

@MainActor
struct OrbMotionTests {
    private func poses(_ mood: Presence.Mood, energy: CGFloat, reduceMotion: Bool = false) -> [OrbPose] {
        stride(from: 0.0, to: 20, by: 1.0 / 30).map {
            OrbMotion.pose(at: $0, mood: mood, energy: energy, reduceMotion: reduceMotion)
        }
    }

    @Test func idleFireDriftsSlowlyAndPulsesClearlyButCalmly() {
        let idle = poses(.idle, energy: 0)
        #expect(idle.allSatisfy { $0.flameSpeed > 0 && $0.flameSpeed <= 0.15 })
        let sizes = idle.map(\.coreScale)
        #expect(sizes.max()! - sizes.min()! >= 0.12)                    // an obvious pulse…
        let step = zip(sizes.dropFirst(8), sizes).map { abs($0 - $1) }.max()!
        #expect(step < 0.03)                                            // …that never jumps
        let intensities = idle.map(\.intensity)
        #expect(intensities.max()! - intensities.min()! >= 0.15)        // brightens and dims with it
        // About one breath every five seconds: 6–10 swings through rest in 20 s.
        let swings = zip(sizes.dropFirst(), sizes).filter { ($0 - 1) * ($1 - 1) < 0 }.count
        #expect((6...10).contains(swings))
        #expect(idle.allSatisfy { $0.intensity < 0.45 })
    }

    @Test func busyFlamesAndSparksStayUnhurried() {
        for mood in [Presence.Mood.working(.transcribing), .working(.editing), .success] {
            #expect(poses(mood, energy: 0).allSatisfy { $0.flameSpeed <= 0.45 && $0.particleSpeed <= 0.6 })
        }
        #expect(poses(.listening(command: false), energy: 1).allSatisfy { $0.flameSpeed <= 0.6 && $0.particleSpeed <= 0.8 })
    }

    @Test func theVoiceFeedsTheFire() {
        let quiet = poses(.listening(command: false), energy: 0.2)[0]
        let loud = poses(.listening(command: false), energy: 1)[0]
        let idle = poses(.idle, energy: 0)[0]
        #expect(quiet.intensity > idle.intensity)
        #expect(loud.intensity > quiet.intensity)
        #expect(loud.flameSpeed > quiet.flameSpeed)
        #expect(loud.coreScale > quiet.coreScale)
        #expect(loud.ripple > quiet.ripple)
        #expect(loud.intensity <= 1 && loud.coreScale <= OrbMotion.maxCoreScale)
    }

    @Test func workingBurnsHotterThanIdle() {
        let idle = poses(.idle, energy: 0)
        for mood in [Presence.Mood.working(.transcribing), .working(.editing), .success] {
            let busy = poses(mood, energy: 0)
            #expect(busy.map(\.intensity).min()! > idle.map(\.intensity).max()! + 0.3)
            #expect(busy.map(\.glow).min()! > idle.map(\.glow).max()!)
            #expect(busy.allSatisfy { $0.flameSpeed > idle[0].flameSpeed * 2.5 })
        }
    }

    @Test func errorsTurnRed() {
        #expect(poses(.error, energy: 0).allSatisfy { $0.isError })
        #expect(poses(.idle, energy: 0).allSatisfy { !$0.isError })
    }

    /// The flames' ragged edge stays well inside the window (the shader fades out before its edge).
    @Test func theFireFitsTheWindow() {
        for mood in [Presence.Mood.idle, .listening(command: true), .working(.writing), .success, .error] {
            for pose in poses(mood, energy: 1) {
                #expect(OrbMotion.fireEdge(pose) <= 0.75)
            }
        }
    }

    @Test func reducedMotionHoldsTheFireStill() {
        let still = poses(.listening(command: false), energy: 1, reduceMotion: true)
        #expect(still.allSatisfy { $0.flameSpeed == 0 && $0.particleOpacity == 0 })
        #expect(Set(poses(.idle, energy: 0, reduceMotion: true).map(\.coreScale)).count == 1)
    }

    /// The fire is a Metal shader compiled into the HUD module; if it were missing the orb would be blank.
    @Test func theFireShaderShipsWithTheModule() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try device.makeDefaultLibrary(bundle: OrbRenderer.shaderBundle)
        #expect(library.makeFunction(name: OrbRenderer.shaderName) != nil)
    }
}

struct OrbVoiceShapeTests {
    let silent = [CGFloat](repeating: 0, count: 32)

    @Test func silenceLeavesTheFireRound() {
        for a in stride(from: 0.0, to: 2 * .pi, by: 0.3) {
            #expect(OrbRenderer.bandValue(at: a, bands: silent) == 0)
        }
    }

    /// Low pitches sit at the top, high ones at the bottom, mirrored left and right (as in the shader).
    @Test func eachPitchBandPushesItsOwnPartOfTheFire() {
        var low = silent; low[1] = 1
        var high = silent; high[30] = 1
        let top = -Double.pi / 2, bottom = Double.pi / 2
        #expect(OrbRenderer.bandValue(at: top, bands: low) > OrbRenderer.bandValue(at: bottom, bands: low))
        #expect(OrbRenderer.bandValue(at: bottom, bands: high) > OrbRenderer.bandValue(at: top, bands: high))
        #expect(abs(OrbRenderer.bandValue(at: 0.4, bands: high) - OrbRenderer.bandValue(at: .pi - 0.4, bands: high)) < 0.001)
    }
}
