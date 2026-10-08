import CoreGraphics
import Testing
@testable import HUD

struct NotchLayoutTests {
    // Measured on the dev MacBook (2026-10-08).
    let macBook = NotchLayout.Screen(
        frame: CGRect(x: 0, y: 0, width: 2704, height: 1756),
        visibleFrame: CGRect(x: 0, y: 0, width: 2704, height: 1698),
        safeTop: 57,
        auxLeft: CGRect(x: 0, y: 1699, width: 1186.5, height: 57),
        auxRight: CGRect(x: 1517.5, y: 1699, width: 1186.5, height: 57))

    let external = NotchLayout.Screen(
        frame: CGRect(x: 2704, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 2704, y: 0, width: 1920, height: 1055),
        safeTop: 0, auxLeft: nil, auxRight: nil)

    @Test func notchedScreenGrowsOutOfTheNotch() {
        let p = NotchLayout.placement(on: macBook, content: CGSize(width: 240, height: 44))
        #expect(p.hasNotch)
        #expect(p.frame.width == 371)                 // notch 331 + 40 > content 240
        #expect(p.frame.height == 101)                // 57 + 44
        #expect(p.frame.maxY == 1756)                 // flush with the top edge
        #expect(p.frame.midX == 1352)                 // centred on the notch
        #expect(p.contentInsetTop == 57)
    }

    @Test func wideContentWidensTheCapsule() {
        let p = NotchLayout.placement(on: macBook, content: CGSize(width: 420, height: 44))
        #expect(p.frame.width == 420)
    }

    @Test func plainScreenHangsBelowMenuBar() {
        let p = NotchLayout.placement(on: external, content: CGSize(width: 240, height: 44))
        #expect(!p.hasNotch)
        #expect(p.frame == CGRect(x: 2704 + 840, y: 1055 - 6 - 44, width: 240, height: 44))
        #expect(p.contentInsetTop == 0)
    }
}
