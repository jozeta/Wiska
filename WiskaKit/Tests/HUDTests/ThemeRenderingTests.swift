import AppKit
import Core
import Testing
@testable import HUD

@MainActor
struct ThemeRenderingTests {
    /// One waveform across listening → working, so it settles flat instead of being replaced.
    @Test func expandedNotchKeepsOneWaveformThroughTheDictation() {
        let speech = AudioLevel(level: 0.5)
        #expect(ExpandedNotchView.waveformAudio(for: .listening(audio: speech, badge: "EN", preview: "",
                                                                handsFree: false)) == speech)
        #expect(ExpandedNotchView.waveformAudio(for: .working("Transcribing…")) == .silent)
        #expect(ExpandedNotchView.waveformAudio(for: .hidden) == nil)
        #expect(ExpandedNotchView.waveformAudio(for: .error("x")) == nil)
    }

    /// Audio frames arrive ~60×/s; the bubble window must not be re-laid-out for each one.
    @Test(.enabled(if: !NSScreen.screens.isEmpty))
    func clippysBubbleIsPlacedOncePerAppearanceNotPerAudioFrame() {
        let clippy = ClippyController(PresenterSetup(options: ThemeOptions(), highlight: .aurora, origin: nil,
                                                     onMoved: { _ in }))
        defer { clippy.deactivate() }
        let before = clippy.bubbleLayouts
        for i in 0..<30 {
            clippy.show(.listening(audio: AudioLevel(level: Float(i) / 30), badge: "EN", preview: "hello",
                                   handsFree: false), hideAfter: .zero)
        }
        #expect(clippy.bubbleLayouts - before <= 1, "\(clippy.bubbleLayouts - before) layouts for 30 frames")
    }
}
