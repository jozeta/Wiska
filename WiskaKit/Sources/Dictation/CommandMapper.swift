import Core

/// Settings + permission state needed to interpret a hotkey event.
public struct HotkeyContext: Sendable, Equatable {
    public var mode: LanguageMode
    public var primary: Language
    /// fn+⇧ language in Per-language hotkeys mode.
    public var secondary: Language
    public var toggle: Language
    /// The ticked languages (Toggle cycles through these).
    public var enabled: [Language]
    /// False while a required permission is missing. Only blocks *starting* (minor d).
    public var canStart: Bool

    public init(mode: LanguageMode, primary: Language, secondary: Language, toggle: Language,
                enabled: [Language], canStart: Bool) {
        self.mode = mode
        self.primary = primary
        self.secondary = secondary
        self.toggle = toggle
        self.enabled = enabled
        self.canStart = canStart
    }
}

public struct MappedHotkey: Equatable {
    public var command: DictationCommand?
    /// Set when a quick fn+⇧ tap in Toggle mode moves to the next ticked language.
    public var newToggleLanguage: Language?

    public init(command: DictationCommand?, newToggleLanguage: Language?) {
        self.command = command
        self.newToggleLanguage = newToggleLanguage
    }
}

public enum CommandMapper {
    public static func map(_ event: HotkeyEvent, context: HotkeyContext) -> MappedHotkey {
        switch event {
        case .pressed(let shifted):
            guard context.canStart else { return MappedHotkey(command: nil, newToggleLanguage: nil) }
            let choice = LanguageRouter.choice(mode: context.mode, shifted: shifted, primary: context.primary,
                                               secondary: context.secondary, toggle: context.toggle)
            return MappedHotkey(command: .start(choice), newToggleLanguage: nil)
        case .released:
            return MappedHotkey(command: .finish, newToggleLanguage: nil)
        case .cancelled:
            return MappedHotkey(command: .cancel, newToggleLanguage: nil)
        case .shiftAdded:
            // Only Per-language mode picks the language from ⇧; Toggle uses it for the tap.
            guard context.canStart, context.mode == .perLanguageHotkeys else {
                return MappedHotkey(command: nil, newToggleLanguage: nil)
            }
            let choice = LanguageRouter.choice(mode: context.mode, shifted: true, primary: context.primary,
                                               secondary: context.secondary, toggle: context.toggle)
            return MappedHotkey(command: .switchLanguage(choice), newToggleLanguage: nil)
        case .locked:
            return MappedHotkey(command: .lockHandsFree, newToggleLanguage: nil)
        case .commandAdded:
            return MappedHotkey(command: .makeCommand, newToggleLanguage: nil)
        case .tapped(let shifted):
            let next = context.toggle.next(in: context.enabled)
            let flip = shifted && context.mode == .toggle && next != context.toggle ? next : nil
            return MappedHotkey(command: .cancel, newToggleLanguage: flip)
        }
    }
}
