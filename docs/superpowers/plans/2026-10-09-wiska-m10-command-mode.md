# Wiska M10 Command Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Select text, hold fn+⌃, say an instruction, release — the selection is rewritten on-device and pasted over itself.

**Architecture:** The hotkey state machine reports ⌃ during a hold as `.commandAdded`; the controller marks the recording as a command and, on finish, transcribes the instruction, reads the selection (`SelectionReader`), edits it (`TextEditor`) and pastes with the existing injector — no cleanup, no History. Concrete `AXSelectionReader` (Accessibility, then ⌘C) lives in Injection, `FoundationModelsEditor` in Cleanup; the app wires both and shows "⌃ Edit" / "Editing…" in the notch.

**Tech Stack:** Swift 6.2, SwiftPM `WiskaKit` (Core, Hotkey, Dictation, Injection, Cleanup), Swift Testing, FoundationModels, ApplicationServices (AX), SwiftUI app `Wiska`.

**Spec:** `docs/superpowers/specs/2026-10-09-wiska-m10-command-mode-design.md`

## Global Constraints

- Gesture: hold fn + ⌃ (key codes 59 and 62); `.commandAdded` once per hold, at fn down or any time later before fn up. Hands-free (locked) ignores ⌃.
- No cleanup for the instruction; commands are not stored in History, don't call `onDictationFinished`, don't update recent apps.
- Selection: Accessibility first; else ⌘C, poll every 20 ms for up to 300 ms, restore the clipboard. Whitespace-only = none.
- Editor: fresh `LanguageModelSession`, temperature 0, 10 s limit, `.tooLong` above 2,000 words (checked before the model).
- HUD messages: "Select text first", "Command mode needs Apple Intelligence", "Selection too long", "Couldn't edit — try again"; badge "⌃ Edit"; working text "Editing…".
- Tests: `cd WiskaKit && swift test`. App build from repo root: `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build -quiet build`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**Decisions made while planning (deviations from the spec's wording, same behaviour):**
- The "⌃ Edit" badge is passed through the existing `HUDContent.listening(badge:)` string instead of a new `command: Bool` field — the HUD needs no change.
- `FnKeyStateMachine.handle` still returns one event; a fn press with ⌃ already down yields `.pressed` and then `.commandAdded` through a new `handleAll(_:) -> [HotkeyEvent]` that the monitor uses.
- The ⌘C sender is a closure on `AXSelectionReader` (not a new `KeySender` requirement), so existing `KeySender` fakes stay untouched.
- The controller gets a new state `.editing` (the HUD's "Editing…").

## Review Focus

1. ⌃ pressed *before* fn (the flags event for fn already carries ⌃) must still become a command. Pinned by `FnKeyStateMachineTests.controlBeforeFnIsACommand`.
2. A fn+⌃ quick tap must not arm hands-free, or the next fn tap would lock a dictation the user didn't ask for. Pinned by `FnKeyStateMachineTests.controlTapDoesNotArm`.
3. Switching language (⇧) after ⌃ restarts the recording — the command mark must survive it. Pinned by `DictationControllerTests.commandSurvivesLanguageSwitch`.
4. The ⌘C fallback must restore the user's clipboard even when the copy produced nothing. Pinned by `AXSelectionReaderTests.noChangeRestoresAndReturnsNil`.
5. A plain dictation right after a command must be a normal dictation (the mark resets). Pinned by `DictationControllerTests.nextDictationIsNotACommand`.

---

### Task 1: Core vocabulary — events, commands, protocols, failures

**Files:**
- Modify: `WiskaKit/Sources/Core/Protocols.swift` (HotkeyEvent case; SelectionReader, TextEditor, EditError)
- Modify: `WiskaKit/Sources/Core/Language.swift` (`DictationCommand.makeCommand`)
- Modify: `WiskaKit/Sources/Dictation/CommandMapper.swift`
- Modify: `WiskaKit/Sources/Dictation/DictationFailure.swift`
- Modify: `Wiska/AppModel.swift` (exhaustive switch on `DictationCommand`)
- Test: `WiskaKit/Tests/DictationTests/CommandMapperTests.swift`, `WiskaKit/Tests/DictationTests/DictationFailureTests.swift` (create)

**Interfaces:**
- Produces: `HotkeyEvent.commandAdded`; `DictationCommand.makeCommand`; `protocol SelectionReader { func selectedText() async -> String? }` (`@MainActor`); `protocol TextEditor { func edit(_ text: String, instruction: String, language: Language?) async throws -> String }` (`@MainActor`); `enum EditError: Error { case unavailable, tooLong, failed }`; `DictationFailure.noSelection / .editUnavailable / .selectionTooLong / .editFailed`.

- [ ] **Step 1: Write the failing tests**

Append to `CommandMapperTests` (inside the struct; it already has a `context` helper — use the same one the other tests use, e.g. `ctx()`; if the helper is named differently, use that name):

```swift
    @Test func commandAddedMakesACommand() {
        let mapped = CommandMapper.map(.commandAdded, context: HotkeyContext(
            mode: .autoDetect, primary: .english, secondary: .swedish, toggle: .english,
            enabled: [.english, .swedish], canStart: true))
        #expect(mapped == MappedHotkey(command: .makeCommand, newToggleLanguage: nil))
    }
```

Create `WiskaKit/Tests/DictationTests/DictationFailureTests.swift`:

```swift
import Testing
@testable import Dictation

struct DictationFailureTests {
    @Test func commandFailureMessages() {
        #expect(DictationFailure.noSelection.message == "Select text first")
        #expect(DictationFailure.editUnavailable.message == "Command mode needs Apple Intelligence")
        #expect(DictationFailure.selectionTooLong.message == "Selection too long")
        #expect(DictationFailure.editFailed.message == "Couldn't edit — try again")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter "CommandMapperTests|DictationFailureTests"`
Expected: FAIL — compile errors (`commandAdded`, `noSelection` unknown).

- [ ] **Step 3: Implement**

`Protocols.swift` — in `HotkeyEvent`, after `case locked`:

```swift
    /// ⌃ went down while fn was held: the recording is an edit instruction for the selected text.
    case commandAdded
```

and at the end of the file:

```swift
/// Reads the text selected in the frontmost app.
@MainActor
public protocol SelectionReader {
    /// The selection, or nil when nothing (or only whitespace) is selected.
    func selectedText() async -> String?
}

public enum EditError: Error, Equatable, Sendable {
    /// No on-device model (Apple Intelligence off or unsupported).
    case unavailable
    /// The selection is longer than the model can take.
    case tooLong
    /// Timeout, refusal, error or empty output.
    case failed
}

/// Rewrites text following a spoken instruction ("make this more formal").
@MainActor
public protocol TextEditor {
    func edit(_ text: String, instruction: String, language: Language?) async throws -> String
}
```

`Language.swift` — in `DictationCommand`, after `case lockHandsFree`:

```swift
    /// The recording in progress is an edit instruction for the selected text (fn+⌃).
    case makeCommand
```

`CommandMapper.swift` — after `case .locked:`:

```swift
        case .commandAdded:
            return MappedHotkey(command: .makeCommand, newToggleLanguage: nil)
```

`DictationFailure.swift`:

```swift
    case noSelection
    case editUnavailable
    case selectionTooLong
    case editFailed
```

and in `message`:

```swift
        case .noSelection: "Select text first"
        case .editUnavailable: "Command mode needs Apple Intelligence"
        case .selectionTooLong: "Selection too long"
        case .editFailed: "Couldn't edit — try again"
```

`Wiska/AppModel.swift` — the switch with `case .finish, .cancel, .lockHandsFree: break` becomes `case .finish, .cancel, .lockHandsFree, .makeCommand: break`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd WiskaKit && swift test --filter "CommandMapperTests|DictationFailureTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit Wiska/AppModel.swift
git commit -m "feat(core): command-mode events, commands, selection/editor protocols and failures"
```

---

### Task 2: ⌃ in the key-state machine and the monitor

**Files:**
- Modify: `WiskaKit/Sources/Hotkey/FnKeyStateMachine.swift`
- Modify: `WiskaKit/Sources/Hotkey/FnHotkeyMonitor.swift`
- Test: `WiskaKit/Tests/HotkeyTests/FnKeyStateMachineTests.swift`

**Interfaces:**
- Consumes: `HotkeyEvent.commandAdded` (Task 1).
- Produces: `KeyInput.flagsChanged(fnDown: Bool, shift: Bool, control: Bool = false, time: TimeInterval)`; `FnKeyStateMachine.handleAll(_ input: KeyInput) -> [HotkeyEvent]`.

- [ ] **Step 1: Write the failing tests**

Append to `FnKeyStateMachineTests`:

```swift
    private func runAll(_ inputs: [KeyInput]) -> [[HotkeyEvent]] {
        var machine = FnKeyStateMachine()
        return inputs.map { machine.handleAll($0) }
    }

    private func ctrl(_ t: Double, fn: Bool = true, control: Bool = true) -> KeyInput {
        .flagsChanged(fnDown: fn, shift: false, control: control, time: t)
    }

    @Test func controlDuringTheHoldIsACommandOnce() {
        #expect(runAll([down(10), ctrl(10.6), ctrl(10.7, control: false), ctrl(10.8), up(11)])
                == [[.pressed(shifted: false)], [.commandAdded], [], [], [.released]])
    }

    @Test func controlBeforeFnIsACommand() {
        #expect(runAll([ctrl(10), up(10.5)]) == [[.pressed(shifted: false), .commandAdded], [.released]])
    }

    @Test func controlWithoutFnDoesNothing() {
        #expect(runAll([ctrl(10, fn: false), ctrl(10.1, fn: false, control: false)]) == [[], []])
    }

    @Test func controlTapDoesNotArm() {
        // fn+⌃ quick tap, then a quick plain tap: no hands-free lock.
        #expect(runAll([ctrl(10), up(10.1), down(10.2), up(10.3)])
                == [[.pressed(shifted: false), .commandAdded], [.tapped(shifted: false)],
                    [.pressed(shifted: false)], [.tapped(shifted: false)]])
    }

    @Test func controlIsIgnoredWhileLocked() {
        #expect(runAll([down(10), up(10.1), down(10.2), up(10.3), ctrl(11, fn: false), ctrl(11.1)])
                == [[.pressed(shifted: false)], [.tapped(shifted: false)], [.pressed(shifted: false)], [.locked],
                    [], []])
    }

    @Test func controlAfterACancelIsIgnored() {
        #expect(runAll([down(10), .keyDown(keyCode: 0, time: 10.2), ctrl(10.3), up(10.6)])
                == [[.pressed(shifted: false)], [.cancelled], [], []])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter FnKeyStateMachineTests`
Expected: FAIL — compile error (`control:` / `handleAll` unknown).

- [ ] **Step 3: Implement**

`KeyInput`:

```swift
public enum KeyInput: Equatable {
    case flagsChanged(fnDown: Bool, shift: Bool, control: Bool = false, time: TimeInterval)
    case keyDown(keyCode: Int64, time: TimeInterval)
}
```

In `FnKeyStateMachine` add to the doc comment: `/// - ⌃ down at any time during a hold → `.commandAdded` once (an edit instruction); a ⌃ tap never arms.`; add state:

