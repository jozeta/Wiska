import Core
import CoreGraphics

/// One way of showing dictation on screen. Every theme gets the same `HUDContent` stream from
/// the app; none of them owns or changes the dictation.
@MainActor
public protocol DictationPresenter: AnyObject {
    /// `hideAfter`: wait before hiding, so a show arriving meanwhile keeps the UI up.
    func show(_ content: HUDContent, hideAfter delay: Duration)
    var highlight: Highlight { get set }
    func apply(_ options: ThemeOptions)
    /// Take everything off screen and stop animating: another theme takes over.
    func deactivate()
}

extension DictationPresenter {
    public func apply(_ options: ThemeOptions) {}
}

/// The theme settings presenters need (from `SettingsStore`; HUD doesn't depend on Preferences).
public struct ThemeOptions: Equatable, Sendable {
    public var orbSize: CGFloat = 140
    public var orbBehavior: FloatingWindowBehavior = .alwaysOnTop
    /// Clippy's height in points.
    public var clippySize: CGFloat = 128
    public var clippyBehavior: FloatingWindowBehavior = .alwaysOnTop
    public var clippyFollowsPointer = false

    public init(orbSize: CGFloat = 140, orbBehavior: FloatingWindowBehavior = .alwaysOnTop,
                clippySize: CGFloat = 128, clippyBehavior: FloatingWindowBehavior = .alwaysOnTop,
                clippyFollowsPointer: Bool = false) {
        self.orbSize = orbSize
        self.orbBehavior = orbBehavior
        self.clippySize = clippySize
        self.clippyBehavior = clippyBehavior
        self.clippyFollowsPointer = clippyFollowsPointer
    }
}

/// What a new presenter starts from.
public struct PresenterSetup {
    public var options: ThemeOptions
    public var highlight: Highlight
    /// Where the user last dragged it; nil = its default spot.
    public var origin: CGPoint?
    /// Called with the window's new origin after the user drags it.
    public var onMoved: (CGPoint) -> Void
}

/// Owns the one live presenter for the chosen theme. Switching drops the old presenter (its
/// windows close, its animations stop) and hands the current content to the new one, so a
/// switch mid-dictation changes only what's on screen.
@MainActor
public final class DictationThemeController {
    public typealias Factory = (DictationTheme, PresenterSetup) -> any DictationPresenter

    public var theme: DictationTheme {
        didSet { if theme != oldValue { activate() } }
    }
    public var highlight: Highlight = .aurora {
        didSet { presenter.highlight = highlight }
    }
    public var options = ThemeOptions() {
        didSet { if options != oldValue { presenter.apply(options) } }
    }
    /// Where each floating theme was last left; read when one is (re)created.
    public var savedOrigin: (DictationTheme) -> CGPoint? = { _ in nil }
    /// The user dragged a floating theme to a new spot.
    public var onMoved: ((DictationTheme, CGPoint) -> Void)?

    private let make: Factory
    private(set) var presenter: any DictationPresenter
    private var content: HUDContent = .hidden

    public init(theme: DictationTheme, highlight: Highlight = .aurora, options: ThemeOptions = ThemeOptions(),
                savedOrigin: @escaping (DictationTheme) -> CGPoint? = { _ in nil }, make: Factory? = nil) {
        self.theme = theme
        self.highlight = highlight
        self.options = options
        self.savedOrigin = savedOrigin
        self.make = make ?? Self.makePresenter
        presenter = Self.placeholder
        presenter = build()
    }

    public func show(_ content: HUDContent, hideAfter delay: Duration = .zero) {
        self.content = content
        presenter.show(content, hideAfter: delay)
    }

    private func activate() {
        presenter.deactivate()
        presenter = build()
        if content != .hidden { presenter.show(content, hideAfter: .zero) }
    }

    private func build() -> any DictationPresenter {
        let presenter = make(theme, setup(for: theme))
        presenter.highlight = highlight
        return presenter
    }

    /// Stands in for the instant before the first presenter exists (init can't call `build` sooner).
    private static let placeholder: any DictationPresenter = NoPresenter()

    private func setup(for theme: DictationTheme) -> PresenterSetup {
        PresenterSetup(options: options, highlight: highlight, origin: savedOrigin(theme),
                       onMoved: { [weak self] origin in self?.onMoved?(theme, origin) })
    }

    private static func makePresenter(_ theme: DictationTheme, _ setup: PresenterSetup) -> any DictationPresenter {
        switch theme {
        case .notchDropdown: HUDPanelController()
        case .expandedNotch: ExpandedNotchController()
        case .orb: OrbController(setup)
        case .clippy: ClippyController(setup)
        }
    }
}

@MainActor
private final class NoPresenter: DictationPresenter {
    var highlight: Highlight = .aurora
    func show(_ content: HUDContent, hideAfter delay: Duration) {}
    func deactivate() {}
}
