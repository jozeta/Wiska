import CoreGraphics
import Testing
@testable import HUD

struct HUDRevealTests {
    @Test func shapeGrowsDownOutOfTheNotch() {
        #expect(HUDReveal.visibleHeight(insetTop: 57, contentHeight: 44, reveal: 0) == 57)
        #expect(HUDReveal.visibleHeight(insetTop: 57, contentHeight: 44, reveal: 0.5) == 79)
        #expect(HUDReveal.visibleHeight(insetTop: 57, contentHeight: 44, reveal: 1) == 101)
    }

    @Test func contentSlidesDownAsItArrives() {
        #expect(HUDReveal.contentOffset(reveal: 0) == -6)
        #expect(HUDReveal.contentOffset(reveal: 1) == 0)
    }

    @Test func previewRowAddsHeightOnlyWhenExpanded() {
        #expect(HUDView.height(expanded: false) == 44)
        #expect(HUDView.height(expanded: true) == 60)
    }

    /// Every word enters from the right: the line starts just past the right edge and its end
    /// is headed for `lead` inside it, however short the text is.
    @Test func tickerTextAlwaysEntersFromTheRight() {
        #expect(PreviewTicker.scrollTarget(text: 0) == 0)
        #expect(PreviewTicker.scrollTarget(text: 120) == 120 + PreviewTicker.lead)
        #expect(PreviewTicker.textX(container: 300, scrolled: 0) == 300)
        #expect(PreviewTicker.textX(container: 300, scrolled: 144) == 156)
    }

    /// Both edges fade over the same width; the newest word rests just clear of the right fade.
    @Test func tickerFadesBothEdgesEqually() {
        let stops = PreviewTicker.fadeStops(width: 300)
        let ramp: CGFloat = 24.0 / 300
        let expected: [CGFloat] = [0, ramp, 1 - ramp, 1]
        #expect(stops.map(\.location) == expected)
        #expect(PreviewTicker.lead > PreviewTicker.fadeWidth)
    }
}
