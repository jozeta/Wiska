import AppKit
import Testing
@testable import HUD

@MainActor
struct HUDPanelControllerTests {
    @Test(.enabled(if: !NSScreen.screens.isEmpty))
    func longMessageNeverWidensTheCapsule() async throws {
        let hud = HUDPanelController()
        hud.show(.error(String(repeating: "This message is far too long for the notch. ", count: 5)))
        hud.panel.contentView?.layoutSubtreeIfNeeded()
        hud.panel.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        hud.panel.contentView?.layoutSubtreeIfNeeded()
        #expect(hud.panel.frame.width <= 340, "panel width \(hud.panel.frame.width)")
        hud.show(.hidden)
    }
}
