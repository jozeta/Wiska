import Core
import Testing
@testable import Dictation

struct CommandMapperTests {
    private func ctx(_ mode: LanguageMode, canStart: Bool = true) -> HotkeyContext {
        HotkeyContext(mode: mode, primary: .english, secondary: .swedish, toggle: .swedish,
                      enabled: [.english, .swedish], canStart: canStart)
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

    @Test func lateShiftSwitchesLanguageInPerLanguageMode() {
        #expect(CommandMapper.map(.shiftAdded, context: ctx(.perLanguageHotkeys))
                == MappedHotkey(command: .switchLanguage(.fixed(.swedish)), newToggleLanguage: nil))
    }

    @Test func lateShiftDoesNothingInOtherModesOrWithoutPermissions() {
        #expect(CommandMapper.map(.shiftAdded, context: ctx(.toggle)).command == nil)
        #expect(CommandMapper.map(.shiftAdded, context: ctx(.autoDetect)).command == nil)
        #expect(CommandMapper.map(.shiftAdded, context: ctx(.perLanguageHotkeys, canStart: false)).command == nil)
    }

    @Test func shiftTapCyclesThroughThreeTickedLanguages() {
        let context = HotkeyContext(mode: .toggle, primary: .english, secondary: .swedish, toggle: .swedish,
                                    enabled: [.english, .swedish, .german], canStart: true)
        #expect(CommandMapper.map(.tapped(shifted: true), context: context).newToggleLanguage == .german)
    }

    @Test func shiftTapWithOneLanguageChangesNothing() {
        let context = HotkeyContext(mode: .toggle, primary: .english, secondary: .english, toggle: .english,
                                    enabled: [.english], canStart: true)
        #expect(CommandMapper.map(.tapped(shifted: true), context: context).newToggleLanguage == nil)
    }

    @Test func lockedMapsToLockHandsFree() {
        let context = HotkeyContext(mode: .autoDetect, primary: .english, secondary: .swedish, toggle: .english,
                                    enabled: [.english, .swedish], canStart: true)
        #expect(CommandMapper.map(.locked, context: context)
                == MappedHotkey(command: .lockHandsFree, newToggleLanguage: nil))
    }

    @Test func commandAddedMakesACommand() {
        let mapped = CommandMapper.map(.commandAdded, context: HotkeyContext(
            mode: .autoDetect, primary: .english, secondary: .swedish, toggle: .english,
            enabled: [.english, .swedish], canStart: true))
        #expect(mapped == MappedHotkey(command: .makeCommand, newToggleLanguage: nil))
    }
}
