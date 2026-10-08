import CoreGraphics

/// Where the capsule goes: exactly the notch when there is one, the same width under the menu bar otherwise.
public enum NotchLayout {
    /// The MacBook notch width, used when no screen reports one.
    public static let fallbackWidth: CGFloat = 331

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

    public static func notchWidth(_ screen: Screen) -> CGFloat? {
        guard screen.safeTop > 0, let left = screen.auxLeft, let right = screen.auxRight,
              right.minX > left.maxX else { return nil }
        return right.minX - left.maxX
    }

    /// Exactly the notch on notched screens; elsewhere the same width, hanging from under the menu bar.
    public static func placement(on screen: Screen, referenceWidth: CGFloat, contentHeight: CGFloat) -> Placement {
        if let width = notchWidth(screen), let left = screen.auxLeft {
            let height = screen.safeTop + contentHeight
            return Placement(frame: CGRect(x: left.maxX, y: screen.frame.maxY - height, width: width, height: height),
                             contentInsetTop: screen.safeTop, hasNotch: true)
        }
        let frame = CGRect(x: screen.frame.midX - referenceWidth / 2, y: screen.visibleFrame.maxY - contentHeight,
                           width: referenceWidth, height: contentHeight)
        return Placement(frame: frame, contentInsetTop: 0, hasNotch: false)
    }
}