```swift
    /// ⌃ was seen during this hold.
    private var commanded = false
    /// A fn press that arrived with ⌃ already down: `.commandAdded` follows `.pressed`.
    private var pendingCommand = false
```

Add `handleAll`:

```swift
    /// Every event for one input: a fn press with ⌃ already down is `.pressed` then `.commandAdded`.
    public mutating func handleAll(_ input: KeyInput) -> [HotkeyEvent] {
        var events = handle(input).map { [$0] } ?? []
        if pendingCommand {
            pendingCommand = false
            events.append(.commandAdded)
        }
        return events
    }
```

Replace the fn-down branch of `handle`:

```swift
        case .flagsChanged(fnDown: true, shift: let shift, control: let control, time: let time):
            // fn went DOWN, or another modifier changed while fn is held.
            if let start = pressedAt {
                guard !interrupted else { return nil }
                if control && !commanded {
                    commanded = true
                    if shift, !shifted, time - start < minimumHold { shifted = true; pendingCommand = true; return .shiftAdded }
                    return .commandAdded
                }
                guard shift, !shifted, time - start < minimumHold else { return nil }
                shifted = true
                return .shiftAdded
            }
            secondPress = armedUntil.map { time <= $0 } ?? false
            armedUntil = nil
            pressedAt = time
            shifted = shift
            interrupted = false
            commanded = control
            pendingCommand = control
            return .pressed(shifted: shift)
```

