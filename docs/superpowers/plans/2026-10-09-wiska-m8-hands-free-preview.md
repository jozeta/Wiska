# Wiska M8 — Hands-free and live preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Double-tap fn for hands-free dictation (fn tap finishes, Esc cancels, silence finishes), and a one-line live preview of the words under the waveform.

**Architecture:** The fn state machine gains an armed/locked state and emits a new `.locked` event, mapped to `DictationCommand.lockHandsFree`. The controller marks the dictation hands-free and feeds mic levels to a pure `SilenceWatch`. Transcription sessions gain a `preview` stream (Apple: volatile results; Parakeet: empty), which the controller exposes as `preview` and the HUD shows as a second row.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, Apple Speech (SpeechAnalyzer), Swift Testing, SwiftPM package `WiskaKit` + Xcode app `Wiska`.

**Spec:** `docs/superpowers/specs/2026-10-09-wiska-m8-hands-free-preview-design.md`

## Global Constraints

- Hold-to-talk behaviour is unchanged (every existing test keeps passing).
- `doubleTapWindow` = 0.4 s; `minimumHold` stays 0.25 s; Esc key code = 53.
- Wiska never swallows keys (event tap stays `.listenOnly`).
- Silence: `speechThreshold` = 0.3 on the 0…1 level scale; setting key `"handsFreeSilence"` (seconds, 0 = Off), choices 0, 10, 30, 60, 120, default 30.
- Preview setting key `"livePreview"`, default on.
- The pasted text is always the finalized, cleaned transcript — never preview text.
- The 5-minute `maxDuration` cap still applies to every dictation.
- The capsule stays exactly notch-wide; the preview is one line that scrolls inside it like a ticker (new words slide in from the right, the left edge fades), never widening the panel.
- Tests: `cd WiskaKit && swift test` (Swift Testing). App build: `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build -quiet build` from the repo root.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A hands-free dictation that ends without an fn tap (silence, 5-min cap, failure, audio loss, missing permission so it never started) must leave the key machine unlocked, so the next fn press starts a new dictation — Task 7 wires `endHandsFree()` on every exit from `.listening` and after an ignored `.locked`.
2. A quick fn tap then a slow (held) fn press within 0.4 s must be an ordinary hold, not a lock — Task 1 test `secondPressHeldIsAnOrdinaryHold`.
3. A stale preview from a previous dictation must never appear at the start of the next — Task 5 test `previewClearsWhenListeningEnds`.
4. Hold-to-talk with long silence must not auto-finish — Task 4 test `holdToTalkIgnoresSilence`.
5. In auto-detect, a preview from a language that later loses must not change what is pasted — Task 3 test `autoDetectPreviewFollowsPreferredSessionButPickIsUnchanged`.

---

### Task 1: Hands-free gesture in the fn state machine

**Files:**
- Modify: `WiskaKit/Sources/Core/Protocols.swift` (HotkeyEvent)
- Modify: `WiskaKit/Sources/Hotkey/FnKeyStateMachine.swift`
- Modify: `WiskaKit/Sources/Hotkey/FnHotkeyMonitor.swift`
- Test: `WiskaKit/Tests/HotkeyTests/FnKeyStateMachineTests.swift`, `WiskaKit/Tests/HotkeyTests/FnHotkeyMonitorTests.swift`

**Interfaces:**
- Produces: `HotkeyEvent.locked`; `KeyInput.keyDown(keyCode: Int64, time: TimeInterval)`; `FnKeyStateMachine.unlock()`, `FnKeyStateMachine.isLocked: Bool`, `FnKeyStateMachine.escapeKeyCode = 53`; `FnHotkeyMonitor.endHandsFree()`.

- [ ] **Step 1: Write the failing tests**

In `FnKeyStateMachineTests.swift`, change the existing `.keyDown(time: X)` uses to `.keyDown(keyCode: 0, time: X)`, add a helper and the new tests:

```swift
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
        #expect(machine.reset())
        #expect(!machine.isLocked)
        #expect(!machine.reset())
    }

    @Test func otherKeyAfterTheFirstTapDisarms() {
        #expect(run([down(10), up(10.1), key(10.2), down(10.3), up(10.4)])
                == [.pressed(shifted: false), .tapped(shifted: false), nil, .pressed(shifted: false), .tapped(shifted: false)])
    }
```

In `FnHotkeyMonitorTests.swift` add:

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `cd WiskaKit && swift test --filter HotkeyTests 2>&1 | tail -20`
Expected: compile errors — `keyDown(keyCode:time:)`, `.locked`, `isLocked`, `unlock`, `endHandsFree` don't exist.

- [ ] **Step 3: Implement**

`Protocols.swift`, in `HotkeyEvent` after `shiftAdded`:

```swift
    /// The second quick tap of a double-tap: the recording that press started keeps going hands-free.
    case locked
```

`FnKeyStateMachine.swift` — replace the type with:

```swift
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
        case .flagsChanged(fnDown: false, shift: _, time: _):
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
    public mutating func unlock() {
        isLocked = false
        pressedAt = nil
        secondPress = false
        armedUntil = nil
    }

    /// Forget any hold or lock in progress (used when the event tap was disabled and events may
    /// have been missed). Returns true if a hold or a hands-free dictation was in progress.
    public mutating func reset() -> Bool {
        let wasActive = (pressedAt != nil && !interrupted) || isLocked
        unlock()
        shifted = false
        interrupted = false
        return wasActive
    }
}
```

