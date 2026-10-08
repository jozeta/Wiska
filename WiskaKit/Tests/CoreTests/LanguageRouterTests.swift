import Testing
@testable import Core

struct LanguageRouterTests {
    @Test(arguments: [false, true])
    func autoDetectIsAlwaysAutomatic(shifted: Bool) {
        #expect(LanguageRouter.choice(mode: .autoDetect, shifted: shifted, primary: .swedish, toggle: .english)
                == .automatic)
    }

    @Test(arguments: [false, true])
    func toggleUsesCurrentToggleLanguage(shifted: Bool) {
        #expect(LanguageRouter.choice(mode: .toggle, shifted: shifted, primary: .english, toggle: .swedish)
                == .fixed(.swedish))
    }

    @Test func perLanguageHotkeysFnIsPrimary() {
        #expect(LanguageRouter.choice(mode: .perLanguageHotkeys, shifted: false, primary: .swedish, toggle: .english)
                == .fixed(.swedish))
    }

    @Test func perLanguageHotkeysShiftIsTheOther() {
        #expect(LanguageRouter.choice(mode: .perLanguageHotkeys, shifted: true, primary: .swedish, toggle: .english)
                == .fixed(.english))
    }
}