Replace the fn-up branch:

```swift
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
```

In `handleLocked`, update the two patterns to include `control: _`:

```swift
        case .flagsChanged(fnDown: true, shift: _, control: _, time: _):
```
```swift
        case .flagsChanged(fnDown: false, shift: _, control: _, time: _):
```

In `clear()` add `commanded = false` and `pendingCommand = false`.

`FnHotkeyMonitor.swift`:
- add `static let controlKeyCodes: Set<Int64> = [59, 62]`;
- `receive` gains a `controlFlag: Bool` parameter (after `shiftFlag`); the `.flagsChanged` guard accepts `Self.controlKeyCodes.contains(keyCode)` too, and feeds `.flagsChanged(fnDown: fnFlag, shift: shiftFlag, control: controlFlag, time: time)`;
- `feed` becomes `for event in machine.handleAll(input) { continuation.yield(event) }`;
- the C callback reads `let controlFlag = event.flags.contains(.maskControl)` and passes it.
- Update any test call of `monitor.receive(...)` in `FnHotkeyMonitorTests` to pass `controlFlag: false`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd WiskaKit && swift test --filter "FnKeyStateMachineTests|FnHotkeyMonitorTests"`
Expected: PASS (old and new).

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(hotkey): fn+⌃ marks the hold as a command"
```

