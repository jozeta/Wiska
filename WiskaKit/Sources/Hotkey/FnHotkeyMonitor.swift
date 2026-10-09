import CoreGraphics
import Core
import Foundation

public enum HotkeyError: Error {
    case tapCreationFailed
}

/// Listens (never blocks) for fn and key-down events system-wide via a CGEventTap.
/// Requires Input Monitoring permission. Must be started on the main thread.
@MainActor
public final class FnHotkeyMonitor {
    static let fnKeyCode: Int64 = 63
    /// Left and right ⇧: needed to notice ⇧ pressed just after fn (`.shiftAdded`).
    static let shiftKeyCodes: Set<Int64> = [56, 60]
    /// Left and right ⌃: fn+⌃ makes the hold an edit command.
    static let controlKeyCodes: Set<Int64> = [59, 62]
    private static let log = Log.logger("Hotkey")

    public let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private var machine = FnKeyStateMachine()
    private var tap: CFMachPort?

    public var isRunning: Bool { tap != nil }

    public init() {
        (events, continuation) = AsyncStream.makeStream(of: HotkeyEvent.self)
    }

    public func start() throws {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: fnTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { throw HotkeyError.tapCreationFailed }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        Self.log.info("fn event tap started")
    }

    func receive(type: CGEventType, keyCode: Int64, fnFlag: Bool, shiftFlag: Bool, controlFlag: Bool = false,
                 time: TimeInterval) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Events were lost while disabled; a missed fn-up would leave us stuck.
            if machine.reset() { continuation.yield(.cancelled) }
            Self.log.notice("event tap was disabled by the system; re-enabled and reset")
        case .flagsChanged:
            guard keyCode == Self.fnKeyCode || Self.shiftKeyCodes.contains(keyCode)
                    || Self.controlKeyCodes.contains(keyCode) else { return }
            feed(.flagsChanged(fnDown: fnFlag, shift: shiftFlag, control: controlFlag, time: time))
        case .keyDown:
            feed(.keyDown(keyCode: keyCode, time: time))
        default:
            break
        }
    }

    /// The hands-free dictation ended without an fn tap or Esc: the next fn press starts afresh.
    public func endHandsFree() {
        machine.unlock()
    }

    private func feed(_ input: KeyInput) {
        for event in machine.handleAll(input) { continuation.yield(event) }
    }
}

/// C callback. The tap's run-loop source is on the main run loop, so we are on the main thread.
private func fnTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let monitor = Unmanaged<FnHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
        // Copy out plain values: CGEvent is not Sendable, so it can't cross into main-actor code.
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let fnFlag = event.flags.contains(.maskSecondaryFn)
        let shiftFlag = event.flags.contains(.maskShift)
        let controlFlag = event.flags.contains(.maskControl)
        let time = TimeInterval(event.timestamp) / 1_000_000_000
        MainActor.assumeIsolated {
            monitor.receive(type: type, keyCode: keyCode, fnFlag: fnFlag, shiftFlag: shiftFlag,
                            controlFlag: controlFlag, time: time)
        }
    }
    return Unmanaged.passUnretained(event)
}
