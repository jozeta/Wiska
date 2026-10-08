import Core
import Testing
@testable import Hotkey

struct FnKeyStateMachineTests {
    private func run(_ inputs: [KeyInput]) -> [HotkeyEvent?] {
        var machine = FnKeyStateMachine()
        return inputs.map { machine.handle($0) }
    }

    private func down(_ t: Double, shift: Bool = false) -> KeyInput { .flagsChanged(fnDown: true, shift: shift, time: t) }
    private func up(_ t: Double, shift: Bool = false) -> KeyInput { .flagsChanged(fnDown: false, shift: shift, time: t) }

    @Test func holdThenReleaseEmitsPressedThenReleased() {
        #expect(run([down(10), up(10.5)]) == [.pressed(shifted: false), .released])
    }

    @Test func shiftHeldAtFnDownIsReported() {
        #expect(run([down(10, shift: true), up(10.5, shift: true)]) == [.pressed(shifted: true), .released])
    }

    @Test func shortTapIsTapped() {
        #expect(run([down(10), up(10.1)]) == [.pressed(shifted: false), .tapped(shifted: false)])
    }

    @Test func shortShiftTapIsShiftedTap() {
        #expect(run([down(10, shift: true), up(10.1)]) == [.pressed(shifted: true), .tapped(shifted: true)])
    }

    @Test func otherKeyWhileHeldCancelsOnceAndReleaseIsSilent() {
        #expect(run([down(10), .keyDown(time: 10.4), .keyDown(time: 10.5), up(11)])
                == [.pressed(shifted: false), .cancelled, nil, nil])
    }

    @Test func repeatedFnDownIsIgnored() {
        #expect(run([down(10), down(10.2, shift: true)]) == [.pressed(shifted: false), nil])
    }

    @Test func releaseWithoutPressIsIgnored() {
        #expect(run([up(10)]) == [nil])
    }

    @Test func keyDownWithoutFnIsIgnored() {
        #expect(run([.keyDown(time: 10)]) == [nil])
    }

    @Test func machineIsReusableAfterCancel() {
        #expect(run([down(10), .keyDown(time: 10.3), up(10.6), down(20), up(21)])
                == [.pressed(shifted: false), .cancelled, nil, .pressed(shifted: false), .released])
    }

    @Test func resetForgetsAHoldInProgress() {
        var machine = FnKeyStateMachine()
        _ = machine.handle(down(10))
        #expect(machine.reset() == true)
        #expect(machine.handle(down(20)) == .pressed(shifted: false))   // not stuck
        #expect(machine.reset() == true)
        #expect(machine.reset() == false)
    }
}