---

### Task 3: The controller runs commands

**Files:**
- Modify: `WiskaKit/Sources/Dictation/DictationController.swift`
- Modify: `WiskaKit/Tests/DictationTests/Fakes.swift` (FakeSelection, FakeEditor)
- Test: `WiskaKit/Tests/DictationTests/DictationControllerTests.swift`

**Interfaces:**
- Consumes: Task 1 protocols/failures.
- Produces: `DictationController.State.editing`; `DictationController.isCommand: Bool`; init params `selection: (any SelectionReader)? = nil, editor: (any TextEditor)? = nil` (after `showPreview`).

- [ ] **Step 1: Write the failing tests**

Append to `Fakes.swift`:

```swift
@MainActor
final class FakeSelection: SelectionReader {
    var text: String? = "hey can u send it"
    private(set) var reads = 0
    func selectedText() async -> String? { reads += 1; return text }
}

@MainActor
final class FakeEditor: TextEditor {
    var error: EditError?
    private(set) var calls: [(text: String, instruction: String)] = []
    func edit(_ text: String, instruction: String, language: Language?) async throws -> String {
        calls.append((text, instruction))
        if let error { throw error }
        return "edited: \(text)"
    }
}
```

In `DictationControllerTests` add properties `let selection = FakeSelection()` and `let editor = FakeEditor()`, pass `selection: selection, editor: editor` in `makeController` (after `showPreview:`), and append:

