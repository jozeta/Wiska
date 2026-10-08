import Core
import Testing
@testable import Hotkey

@MainActor
struct FnHotkeyMonitorTests {
    @Test(.timeLimit(.minutes(1))) func shiftPressedJustAfterFnReachesTheStateMachine() async {
        let monitor = FnHotkeyMonitor()
        monitor.receive(type: .flagsChanged, keyCode: 63, fnFlag: true, shiftFlag: false, time: 10)
        monitor.receive(type: .flagsChanged, keyCode: 56, fnFlag: true, shiftFlag: true, time: 10.05)
        monitor.receive(type: .flagsChanged, keyCode: 63, fnFlag: false, shiftFlag: true, time: 10.1)
        var events: [HotkeyEvent] = []
        for await event in monitor.events {
            events.append(event)
            if events.count == 3 { break }
        }
        #expect(events == [.pressed(shifted: false), .shiftAdded, .tapped(shifted: true)])
    }

    @Test(.timeLimit(.minutes(1))) func otherModifiersAreStillIgnored() async {
        let monitor = FnHotkeyMonitor()
        monitor.receive(type: .flagsChanged, keyCode: 55, fnFlag: true, shiftFlag: false, time: 10)   // ⌘
        monitor.receive(type: .flagsChanged, keyCode: 63, fnFlag: true, shiftFlag: false, time: 10.1)
        for await event in monitor.events {
            #expect(event == .pressed(shifted: false))
            break
        }
    }
}
