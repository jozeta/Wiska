import Core
import Foundation
import Testing
@testable import Audio

struct SpectrumAnalyzerTests {
    private func sine(_ hz: Float, amplitude: Float = 0.1, count: Int = 4_096) -> [Float] {
        (0..<count).map { amplitude * sin(2 * .pi * hz * Float($0) / 16_000) }
    }

    @Test func emitsAFrameEveryHopOnceAWindowIsFull() {
        let analyzer = SpectrumAnalyzer()
        // 1600 samples (100 ms): windows end at 512, 768, …, 1536 → 5 frames.
        #expect(analyzer.analyze(Array(repeating: 0, count: 1_600)).count == 5)
        // The leftover carries over: 800 more samples → frames ending at 1792, 2048, 2304.
        #expect(analyzer.analyze(Array(repeating: 0, count: 800)).count == 3)
    }

    @Test func framesHaveOneValuePerBar() {
        let frames = SpectrumAnalyzer().analyze(sine(1_000))
        #expect(frames.allSatisfy { $0.bands.count == SpectrumAnalyzer.bandCount })
    }

    @Test func silenceIsQuietEverywhere() {
        let frame = SpectrumAnalyzer().analyze(Array(repeating: 0, count: 1_024)).last!
        #expect(frame.level == 0)
        #expect(frame.bands.allSatisfy { $0 <= SpectrumAnalyzer.floorDecibels })
    }

    @Test func everyBandHasItsOwnBins() {
        let bins = SpectrumAnalyzer().bandBins
        #expect(bins.count == SpectrumAnalyzer.bandCount)
        let empty = bins.filter(\.isEmpty)
        #expect(empty.isEmpty)
        let overlapping = zip(bins, bins.dropFirst()).filter { $0.upperBound > $1.lowerBound }
        #expect(overlapping.isEmpty)
    }

    @Test func aToneLightsTheBarForItsPitch() {
        let low = SpectrumAnalyzer().analyze(sine(200)).last!
        let high = SpectrumAnalyzer().analyze(sine(3_000)).last!
        let lowPeak = low.bands.indices.max { low.bands[$0] < low.bands[$1] }!
        let highPeak = high.bands.indices.max { high.bands[$0] < high.bands[$1] }!
        #expect(lowPeak < highPeak)
        #expect(highPeak - lowPeak >= 8)
    }

    @Test func levelIsTheFramesLoudness() {
        let frame = SpectrumAnalyzer().analyze(sine(1_000, amplitude: 0.1)).last!
        // RMS of a 0.1 sine ≈ 0.0707 ≈ −23 dBFS → (50 − 23) / 50 ≈ 0.54.
        #expect(abs(frame.level - Levels.normalized(rms: 0.0707)) < 0.02)
    }
}
