import AppKit
import SwiftUI

/// The notch capsule: a click-through panel above the menu bar that never takes focus.
@MainActor
public final class HUDPanelController {
    static let contentSize = CGSize(width: 260, height: 44)
    static let animation: TimeInterval = 0.18
    /// Failure texts shown in the danger colour (matches DictationFailure messages).
    static let errorMessages: Set<String> = [
        "No speech detected", "Can't type here", "Microphone unavailable",
        "Couldn't transcribe", "Couldn't insert text",
    ]

    private let model = HUDModel()
    private let panel: NSPanel
    private var placement: NotchLayout.Placement?

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

    public func show(_ content: HUDContent) {
        guard model.content != content else { return }
        let wasHidden = model.content == .hidden
        if content == .hidden {
            collapse()
            return
        }
        if case .message(let text) = content { model.isError = Self.errorMessages.contains(text) }
        else { model.isError = false }
        model.content = content
        if wasHidden { expand() }
    }

    private func expand() {
        guard let screen = activeScreen() else { return }
        let placement = NotchLayout.placement(on: NotchLayout.Screen(
            frame: screen.frame, visibleFrame: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
            auxLeft: screen.auxiliaryTopLeftArea, auxRight: screen.auxiliaryTopRightArea),
            content: Self.contentSize)
        self.placement = placement
        model.insetTop = placement.contentInsetTop
        model.hasNotch = placement.hasNotch
        var start = placement.frame
        start.origin.y = placement.frame.maxY - placement.contentInsetTop - 1
        start.size.height = placement.contentInsetTop + 1
        panel.setFrame(start, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animation
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(placement.frame, display: true)
        }
    }

    private func collapse() {
        guard let placement else {
            model.content = .hidden
            panel.orderOut(nil)
            return
        }
        var end = placement.frame
        end.origin.y = placement.frame.maxY - placement.contentInsetTop - 1
        end.size.height = placement.contentInsetTop + 1
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.animation
            panel.animator().setFrame(end, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.content == .hidden else { return }
                self.panel.orderOut(nil)
            }
        })
        model.content = .hidden
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
