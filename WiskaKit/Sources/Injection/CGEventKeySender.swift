import CoreGraphics
import Core

@MainActor
public protocol KeySender {
    func sendPaste() throws
}

/// Posts ⌘V to the frontmost app. Requires Accessibility permission.
public struct CGEventKeySender: KeySender {
    private static let vKeyCode: CGKeyCode = 9   // physical V position; same on ANSI and Swedish ISO

    public init() {}

    public func sendPaste() throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        else { throw InjectionError.eventCreationFailed }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static let cKeyCode: CGKeyCode = 8   // physical C position

    /// Posts ⌘C (used to read a selection that Accessibility doesn't expose).
    public func sendCopy() throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: Self.cKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: Self.cKeyCode, keyDown: false)
        else { throw InjectionError.eventCreationFailed }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
