import Testing
@testable import Dictation

/// When the app must release the fn lock: only when a hands-free dictation stops.
struct HandsFreeLatchTests {
    @Test func aCancelledFirstTapDoesNotRelease() {
        var latch = HandsFreeLatch()
        #expect(latch.update(listening: true, handsFree: false) == false)
        #expect(latch.update(listening: false, handsFree: false) == false)   // the first tap's cancel
        #expect(latch.update(listening: true, handsFree: false) == false)    // the second press
        #expect(latch.update(listening: true, handsFree: true) == false)     // locked
    }

    @Test func aHandsFreeDictationEndingReleasesOnce() {
        var latch = HandsFreeLatch()
        _ = latch.update(listening: true, handsFree: true)
        #expect(latch.update(listening: false, handsFree: false) == true)
        #expect(latch.update(listening: false, handsFree: false) == false)
    }
}
