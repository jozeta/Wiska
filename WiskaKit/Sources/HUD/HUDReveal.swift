import CoreGraphics

/// The glide: `reveal` goes 0 (tucked into the notch) → 1 (fully down).
enum HUDReveal {
    static let slide: CGFloat = 6

    static func visibleHeight(insetTop: CGFloat, contentHeight: CGFloat, reveal: CGFloat) -> CGFloat {
        insetTop + reveal * contentHeight
    }

    static func contentOffset(reveal: CGFloat) -> CGFloat {
        (reveal - 1) * slide
    }
}
