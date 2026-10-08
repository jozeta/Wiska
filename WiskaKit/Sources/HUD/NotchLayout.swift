import CoreGraphics

/// Where the capsule goes: out of the notch when there is one, under the menu bar otherwise.
public enum NotchLayout {
    public static let notchPadding: CGFloat = 40
    public static let menuBarGap: CGFloat = 6

    public struct Screen {
        public var frame: CGRect
        public var visibleFrame: CGRect
        public var safeTop: CGFloat
        public var auxLeft: CGRect?
        public var auxRight: CGRect?

        public init(frame: CGRect, visibleFrame: CGRect, safeTop: CGFloat, auxLeft: CGRect?, auxRight: CGRect?) {
            self.frame = frame
            self.visibleFrame = visibleFrame
            self.safeTop = safeTop
            self.auxLeft = auxLeft
            self.auxRight = auxRight
        }
    }

    public struct Placement: Equatable {
        public var frame: CGRect
        /// Height reserved at the top for the notch itself.
        public var contentInsetTop: CGFloat
        public var hasNotch: Bool
    }

    public static func placement(on screen: Screen, content: CGSize) -> Placement {
        if screen.safeTop > 0, let left = screen.auxLeft, let right = screen.auxRight, right.minX > left.maxX {
            let notchWidth = right.minX - left.maxX
            let width = max(content.width, notchWidth + notchPadding)
            let height = screen.safeTop + content.height
            let midX = (left.maxX + right.minX) / 2
            return Placement(frame: CGRect(x: midX - width / 2, y: screen.frame.maxY - height,
                                           width: width, height: height),
                             contentInsetTop: screen.safeTop, hasNotch: true)
        }
        let frame = CGRect(x: screen.frame.midX - content.width / 2,
                           y: screen.visibleFrame.maxY - menuBarGap - content.height,
                           width: content.width, height: content.height)
        return Placement(frame: frame, contentInsetTop: 0, hasNotch: false)
    }
}