```swift
    func runCommand(_ controller: DictationController) async {
        controller.handle(en)
        controller.handle(.makeCommand)
        audio.emit([0.1])
        controller.handle(.finish)
        await controller.currentTask?.value
    }

    @Test func commandEditsTheSelectionAndPastesIt() async {
        let controller = makeController()
        let recorder = StateRecorder()
        controller.onChange = { state, _ in recorder.record(state) }
        let finished = Box(0)
        controller.onDictationFinished = { _ in finished.value += 1 }
        await runCommand(controller)
        #expect(editor.calls.map(\.instruction) == ["hello world"])
        #expect(editor.calls.map(\.text) == ["hey can u send it"])
        #expect(injector.injected == ["edited: hey can u send it"])
        #expect(cleaner.contexts.isEmpty)
        #expect(finished.value == 0)
        #expect(recorder.states == [.listening, .transcribing, .editing, .injecting, .idle])
    }

    @Test func commandWithoutSelectionFails() async {
        selection.text = nil
        let controller = makeController()
        await runCommand(controller)
        #expect(controller.state == .failed(.noSelection))
        #expect(injector.injected.isEmpty)
    }

    @Test(arguments: [(EditError.unavailable, DictationFailure.editUnavailable),
                      (.tooLong, .selectionTooLong), (.failed, .editFailed)])
    func editErrorsBecomeFailures(error: EditError, failure: DictationFailure) async {
        editor.error = error
        let controller = makeController()
        await runCommand(controller)
        #expect(controller.state == .failed(failure))
        #expect(injector.injected.isEmpty)
    }

    @Test func makeCommandOutsideListeningIsIgnored() async {
        let controller = makeController()
        controller.handle(.makeCommand)
        #expect(!controller.isCommand)
    }

    @Test func nextDictationIsNotACommand() async {
        let controller = makeController()
        await runCommand(controller)
        controller.handle(en)
        #expect(!controller.isCommand)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(injector.injected.last == "cleaned: hello world")
    }

    @Test func commandSurvivesLanguageSwitch() async {
        let controller = makeController()
        controller.handle(en)
        controller.handle(.makeCommand)
        controller.handle(.switchLanguage(.fixed(.swedish)))
        #expect(controller.isCommand)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(injector.injected == ["edited: hey can u send it"])
    }

    @Test func cancelledCommandResets() async {
        let controller = makeController()
        controller.handle(en)
        controller.handle(.makeCommand)
        controller.handle(.cancel)
        #expect(!controller.isCommand)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter DictationControllerTests`
Expected: FAIL — compile errors (`selection:` / `.editing` / `isCommand`).

- [ ] **Step 3: Implement**

In `DictationController`:
- `State` gains `case editing` (after `cleaning`).
- Property: `/// The recording in progress is an edit instruction for the selected text (fn+⌃).` `public private(set) var isCommand = false { didSet { if oldValue != isCommand { notify() } } }`
- Stored `private let selection: (any SelectionReader)?` and `private let editor: (any TextEditor)?`; init params `selection: (any SelectionReader)? = nil, editor: (any TextEditor)? = nil` after `showPreview`, assigned in the body.
- `handle(_:)`:
  - `.start`: after `guard canStart`, set `isCommand = false` before `startListening(choice)`.
  - `.cancel`: after `cancelListening()`, set `isCommand = false`.
  - new `case .makeCommand: guard state == .listening else { return }; isCommand = true`.
- In `finishDictation`, right after the empty-transcript guard (`fail(.noSpeech)`) and before the cleaning `do`, add:

```swift
        if isCommand {
            await runCommand(instruction: transcript)
            return
        }
```

- New method:

```swift
    /// fn+⌃: the transcript is an instruction; the selection is edited and pasted over itself.
    /// Not cleaned and not recorded (the selection may be anything).
    private func runCommand(instruction transcript: Transcript) async {
        isCommand = false
        state = .editing
        guard let selection, let editor else {
            fail(.editUnavailable)
            return
        }
        guard let text = await selection.selectedText() else {
            fail(.noSelection)
            return
        }
        do {
            let edited = try await editor.edit(text, instruction: transcript.text, language: transcript.language)
            state = .injecting
            try await injector.inject(edited)
        } catch EditError.unavailable {
            fail(.editUnavailable); return
        } catch EditError.tooLong {
            fail(.selectionTooLong); return
        } catch EditError.failed {
            fail(.editFailed); return
        } catch InjectionError.secureInputActive {
            fail(.secureInput); return
        } catch {
            fail(.injection(String(describing: error))); return
        }
        state = .idle
    }
```

