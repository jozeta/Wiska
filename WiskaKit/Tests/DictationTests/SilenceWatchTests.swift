import Testing
@testable import Dictation

struct SilenceWatchTests {
    @Test func stopsAfterTheTimeoutOfQuiet() {
        var watch = SilenceWatch(timeout: 2)
        #expect(watch.feed(level: 0.1, time: 10) == false)
        #expect(watch.feed(level: 0.1, time: 11.9) == false)
        #expect(watch.feed(level: 0.1, time: 12) == true)
    }

    @Test func speechResetsTheClock() {
        var watch = SilenceWatch(timeout: 2)
        #expect(watch.feed(level: 0.1, time: 10) == false)
        #expect(watch.feed(level: 0.6, time: 11.5) == false)
        #expect(watch.feed(level: 0.1, time: 13) == false)
        #expect(watch.feed(level: 0.1, time: 14.9) == false)
        #expect(watch.feed(level: 0.1, time: 15) == true)
    }

    @Test func thresholdLevelCountsAsSpeech() {
        var watch = SilenceWatch(timeout: 1)
        #expect(watch.feed(level: 0.1, time: 10) == false)
        #expect(watch.feed(level: SilenceWatch.speechThreshold, time: 10.9) == false)
        #expect(watch.feed(level: 0.1, time: 11.5) == false)
    }

    @Test func reportsOnlyOnce() {
        var watch = SilenceWatch(timeout: 1)
        _ = watch.feed(level: 0, time: 10)
        #expect(watch.feed(level: 0, time: 11) == true)
        #expect(watch.feed(level: 0, time: 12) == false)
    }

    @Test func zeroTimeoutNeverStops() {
        var watch = SilenceWatch(timeout: 0)
        #expect(watch.feed(level: 0, time: 10) == false)
        #expect(watch.feed(level: 0, time: 1_000) == false)
    }
}
