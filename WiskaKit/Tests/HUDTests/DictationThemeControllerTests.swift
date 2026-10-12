import Core
import CoreGraphics
import Testing
@testable import HUD

@MainActor
final class FakePresenter: DictationPresenter {
    let theme: DictationTheme
    var shown: [HUDContent] = []
    var highlight: Highlight = .aurora
    var options = ThemeOptions()
    var deactivated = false
    init(_ theme: DictationTheme) { self.theme = theme }
    func show(_ content: HUDContent, hideAfter delay: Duration) { shown.append(content) }
    func apply(_ options: ThemeOptions) { self.options = options }
    func deactivate() { deactivated = true }
}

@MainActor
struct DictationThemeControllerTests {
    final class Made { var all: [FakePresenter] = []; var setups: [PresenterSetup] = [] }

    private func controller(_ theme: DictationTheme, _ made: Made) -> DictationThemeController {
        DictationThemeController(theme: theme, make: { theme, setup in
            let presenter = FakePresenter(theme)
            made.all.append(presenter)
            made.setups.append(setup)
            return presenter
        })
    }

    let listening = HUDContent.listening(audio: AudioLevel(level: 0.4), badge: "EN", preview: "hello",
                                         handsFree: false)

    @Test func showsGoToTheSelectedTheme() {
        let made = Made()
        let themes = controller(.orb, made)
        themes.show(listening)
        #expect(made.all.map(\.theme) == [.orb])
        #expect(made.all[0].shown == [listening])
    }

    @Test func switchingHandsTheCurrentDictationToTheNewTheme() {
        let made = Made()
        let themes = controller(.notchDropdown, made)
        themes.highlight = .sunset
        themes.options.orbSize = 200
        themes.show(listening)
        themes.theme = .clippy
        #expect(made.all.count == 2)
        #expect(made.all[0].deactivated)
        #expect(!made.all[1].deactivated)
        #expect(made.all[1].shown == [listening])     // picks up mid-dictation, nothing restarts
        #expect(made.all[1].highlight == .sunset)
        #expect(made.setups[1].options.orbSize == 200)
        themes.show(.working("Transcribing…"))
        #expect(made.all[0].shown == [listening])     // the old theme hears nothing more
        #expect(made.all[1].shown.last == .working("Transcribing…"))
    }

    @Test func switchingWhileIdleShowsNothing() {
        let made = Made()
        let themes = controller(.notchDropdown, made)
        themes.theme = .expandedNotch
        #expect(made.all[1].shown.isEmpty)
    }

    @Test func choosingTheSameThemeAgainKeepsItsPresenter() {
        let made = Made()
        let themes = controller(.orb, made)
        themes.theme = .orb
        #expect(made.all.count == 1)
    }

    @Test func optionsAndMovesReachThePresenter() {
        let made = Made()
        var moved: [(DictationTheme, CGPoint)] = []
        let themes = controller(.orb, made)
        themes.onMoved = { moved.append(($0, $1)) }
        themes.options.orbBehavior = .desktop
        #expect(made.all[0].options.orbBehavior == .desktop)
        made.setups[0].onMoved(CGPoint(x: 5, y: 6))
        #expect(moved.count == 1 && moved[0].0 == .orb && moved[0].1 == CGPoint(x: 5, y: 6))
    }

    @Test func savedPositionsAreHandedToNewPresenters() {
        let made = Made()
        let themes = controller(.notchDropdown, made)
        themes.savedOrigin = { $0 == .clippy ? CGPoint(x: 1, y: 2) : nil }
        themes.theme = .clippy
        #expect(made.setups[1].origin == CGPoint(x: 1, y: 2))
    }
}
