import CoreGraphics

/// Frames for the capsule's grow/shrink animation.
enum HUDTransition {
    /// Just the notch strip (plus one point) — where the capsule grows from and shrinks to.
    static func collapsedFrame(_ placement: NotchLayout.Placement) -> CGRect {
        var frame = placement.frame
        frame.origin.y = placement.frame.maxY - placement.contentInsetTop - 1
        frame.size.height = placement.contentInsetTop + 1
        return frame
    }

    /// Where a (re)expansion starts: from the notch when hidden, or — if a hide is still
    /// animating (e.g. the language flash right after a dictation) — from where the capsule
    /// is now, so it doesn't snap thin and regrow.
    static func expandStart(placement: NotchLayout.Placement, currentFrame: CGRect, isVisible: Bool) -> CGRect {
        isVisible ? currentFrame : collapsedFrame(placement)
    }
}
