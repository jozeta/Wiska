import Core
import Testing
@testable import Dictation

struct CommandMapperTests {
    private func ctx(_ mode: LanguageMode, canStart: Bool = true) -> HotkeyContext {
        HotkeyContext(mode: mode, primary: .english, toggle: .swedish, canStart: canStart)
    }

    @Test func pressStartsWithRoutedLanguage() {
        #expect(CommandMapper.map(.pressed(shifted: true), context: ctx(.perLanguageHotkeys))
                == MappedHotkey(command: .start(.fixed(.swedish)), newToggleLanguage: nil))
    }

    @Test func pressIsDroppedWhenCannotStart() {
        #expect(CommandMapper.map(.pressed(shifted: false), context: ctx(.autoDetect, canStart: false))
                == MappedHotkey(command: nil, newToggleLanguage: nil))
    }

    @Test func releaseAndCancelPassEvenWithoutPermissions() {
        #expect(CommandMapper.map(.released, context: ctx(.autoDetect, canStart: false)).command == .finish)
        #expect(CommandMapper.map(.cancelled, context: ctx(.autoDetect, canStart: false)).command == .cancel)
        #expect(CommandMapper.map(.tapped(shifted: false), context: ctx(.autoDetect, canStart: false)).command == .cancel)
    }

    @Test func shiftTapFlipsToggleLanguageInToggleMode() {
        #expect(CommandMapper.map(.tapped(shifted: true), context: ctx(.toggle))
                == MappedHotkey(command: .cancel, newToggleLanguage: .english))
    }

    @Test func shiftTapDoesNothingSpecialInOtherModes() {
        #expect(CommandMapper.map(.tapped(shifted: true), context: ctx(.autoDetect)).newToggleLanguage == nil)
        #expect(CommandMapper.map(.tapped(shifted: true), context: ctx(.perLanguageHotkeys)).newToggleLanguage == nil)
    }

    @Test func plainTapNeverFlips() {
        #expect(CommandMapper.map(.tapped(shifted: false), context: ctx(.toggle)).newToggleLanguage == nil)
    }
}
