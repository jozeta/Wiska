import AppKit
import Core
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

    @Test(.enabled(if: !NSScreen.screens.isEmpty))
    func longPreviewNeverWidensTheCapsule() async throws {
        let hud = HUDPanelController()
        hud.show(.listening(audio: .silent, badge: "EN", preview: String(repeating: "words keep coming ", count: 20),
                            handsFree: true))
        try await Task.sleep(for: .milliseconds(300))
        hud.panel.contentView?.layoutSubtreeIfNeeded()
        #expect(hud.panel.frame.width <= 340, "panel width \(hud.panel.frame.width)")
        hud.show(.hidden)
    }

    @Test func capsuleExpandsWithTheFirstWordsAndStaysUntilHidden() {
        let quiet = HUDContent.listening(audio: .silent, badge: "EN", preview: "", handsFree: false)
        let words = HUDContent.listening(audio: .silent, badge: "EN", preview: "hello", handsFree: false)
        #expect(!HUDPanelController.expands(false, for: quiet))
        #expect(HUDPanelController.expands(false, for: words))
        #expect(HUDPanelController.expands(true, for: quiet))
        #expect(HUDPanelController.expands(true, for: .working("Transcribing…")))
        #expect(!HUDPanelController.expands(true, for: .hidden))
    }

    /// A dictation started while the capsule was still hiding starts with one row again.
    @Test func aNewDictationStartsCollapsed() {
        let quiet = HUDContent.listening(audio: .silent, badge: "EN", preview: "", handsFree: false)
        let afterHide = HUDPanelController.expands(true, for: quiet, after: HUDContent.hidden)
        let meanwhile = HUDPanelController.expands(true, for: quiet, after: quiet)
        #expect(afterHide == false)
        #expect(meanwhile == true)
    }
}
