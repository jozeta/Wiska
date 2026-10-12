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

@MainActor
struct PresenceRedrawTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    /// The view picks its frame rate only when told the mood changed. A celebration that ran out
    /// while other hides arrived must still be reported, or an idle theme animates at full rate forever.
    @Test func anExpiredCelebrationIsReportedEvenAfterRepeatedHides() {
        let presence = Presence()
        presence.update(.working("Transcribing…"), at: t0)
        #expect(presence.takeMoodChange(at: t0))
        presence.update(.hidden, at: t0)
        #expect(presence.takeMoodChange(at: t0))                       // → success
        let later = t0.addingTimeInterval(Presence.successDuration + 0.2)
        presence.update(.hidden, at: later)                            // a delayed hide, after it expired
        #expect(presence.takeMoodChange(at: later))                    // success → idle: redraw
        #expect(!presence.takeMoodChange(at: later))                   // reported once
    }

    @Test func audioFramesAreNotMoodChanges() {
        let presence = Presence()
        presence.update(.listening(audio: AudioLevel(level: 0.2), badge: "EN", preview: "", handsFree: false), at: t0)
        #expect(presence.takeMoodChange(at: t0))
        presence.update(.listening(audio: AudioLevel(level: 0.6), badge: "EN", preview: "hi", handsFree: false), at: t0)
        #expect(!presence.takeMoodChange(at: t0))
    }
}
