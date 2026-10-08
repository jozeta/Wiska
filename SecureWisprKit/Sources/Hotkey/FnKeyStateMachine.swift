import Core
import Foundation

public enum KeyInput: Equatable {
    case flagsChanged(fnDown: Bool, shift: Bool, time: TimeInterval)
    case keyDown(time: TimeInterval)
}

/// Turns raw fn / key events into push-to-talk events.
/// - fn down → `.pressed(shifted:)` (recording starts immediately).
/// - fn up after ≥ `minimumHold` → `.released`; sooner → `.tapped(shifted:)`.
/// - any key down while fn is held → `.cancelled` once; the later fn up is then silent.
///   ⇧ is a modifier (flagsChanged), so it never counts as "another key".
public struct FnKeyStateMachine {
    public var minimumHold: TimeInterval = 0.25
    private var pressedAt: TimeInterval?
    private var shifted = false
    private var interrupted = false

    public init() {}

    public mutating func handle(_ input: KeyInput) -> HotkeyEvent? {
        switch input {
        case .flagsChanged(fnDown: true, shift: let shift, time: let time):
            // fn went DOWN.
            guard pressedAt == nil else { return nil }
            pressedAt = time
            shifted = shift
            interrupted = false
            return .pressed(shifted: shift)

        case .keyDown:
            // Another key was pressed.
            guard pressedAt != nil, !interrupted else { return nil }
            interrupted = true
            return .cancelled

        case .flagsChanged(fnDown: false, shift: _, time: let time):
            // fn went UP.
            guard let start = pressedAt else { return nil }
            pressedAt = nil
            if interrupted { return nil }
            return time - start < minimumHold ? .tapped(shifted: shifted) : .released
        }
    }

    /// Forget any hold in progress (used when the event tap was disabled and events may
    /// have been missed). Returns true if a hold was in progress.
    public mutating func reset() -> Bool {
        defer {
            pressedAt = nil
            shifted = false
            interrupted = false
        }
        return pressedAt != nil && !interrupted
    }
}
