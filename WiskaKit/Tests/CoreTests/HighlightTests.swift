import Testing
@testable import Core

struct HighlightTests {
    @Test func auroraIsTheCurrentLook() {
        #expect(Highlight.aurora.start == 0x3EE6C1)
        #expect(Highlight.aurora.end == 0x8B6CFF)
    }

    @Test func everyPresetIsAGradient() {
        for preset in Highlight.allCases { #expect(preset.start != preset.end, "\(preset)") }
        #expect(Highlight.allCases.count == 7)
    }

    @Test func rawValuesRoundTrip() {
        for preset in Highlight.allCases { #expect(Highlight(rawValue: preset.rawValue) == preset) }
    }
}
