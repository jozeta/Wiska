import AppKit
import Core
import SwiftUI

/// The notch capsule: a click-through panel above the menu bar that never takes focus.
/// The panel keeps a fixed frame while shown; the capsule glides inside it (`HUDModel.reveal`).
@MainActor
public final class HUDPanelController {
    static let contentSize = CGSize(width: NotchLayout.fallbackWidth, height: HUDView.contentHeight)

    private let model = HUDModel()
    private let panel: NSPanel
    private var requested: HUDContent = .hidden
    /// Bumped by every show and hide, so a finished hide animation only orders the panel out
    /// if nothing has happened since (a quick hide → show must not cut short).
    private var generation = 0

    public init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
    }

    public var highlight: Highlight {
        get { model.highlight }
        set { model.highlight = newValue }
    }

    public func show(_ content: HUDContent) {
        guard content != requested else { return }
        requested = content
        generation += 1
        guard content != .hidden else { return hide() }
        if !panel.isVisible { place() }
        // Waveform levels update ~10×/s: only a change of kind (listening → transcribing) cross-fades.
        if Self.kind(model.content) == Self.kind(content) {
            model.content = content
        } else {
            withAnimation(.easeInOut(duration: 0.12)) { model.content = content }
        }
        if model.reveal < 1 {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { model.reveal = 1 }
        }
    }

    private func place() {
        guard let screen = activeScreen() else { return }
        let placement = NotchLayout.placement(on: Self.layoutScreen(screen), referenceWidth: Self.referenceWidth,
                                              contentHeight: HUDView.contentHeight)
        model.insetTop = placement.contentInsetTop
        model.hasNotch = placement.hasNotch
        model.reveal = 0
        panel.setFrame(placement.frame, display: false)
        panel.orderFrontRegardless()
    }

    private func hide() {
        let token = generation
        withAnimation(.easeIn(duration: 0.2)) {
            model.reveal = 0
        } completion: { [weak self] in
            guard let self, self.generation == token else { return }   // shown again meanwhile
            self.model.content = .hidden
            self.panel.orderOut(nil)
        }
    }

    private static func kind(_ content: HUDContent) -> Int {
        switch content {
        case .hidden: 0
        case .listening: 1
        case .working: 2
        case .message: 3
        case .error: 4
        }
    }

    /// The built-in notch width, so capsules on other screens match it.
    private static var referenceWidth: CGFloat {
        NSScreen.screens.lazy.compactMap { NotchLayout.notchWidth(layoutScreen($0)) }.first
            ?? NotchLayout.fallbackWidth
    }

    private static func layoutScreen(_ screen: NSScreen) -> NotchLayout.Screen {
        NotchLayout.Screen(frame: screen.frame, visibleFrame: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
                           auxLeft: screen.auxiliaryTopLeftArea, auxRight: screen.auxiliaryTopRightArea)
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
