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
}
