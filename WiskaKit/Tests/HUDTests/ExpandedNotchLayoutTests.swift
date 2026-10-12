import CoreGraphics
import Testing
@testable import HUD

struct ExpandedNotchLayoutTests {
    // A 14" MacBook Pro: 1512 × 982, notch 185 wide and 32 tall.
    let notched = NotchLayout.Screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950), safeTop: 32,
                                     auxLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
                                     auxRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32))
    let external = NotchLayout.Screen(frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
                                      visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415), safeTop: 0,
                                      auxLeft: nil, auxRight: nil)

    @Test func wingsGrowEquallyOutOfBothSidesOfTheNotch() {
        let placement = ExpandedNotchLayout.placement(on: notched)
        #expect(placement.hasNotch)
        #expect(placement.centerWidth == 185)
        #expect(placement.frame.midX == 756)                       // the notch's centre
        #expect(placement.frame.width == 185 + 2 * ExpandedNotchLayout.wing)
    }

    @Test func itIsExactlyAsTallAsTheNotchAndHangsFromTheTop() {
        let placement = ExpandedNotchLayout.placement(on: notched)
        #expect(placement.frame.height == 32)
        #expect(placement.frame.maxY == 982)
    }

    @Test func withoutANotchItSitsInTheMenuBarCentre() {
        let placement = ExpandedNotchLayout.placement(on: external)
        #expect(!placement.hasNotch)
        #expect(placement.frame.height == 25)                      // the menu bar
        #expect(placement.frame.maxY == 1440)
        #expect(abs(placement.frame.midX - 2792) < 0.001)
        #expect(placement.centerWidth == ExpandedNotchLayout.gapWithoutNotch)
    }

    @Test func aScreenWithoutAMenuBarUsesTheFallbackHeight() {
        var hidden = external
        hidden.visibleFrame = hidden.frame
        #expect(ExpandedNotchLayout.placement(on: hidden).frame.height == ExpandedNotchLayout.fallbackHeight)
    }

    @Test func theWaveformShrinksToFitTheBar() {
        #expect(ExpandedNotchLayout.waveformScale(height: 32) < 1)
        #expect(ExpandedNotchLayout.waveformScale(height: 32) * WaveformView.maxBar <= 32 - 8)
        #expect(ExpandedNotchLayout.waveformScale(height: 80) == 1)
    }
}
