import AppKit
import Core
import SwiftUI

/// A borderless, transparent window for the floating themes (orb, Clippy). It never takes focus
/// — the app being dictated into stays active — and the user drags it by its content.
/// Kept on a screen that exists: after every drag and whenever displays change.
@MainActor
final class FloatingPanel: NSPanel {
    var behavior: FloatingWindowBehavior { didSet { applyBehavior() } }
    /// The window moved (during a drag too), for windows that follow it.
    var onMove: (() -> Void)?
    /// A drag ended at this origin.
    var onDragEnded: ((CGPoint) -> Void)?
    /// The window became visible (true) or fully covered, off screen or on another Space (false):
    /// the animation pauses while nobody can see it.
    var onVisibilityChanged: ((Bool) -> Void)?
    private var screenObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?

    init(size: CGSize, behavior: FloatingWindowBehavior) {
        self.behavior = behavior
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false            // moved by `DragHostingView`, not by the window server
        isReleasedWhenClosed = false
        applyBehavior()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepOnScreen() }
        }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onVisibilityChanged?(self.occlusionState.contains(.visible))
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Above normal windows, or on the desktop: just above the wallpaper and icons, below every
    /// app window (macOS has no public API to embed a window in the desktop itself).
    static func level(for behavior: FloatingWindowBehavior) -> NSWindow.Level {
        switch behavior {
        case .alwaysOnTop: .floating
        case .desktop: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }

    static func collectionBehavior(for behavior: FloatingWindowBehavior) -> NSWindow.CollectionBehavior {
        switch behavior {
        case .alwaysOnTop: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        case .desktop: [.canJoinAllSpaces, .stationary, .ignoresCycle]
        }
    }

    private func applyBehavior() {
        level = Self.level(for: behavior)
        collectionBehavior = Self.collectionBehavior(for: behavior)
        for child in childWindows ?? [] {
            child.level = level
            child.collectionBehavior = collectionBehavior
        }
    }

    /// Puts the window at `origin` (nil = its default spot), clamped to a screen present now.
    func place(origin: CGPoint?, size: CGSize? = nil) {
        let frame = FloatingPlacement.frame(origin: origin, size: size ?? self.frame.size,
                                            screens: NSScreen.screens.map(\.visibleFrame))
        setFrame(frame, display: true)
        onMove?()
    }

    func keepOnScreen() {
        place(origin: frame.origin)
    }

    override func close() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        onVisibilityChanged = nil
        onMove = nil
        onDragEnded = nil
        super.close()
    }
}

/// Hosts a floating theme's SwiftUI view and drags its window. A click does nothing else — it
/// can't start a dictation or reach the app underneath.
final class DragHostingView<Content: View>: NSHostingView<Content> {
    private var grab: CGPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        grab = CGPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let grab else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(CGPoint(x: mouse.x - grab.x, y: mouse.y - grab.y))
        (window as? FloatingPanel)?.onMove?()
    }

    override func mouseUp(with event: NSEvent) {
        guard grab != nil, let panel = window as? FloatingPanel else { return }
        grab = nil
        panel.keepOnScreen()
        panel.onDragEnded?(panel.frame.origin)
    }

    override func rightMouseDown(with event: NSEvent) {}
}