Note `isCommand = false` happens at the start of `runCommand` so the HUD badge returns to normal for the next dictation; the `.editing` state carries the "Editing…" text.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd WiskaKit && swift test --filter DictationTests`
Expected: PASS (all Dictation tests).

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(dictation): commands edit the selection and paste it; no cleanup, no history"
```

---

### Task 4: AXSelectionReader (Accessibility, then ⌘C)

**Files:**
- Create: `WiskaKit/Sources/Injection/AXSelectionReader.swift`
- Modify: `WiskaKit/Sources/Injection/CGEventKeySender.swift` (add `sendCopy()`)
- Test: `WiskaKit/Tests/InjectionTests/AXSelectionReaderTests.swift`

**Interfaces:**
- Consumes: `SelectionReader` (Task 1), `PasteboardSnapshot`.
- Produces: `AXSelectionReader(pasteboard: NSPasteboard = .general, accessibilitySelection: @escaping @MainActor () -> String? = AXSelectionReader.focusedSelection, sendCopy: @escaping @MainActor () throws -> Void = { try CGEventKeySender().sendCopy() }, copyTimeout: Duration = .milliseconds(300))`; `CGEventKeySender.sendCopy() throws`.

- [ ] **Step 1: Write the failing test**

```swift
// WiskaKit/Tests/InjectionTests/AXSelectionReaderTests.swift
import AppKit
import Testing
@testable import Injection

@MainActor
struct AXSelectionReaderTests {
    let pasteboard = NSPasteboard(name: .init("WiskaSelectionTests-\(UUID().uuidString)"))

    func reader(ax: String?, copies: String?) -> AXSelectionReader {
        AXSelectionReader(pasteboard: pasteboard, accessibilitySelection: { ax }, sendCopy: { [pasteboard] in
            guard let copies else { return }
            pasteboard.clearContents()
            pasteboard.setString(copies, forType: .string)
        }, copyTimeout: .milliseconds(100))
    }

    @Test func accessibilityAnswerWins() async {
        pasteboard.clearContents()
        pasteboard.setString("clipboard", forType: .string)
        #expect(await reader(ax: "selected", copies: "copied").selectedText() == "selected")
        #expect(pasteboard.string(forType: .string) == "clipboard")
    }

    @Test func copyFallbackReturnsTextAndRestoresTheClipboard() async {
        pasteboard.clearContents()
        pasteboard.setString("clipboard", forType: .string)
        #expect(await reader(ax: nil, copies: "copied").selectedText() == "copied")
        #expect(pasteboard.string(forType: .string) == "clipboard")
    }

    @Test func noChangeRestoresAndReturnsNil() async {
        pasteboard.clearContents()
        pasteboard.setString("clipboard", forType: .string)
        #expect(await reader(ax: nil, copies: nil).selectedText() == nil)
        #expect(pasteboard.string(forType: .string) == "clipboard")
    }

    @Test func whitespaceIsNoSelection() async {
        #expect(await reader(ax: "  \n ", copies: nil).selectedText() == nil)
        #expect(await reader(ax: nil, copies: "   ").selectedText() == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WiskaKit && swift test --filter AXSelectionReaderTests`
Expected: FAIL — `AXSelectionReader` not found.

- [ ] **Step 3: Implement**

`CGEventKeySender.swift` — add to the struct:

```swift
    private static let cKeyCode: CGKeyCode = 8   // physical C position

    /// Posts ⌘C (used to read a selection that Accessibility doesn't expose).
    public func sendCopy() throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: Self.cKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: Self.cKeyCode, keyDown: false)
        else { throw InjectionError.eventCreationFailed }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
```

