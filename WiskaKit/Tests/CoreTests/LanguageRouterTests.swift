import Testing
@testable import Core

struct LanguageRouterTests {
    @Test(arguments: [false, true])
    func autoDetectIsAlwaysAutomatic(shifted: Bool) {
        #expect(LanguageRouter.choice(mode: .autoDetect, shifted: shifted, primary: .swedish, secondary: .english, toggle: .english)
                == .automatic)
    }

    @Test(arguments: [false, true])
    func toggleUsesCurrentToggleLanguage(shifted: Bool) {
        #expect(LanguageRouter.choice(mode: .toggle, shifted: shifted, primary: .english, secondary: .swedish, toggle: .swedish)
                == .fixed(.swedish))
    }

    @Test func perLanguageHotkeysFnIsPrimary() {
        #expect(LanguageRouter.choice(mode: .perLanguageHotkeys, shifted: false, primary: .swedish, secondary: .english, toggle: .english)
                == .fixed(.swedish))
    }

    @Test func perLanguageHotkeysUseTheSecondaryLanguage() {
        #expect(LanguageRouter.choice(mode: .perLanguageHotkeys, shifted: true, primary: .english,
                                      secondary: .german, toggle: .english) == .fixed(.german))
    }

    @Test func perLanguageHotkeysShiftIsTheSecondary() {
        #expect(LanguageRouter.choice(mode: .perLanguageHotkeys, shifted: true, primary: .swedish, secondary: .english, toggle: .english)
                == .fixed(.english))
    }
}
