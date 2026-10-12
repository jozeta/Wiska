import CoreGraphics
import Testing
@testable import HUD

struct FloatingPlacementTests {
    let main = CGRect(x: 0, y: 0, width: 1512, height: 944)       // visible frames
    let right = CGRect(x: 1512, y: -200, width: 1920, height: 1055)
    let size = CGSize(width: 140, height: 140)

    @Test func noSavedPositionUsesTheDefaultCornerOfTheMainScreen() {
        let frame = FloatingPlacement.frame(origin: nil, size: size, screens: [main, right])
        #expect(main.contains(frame))
        #expect(frame.maxX == main.maxX - FloatingPlacement.margin)
        #expect(frame.minY == main.minY + FloatingPlacement.margin)
    }

    @Test func aSavedPositionInsideAScreenIsKept() {
        let frame = FloatingPlacement.frame(origin: CGPoint(x: 2000, y: 300), size: size, screens: [main, right])
        #expect(frame.origin == CGPoint(x: 2000, y: 300))
    }

    @Test func aPositionHangingOffTheEdgeIsPulledBackIn() {
        let frame = FloatingPlacement.frame(origin: CGPoint(x: 1450, y: 900), size: size, screens: [main])
        #expect(main.contains(frame))
    }

    @Test func aDisconnectedScreensPositionMovesToTheNearestScreen() {
        let frame = FloatingPlacement.frame(origin: CGPoint(x: 2600, y: 400), size: size, screens: [main])
        #expect(main.contains(frame))
        #expect(frame.maxX == main.maxX)   // nearest edge, not the far corner
    }

    @Test func noScreensKeepsTheSavedPosition() {
        let frame = FloatingPlacement.frame(origin: CGPoint(x: 10, y: 10), size: size, screens: [])
        #expect(frame.origin == CGPoint(x: 10, y: 10))
    }

    @Test func aWindowLargerThanTheScreenStartsAtItsCorner() {
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 100)
        let frame = FloatingPlacement.frame(origin: CGPoint(x: 50, y: 50), size: size, screens: [tiny])
        #expect(frame.origin == CGPoint(x: 0, y: 0))
    }
}
