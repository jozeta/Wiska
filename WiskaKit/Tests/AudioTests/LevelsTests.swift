import Testing
@testable import Audio

struct LevelsTests {
    @Test func rmsOfEmptyIsZero() {
        #expect(Levels.rms([]) == 0)
    }

    @Test func rmsOfFullScaleSquareIsOne() {
        #expect(Levels.rms([1, -1, 1, -1]) == 1)
    }

    @Test func normalizedMapsDecibelsLinearlyFromMinus50() {
        #expect(Levels.normalized(rms: 0) == 0)
        #expect(Levels.normalized(rms: 1) == 1)
        #expect(abs(Levels.normalized(rms: 0.01) - 0.2) < 0.0001)   // −40 dB
        #expect(Levels.normalized(rms: 2) == 1)                     // clamped
    }
}
