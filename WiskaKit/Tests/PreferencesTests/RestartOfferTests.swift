import Testing
@testable import Preferences

/// When to ask "Restart Wiska?": the fn listener follows Accessibility, but only after a restart.
struct RestartOfferTests {
    typealias P = RestartOffer.Permissions

    @Test func grantingTheLastOfMicrophoneAndAccessibilityOffersARestart() {
        var offer = RestartOffer()
        let r1 = offer.update(P(microphone: true, accessibility: false, inputMonitoring: false))
        #expect(!r1)
        let r2 = offer.update(P(microphone: true, accessibility: true, inputMonitoring: false))
        #expect(r2)
    }

    @Test func itAsksOnlyOncePerLaunch() {
        var offer = RestartOffer()
        _ = offer.update(P(microphone: false, accessibility: false, inputMonitoring: false))
        let r3 = offer.update(P(microphone: true, accessibility: true, inputMonitoring: false))
        #expect(r3)
        let r4 = offer.update(P(microphone: true, accessibility: true, inputMonitoring: false))
        #expect(!r4)
    }

    /// Already like that at launch (e.g. just after the restart): restarting again wouldn't help.
    @Test func noOfferWithoutAChangeDuringThisLaunch() {
        var offer = RestartOffer()
        let r5 = offer.update(P(microphone: true, accessibility: true, inputMonitoring: false))
        #expect(!r5)
        let r6 = offer.update(P(microphone: true, accessibility: true, inputMonitoring: false))
        #expect(!r6)
    }

    @Test func noOfferWhenTheListenerAlreadyWorks() {
        var offer = RestartOffer()
        _ = offer.update(P(microphone: false, accessibility: false, inputMonitoring: false))
        let r7 = offer.update(P(microphone: true, accessibility: true, inputMonitoring: true))
        #expect(!r7)
    }

    @Test func microphoneLastAlsoCounts() {
        var offer = RestartOffer()
        _ = offer.update(P(microphone: false, accessibility: true, inputMonitoring: false))
        let r8 = offer.update(P(microphone: true, accessibility: true, inputMonitoring: false))
        #expect(r8)
    }
}
