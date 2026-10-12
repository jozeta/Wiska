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

    @Test func idleBreathesVerySlowlyWithoutLightning() {
        let idle = poses(.idle, energy: 0)
        let scales = idle.map(\.coreScale)
        #expect(scales.max()! - scales.min()! >= 0.05)                 // you can see it breathe
        #expect(scales.max()! - scales.min()! <= 0.1)
        // Slow: from one quarter second to the next it barely changes (a breath takes ~10 s).
        let step = zip(scales.dropFirst(8), scales).map { abs($0 - $1) }.max()!
        #expect(step < 0.012)
        #expect(idle.allSatisfy { $0.glow > 0.2 && $0.glow < 0.6 })   // a soft glow, never dark
        #expect(idle.allSatisfy { $0.boltChance == 0 })
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
        let quiet = poses(.listening(command: false), energy: 0.2)[0]
        let loud = poses(.listening(command: false), energy: 1)[0]
        #expect(quiet.boltChance < loud.boltChance)
        #expect(quiet.maxBolts < loud.maxBolts)
        #expect(loud.maxBolts <= 3)                       // a notch calmer than before
        #expect(OrbRenderer.boltRate <= 4)
        #expect(poses(.working(.transcribing), energy: 0).allSatisfy { $0.boltChance <= 0.1 && $0.maxBolts <= 1 })
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

struct OrbVoiceShapeTests {
    let silent = [CGFloat](repeating: 0, count: 32)

    @Test func silenceLeavesTheAuraRound() {
        for a in stride(from: 0.0, to: 2 * .pi, by: 0.3) {
            #expect(OrbRenderer.bandValue(at: a, bands: silent) == 0)
        }
    }

    /// Low pitches sit at the top, high ones at the bottom, mirrored left and right.
    @Test func eachPitchBandPushesItsOwnPartOfTheAura() {
        var low = silent; low[1] = 1
        var high = silent; high[30] = 1
        let top = -Double.pi / 2, bottom = Double.pi / 2
        #expect(OrbRenderer.bandValue(at: top, bands: low) > OrbRenderer.bandValue(at: bottom, bands: low))
        #expect(OrbRenderer.bandValue(at: bottom, bands: high) > OrbRenderer.bandValue(at: top, bands: high))
        #expect(abs(OrbRenderer.bandValue(at: 0.4, bands: high) - OrbRenderer.bandValue(at: .pi - 0.4, bands: high)) < 0.001)
    }

    @Test func lightningFiresFromTheLoudestBands() {
        var bands = silent; bands[5] = 0.9; bands[20] = 0.6; bands[11] = 0.3
        #expect(OrbRenderer.loudestBand(rank: 0, bands: bands) == 5)
        #expect(OrbRenderer.loudestBand(rank: 1, bands: bands) == 20)
        #expect(OrbRenderer.loudestBand(rank: 2, bands: bands) == 11)
    }

    @Test func sparkSpeedFollowsTheVoiceAndStaysCalm() {
        let quiet = OrbMotion.pose(at: 0, mood: .listening(command: false), energy: 0.2, reduceMotion: false)
        let loud = OrbMotion.pose(at: 0, mood: .listening(command: false), energy: 1, reduceMotion: false)
        #expect(loud.particleSpeed > quiet.particleSpeed)
        #expect(loud.particleSpeed <= 1.5)
        #expect(loud.ringSpeed <= 1.8)
    }
}