```swift
// WiskaKit/Sources/Injection/AXSelectionReader.swift
import AppKit
import ApplicationServices
import Core

/// The selected text in the frontmost app: asked through Accessibility (no clipboard), else
/// copied with ⌘C for apps that don't expose it (Electron, browsers), with the clipboard restored.
@MainActor
public final class AXSelectionReader: SelectionReader {
    private let pasteboard: NSPasteboard
    private let accessibilitySelection: @MainActor () -> String?
    private let sendCopy: @MainActor () throws -> Void
    private let copyTimeout: Duration

    public init(pasteboard: NSPasteboard = .general,
                accessibilitySelection: @escaping @MainActor () -> String? = AXSelectionReader.focusedSelection,
                sendCopy: @escaping @MainActor () throws -> Void = { try CGEventKeySender().sendCopy() },
                copyTimeout: Duration = .milliseconds(300)) {
        self.pasteboard = pasteboard
        self.accessibilitySelection = accessibilitySelection
        self.sendCopy = sendCopy
        self.copyTimeout = copyTimeout
    }

    public func selectedText() async -> String? {
        if let text = Self.nonBlank(accessibilitySelection()) { return text }
        let snapshot = PasteboardSnapshot.capture(pasteboard)
        let before = pasteboard.changeCount
        defer { snapshot.restore(to: pasteboard) }
        do { try sendCopy() } catch { return nil }
        let deadline = ContinuousClock.now + copyTimeout
        while pasteboard.changeCount == before, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard pasteboard.changeCount != before else { return nil }
        return Self.nonBlank(pasteboard.string(forType: .string))
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// The focused element's selected text, via Accessibility; nil when the app doesn't say.
    public static func focusedSelection() -> String? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success, let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString,
                                            &selected) == .success else { return nil }
        return selected as? String
    }
}
```

Note: `defer` restores the snapshot on every path, including when the copy produced nothing — `restore` is a no-op-equivalent rewrite of the same contents in that case.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WiskaKit && swift test --filter "AXSelectionReaderTests|PasteboardInjectorTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(injection): read the selection via Accessibility, else ⌘C with the clipboard restored"
```

---

### Task 5: FoundationModelsEditor

**Files:**
- Create: `WiskaKit/Sources/Cleanup/FoundationModelsEditor.swift`
- Test: `WiskaKit/Tests/CleanupTests/FoundationModelsEditorTests.swift`

**Interfaces:**
- Consumes: `TextEditor`, `EditError` (Task 1); `CleanupPipeline.stripWrappingQuotes` (internal, same module).
- Produces: `FoundationModelsEditor()` with `static let maxWords = 2_000`, `static let timeout: Duration = .seconds(10)`, `static let instructions: String`, `static func prompt(text:instruction:) -> String`.

- [ ] **Step 1: Write the failing test**

```swift
// WiskaKit/Tests/CleanupTests/FoundationModelsEditorTests.swift
import Core
import FoundationModels
import Testing
@testable import Cleanup

