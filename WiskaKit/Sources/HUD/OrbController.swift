import AppKit
import Core
import SwiftUI

/// The Magical Orb theme: always on screen while chosen, dragged anywhere, glowing with the voice.
@MainActor
final class OrbController: DictationPresenter {
    private let model = OrbModel()
    let panel: FloatingPanel
    private var options: ThemeOptions
    private var appHighlight: Highlight
    private var generation = 0

    init(_ setup: PresenterSetup) {
        options = setup.options
        appHighlight = setup.highlight
        let side = setup.options.orbSize
        panel = FloatingPanel(size: CGSize(width: side, height: side), behavior: setup.options.orbBehavior)
        panel.contentView = DragHostingView(rootView: OrbView(model: model))
        panel.onDragEnded = setup.onMoved
        panel.onVisibilityChanged = { [weak model] visible in
            if model?.isCovered == visible { model?.isCovered = !visible }
        }
        updateColour()
        panel.place(origin: setup.origin)
        panel.orderFrontRegardless()
    }

    var highlight: Highlight {
        get { appHighlight }
        set { appHighlight = newValue; updateColour() }
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

    private func present(_ content: HUDContent) {
        model.presence.update(content)
        // Audio frames don't need a new revision: the running timeline reads them.
        if model.presence.takeMoodChange() { model.revision += 1 }
        // The celebration ends on its own: redraw then, so the orb drops back to its idle pace.
        // Not tied to `generation`: a later hide must not cancel this check.
        if model.presence.mood() == .success {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Presence.successDuration + 0.05))
                guard let self, self.model.presence.takeMoodChange() else { return }
                self.model.revision += 1
            }
        }
    }

    func apply(_ options: ThemeOptions) {
        let resized = options.orbSize != self.options.orbSize
        self.options = options
        panel.behavior = options.orbBehavior
        updateColour()
        if resized {
            // Grow or shrink around the centre, then keep it on screen.
            let old = panel.frame
            let side = options.orbSize
            panel.place(origin: CGPoint(x: old.midX - side / 2, y: old.midY - side / 2),
                        size: CGSize(width: side, height: side))
            panel.onDragEnded?(panel.frame.origin)
        }
    }

    func deactivate() {
        generation += 1
        panel.close()
    }

    private func updateColour() {
        model.colour = appHighlight
    }
}
