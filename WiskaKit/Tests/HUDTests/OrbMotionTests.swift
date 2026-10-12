import CoreGraphics
import Testing
@testable import HUD

@MainActor
struct OrbMotionTests {
    private func poses(_ mood: Presence.Mood, energy: CGFloat, reduceMotion: Bool = false) -> [OrbPose] {
        stride(from: 0.0, to: 10, by: 1.0 / 30).map {
            OrbMotion.pose(at: $0, mood: mood, energy: energy, reduceMotion: reduceMotion)
        }
    }

    @Test func idleBreathesGentlyWithoutPulsing() {
        let idle = poses(.idle, energy: 0)
        let scales = idle.map(\.coreScale)
        #expect(scales.max()! - scales.min()! <= 0.06)
        #expect(idle.allSatisfy { $0.glow > 0.2 && $0.glow < 0.6 })   // a soft glow, never dark
    }

    @Test func quietSpeechIsVisibleAndLoudSpeechIsStrongerButBounded() {
        let silent = poses(.listening(command: false), energy: 0).map(\.coreScale).max()!
        let quiet = poses(.listening(command: false), energy: 0.3).map(\.coreScale).max()!
        let loud = poses(.listening(command: false), energy: 1).map(\.coreScale).max()!
        #expect(quiet > silent + 0.05)
        #expect(loud > quiet)
        #expect(loud <= OrbMotion.maxCoreScale)
        let glowQuiet = poses(.listening(command: false), energy: 0.3).map(\.glow).max()!
        let glowLoud = poses(.listening(command: false), energy: 1).map(\.glow).max()!
        #expect(glowLoud > glowQuiet)
        #expect(glowLoud <= 1)
    }

    @Test func everythingFitsInsideTheWindow() {
        for mood in [Presence.Mood.idle, .listening(command: false), .working(.transcribing), .success, .error] {
            for pose in poses(mood, energy: 1) {
                #expect(OrbMotion.outerRadius(pose, side: 100) <= 50)
            }
        }
    }

    @Test func processingSpinsAndListeningDoesNot() {
        #expect(poses(.working(.transcribing), energy: 0).allSatisfy { $0.spinOpacity > 0 })
        #expect(poses(.listening(command: false), energy: 0.5).allSatisfy { $0.spinOpacity == 0 })
    }

    @Test func errorsTurnRedAndSuccessFlashes() {
        #expect(poses(.error, energy: 0).allSatisfy { $0.isError })
        #expect(poses(.success, energy: 0).map(\.glow).max()! > poses(.idle, energy: 0).map(\.glow).max()!)
    }

    @Test func theAuraRipplesStronglyWithTheVoice() {
        let quiet = poses(.listening(command: false), energy: 0.2).map(\.ripple).max()!
        let loud = poses(.listening(command: false), energy: 1).map(\.ripple).max()!
        #expect(loud >= 0.25)
        #expect(loud > quiet * 2)
    }

    @Test func lightningCracklesMoreWithTheVoice() {
        let idle = poses(.idle, energy: 0)[0]
        let quiet = poses(.listening(command: false), energy: 0.2)[0]
        let loud = poses(.listening(command: false), energy: 1)[0]
        #expect(idle.boltChance < quiet.boltChance)
        #expect(quiet.boltChance < loud.boltChance)
        #expect(quiet.maxBolts < loud.maxBolts)
        #expect(poses(.error, energy: 1).allSatisfy { $0.boltChance == 0 })
    }

    @Test func theRingsAndLightningStayInsideTheWindow() {
        for mood in [Presence.Mood.idle, .listening(command: true), .working(.writing), .success] {
            for pose in poses(mood, energy: 1) {
                #expect(OrbMotion.maxReach(pose, side: 100) <= 50)
            }
        }
    }

    @Test func reducedMotionHoldsStillAndDropsParticles() {
        let still = poses(.idle, energy: 0, reduceMotion: true)
        #expect(Set(still.map(\.coreScale)).count == 1)
        #expect(still.allSatisfy { $0.particleOpacity == 0 && $0.boltChance == 0 && $0.ringSpeed == 0 })
    }
}
