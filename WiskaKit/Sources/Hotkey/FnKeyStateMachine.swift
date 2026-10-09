import Core
import Foundation

public enum KeyInput: Equatable {
    case flagsChanged(fnDown: Bool, shift: Bool, control: Bool = false, time: TimeInterval)
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
/// - ⌃ down at any time during a hold → `.commandAdded` once (an edit instruction); a ⌃ tap never arms.
public struct FnKeyStateMachine {
    public static let escapeKeyCode: Int64 = 53
    /// macOS sends this key down right after a real fn/🌐 tap (the 🌐 key's own action).
    /// It is the fn key itself, never "another key".
    public static let globeKeyCode: Int64 = 179
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
    /// ⌃ was seen during this hold.
    private var commanded = false
    /// A fn press that arrived with ⌃ already down: `.commandAdded` follows `.pressed`.
    private var pendingCommand = false

    public init() {}

    /// Every event for one input: a fn press with ⌃ already down is `.pressed` then `.commandAdded`.
    public mutating func handleAll(_ input: KeyInput) -> [HotkeyEvent] {
        var events = handle(input).map { [$0] } ?? []
        if pendingCommand {
            pendingCommand = false
            events.append(.commandAdded)
        }
        return events
    }

    public mutating func handle(_ input: KeyInput) -> HotkeyEvent? {
        if isLocked { return handleLocked(input) }
        switch input {
        case .flagsChanged(fnDown: true, shift: let shift, control: let control, time: let time):
            // fn went DOWN, or another modifier changed while fn is held.
            if let start = pressedAt {
                guard !interrupted else { return nil }
                let shiftAdded = shift && !shifted && time - start < minimumHold
                if shiftAdded { shifted = true }
                if control && !commanded {
                    commanded = true
                    if shiftAdded {
                        pendingCommand = true
                        return .shiftAdded
                    }
                    return .commandAdded
                }
                return shiftAdded ? .shiftAdded : nil
            }
            secondPress = armedUntil.map { time <= $0 } ?? false
            armedUntil = nil
            pressedAt = time
            shifted = shift
            interrupted = false
            commanded = control
            pendingCommand = control
            return .pressed(shifted: shift)

        case .keyDown(keyCode: Self.globeKeyCode, time: _):
            return nil

        case .keyDown:
            armedUntil = nil
            // Another key was pressed.
            guard pressedAt != nil, !interrupted else { return nil }
            interrupted = true
            return .cancelled

        case .flagsChanged(fnDown: false, shift: _, control: _, time: let time):
            // fn went UP (or ⌃/⇧ changed with fn not held: harmless, pressedAt is nil).
            guard let start = pressedAt else { return nil }
            pressedAt = nil
            if interrupted { return nil }
            guard time - start < minimumHold else { return .released }
            if secondPress && !commanded {
                secondPress = false
                isLocked = true
                return .locked
            }
            secondPress = false
            if !shifted && !commanded { armedUntil = time + doubleTapWindow }
            return .tapped(shifted: shifted)
        }
    }

    private mutating func handleLocked(_ input: KeyInput) -> HotkeyEvent? {
        switch input {
        case .flagsChanged(fnDown: true, shift: _, control: _, time: _):
            lockedFnDown = true
            return nil
        case .flagsChanged(fnDown: false, shift: _, control: _, time: _):
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
        commanded = false
        pendingCommand = false
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
