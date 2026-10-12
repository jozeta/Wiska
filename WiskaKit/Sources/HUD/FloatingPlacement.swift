import CoreGraphics

/// Where a floating theme's window goes: its saved spot, kept fully on a screen that exists now.
enum FloatingPlacement {
    /// Inset from the screen corner for the first, default position.
    static let margin: CGFloat = 40

    /// `screens`: visible frames, the main (menu bar) screen first.
    static func frame(origin: CGPoint?, size: CGSize, screens: [CGRect]) -> CGRect {
        guard let main = screens.first else { return CGRect(origin: origin ?? .zero, size: size) }
        guard let origin else {
            // Bottom-right of the main screen, out of the way of menus and the Dock's usual centre.
            return clamp(CGRect(x: main.maxX - margin - size.width, y: main.minY + margin,
                                width: size.width, height: size.height), into: main)
        }
        let frame = CGRect(origin: origin, size: size)
        let screen = screens.max { overlap(frame, $0) < overlap(frame, $1) }
            .flatMap { overlap(frame, $0) > 0 ? $0 : nil }
            ?? screens.min { distance(frame, $0) < distance(frame, $1) }!
        return clamp(frame, into: screen)
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    private static func distance(_ frame: CGRect, _ screen: CGRect) -> CGFloat {
        let dx = max(screen.minX - frame.midX, 0, frame.midX - screen.maxX)
        let dy = max(screen.minY - frame.midY, 0, frame.midY - screen.maxY)
        return dx * dx + dy * dy
    }

    private static func clamp(_ frame: CGRect, into screen: CGRect) -> CGRect {
        var frame = frame
        frame.origin.x = max(screen.minX, min(frame.minX, screen.maxX - frame.width))
        frame.origin.y = max(screen.minY, min(frame.minY, screen.maxY - frame.height))
        return frame
    }
}
