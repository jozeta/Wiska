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
        #expect(HUDView.height(expanded: true) == 62)
    }

    @Test func tickerStaysPutUntilTheTextOverflowsThenShowsTheNewestWords() {
        #expect(PreviewTicker.scrollTarget(container: 300, text: 120) == 0)
        #expect(PreviewTicker.scrollTarget(container: 300, text: 276) == 0)
        #expect(PreviewTicker.scrollTarget(container: 300, text: 450) == 174)
    }
}
