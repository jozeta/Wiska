import AppKit
import Core
import SwiftUI

/// The Clippy theme: the character in a draggable floating window, with its speech bubble in a
/// click-through child window that moves with it and flips or slides to stay on screen.
@MainActor
final class ClippyController: DictationPresenter {
    static let characterSize = CGSize(width: 84, height: 128)
    static let bubbleSize = CGSize(width: 250, height: 170)

    private let model = ClippyModel()
    let panel: FloatingPanel
    let bubble: NSPanel
    private var generation = 0

    init(_ setup: PresenterSetup) {
        panel = FloatingPanel(size: Self.characterSize, behavior: setup.options.clippyBehavior)
        panel.contentView = DragHostingView(rootView: ClippyView(model: model))
        bubble = NSPanel(contentRect: NSRect(origin: .zero, size: Self.bubbleSize),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        bubble.ignoresMouseEvents = true
        bubble.hidesOnDeactivate = false
        bubble.isOpaque = false
        bubble.backgroundColor = .clear
        bubble.hasShadow = true
        bubble.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: ClippyBubbleView(model: model))
        hosting.sizingOptions = []
        bubble.contentView = hosting
        model.highlight = setup.highlight
        panel.onDragEnded = setup.onMoved
        panel.onMove = { [weak self] in self?.placeBubble() }
        panel.place(origin: setup.origin)
        panel.orderFrontRegardless()
    }

    var highlight: Highlight {
        get { model.highlight }
        set { model.highlight = newValue }
    }

    func show(_ content: HUDContent, hideAfter delay: Duration) {
        generation += 1
        guard content == .hidden, delay > .zero else { return present(content) }
        let token = generation
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.generation == token else { return }
            self.present(.hidden)
        }
    }

    func apply(_ options: ThemeOptions) {
        panel.behavior = options.clippyBehavior
    }

    func deactivate() {
        generation += 1
        bubble.close()
        panel.close()
    }

    private func present(_ content: HUDContent) {
        let before = model.presence.mood()
        model.presence.update(content)
        let mood = model.presence.mood()
        if mood != before { model.revision += 1 }
        let speech = Self.speech(for: content, mood: mood, lastText: model.text)
        if model.status != speech.status { model.status = speech.status }
        if model.text != speech.text { model.text = speech.text }
        if model.isError != speech.isError { model.isError = speech.isError }
        if speech.visible { showBubble() } else { bubble.orderOut(nil) }
        if mood == .success {
            // "Done" for a moment, then Clippy goes quiet again.
            let token = generation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Presence.successDuration + 0.05))
                guard let self, self.generation == token else { return }
                self.present(.hidden)
            }
        }
    }

    /// What the bubble says for a content. The words come from the live preview (empty when it's
    /// off) and stay up while they're transcribed; they're gone once the dictation ends.
    static func speech(for content: HUDContent, mood: Presence.Mood, lastText: String)
        -> (status: String, text: String, isError: Bool, visible: Bool) {
        switch content {
        case .hidden:
            mood == .success ? ("Done!", "", false, true) : ("", "", false, false)
        case .listening(_, let badge, let preview, let handsFree, let isCommand):
            (isCommand ? "\(badge) — I'm listening…" : handsFree ? "Listening (hands-free)…" : "Listening…",
             preview, false, true)
        case .working(let text, _):
            (text, lastText, false, true)
        case .message(let text):
            (text, "", false, true)
        case .error(let text):
            (text, "", true, true)
        }
    }

    private func showBubble() {
        if bubble.parent == nil {
            bubble.level = panel.level
            bubble.collectionBehavior = panel.collectionBehavior
            panel.addChildWindow(bubble, ordered: .above)
        }
        placeBubble()
        if !bubble.isVisible { bubble.orderFront(nil) }
    }

    private func placeBubble() {
        let screen = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        let placed = BubblePlacement.place(bubble: Self.bubbleSize, character: panel.frame, screen: screen)
        if model.bubbleAbove != placed.above { model.bubbleAbove = placed.above }
        if model.tailX != placed.tailX { model.tailX = placed.tailX }
        bubble.setFrame(placed.frame, display: bubble.isVisible)
    }
}
