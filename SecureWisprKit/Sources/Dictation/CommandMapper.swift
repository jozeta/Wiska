import Core

/// Settings + permission state needed to interpret a hotkey event.
public struct HotkeyContext: Sendable, Equatable {
    public var mode: LanguageMode
    public var primary: Language
    public var toggle: Language
    /// False while a required permission is missing. Only blocks *starting* (minor d).
    public var canStart: Bool

    public init(mode: LanguageMode, primary: Language, toggle: Language, canStart: Bool) {
        self.mode = mode
        self.primary = primary
        self.toggle = toggle
        self.canStart = canStart
    }
}

public struct MappedHotkey: Equatable {
    public var command: DictationCommand?
    /// Set when a quick fn+⇧ tap in Toggle mode flips the language.
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
            let choice = LanguageRouter.choice(mode: context.mode, shifted: shifted,
                                               primary: context.primary, toggle: context.toggle)
            return MappedHotkey(command: .start(choice), newToggleLanguage: nil)
        case .released:
            return MappedHotkey(command: .finish, newToggleLanguage: nil)
        case .cancelled:
            return MappedHotkey(command: .cancel, newToggleLanguage: nil)
        case .tapped(let shifted):
            let flip = shifted && context.mode == .toggle ? context.toggle.other : nil
            return MappedHotkey(command: .cancel, newToggleLanguage: flip)
        }
    }
}