@MainActor
struct FoundationModelsEditorTests {
    nonisolated static var modelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    @Test func tooLongIsRejectedBeforeTheModel() async {
        let long = Array(repeating: "word", count: FoundationModelsEditor.maxWords + 1).joined(separator: " ")
        await #expect(throws: EditError.tooLong) {
            try await FoundationModelsEditor().edit(long, instruction: "shorten", language: .english)
        }
    }

    @Test func promptCarriesInstructionAndText() {
        let prompt = FoundationModelsEditor.prompt(text: "hey can u send it", instruction: "make it formal")
        #expect(prompt.contains("make it formal"))
        #expect(prompt.contains("hey can u send it"))
        #expect(FoundationModelsEditor.instructions.contains("Output only the edited text"))
    }

    @Test(.enabled(if: modelAvailable), .timeLimit(.minutes(1)))
    func makesTextMoreFormal() async throws {
        let original = "hey can u send it asap"
        let edited = try await FoundationModelsEditor().edit(original, instruction: "make this more formal",
                                                             language: .english)
        #expect(!edited.isEmpty)
        #expect(edited != original)
        #expect(!CleanupGuard.words(edited).contains("u"), "\(edited)")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WiskaKit && swift test --filter FoundationModelsEditorTests`
Expected: FAIL — `FoundationModelsEditor` not found.

- [ ] **Step 3: Implement**

```swift
// WiskaKit/Sources/Cleanup/FoundationModelsEditor.swift
import Core
import Foundation
import FoundationModels

/// Command mode: rewrites the selected text following a spoken instruction, on-device.
@MainActor
public final class FoundationModelsEditor: TextEditor {
    /// The on-device model's context is about 4,096 tokens; leave room for the answer.
    public static let maxWords = 2_000
    public static let timeout: Duration = .seconds(10)
    static let instructions = """
    You edit text. Apply the instruction to the text. \
    Keep the text's language unless the instruction asks for another. \
    Output only the edited text, without quotes or commentary.
    """

    public init() {}

    static func prompt(text: String, instruction: String) -> String {
        "Instruction: \(instruction)\n\nText:\n\(text)"
    }

    public func edit(_ text: String, instruction: String, language: Language?) async throws -> String {
        guard text.split(whereSeparator: \.isWhitespace).count <= Self.maxWords else { throw EditError.tooLong }
        guard case .available = SystemLanguageModel.default.availability else { throw EditError.unavailable }
        let prompt = Self.prompt(text: text, instruction: instruction)
        let work = Task { @MainActor in
            let session = LanguageModelSession(instructions: Self.instructions)
            return try await session.respond(to: prompt, options: GenerationOptions(temperature: 0)).content
        }
        let timer = Task {
            try? await Task.sleep(for: Self.timeout)
            work.cancel()
        }
        defer { timer.cancel() }
        let output: String
        do { output = try await work.value } catch { throw EditError.failed }
        let edited = CleanupPipeline.stripWrappingQuotes(output)
        guard !edited.isEmpty else { throw EditError.failed }
        return edited
    }
}
```

(The model honours cancellation — verified in M3 by `cancelledRewriteStopsPromptly` — so cancelling `work` ends `work.value` with an error, mapped to `.failed`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WiskaKit && swift test --filter FoundationModelsEditorTests`
Expected: PASS (the real-model test runs when Apple Intelligence is available).

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(cleanup): on-device editor for command mode"
```

---

### Task 6: App wiring, notch and Settings

**Files:**
- Modify: `Wiska/AppModel.swift`
- Modify: `Wiska/Settings/GeneralTab.swift`

**Interfaces:**
- Consumes: Tasks 1–5.

- [ ] **Step 1: Wire**

In `AppModel.init`, the `DictationController(...)` call gains, after `showPreview: { settings.livePreview }`:

```swift
            ,
            selection: AXSelectionReader(),
            editor: FoundationModelsEditor()
```

(i.e. `showPreview: { settings.livePreview },\n            selection: AXSelectionReader(),\n            editor: FoundationModelsEditor()`).

In `hudContent(for:audio:)`:

```swift
        case .listening: .listening(audio: audio, badge: controller.isCommand ? "⌃ Edit" : badge,
                                    preview: controller.preview, handsFree: controller.isHandsFree)
        case .editing: .working("Editing…")
```

In the two other `switch` statements over `DictationController.State` (status icon around line 281 and status text around line 292), add `.editing` next to `.cleaning` — icon `"ellipsis"`, text `"Editing…"` (give `.editing` its own case line for the text: `case .editing: "Editing…"`).

`GeneralTab.swift` — in the Dictation section, after the "Hands-free" line, add a row in the same style:

```swift
                LabeledContent("Edit", value: "Select text, hold fn+⌃, say what to change")
```

(If the existing rows are plain `Text`, mirror their exact form instead.)

- [ ] **Step 2: Build and full suite**

Run: `cd WiskaKit && swift test` then from the repo root `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build -quiet build`
Expected: all tests pass (1 known Parakeet Danish issue); the app builds.

- [ ] **Step 3: Manual check**

Relaunch (`pkill -x Wiska; open build/Build/Products/Debug/Wiska.app`). In TextEdit select "hey can u send it asap", hold fn+⌃, say "make this more formal", release → notch shows "⌃ Edit", then "Editing…", the selection is replaced; ⌘Z restores it. Repeat in Slack or a browser text field (⌘C path). With nothing selected → "Select text first".

- [ ] **Step 4: Commit**

```bash
git add Wiska
git commit -m "feat(app): command mode wired — ⌃ Edit badge, Editing…, gesture listed in Settings"
```
