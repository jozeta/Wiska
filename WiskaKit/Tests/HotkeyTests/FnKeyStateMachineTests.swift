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
        #expect(run([down(10), .keyDown(keyCode: 0, time: 10.4), .keyDown(keyCode: 0, time: 10.5), up(11)])
                == [.pressed(shifted: false), .cancelled, nil, nil])
    }

    @Test func repeatedFnDownIsIgnored() {
        #expect(run([down(10), down(10.2)]) == [.pressed(shifted: false), nil])
    }

    @Test func shiftShortlyAfterFnIsReportedOnceAndShiftsTheTap() {
        #expect(run([down(10), down(10.1, shift: true), down(10.15, shift: true), up(10.2)])
                == [.pressed(shifted: false), .shiftAdded, nil, .tapped(shifted: true)])
    }

    @Test func shiftLateInAHoldIsIgnored() {
        #expect(run([down(10), down(10.3, shift: true), up(10.5)])
                == [.pressed(shifted: false), nil, .released])
    }

    @Test func shiftAfterACancelIsIgnored() {
        #expect(run([down(10), .keyDown(keyCode: 0, time: 10.05), down(10.1, shift: true)])
                == [.pressed(shifted: false), .cancelled, nil])
    }

    @Test func releaseWithoutPressIsIgnored() {
        #expect(run([up(10)]) == [nil])
    }

    @Test func keyDownWithoutFnIsIgnored() {
        #expect(run([.keyDown(keyCode: 0, time: 10)]) == [nil])
    }

    @Test func machineIsReusableAfterCancel() {
        #expect(run([down(10), .keyDown(keyCode: 0, time: 10.3), up(10.6), down(20), up(21)])
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

    private func key(_ t: Double, _ code: Int64 = 0) -> KeyInput { .keyDown(keyCode: code, time: t) }
    private func esc(_ t: Double) -> KeyInput { .keyDown(keyCode: 53, time: t) }

    @Test func doubleTapLocks() {
        #expect(run([down(10), up(10.1), down(10.3), up(10.4)])
                == [.pressed(shifted: false), .tapped(shifted: false), .pressed(shifted: false), .locked])
    }

    @Test func secondPressHeldIsAnOrdinaryHold() {
        #expect(run([down(10), up(10.1), down(10.3), up(11)])
                == [.pressed(shifted: false), .tapped(shifted: false), .pressed(shifted: false), .released])
    }

    @Test func secondTapAfterTheWindowIsJustAnotherTap() {
        #expect(run([down(10), up(10.1), down(10.6), up(10.7)])
                == [.pressed(shifted: false), .tapped(shifted: false), .pressed(shifted: false), .tapped(shifted: false)])
    }

    @Test func shiftTapNeverArms() {
        #expect(run([down(10, shift: true), up(10.1), down(10.3), up(10.4)])
                == [.pressed(shifted: true), .tapped(shifted: true), .pressed(shifted: false), .tapped(shifted: false)])
    }

    @Test func shiftOnTheSecondPressPicksTheLanguage() {
        #expect(run([down(10), up(10.1), down(10.3, shift: true), up(10.4, shift: true)])
                == [.pressed(shifted: false), .tapped(shifted: false), .pressed(shifted: true), .locked])
    }

    @Test func lockedFnTapFinishesAndUnlocks() {
        var machine = FnKeyStateMachine()
        _ = [down(10), up(10.1), down(10.3), up(10.4)].map { machine.handle($0) }
        #expect(machine.isLocked)
        #expect(machine.handle(down(20)) == nil)
        #expect(machine.handle(up(20.05)) == .released)
        #expect(!machine.isLocked)
        #expect(machine.handle(down(30)) == .pressed(shifted: false))
    }

    @Test func lockedFnHeldLongStillFinishes() {
        #expect(run([down(10), up(10.1), down(10.3), up(10.4), down(20), up(22)])
                == [.pressed(shifted: false), .tapped(shifted: false), .pressed(shifted: false), .locked, nil, .released])
    }

    @Test func lockedEscCancelsOtherKeysAreIgnored() {
        #expect(run([down(10), up(10.1), down(10.3), up(10.4), key(11), key(12, 49), esc(13), key(14)])
                == [.pressed(shifted: false), .tapped(shifted: false), .pressed(shifted: false), .locked,
                    nil, nil, .cancelled, nil])
    }

    @Test func lockedShiftIsIgnored() {
        #expect(run([down(10), up(10.1), down(10.3), up(10.4), down(11, shift: true)])
                == [.pressed(shifted: false), .tapped(shifted: false), .pressed(shifted: false), .locked, nil])
    }

    @Test func unlockLetsTheNextPressStartFresh() {
        var machine = FnKeyStateMachine()
        _ = [down(10), up(10.1), down(10.3), up(10.4)].map { machine.handle($0) }
        machine.unlock()
        #expect(!machine.isLocked)
        #expect(machine.handle(down(20)) == .pressed(shifted: false))
        #expect(machine.handle(up(21)) == .released)
    }

    @Test func resetClearsTheLockAndReportsIt() {
        var machine = FnKeyStateMachine()
        _ = [down(10), up(10.1), down(10.3), up(10.4)].map { machine.handle($0) }
        #expect(machine.reset() == true)
        #expect(!machine.isLocked)
        #expect(machine.reset() == false)
    }

    @Test func otherKeyAfterTheFirstTapDisarms() {
        #expect(run([down(10), up(10.1), key(10.2), down(10.3), up(10.4)])
                == [.pressed(shifted: false), .tapped(shifted: false), nil, .pressed(shifted: false), .tapped(shifted: false)])
    }
}
