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
        #expect(idle.allSatisfy { $0.flameSpeed >= 0.2 && $0.flameSpeed <= 0.3 })   // lively, not rushing
        let sizes = idle.map(\.coreScale)
        #expect(sizes.max()! - sizes.min()! >= 0.24)                    // a strong pulse…
        let step = zip(sizes.dropFirst(8), sizes).map { abs($0 - $1) }.max()!
        #expect(step < 0.045)                                           // …that never jumps
        let intensities = idle.map(\.intensity)
        #expect(intensities.max()! - intensities.min()! >= 0.28)        // brightens and dims with it
        // About one breath every five seconds: 6–10 swings through rest in 20 s.
        let swings = zip(sizes.dropFirst(), sizes).filter { ($0 - 1) * ($1 - 1) < 0 }.count
        #expect((6...10).contains(swings))
        #expect(idle.allSatisfy { $0.intensity < 0.45 })
    }

    @Test func busyFlamesAreLivelyButUnhurried() {
        for mood in [Presence.Mood.working(.transcribing), .working(.editing)] {
            #expect(poses(mood, energy: 0).allSatisfy { $0.flameSpeed >= 0.5 && $0.flameSpeed <= 0.7 })
        }
        #expect(poses(.listening(command: false), energy: 1).allSatisfy { $0.flameSpeed <= 0.8 })
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
        // Strongly: a loud voice grows the fire by about a third and brightens it a lot.
        // Strongly: a loud voice grows the fire by ~40%, takes it to full brightness, flares its tongues.
        #expect(loud.coreScale - poses(.listening(command: false), energy: 0)[0].coreScale >= 0.4)
        #expect(loud.intensity - poses(.listening(command: false), energy: 0)[0].intensity >= 0.6)
        #expect(loud.ripple >= 0.5)
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

    /// Wavy borders float round the fire: always a few, slow when idle, bigger and quicker with the voice.
    @Test func wavyBordersFloatAroundAndRespondToTheVoice() {
        let idle = poses(.idle, energy: 0)
        #expect(idle.allSatisfy { (2...3).contains($0.waveCount) && $0.waveAmplitude > 0 && $0.waveSpeed <= 0.4 })
        let quiet = poses(.listening(command: false), energy: 0.1)[0]
        let loud = poses(.listening(command: false), energy: 1)[0]
        #expect(loud.waveAmplitude > quiet.waveAmplitude * 2)
        #expect(loud.waveSpeed > quiet.waveSpeed)
        #expect(poses(.idle, energy: 0, reduceMotion: true).allSatisfy { $0.waveSpeed == 0 })
    }

    @Test func errorsTurnRed() {
        #expect(poses(.error, energy: 0).allSatisfy { $0.isError })
        #expect(poses(.idle, energy: 0).allSatisfy { !$0.isError })
    }

    /// The flames' ragged edge stays well inside the window (the shader fades out before its edge).
    @Test func theFireFitsTheWindow() {
        for mood in [Presence.Mood.idle, .listening(command: true), .working(.writing), .success, .error] {
            for pose in poses(mood, energy: 1) {
                #expect(OrbMotion.fireEdge(pose) <= OrbMotion.fadeStart)
                #expect(OrbMotion.waveReach(pose) <= 0.95)
            }
        }
    }

    @Test func reducedMotionHoldsTheFireStill() {
        let still = poses(.listening(command: false), energy: 1, reduceMotion: true)
        #expect(still.allSatisfy { $0.flameSpeed == 0 })
        #expect(Set(poses(.idle, energy: 0, reduceMotion: true).map(\.coreScale)).count == 1)
    }

    /// The fire is a Metal shader compiled into the HUD module; if it were missing the orb would be blank.
    @Test func theFireShaderShipsWithTheModule() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try device.makeDefaultLibrary(bundle: OrbRenderer.shaderBundle)
        #expect(library.makeFunction(name: OrbRenderer.shaderName) != nil)
    }
}
