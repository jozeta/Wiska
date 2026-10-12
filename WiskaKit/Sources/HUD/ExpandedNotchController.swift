import AppKit
import Core
import SwiftUI

/// The Expanded Notch theme: a click-through bar around the notch that never takes focus.
@MainActor
final class ExpandedNotchController: DictationPresenter {
    private let model = ExpandedNotchModel()
    let panel: NSPanel
    private var requested: HUDContent = .hidden
    /// Bumped by every show and hide, so a stale hide never cuts a newer show short.
    private var generation = 0

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 2 * ExpandedNotchLayout.wing + 200, height: 32),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: ExpandedNotchView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    var highlight: Highlight {
        get { model.highlight }
        set { model.highlight = newValue }
    }

    var placementForTesting: ExpandedNotchLayout.Placement?

    func show(_ content: HUDContent, hideAfter delay: Duration) {
        guard content != requested else { return }
        requested = content
        generation += 1
        guard content != .hidden else {
            guard delay > .zero else { return hide() }
            let token = generation
            Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard let self, self.generation == token else { return }
                self.hide()
            }
            return
        }
        if !panel.isVisible { place() }
        if Self.sameKind(model.content, content) {
            model.content = content          // audio frames, ~60×/s
        } else {
            withAnimation(.easeInOut(duration: 0.12)) { model.content = content }
        }
        if model.reveal < 1 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { model.reveal = 1 }
        }
    }

    func deactivate() {
        generation += 1
        requested = .hidden
        model.content = .hidden
        model.reveal = 0
        panel.close()
    }

    private func hide() {
        let token = generation
        withAnimation(.easeIn(duration: 0.2)) {
            model.reveal = 0
        } completion: { [weak self] in
            guard let self, self.generation == token else { return }
            self.model.content = .hidden
            self.panel.orderOut(nil)
        }
    }

    private func place() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let placement = ExpandedNotchLayout.placement(on: NotchLayout.Screen(
            frame: screen.frame, visibleFrame: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
            auxLeft: screen.auxiliaryTopLeftArea, auxRight: screen.auxiliaryTopRightArea))
        placementForTesting = placement
        model.centerWidth = placement.centerWidth
        model.height = placement.frame.height
        model.hasNotch = placement.hasNotch
        model.reveal = 0
        panel.setFrame(placement.frame, display: false)
        panel.orderFrontRegardless()
    }

    private static func sameKind(_ a: HUDContent, _ b: HUDContent) -> Bool {
        switch (a, b) {
        case (.listening, .listening), (.working, .working), (.message, .message), (.error, .error),
             (.hidden, .hidden): true
        default: false
        }
    }
}
