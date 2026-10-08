import Core
import Testing
@testable import Hotkey

struct FnKeyStateMachineTests {
    private func run(_ inputs: [KeyInput]) -> [HotkeyEvent?] {
        var machine = FnKeyStateMachine()
        return inputs.map { machine.handle($0) }
    }

    @Test func holdThenReleaseEmitsPressedThenReleased() {
        #expect(run([.flagsChanged(fnDown: true, time: 10), .flagsChanged(fnDown: false, time: 10.5)])
                == [.pressed, .released])
    }

    @Test func shortTapIsCancelled() {
        #expect(run([.flagsChanged(fnDown: true, time: 10), .flagsChanged(fnDown: false, time: 10.1)])
                == [.pressed, .cancelled])
    }

    @Test func otherKeyWhileHeldCancelsOnceAndReleaseIsSilent() {
        #expect(run([.flagsChanged(fnDown: true, time: 10), .keyDown(time: 10.4),
                     .keyDown(time: 10.5), .flagsChanged(fnDown: false, time: 11)])
                == [.pressed, .cancelled, nil, nil])
    }

    @Test func repeatedFnDownIsIgnored() {
        #expect(run([.flagsChanged(fnDown: true, time: 10), .flagsChanged(fnDown: true, time: 10.2)])
                == [.pressed, nil])
    }

    @Test func releaseWithoutPressIsIgnored() {
        #expect(run([.flagsChanged(fnDown: false, time: 10)]) == [nil])
    }

    @Test func keyDownWithoutFnIsIgnored() {
        #expect(run([.keyDown(time: 10)]) == [nil])
    }

    @Test func machineIsReusableAfterCancel() {
        #expect(run([.flagsChanged(fnDown: true, time: 10), .keyDown(time: 10.3),
                     .flagsChanged(fnDown: false, time: 10.6),
                     .flagsChanged(fnDown: true, time: 20), .flagsChanged(fnDown: false, time: 21)])
                == [.pressed, .cancelled, nil, .pressed, .released])
    }
}