`FnHotkeyMonitor.swift` — pass the key code, and add `endHandsFree()` after `receive`:

```swift
        case .keyDown:
            feed(.keyDown(keyCode: keyCode, time: time))
```

```swift
    /// The hands-free dictation ended without an fn tap or Esc: the next fn press starts afresh.
    public func endHandsFree() {
        machine.unlock()
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd WiskaKit && swift test --filter HotkeyTests 2>&1 | tail -5`
Expected: all Hotkey tests pass. (Other modules may fail to compile on the new `HotkeyEvent` case only if they switch exhaustively — `CommandMapper` does; Task 2 fixes it. If `swift test --filter` fails to build because of it, add a temporary `case .locked: return MappedHotkey(command: nil, newToggleLanguage: nil)` to `CommandMapper.map` now; Task 2 replaces it.)

- [ ] **Step 5: Commit**

```bash
git add WiskaKit/Sources/Core/Protocols.swift WiskaKit/Sources/Hotkey WiskaKit/Sources/Dictation/CommandMapper.swift WiskaKit/Tests/HotkeyTests
git commit -m "feat(hotkey): double-tap fn locks hands-free; fn tap finishes, Esc cancels

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: lockHandsFree command and SilenceWatch

**Files:**
- Modify: `WiskaKit/Sources/Core/Language.swift` (DictationCommand)
- Modify: `WiskaKit/Sources/Dictation/CommandMapper.swift`
- Create: `WiskaKit/Sources/Dictation/SilenceWatch.swift`
- Test: `WiskaKit/Tests/DictationTests/CommandMapperTests.swift`, Create `WiskaKit/Tests/DictationTests/SilenceWatchTests.swift`

**Interfaces:**
- Consumes: `HotkeyEvent.locked` (Task 1).
- Produces: `DictationCommand.lockHandsFree`; `struct SilenceWatch { static let speechThreshold: Float = 0.3; init(timeout: TimeInterval); mutating func feed(level: Float, time: TimeInterval) -> Bool }` (true exactly once, when silence reached `timeout`; never when `timeout <= 0`).

- [ ] **Step 1: Write the failing tests**

`CommandMapperTests.swift` — add (reuse the file's existing context helper; if it has none, build `HotkeyContext(mode: .autoDetect, primary: .english, secondary: .swedish, toggle: .english, enabled: [.english, .swedish], canStart: true)`):

```swift
    @Test func lockedMapsToLockHandsFree() {
        let context = HotkeyContext(mode: .autoDetect, primary: .english, secondary: .swedish, toggle: .english,
                                    enabled: [.english, .swedish], canStart: true)
        #expect(CommandMapper.map(.locked, context: context)
                == MappedHotkey(command: .lockHandsFree, newToggleLanguage: nil))
    }
```

`SilenceWatchTests.swift`:

```swift
import Testing
@testable import Dictation

struct SilenceWatchTests {
    @Test func stopsAfterTheTimeoutOfQuiet() {
        var watch = SilenceWatch(timeout: 2)
        #expect(!watch.feed(level: 0.1, time: 10))
        #expect(!watch.feed(level: 0.1, time: 11.9))
        #expect(watch.feed(level: 0.1, time: 12))
    }

    @Test func speechResetsTheClock() {
        var watch = SilenceWatch(timeout: 2)
        #expect(!watch.feed(level: 0.1, time: 10))
        #expect(!watch.feed(level: 0.6, time: 11.5))
        #expect(!watch.feed(level: 0.1, time: 13))
        #expect(!watch.feed(level: 0.1, time: 14.9))
        #expect(watch.feed(level: 0.1, time: 15))
    }

    @Test func thresholdLevelCountsAsSpeech() {
        var watch = SilenceWatch(timeout: 1)
        #expect(!watch.feed(level: 0.1, time: 10))
        #expect(!watch.feed(level: SilenceWatch.speechThreshold, time: 10.9))
        #expect(!watch.feed(level: 0.1, time: 11.5))
    }

    @Test func reportsOnlyOnce() {
        var watch = SilenceWatch(timeout: 1)
        _ = watch.feed(level: 0, time: 10)
        #expect(watch.feed(level: 0, time: 11))
        #expect(!watch.feed(level: 0, time: 12))
    }

