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

    @Test(.timeLimit(.minutes(1))) func escapeKeyCodeReachesTheMachine() async {
        let monitor = FnHotkeyMonitor()
        for (t, down) in [(10.0, true), (10.1, false), (10.3, true), (10.4, false)] {
            monitor.receive(type: .flagsChanged, keyCode: 63, fnFlag: down, shiftFlag: false, time: t)
        }
        monitor.receive(type: .keyDown, keyCode: 53, fnFlag: false, shiftFlag: false, time: 11)
        var events: [HotkeyEvent] = []
        for await event in monitor.events {
            events.append(event)
            if events.count == 5 { break }
        }
        #expect(events.suffix(2) == [.locked, .cancelled])
    }

    @Test(.timeLimit(.minutes(1))) func endHandsFreeUnlocks() async {
        let monitor = FnHotkeyMonitor()
        for (t, down) in [(10.0, true), (10.1, false), (10.3, true), (10.4, false), (20.0, true)] {
            monitor.receive(type: .flagsChanged, keyCode: 63, fnFlag: down, shiftFlag: false, time: t)
        }
        monitor.endHandsFree()
        monitor.receive(type: .flagsChanged, keyCode: 63, fnFlag: true, shiftFlag: false, time: 30)
        var events: [HotkeyEvent] = []
        for await event in monitor.events {
            events.append(event)
            if events.count == 5 { break }
        }
        // fn down at 20 was swallowed by the lock; after endHandsFree the press at 30 starts.
        #expect(events.last == .pressed(shifted: false))
    }
}
