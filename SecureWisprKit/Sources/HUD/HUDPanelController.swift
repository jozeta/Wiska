import AppKit
import SwiftUI

/// A floating, click-through panel that never takes focus from the app being dictated into.
@MainActor
public final class HUDPanelController {
    private static let size = NSSize(width: 260, height: 60)
    private static let bottomMargin: CGFloat = 90

    private let model = HUDModel()
    private let panel: NSPanel

    public init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
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
        model.content = content
        if content == .hidden {
            panel.orderOut(nil)
            return
        }
        if wasHidden {
            positionOnActiveScreen()
            panel.orderFrontRegardless()
        }
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + Self.bottomMargin))
    }
}
