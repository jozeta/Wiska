import Core
import Foundation

public enum KeyInput: Equatable {
    case flagsChanged(fnDown: Bool, shift: Bool, time: TimeInterval)
    case keyDown(keyCode: Int64, time: TimeInterval)
}

/// Turns raw fn / key events into push-to-talk events.
/// - fn down → `.pressed(shifted:)` (recording starts immediately).
/// - fn up after ≥ `minimumHold` → `.released`; sooner → `.tapped(shifted:)`.
/// - any key down while fn is held → `.cancelled` once; the later fn up is then silent.
///   ⇧ is a modifier (flagsChanged), so it never counts as "another key".
/// - ⇧ down within `minimumHold` of fn down → `.shiftAdded` once, and a tap counts as shifted:
///   people press fn+⇧ together, and ⇧ often lands a moment after fn.
/// - Hands-free: a plain quick tap arms for `doubleTapWindow`; if the next press is also a quick
///   tap, its fn up is `.locked` instead of `.tapped`. While locked, fn up → `.released`,
///   Esc → `.cancelled`, everything else is ignored, until one of those or `unlock()`.
public struct FnKeyStateMachine {
    public static let escapeKeyCode: Int64 = 53
    public var minimumHold: TimeInterval = 0.25
    public var doubleTapWindow: TimeInterval = 0.4
    private var pressedAt: TimeInterval?
    private var shifted = false
    private var interrupted = false
    /// Set by a plain quick tap: until this time, a quick tap locks.
    private var armedUntil: TimeInterval?
    /// The press in progress began while armed.
    private var secondPress = false
    public private(set) var isLocked = false
    /// fn went down while locked: only its release finishes (⇧ alone also arrives as "fn up").
    private var lockedFnDown = false

    public init() {}

    public mutating func handle(_ input: KeyInput) -> HotkeyEvent? {
        if isLocked { return handleLocked(input) }
        switch input {
        case .flagsChanged(fnDown: true, shift: let shift, time: let time):
            // fn went DOWN, or another modifier changed while fn is held.
            if let start = pressedAt {
                guard shift, !shifted, !interrupted, time - start < minimumHold else { return nil }
                shifted = true
                return .shiftAdded
            }
            secondPress = armedUntil.map { time <= $0 } ?? false
            armedUntil = nil
            pressedAt = time
            shifted = shift
            interrupted = false
            return .pressed(shifted: shift)

        case .keyDown:
            armedUntil = nil
            // Another key was pressed.
            guard pressedAt != nil, !interrupted else { return nil }
            interrupted = true
            return .cancelled

        case .flagsChanged(fnDown: false, shift: _, time: let time):
            // fn went UP.
            guard let start = pressedAt else { return nil }
            pressedAt = nil
            if interrupted { return nil }
            guard time - start < minimumHold else { return .released }
            if secondPress {
                secondPress = false
                isLocked = true
                return .locked
            }
            if !shifted { armedUntil = time + doubleTapWindow }
            return .tapped(shifted: shifted)
        }
    }

    private mutating func handleLocked(_ input: KeyInput) -> HotkeyEvent? {
        switch input {
        case .flagsChanged(fnDown: true, shift: _, time: _):
            lockedFnDown = true
            return nil
        case .flagsChanged(fnDown: false, shift: _, time: _):
            guard lockedFnDown else { return nil }
            unlock()
            return .released
        case .keyDown(keyCode: Self.escapeKeyCode, time: _):
            unlock()
            return .cancelled
        default:
            return nil
        }
    }

    /// Leave hands-free (the dictation ended some other way: silence, the time cap, an error).
    /// Does nothing unless locked, so it never disarms a first tap.
    public mutating func unlock() {
        guard isLocked else { return }
        clear()
    }

    private mutating func clear() {
        isLocked = false
        lockedFnDown = false
        pressedAt = nil
        secondPress = false
        armedUntil = nil
    }

    /// Forget any hold or lock in progress (used when the event tap was disabled and events may
    /// have been missed). Returns true if a hold or a hands-free dictation was in progress.
    public mutating func reset() -> Bool {
        let wasActive = (pressedAt != nil && !interrupted) || isLocked
        clear()
        shifted = false
        interrupted = false
        return wasActive
    }
}
