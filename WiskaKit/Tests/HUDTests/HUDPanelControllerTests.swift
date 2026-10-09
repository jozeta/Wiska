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

    /// A double-tap's first tap cancels: the capsule waits before hiding, so the second press
    /// doesn't make it blink.
    @Test(.enabled(if: !NSScreen.screens.isEmpty))
    func delayedHideIsCancelledByTheNextShow() async throws {
        let hud = HUDPanelController()
        let listening = HUDContent.listening(audio: .silent, badge: "EN", preview: "", handsFree: false)
        hud.show(listening)
        hud.show(.hidden, hideAfter: .milliseconds(300))
        try await Task.sleep(for: .milliseconds(100))
        let stillShown = hud.revealForTesting
        #expect(stillShown == 1)   // a plain hide would already be gliding away
        hud.show(listening)
        try await Task.sleep(for: .milliseconds(500))
        let visible = hud.panel.isVisible
        let reveal = hud.revealForTesting
        #expect(visible)
        #expect(reveal == 1)
        hud.show(.hidden)
    }
}
