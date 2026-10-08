import Core
import Foundation

public enum KeyInput: Equatable {
    case flagsChanged(fnDown: Bool, time: TimeInterval)
    case keyDown(time: TimeInterval)
}

/// Turns raw fn / key events into push-to-talk events.
/// - fn down → `.pressed` (recording starts immediately).
/// - fn up after ≥ `minimumHold` → `.released`; sooner → `.cancelled` (accidental tap).
/// - any key down while fn is held → `.cancelled` once (user is doing fn+arrow etc.);
///   the later fn up is then silent.
public struct FnKeyStateMachine {
    public var minimumHold: TimeInterval = 0.25
    private var pressedAt: TimeInterval?
    private var interrupted = false

    public init() {}

    public mutating func handle(_ input: KeyInput) -> HotkeyEvent? {
        switch input {
        case .flagsChanged(fnDown: true, time: let time):
            // fn went DOWN.
            // If fn is already held (pressedAt != nil) → return nil.
            // Otherwise: remember the time, clear `interrupted`, return .pressed.
            guard pressedAt == nil else { return nil }
            pressedAt = time
            interrupted = false
            return .pressed

        case .keyDown:
            // Another key was pressed.
            // If fn isn't held, or we already cancelled this hold → return nil.
            // Otherwise: mark interrupted = true, return .cancelled.
            guard pressedAt != nil, !interrupted else { return nil }
            interrupted = true
            return .cancelled

        case .flagsChanged(fnDown: false, time: let time):
            // fn went UP.
            // If it was never pressed → return nil.
            // Otherwise: get the start time and reset pressedAt to nil (so the next hold starts fresh).
            //   If interrupted → return nil (we already sent .cancelled).
            //   If held less than minimumHold → return .cancelled, else return .released.
            guard let start = pressedAt else { return nil }
            pressedAt = nil
            if interrupted { return nil }
            return time - start < minimumHold ? .cancelled : .released
        }
    }
}