    @Test func zeroTimeoutNeverStops() {
        var watch = SilenceWatch(timeout: 0)
        #expect(!watch.feed(level: 0, time: 10))
        #expect(!watch.feed(level: 0, time: 1_000))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd WiskaKit && swift test --filter "SilenceWatchTests|CommandMapperTests" 2>&1 | tail -20`
Expected: compile errors — `SilenceWatch`, `.lockHandsFree` undefined.

- [ ] **Step 3: Implement**

`Language.swift`, in `DictationCommand` after `cancel`:

```swift
    /// The recording in progress continues hands-free (double-tap fn).
    case lockHandsFree
```

`CommandMapper.swift`, in `map` (replacing any temporary `.locked` case):

```swift
        case .locked:
            return MappedHotkey(command: .lockHandsFree, newToggleLanguage: nil)
```

`SilenceWatch.swift`:

```swift
import Foundation

/// Decides when a hands-free dictation has been quiet long enough to finish.
/// Fed the microphone's 0…1 levels with their times; speech resets the clock.
struct SilenceWatch {
    /// ≈ −35 dBFS on `Levels.normalized`: quieter than speech, louder than a quiet room.
    static let speechThreshold: Float = 0.3

    private let timeout: TimeInterval
    private var quietSince: TimeInterval?
    private var reported = false

    /// `timeout` ≤ 0 means never.
    init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    /// True exactly once: when the level has stayed below the threshold for `timeout`.
    mutating func feed(level: Float, time: TimeInterval) -> Bool {
        guard timeout > 0, !reported else { return false }
        guard level < Self.speechThreshold else {
            quietSince = nil
            return false
        }
        let since = quietSince ?? time
        quietSince = since
        guard time - since >= timeout else { return false }
        reported = true
        return true
    }
}
```

Also `DictationController.handle` must compile with the new case; add a placeholder that Task 4 replaces:

```swift
        case .lockHandsFree:
            break   // Task 4
```

And `Wiska/AppModel.swift` `handle(_ event:)` switch: change `case .finish, .cancel: break` to `case .finish, .cancel, .lockHandsFree: break`.

- [ ] **Step 4: Run to verify pass**

Run: `cd WiskaKit && swift test --filter "SilenceWatchTests|CommandMapperTests" 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit/Sources WiskaKit/Tests/DictationTests Wiska/AppModel.swift
git commit -m "feat(dictation): lockHandsFree command and SilenceWatch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Sessions report a live preview

**Files:**
- Modify: `WiskaKit/Sources/Core/Protocols.swift` (TranscriptionSession)
- Modify: `WiskaKit/Sources/SpeechToText/AppleModule.swift`, `AppleTranscriptionSession.swift`, `AutoDetectSession.swift`, `AppleTranscriber.swift`
- Modify: `WiskaKit/Sources/Dictation/HybridTranscriber.swift`
- Test: `WiskaKit/Tests/SpeechToTextTests/AutoDetectSessionTests.swift`, `AppleTranscriberTests.swift`, `WiskaKit/Tests/DictationTests/HybridTranscriberTests.swift`

**Interfaces:**
- Produces: `TranscriptionSession.preview: AsyncStream<String>` (default: an already-finished empty stream; each access of a real session returns the same stream); `AutoDetectSession.init(sessions:fallback:previewIndex: Int = 0)`; `AppleTranscriber.init(..., livePreview: @escaping @MainActor () -> Bool = { false }, ...)`; `HybridSession.init(parakeet:apple:fallbackLanguage:)` picks its preview from `apple[fallbackLanguage]`, else the first Apple session in `Language.allCases` order, else Parakeet's.

- [ ] **Step 1: Write the failing tests**

`AutoDetectSessionTests.swift` — give `StubSession` a preview and add tests:

```swift
    let preview: AsyncStream<String>
    let previewInput: AsyncStream<String>.Continuation
    init(_ outcome: Result<Transcript, StubError>) {
        self.outcome = outcome
        (preview, previewInput) = AsyncStream.makeStream(of: String.self)
    }
```

```swift
    @Test func autoDetectPreviewFollowsPreferredSessionButPickIsUnchanged() async throws {
        let a = StubSession(.success(t("hello there", .english, 0.9)))
        let b = StubSession(.success(t("hej där", .swedish, 0.2)))
        let session = AutoDetectSession(sessions: [a, b], fallback: .swedish, previewIndex: 1)
        b.previewInput.yield("hej")
        b.previewInput.finish()
        var seen: [String] = []
        for await text in session.preview { seen.append(text) }
        #expect(seen == ["hej"])
        #expect(try await session.finish().language == .english)
    }

    @Test func previewDefaultsToTheFirstSession() async {
        let a = StubSession(.success(t("a", .english, 0.9)))
        let b = StubSession(.success(t("b", .swedish, 0.1)))
        a.previewInput.yield("a")
        a.previewInput.finish()
        var seen: [String] = []
        for await text in AutoDetectSession(sessions: [a, b], fallback: .english).preview { seen.append(text) }
        #expect(seen == ["a"])
    }
```

`AppleTranscriberTests.swift` — real audio (add next to `transcribesSpokenSwedish`):

```swift
    @Test(.timeLimit(.minutes(2)))
    func livePreviewShowsWordsBeforeTheFinalText() async throws {
        let samples = try spokenSamples("Can you send me the quarterly report before lunch tomorrow")
        let session = try await AppleTranscriber(languages: { [.english] }, livePreview: { true })
            .makeSession(language: .fixed(.english))
        let previews = Task { @MainActor in
            var seen: [String] = []
            for await text in session.preview { seen.append(text) }
            return seen
        }
        for start in stride(from: 0, to: samples.count, by: 1_600) {
            session.append(AudioChunk(samples: Array(samples[start..<min(start + 1_600, samples.count)])))
            try await Task.sleep(for: .milliseconds(20))
        }
        let transcript = try await session.finish()
        let seen = await previews.value
        #expect(seen.count >= 2, "previews: \(seen)")
        #expect(seen.contains { !$0.isEmpty })
        #expect(transcript.text.lowercased().contains("quarterly report"))
    }

    @Test(.timeLimit(.minutes(1)))
    func previewOffYieldsOnlyFinishedSegments() async throws {
        let session = try await AppleTranscriber(languages: { [.english] }, livePreview: { false })
            .makeSession(language: .fixed(.english))
        session.append(AudioChunk(samples: Array(repeating: 0, count: 16_000)))
        _ = try await session.finish()
        var seen: [String] = []
        for await text in session.preview { seen.append(text) }
        #expect(seen.allSatisfy(\.isEmpty))
    }
```

`HybridTranscriberTests.swift` — add (use the file's existing fakes; if its Apple fake session type lacks a preview, give it `let preview: AsyncStream<String>` + `previewInput` exactly as `StubSession` above):

```swift
    @Test func hybridPreviewFollowsTheFallbackAppleSession() async {
        let parakeet = FakeSession()
        let english = PreviewSession()
        let swedish = PreviewSession()
        let session = HybridSession(parakeet: parakeet, apple: [.english: english, .swedish: swedish],
                                    fallbackLanguage: .swedish)
        swedish.previewInput.yield("hej")
        swedish.previewInput.finish()
        var seen: [String] = []
        for await text in session.preview { seen.append(text) }
        #expect(seen == ["hej"])
    }
```

and in `WiskaKit/Tests/DictationTests/Fakes.swift`:

```swift
/// A session whose preview the test drives.
@MainActor
final class PreviewSession: TranscriptionSession {
    let preview: AsyncStream<String>
    let previewInput: AsyncStream<String>.Continuation
    var text = "hello world"
    init() { (preview, previewInput) = AsyncStream.makeStream(of: String.self) }
    func append(_ chunk: AudioChunk) {}
    func finish() async throws -> Transcript {
        Transcript(text: text, locale: Locale(identifier: "en_US"), language: .english)
    }
    func cancel() { previewInput.finish() }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd WiskaKit && swift test --filter "AutoDetectSessionTests|HybridTranscriberTests|livePreview|previewOff" 2>&1 | tail -20`
Expected: compile errors — `preview` not a member of `TranscriptionSession`, `previewIndex`/`livePreview` unknown.

- [ ] **Step 3: Implement**

`Protocols.swift`:

```swift
public protocol TranscriptionSession: AnyObject, Sendable {
    func append(_ chunk: AudioChunk)
    func finish() async throws -> Transcript
    func cancel()
    /// The words heard so far, while listening (for the HUD). Ends when the session does.
    /// Engines without partial results (Parakeet) report nothing.
    var preview: AsyncStream<String> { get }
}

public extension TranscriptionSession {
    var preview: AsyncStream<String> { AsyncStream { $0.finish() } }
}
```

`AppleModule.swift` — `make(_:volatile:)` and a progress callback; the final list stays finalized-only:

```swift
struct AppleModule {
    let language: Language
    let module: any SpeechModule
    /// Collects finalized results; calls `progress` with the text so far (finalized + volatile).
    let collect: @Sendable (_ progress: @escaping @Sendable (String) -> Void) async throws -> [AttributedString]

    static func make(_ language: Language, volatile: Bool = false) -> AppleModule {
        if !language.usesDictationTranscriber {
            let module = SpeechTranscriber(
                locale: language.locale, transcriptionOptions: [],
                reportingOptions: volatile ? [.volatileResults] : [],
                attributeOptions: [.transcriptionConfidence]
            )
            let results = module.results
            return AppleModule(language: language, module: module) { progress in
                var finals: [AttributedString] = []
                for try await result in results {
                    if result.isFinal { finals.append(result.text) }
                    progress(text(finals, pending: result.isFinal ? nil : result.text))
                }
                return finals
            }
        } else {
            let module = DictationTranscriber(
                locale: language.locale, contentHints: [.shortForm], transcriptionOptions: [.punctuation],
                reportingOptions: volatile ? [.volatileResults] : [],
                attributeOptions: [.transcriptionConfidence]
            )
            let results = module.results
            return AppleModule(language: language, module: module) { progress in
                var finals: [AttributedString] = []
                for try await result in results {
                    if result.isFinal { finals.append(result.text) }
                    progress(text(finals, pending: result.isFinal ? nil : result.text))
                }
                return finals
            }
        }
    }

    /// Finalized text plus the segment still being heard, whitespace-normalized.
    static func text(_ finals: [AttributedString], pending: AttributedString?) -> String {
        summarize(finals + (pending.map { [$0] } ?? [])).text
    }
```

(`summarize` is unchanged. `text` is `static`, so call it as `AppleModule.text(...)` inside the closures if the compiler requires.)

`AppleTranscriptionSession.swift`:
- Add a stored `let preview: AsyncStream<String>` and pass it through the private init.
- `start(language:vocabulary:volatile: Bool = false)`:

```swift
        let apple = AppleModule.make(language, volatile: volatile)
        ...
        let (preview, previewInput) = AsyncStream.makeStream(of: String.self,
                                                             bufferingPolicy: .bufferingNewest(1))
        let collector = Task<[AttributedString], Error> {
            defer { previewInput.finish() }
            return try await apple.collect { previewInput.yield($0) }
        }
```

and in the `catch` path also call `previewInput.finish()`. Pass `preview: preview` to the init.

`AutoDetectSession.swift`:

```swift
    private let previewIndex: Int

    init(sessions: [any TranscriptionSession], fallback: Language, previewIndex: Int = 0) {
        self.sessions = sessions
        self.fallback = fallback
        self.previewIndex = sessions.indices.contains(previewIndex) ? previewIndex : 0
    }

    /// One session's words: the language Wiska expects (the last one detected).
    var preview: AsyncStream<String> {
        sessions.isEmpty ? AsyncStream { $0.finish() } : sessions[previewIndex].preview
    }
```

`AppleTranscriber.swift`:
- Add `@ObservationIgnored private let livePreview: @MainActor () -> Bool` and the init parameter `livePreview: @escaping @MainActor () -> Bool = { false }` (after `vocabulary`).
- `.fixed`: `return try await AppleTranscriptionSession.start(language: fixed, vocabulary: words, volatile: livePreview())`
- `.automatic`: only the language that will be previewed asks for volatile results; track started languages:

```swift
            let preferred = fallbackLanguage()
            let candidates = ready.isEmpty ? ticked : ready
            let previewed = candidates.contains(preferred) ? preferred : candidates.first
            var sessions: [any TranscriptionSession] = []
            var started: [Language] = []
            var firstError: Error?
            for language in candidates {
                do {
                    try await prepare(language)
                    sessions.append(try await AppleTranscriptionSession.start(
                        language: language, vocabulary: words, volatile: livePreview() && language == previewed))
                    started.append(language)
                } catch {
                    Self.log.error("auto-detect without \(language.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    firstError = firstError ?? error
                }
            }
            if let only = sessions.first, sessions.count == 1 { return only }
            guard !sessions.isEmpty else { throw firstError ?? TranscriptionError.noCompatibleAudioFormat }
            return AutoDetectSession(sessions: sessions, fallback: preferred,
                                     previewIndex: previewed.flatMap(started.firstIndex(of:)) ?? 0)
```

`HybridTranscriber.swift`:
- `HybridSession` gains:

```swift
    /// Parakeet has no partial results: preview the Apple session for the expected language.
    var preview: AsyncStream<String> {
        let source = apple[fallbackLanguage]
            ?? Language.allCases.lazy.compactMap { self.apple[$0] }.first
        return source?.preview ?? parakeet.preview
    }
```

- `LabeledSession` gains `var preview: AsyncStream<String> { inner.preview }`.

- [ ] **Step 4: Run to verify pass**

Run: `cd WiskaKit && swift test --filter "AutoDetectSessionTests|HybridTranscriberTests|AppleTranscriberTests" 2>&1 | tail -8`
Expected: PASS, including the real-audio `livePreviewShowsWordsBeforeTheFinalText`.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit/Sources WiskaKit/Tests
git commit -m "feat(speech): sessions report the words heard so far (Apple volatile results)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Controller — hands-free and silence stop

**Files:**
- Modify: `WiskaKit/Sources/Dictation/DictationController.swift`
- Test: `WiskaKit/Tests/DictationTests/DictationControllerTests.swift`

**Interfaces:**
- Consumes: `DictationCommand.lockHandsFree`, `SilenceWatch` (Task 2).
- Produces: `DictationController.isHandsFree: Bool` (public, read-only; changes call `onChange`); init parameter `handsFreeSilence: @escaping @MainActor () -> TimeInterval = { 30 }` (seconds, 0 = off), placed after `contextProvider`.

- [ ] **Step 1: Write the failing tests**

Extend `makeController` with `silence: TimeInterval = 30` and pass `handsFreeSilence: { silence }`. Add:

```swift
    @Test func lockOutsideListeningIsIgnored() {
        let controller = makeController()
        controller.handle(.lockHandsFree)
        #expect(!controller.isHandsFree)
        #expect(controller.state == .idle)
    }

    @Test func lockMarksTheDictationHandsFreeAndNotifies() {
        let controller = makeController()
        let changes = Box(0)
        controller.onChange = { _, _ in changes.value += 1 }
        controller.handle(en)
        let before = changes.value
        controller.handle(.lockHandsFree)
        #expect(controller.isHandsFree)
        #expect(changes.value > before)
    }

    @Test(.timeLimit(.minutes(1))) func handsFreeSilenceFinishesAndPastes() async throws {
        let controller = makeController(silence: 0.05)
        controller.handle(en)
        controller.handle(.lockHandsFree)
        audio.emit([0.1])
        audio.emitLevel(0.05)
        try await Task.sleep(for: .milliseconds(100))
        audio.emitLevel(0.05)
        while controller.currentTask == nil { try await Task.sleep(for: .milliseconds(10)) }
        await controller.currentTask?.value
        #expect(injector.injected == ["cleaned: hello world"])
        #expect(!controller.isHandsFree)
    }

    @Test func holdToTalkIgnoresSilence() async throws {
        let controller = makeController(silence: 0.05)
        controller.handle(en)
        audio.emitLevel(0.05)
        try await Task.sleep(for: .milliseconds(100))
        audio.emitLevel(0.05)
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.state == .listening)
        controller.handle(.cancel)
    }

    @Test func silenceOffNeverFinishes() async throws {
        let controller = makeController(silence: 0)
        controller.handle(en)
        controller.handle(.lockHandsFree)
        audio.emitLevel(0.05)
        try await Task.sleep(for: .milliseconds(100))
        audio.emitLevel(0.05)
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.state == .listening)
        controller.handle(.cancel)
        #expect(!controller.isHandsFree)
    }

    @Test func aNewDictationStartsNotHandsFree() async {
        let controller = makeController()
        controller.handle(en)
        controller.handle(.lockHandsFree)
        controller.handle(.finish)
        await controller.currentTask?.value
        controller.handle(en)
        #expect(!controller.isHandsFree)
        controller.handle(.cancel)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd WiskaKit && swift test --filter DictationControllerTests 2>&1 | tail -20`
Expected: compile errors — `handsFreeSilence`, `isHandsFree` unknown.

- [ ] **Step 3: Implement**

In `DictationController`:

```swift
    /// The dictation in progress was locked with a double-tap (no fn to hold).
    public private(set) var isHandsFree = false { didSet { if oldValue != isHandsFree { notify() } } }
    private let handsFreeSilence: @MainActor () -> TimeInterval
    private var silence: SilenceWatch?
```

Init: add `handsFreeSilence: @escaping @MainActor () -> TimeInterval = { 30 },` after `contextProvider`, assign it.

`handle`: replace the Task 2 placeholder:

```swift
        case .lockHandsFree:
            guard state == .listening, !isHandsFree else { return }
            silence = SilenceWatch(timeout: handsFreeSilence())
            isHandsFree = true
```

In `.finish` (before `state = ready ? …`) and at the top of `startListening` and in `cancelListening`: `endHandsFree()` where

```swift
    private func endHandsFree() {
        silence = nil
        isHandsFree = false
    }
```

`pushLevel` — after updating `levels`:

```swift
        if silence?.feed(level: level, time: ProcessInfo.processInfo.systemUptime) == true {
            Self.log.notice("hands-free: silence; auto-finishing")
            handle(.finish)
        }
```

(`cancelListening(endState: .listening)` on a language switch also ends hands-free; a switch can't happen while locked because the key machine ignores fn while locked.)

- [ ] **Step 4: Run to verify pass**

Run: `cd WiskaKit && swift test --filter DictationControllerTests 2>&1 | tail -5`
Expected: PASS (old and new).

- [ ] **Step 5: Commit**

```bash
git add WiskaKit/Sources/Dictation/DictationController.swift WiskaKit/Tests/DictationTests/DictationControllerTests.swift
git commit -m "feat(dictation): hands-free dictations finish after a stretch of silence

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Controller — forward the preview

**Files:**
- Modify: `WiskaKit/Sources/Dictation/DictationController.swift`
- Test: `WiskaKit/Tests/DictationTests/DictationControllerTests.swift`, `Fakes.swift`

**Interfaces:**
- Consumes: `TranscriptionSession.preview` (Task 3), `PreviewSession` fake (Task 3).
- Produces: `DictationController.preview: String` (public, read-only; changes call `onChange`); init parameter `showPreview: @escaping @MainActor () -> Bool = { true }` after `handsFreeSilence`.

Ruling vs spec: the spec names an `onPreview(String)` callback; the controller instead exposes `preview` and notifies through the existing `onChange`, like `levels` — one channel for the HUD.

- [ ] **Step 1: Write the failing tests**

Give `FakeTranscriber` an optional session override in `Fakes.swift`:

```swift
    var sessionOverride: (any TranscriptionSession)?
```

and in its `makeSession` return `sessionOverride ?? session`. Extend `makeController` with `showPreview: Bool = true` → `showPreview: { showPreview }`. Tests:

```swift
    @Test(.timeLimit(.minutes(1))) func previewIsForwardedWhileListening() async throws {
        let live = PreviewSession()
        transcriber.sessionOverride = live
        let controller = makeController()
        controller.handle(en)
        live.previewInput.yield("hello")
        while controller.preview != "hello" { try await Task.sleep(for: .milliseconds(10)) }
        controller.handle(.cancel)
    }

    @Test(.timeLimit(.minutes(1))) func previewClearsWhenListeningEnds() async throws {
        let live = PreviewSession()
        transcriber.sessionOverride = live
        let controller = makeController()
        controller.handle(en)
        live.previewInput.yield("hello")
        while controller.preview.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        controller.handle(.finish)
        #expect(controller.preview.isEmpty)
        await controller.currentTask?.value
        live.previewInput.yield("late words")
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.preview.isEmpty)
    }

    @Test func previewOffIsNotForwarded() async throws {
        let live = PreviewSession()
        transcriber.sessionOverride = live
        let controller = makeController(showPreview: false)
        controller.handle(en)
        live.previewInput.yield("hello")
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.preview.isEmpty)
        controller.handle(.cancel)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd WiskaKit && swift test --filter DictationControllerTests 2>&1 | tail -20`
Expected: compile errors — `preview`, `showPreview`, `sessionOverride` unknown.

- [ ] **Step 3: Implement**

```swift
    /// The words heard so far in this dictation (empty when the preview is off or not available).
    public private(set) var preview = "" { didSet { if oldValue != preview { notify() } } }
    private let showPreview: @MainActor () -> Bool
    private var previewTask: Task<Void, Never>?
```

Init parameter `showPreview: @escaping @MainActor () -> Bool = { true },` after `handsFreeSilence`; assign.

In `startListening`, at the top (after `resetTask?.cancel()`): `preview = ""`. Inside `sessionTask`, right after `let session = try await transcriber.makeSession(language: choice)`:

```swift
            if let self, self.showPreview() {
                self.previewTask = Task { [weak self] in
                    for await text in session.preview {
                        guard !Task.isCancelled, let self, self.state == .listening else { return }
                        self.preview = text
                    }
                }
            }
```

In `stopCapture()` add:

```swift
        previewTask?.cancel()
        previewTask = nil
        preview = ""
```

In `handle(.finish)`, before `state = ready ? …`, add `preview = ""` (stopCapture runs later, after the release tail; the preview must vanish the moment listening ends) and `previewTask?.cancel()`.

- [ ] **Step 4: Run to verify pass**

Run: `cd WiskaKit && swift test --filter DictationControllerTests 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit/Sources/Dictation/DictationController.swift WiskaKit/Tests/DictationTests
git commit -m "feat(dictation): controller exposes the live preview while listening

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: HUD — preview line and lock mark

**Files:**
- Modify: `WiskaKit/Sources/HUD/HUDContent.swift`, `HUDView.swift`, `HUDPanelController.swift`
- Create: `WiskaKit/Sources/HUD/PreviewTicker.swift`
- Test: `WiskaKit/Tests/HUDTests/HUDRevealTests.swift`, `HUDPanelControllerTests.swift`

**Interfaces:**
- Produces: `HUDContent.listening(levels: [Float], badge: String, preview: String, handsFree: Bool)`; `HUDView.previewHeight: CGFloat = 18`; `HUDView.height(expanded: Bool) -> CGFloat`; `PreviewTicker(text:)` view; `HUDPanelController.expands(_ current: Bool, for content: HUDContent) -> Bool` (static).

- [ ] **Step 1: Write the failing tests**

`HUDRevealTests.swift`:

```swift
    @Test func previewRowAddsHeightOnlyWhenExpanded() {
        #expect(HUDView.height(expanded: false) == 44)
        #expect(HUDView.height(expanded: true) == 62)
    }
```

`HUDPanelControllerTests.swift`:

```swift
    @Test(.enabled(if: !NSScreen.screens.isEmpty))
    func longPreviewNeverWidensTheCapsule() async throws {
        let hud = HUDPanelController()
        hud.show(.listening(levels: [], badge: "EN", preview: String(repeating: "words keep coming ", count: 20),
                            handsFree: true))
        try await Task.sleep(for: .milliseconds(300))
        hud.panel.contentView?.layoutSubtreeIfNeeded()
        #expect(hud.panel.frame.width <= 340, "panel width \(hud.panel.frame.width)")
        hud.show(.hidden)
    }

    @Test func capsuleExpandsWithTheFirstWordsAndStaysUntilHidden() {
        let quiet = HUDContent.listening(levels: [], badge: "EN", preview: "", handsFree: false)
        let words = HUDContent.listening(levels: [], badge: "EN", preview: "hello", handsFree: false)
        #expect(!HUDPanelController.expands(false, for: quiet))
        #expect(HUDPanelController.expands(false, for: words))
        #expect(HUDPanelController.expands(true, for: quiet))
        #expect(HUDPanelController.expands(true, for: .working("Transcribing…")))
        #expect(!HUDPanelController.expands(true, for: .hidden))
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd WiskaKit && swift test --filter HUDTests 2>&1 | tail -20`
Expected: compile errors — `height(expanded:)`, `expands`, 4-field `.listening` unknown.

- [ ] **Step 3: Implement**

`HUDContent.swift`:

```swift
    case listening(levels: [Float], badge: String, preview: String, handsFree: Bool)
```

and in `HUDModel` add `var expanded = false`.

`HUDView.swift`:

```swift
    static let contentHeight: CGFloat = 44
    static let previewHeight: CGFloat = 18

    static func height(expanded: Bool) -> CGFloat {
        contentHeight + (expanded ? previewHeight : 0)
    }
```

In `body`, use `let height = Self.height(expanded: model.expanded)` for both `visibleHeight(contentHeight: height, …)` and `.frame(height: height)` (replacing `Self.contentHeight` in those two places). Replace the `.listening` case:

```swift
        case .listening(let levels, let badge, let preview, let handsFree):
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Text(badge)
                        if handsFree { Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold)) }
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .foregroundStyle(AuroraTheme.start(model.highlight))
                    .background(AuroraTheme.start(model.highlight).opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
                    WaveformView(levels: levels, highlight: model.highlight)
                }
                .frame(height: Self.contentHeight)
                if model.expanded {
                    PreviewTicker(text: preview)
                        .frame(height: Self.previewHeight, alignment: .top)
                }
            }
```

Create `WiskaKit/Sources/HUD/PreviewTicker.swift` — the scrolling line:

```swift
import SwiftUI

/// The live preview as a ticker inside the notch: one line anchored to the right edge, so new
/// words slide in from the right and older ones scroll out past a faded left edge.
/// The text is laid out at its natural width and clipped, so it never widens the capsule.
struct PreviewTicker: View {
    let text: String

    var body: some View {
        Color.clear
            .overlay(alignment: .trailing) {
                Text(text)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AuroraTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .animation(.easeOut(duration: 0.25), value: text)
            }
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12)],
                               startPoint: .leading, endPoint: .trailing)
            }
    }
}
```

`HUDPanelController.swift`:
- `static let contentSize = CGSize(width: NotchLayout.fallbackWidth, height: HUDView.height(expanded: true))`.
- In `place()`: `contentHeight: HUDView.height(expanded: true)` (the panel is transparent and click-through; only the visible shape grows) and `model.expanded = false`.
- Add:

```swift
    /// The capsule grows a row when the first words arrive and keeps it until it hides.
    static func expands(_ current: Bool, for content: HUDContent) -> Bool {
        switch content {
        case .hidden: false
        case .listening(_, _, let preview, _): current || !preview.isEmpty
        default: current
        }
    }
