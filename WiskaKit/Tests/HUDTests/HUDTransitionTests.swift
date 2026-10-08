import CoreGraphics
import Testing
@testable import HUD

struct HUDTransitionTests {
    let placement = NotchLayout.Placement(frame: CGRect(x: 1166.5, y: 1655, width: 371, height: 101),
                                          contentInsetTop: 57, hasNotch: true)

    @Test func hiddenPanelGrowsFromTheNotch() {
        let start = HUDTransition.expandStart(placement: placement, currentFrame: .zero, isVisible: false)
        #expect(start == HUDTransition.collapsedFrame(placement))
        #expect(start.height == 58)
        #expect(start.maxY == placement.frame.maxY)
    }

    @Test func stillVisiblePanelContinuesFromWhereItIs() {
        // Language flash right after the hide began: no snap back to the thin start frame.
        let midCollapse = CGRect(x: 1166.5, y: 1680, width: 371, height: 76)
        #expect(HUDTransition.expandStart(placement: placement, currentFrame: midCollapse, isVisible: true)
                == midCollapse)
    }
}
