import Testing
@testable import HUD

/// A floating theme behind other windows (Desktop behaviour) stops drawing until it shows again.
@MainActor
struct CoveredPauseTests {
    @Test func aCoveredOrbNeverDraws() {
        #expect(OrbView.isPaused(idle: false, reduceMotion: false, covered: true))
        #expect(OrbView.isPaused(idle: true, reduceMotion: false, covered: true))
        #expect(!OrbView.isPaused(idle: true, reduceMotion: false, covered: false))
        #expect(OrbView.isPaused(idle: true, reduceMotion: true, covered: false))
        #expect(!OrbView.isPaused(idle: false, reduceMotion: true, covered: false))
    }

    @Test func aCoveredClippyNeverDraws() {
        #expect(ClippyView.isPaused(idle: false, reduceMotion: false, followsPointer: true, covered: true))
        #expect(!ClippyView.isPaused(idle: true, reduceMotion: true, followsPointer: true, covered: false))
        #expect(ClippyView.isPaused(idle: true, reduceMotion: true, followsPointer: false, covered: false))
        #expect(!ClippyView.isPaused(idle: false, reduceMotion: false, followsPointer: false, covered: false))
    }
}