```

- In `show(_:)`, after the content update block and before the reveal animation:

```swift
        let expanded = Self.expands(model.expanded, for: content)
        if expanded != model.expanded {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { model.expanded = expanded }
        }
```

- In `hide()`'s completion, after `self.model.content = .hidden`: `self.model.expanded = false`.

- [ ] **Step 4: Run to verify pass**

Run: `cd WiskaKit && swift test --filter HUDTests 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit/Sources/HUD WiskaKit/Tests/HUDTests
git commit -m "feat(hud): live preview line under the waveform; lock mark when hands-free

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Settings and app wiring

**Files:**
- Modify: `WiskaKit/Sources/Preferences/SettingsStore.swift`
- Modify: `Wiska/AppModel.swift`, `Wiska/Settings/GeneralTab.swift`
- Test: `WiskaKit/Tests/PreferencesTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `SettingsStore.handsFreeSilence: TimeInterval` (default 30), `SettingsStore.livePreview: Bool` (default true), `SettingsStore.handsFreeSilenceChoices: [TimeInterval] = [0, 10, 30, 60, 120]`.

- [ ] **Step 1: Write the failing test**

```swift
    @Test func handsFreeAndPreviewDefaultsAndPersist() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.handsFreeSilence == 30)
        #expect(store.livePreview)
        store.handsFreeSilence = 0
        store.livePreview = false
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.handsFreeSilence == 0)
        #expect(!reloaded.livePreview)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd WiskaKit && swift test --filter SettingsStoreTests 2>&1 | tail -10`
