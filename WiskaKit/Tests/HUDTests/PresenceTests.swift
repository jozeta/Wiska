import Core
import Foundation
import Testing
@testable import HUD

@MainActor
struct PresenceTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func moodFollowsTheDictation() {
        let presence = Presence()
        #expect(presence.mood(at: t0) == .idle)
        presence.update(.listening(audio: .silent, badge: "EN", preview: "", handsFree: false), at: t0)
        #expect(presence.mood(at: t0) == .listening(command: false))
        presence.update(.listening(audio: .silent, badge: "Edit", preview: "", handsFree: false, isCommand: true), at: t0)
        #expect(presence.mood(at: t0) == .listening(command: true))
        presence.update(.working("Editing…", activity: .editing), at: t0)
        #expect(presence.mood(at: t0) == .working(.editing))
        presence.update(.error("No speech"), at: t0)
        #expect(presence.mood(at: t0) == .error)
        presence.update(.message("Copied"), at: t0)
        #expect(presence.mood(at: t0) == .message)
    }

    @Test func finishingWorkCelebratesBrieflyThenRests() {
        let presence = Presence()
        presence.update(.working("Transcribing…"), at: t0)
        presence.update(.hidden, at: t0)
        #expect(presence.mood(at: t0.addingTimeInterval(0.3)) == .success)
        #expect(presence.mood(at: t0.addingTimeInterval(Presence.successDuration + 0.01)) == .idle)
    }

    @Test func cancellingWhileListeningIsNotASuccess() {
        let presence = Presence()
        presence.update(.listening(audio: .silent, badge: "EN", preview: "", handsFree: false), at: t0)
        presence.update(.hidden, at: t0)
        #expect(presence.mood(at: t0) == .idle)
    }

    @Test func audioFramesDoNotRestartTheMood() {
        let presence = Presence()
        presence.update(.working("Transcribing…"), at: t0)
        presence.update(.hidden, at: t0)
        presence.update(.hidden, at: t0.addingTimeInterval(0.1))   // repeated hides keep the celebration
        #expect(presence.mood(at: t0.addingTimeInterval(0.2)) == .success)
    }
}
