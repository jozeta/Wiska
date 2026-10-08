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

    @Test func notchedScreenIsExactlyAsWideAsTheNotch() {
        let p = NotchLayout.placement(on: macBook, referenceWidth: 331, contentHeight: 44)
        #expect(p.hasNotch)
        #expect(p.frame == CGRect(x: 1186.5, y: 1756 - 101, width: 331, height: 101))
        #expect(p.contentInsetTop == 57)
    }

    @Test func notchWidthIsMeasuredFromTheScreen() {
        #expect(NotchLayout.notchWidth(macBook) == 331)
        #expect(NotchLayout.notchWidth(external) == nil)
    }

    @Test func plainScreenUsesTheReferenceWidth() {
        let p = NotchLayout.placement(on: external, referenceWidth: 331, contentHeight: 44)
        #expect(!p.hasNotch)
        #expect(p.frame == CGRect(x: 3498.5, y: 1011, width: 331, height: 44))   // centred: 2704 + (1920 − 331) / 2
        #expect(p.contentInsetTop == 0)
    }

    @Test func fallbackWidthMatchesTheMacBookNotch() {
        #expect(NotchLayout.fallbackWidth == 331)
    }
}