Expected: compile error — `handsFreeSilence` unknown.

- [ ] **Step 3: Implement**

`SettingsStore.swift`: keys `static let handsFreeSilence = "handsFreeSilence"`, `static let livePreview = "livePreview"`;

```swift
    public static let handsFreeSilenceChoices: [TimeInterval] = [0, 10, 30, 60, 120]
    /// Seconds of silence after which a hands-free dictation finishes; 0 = never.
    public var handsFreeSilence: TimeInterval { didSet { defaults.set(handsFreeSilence, forKey: Key.handsFreeSilence) } }
    public var livePreview: Bool { didSet { defaults.set(livePreview, forKey: Key.livePreview) } }
```

in `init`:

```swift
        handsFreeSilence = defaults.object(forKey: Key.handsFreeSilence) as? TimeInterval ?? 30
        livePreview = defaults.object(forKey: Key.livePreview) as? Bool ?? true
```

`AppModel.swift`:
- `AppleTranscriber(…, vocabulary: …, livePreview: { settings.livePreview })` (argument order per Task 3's init).
- `DictationController(…, contextProvider: {…}, handsFreeSilence: { settings.handsFreeSilence }, showPreview: { settings.livePreview })`.
- In `controller.onChange`: after `if dictationState != state …`, add

```swift
            if state != .listening { hotkey.endHandsFree() }
```

- In `handle(_ event:)`, after `controller.handle(command)`:

```swift
            // A lock that didn't take (no dictation running) must not swallow the next fn press.
            if command == .lockHandsFree, !controller.isHandsFree { hotkey.endHandsFree() }
```

and `case .finish, .cancel, .lockHandsFree: break` in its switch (already from Task 2).
- `hudContent`: `case .listening: .listening(levels: levels, badge: badge, preview: controller.preview, handsFree: controller.isHandsFree)`.

`GeneralTab.swift` — replace `Section("Push-to-talk")`:

```swift
            Section("Dictation") {
                LabeledContent("Dictate", value: "Hold fn, speak, release")
                LabeledContent("Hands-free", value: "Double-tap fn · tap fn to finish · Esc cancels")
                Picker("Finish hands-free after silence", selection: Binding(
                    get: { model.settings.handsFreeSilence },
                    set: { model.settings.handsFreeSilence = $0 })) {
                    ForEach(SettingsStore.handsFreeSilenceChoices, id: \.self) { seconds in
                        Text(Self.silenceLabel(seconds)).tag(seconds)
                    }
                }
                Toggle("Show live preview in the notch", isOn: Binding(get: { model.settings.livePreview },
                                                          set: { model.settings.livePreview = $0 }))
                Text("The words appear under the waveform as you speak (Apple engine only).")
                    .font(.caption).foregroundStyle(.secondary)
            }
```

```swift
    private static func silenceLabel(_ seconds: TimeInterval) -> String {
        switch seconds {
        case 0: "Never"
        case ..<60: "\(Int(seconds)) seconds"
        case 60: "1 minute"
        default: "\(Int(seconds / 60)) minutes"
        }
    }
```

(If `GeneralTab` doesn't import Preferences, add `import Preferences`; check how `model.settings` is reached in other tabs, e.g. `CleanupTab.swift`, and match it.)

- [ ] **Step 4: Verify**

Run: `cd WiskaKit && swift test 2>&1 | tail -5`
Expected: the full suite passes (read the summary line before committing).

Run (repo root): `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build -quiet build 2>&1 | tail -5`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit/Sources/Preferences WiskaKit/Tests/PreferencesTests Wiska
git commit -m "feat(settings): hands-free silence and live preview settings; wire M8 into the app

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Manual check (relaunch `build/Build/Products/Debug/Wiska.app`)**

Double-tap fn → lock mark, words appear under the waveform; tap fn → pastes. Double-tap, press Esc → nothing pasted. Double-tap, stay quiet 30 s → pastes what was said. Hold fn → unchanged. Toggle the preview off → waveform only.
