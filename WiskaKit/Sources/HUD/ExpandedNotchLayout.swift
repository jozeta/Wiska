import CoreGraphics

/// The Expanded Notch: a bar exactly as tall as the notch, growing out of both its sides.
/// Without a notch it sits in the middle of the menu bar, as tall as the menu bar.
enum ExpandedNotchLayout {
    /// Each side's width.
    static let wing: CGFloat = 150
    /// The space between the two sides when there's no notch to wrap around.
    static let gapWithoutNotch: CGFloat = 24
    /// For a screen whose menu bar is hidden.
    static let fallbackHeight: CGFloat = 32

    struct Placement: Equatable {
        var frame: CGRect
        /// The notch's width (or the gap between the sides without one).
        var centerWidth: CGFloat
        var hasNotch: Bool
    }

    static func placement(on screen: NotchLayout.Screen) -> Placement {
        if let notch = NotchLayout.notchWidth(screen), let left = screen.auxLeft {
            let height = screen.safeTop
            return Placement(frame: CGRect(x: left.maxX - wing, y: screen.frame.maxY - height,
                                           width: notch + 2 * wing, height: height),
                             centerWidth: notch, hasNotch: true)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let height = menuBar > 0 ? menuBar : fallbackHeight
        let width = gapWithoutNotch + 2 * wing
        return Placement(frame: CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height,
                                       width: width, height: height),
                         centerWidth: gapWithoutNotch, hasNotch: false)
    }

    /// The waveform's bars scaled to leave 4 pt above and below them.
    static func waveformScale(height: CGFloat) -> CGFloat {
        min(1, max(0.3, (height - 8) / WaveformView.maxBar))
    }
}
