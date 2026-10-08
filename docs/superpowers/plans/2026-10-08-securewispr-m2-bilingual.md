# SecureWispr M2 Bilingual + Engines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swedish + English dictation with three selectable language modes (Auto-detect, Toggle, Per-language hotkeys), and an optional Parakeet engine downloadable from Settings.

**Architecture:** Pure language logic (`Language`, `LanguageRouter`, `LanguagePicker`) lives in `Core`. Hotkeys emit richer events (`pressed(shifted:)`, `tapped(shifted:)`); a pure `CommandMapper` in `Dictation` turns them plus settings into `DictationCommand`s, so the controller never knows about modes. `AppleTranscriber` serves EN (`SpeechTranscriber`), SV (`DictationTranscriber`) and automatic (an `AutoDetectSession` running both and picking by confidence). A new `Parakeet` module wraps FluidAudio behind a backend protocol; a new `Preferences` module persists settings. The app picks the engine per dictation through a transcriber provider closure.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, Speech (`SpeechAnalyzer`, `SpeechTranscriber`, `DictationTranscriber`), NaturalLanguage (`NLLanguageRecognizer`), FluidAudio 0.17.7 (Parakeet TDT 0.6B v3), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-08-securewispr-m2-bilingual-design.md` (builds on the M1 spec)

## Global Constraints

- Deployment target macOS 26.0; package modules depend only on `Core` (plus FluidAudio for `Parakeet` only); never import one component module from another.
- Default engine `.apple`; default language mode `.autoDetect`; default primary language `.english`.
- English = `SpeechTranscriber(en_US)`; Swedish = `DictationTranscriber(sv_SE, contentHints: [.shortForm], transcriptionOptions: [.punctuation])`; both with `attributeOptions: [.transcriptionConfidence]`.
- `LanguagePicker.minimumMargin = 0.15`; within margin → `lastDetectedLanguage`.
- Toggle: quick fn+⇧ tap flips the language; HUD flash 1 s. Auto-detect winner flash 0.8 s after paste.
- Per-language hotkeys: fn = primary, fn+⇧ = the other language. ⇧ never counts as "another key".
- Release tail: keep capturing 150 ms after `finish` before stopping the recorder.
- Network: only `ParakeetModelStore.download()` may touch the network. Model dir: `~/Library/Application Support/SecureWispr/Models/parakeet-tdt-0.6b-v3/`.
- Parakeet selected but not ready → use Apple; menu shows "Parakeet unavailable — using Apple".
- Missing permissions block only `start`, never `finish`/`cancel`.
- In the `Parakeet` module always write `Core.Language` (FluidAudio also defines `Language`).
- Logging: transcript text only with `privacy: .private`.
- Package commands from `SecureWisprKit/`; app build: `xcodebuild -project SecureWispr.xcodeproj -scheme SecureWispr -configuration Debug -derivedDataPath build -allowProvisioningUpdates build`.

## Review Focus

1. **Settings changed while a dictation is running** (engine or mode switched in Settings mid-hold) → the running dictation finishes with the engine/language it started with; changes apply from the next press. (Test: Task 3 `transcriberIsChosenAtStartNotAtFinish`.)
2. **Parakeet model removed while Parakeet is selected and loaded** → the next dictation falls back to Apple without a crash. (Test: Task 7 `removingModelMakesTranscriberNotReady`.)
3. **Very short utterance with Parakeet (< 1 s)** → padded to 1 s so FluidAudio doesn't reject it; no error. (Test: Task 7 `shortAudioIsPaddedToOneSecond`.)
4. **Download interrupted** (failure, cancel, or app quit mid-download) → partial files never make the model look installed; status returns to Not downloaded / Failed and the directory is cleaned. (Tests: Task 7 `failedDownloadCleansUpAndReportsFailure`, `cancelledDownloadReturnsToNotDownloaded`, `partialFilesAreNotInstalled`.)
5. **Swedish characters (å ä ö) and Swedish punctuation** survive paste exactly. (Test: Task 4 `pastesSwedishCharactersExactly`.)

---

## File Structure

```
SecureWisprKit/
  Package.swift                                   + FluidAudio dep, Parakeet + Preferences targets
  Sources/Core/
    Language.swift                 NEW  Language, LanguageChoice, LanguageMode, SpeechEngine, DictationCommand
    LanguageRouter.swift           NEW  (mode, shifted, primary, toggle) → LanguageChoice
    LanguagePicker.swift           NEW  pick best Transcript by confidence with margin + fallback
    Transcript.swift               MOD  LanguageChoice moved out; Transcript.language added
    Protocols.swift                MOD  HotkeyEvent: pressed(shifted:), released, tapped(shifted:), cancelled
  Sources/Hotkey/
    FnKeyStateMachine.swift        MOD  ⇧ tracking, tapped(shifted:), reset()
    FnHotkeyMonitor.swift          MOD  passes ⇧ flag; resets machine on tap re-enable (minor c)
  Sources/Dictation/
    CommandMapper.swift            NEW  HotkeyEvent + HotkeyContext → MappedHotkey (minor d)
    DictationController.swift      MOD  handle(DictationCommand), transcriber provider, release tail (minor b), onLanguageDetected
  Sources/SpeechToText/
    AppleModule.swift              NEW  builds EN/SV modules + result collectors
    AppleTranscriptionSession.swift MOD language-generic, confidence, cleanup on error (minor a)
    AutoDetectSession.swift        NEW  fan-out to two sessions, pick winner
    AppleTranscriber.swift         MOD  fixed(EN/SV) + automatic; prepares both
    AppleSpeechAssets.swift        MOD  takes any SpeechModule
  Sources/Preferences/
    SettingsStore.swift            NEW  UserDefaults-backed @Observable settings
  Sources/Parakeet/
    SpeechRecognizerBackend.swift  NEW  protocol + FluidAudioBackend
    LanguageGuess.swift            NEW  NLLanguageRecognizer EN/SV
    ParakeetSession.swift          NEW  buffer → transcribe on finish
    ParakeetTranscriber.swift      NEW  Transcriber over a backend
    ParakeetModelStore.swift       NEW  download/cancel/remove + ModelDownloader protocol + FluidAudioDownloader
  Sources/HUD/
    HUDContent.swift, HUDView.swift MOD listening(levels:badge:)
  Tests/…                          new/updated per task
SecureWispr/
  AppModel.swift                   MOD  settings, engines, mapper, flashes, minor d/e
  MenuContent.swift                MOD  mode/language line, toggle item, engine notice
  SettingsView.swift               MOD  real controls + Parakeet card
  SecureWisprApp.swift             MOD  pass model to SettingsView
```

---

### Task 1: Core language types, router, picker

**Files:**
- Create: `SecureWisprKit/Sources/Core/Language.swift`, `LanguageRouter.swift`, `LanguagePicker.swift`
- Modify: `SecureWisprKit/Sources/Core/Transcript.swift`, `SecureWisprKit/Sources/SpeechToText/AppleTranscriber.swift:36-40`, `SecureWisprKit/Sources/Dictation/DictationController.swift:99`, `SecureWisprKit/Tests/SpeechToTextTests/AppleTranscriberTests.swift`, `SecureWisprKit/Tests/DictationTests/DictationControllerTests.swift`
- Test: `SecureWisprKit/Tests/CoreTests/LanguageRouterTests.swift`, `SecureWisprKit/Tests/CoreTests/LanguagePickerTests.swift`

**Interfaces:**
- Consumes: M1 `Transcript`, `LanguageChoice.english` users.
- Produces (module `Core`, all public):
  - `enum Language: String, Sendable, CaseIterable, Codable { case english, swedish; var other: Language; var locale: Locale; var displayName: String; var flag: String; var badge: String }`
  - `enum LanguageChoice: Sendable, Equatable { case fixed(Language), automatic }`
  - `enum LanguageMode: String, Sendable, CaseIterable, Codable { case autoDetect, toggle, perLanguageHotkeys; var displayName: String }`
  - `enum SpeechEngine: String, Sendable, CaseIterable, Codable { case apple, parakeet; var displayName: String }`
  - `enum DictationCommand: Sendable, Equatable { case start(LanguageChoice), finish, cancel }`
  - `Transcript.init(text:locale:confidence:language:)` with `language: Language? = nil`
  - `enum LanguageRouter { static func choice(mode:shifted:primary:toggle:) -> LanguageChoice }`
  - `enum LanguagePicker { static let minimumMargin: Double = 0.15; static func pick(_ candidates: [Transcript], fallback: Language) -> Transcript }`

- [ ] **Step 1: Write the failing tests**

`Tests/CoreTests/LanguageRouterTests.swift`:
```swift
import Testing
@testable import Core

struct LanguageRouterTests {
    @Test(arguments: [false, true])
    func autoDetectIsAlwaysAutomatic(shifted: Bool) {
        #expect(LanguageRouter.choice(mode: .autoDetect, shifted: shifted, primary: .swedish, toggle: .english)
                == .automatic)
    }

    @Test(arguments: [false, true])
    func toggleUsesCurrentToggleLanguage(shifted: Bool) {
        #expect(LanguageRouter.choice(mode: .toggle, shifted: shifted, primary: .english, toggle: .swedish)
                == .fixed(.swedish))
    }

    @Test func perLanguageHotkeysFnIsPrimary() {
        #expect(LanguageRouter.choice(mode: .perLanguageHotkeys, shifted: false, primary: .swedish, toggle: .english)
                == .fixed(.swedish))
    }

    @Test func perLanguageHotkeysShiftIsTheOther() {
        #expect(LanguageRouter.choice(mode: .perLanguageHotkeys, shifted: true, primary: .swedish, toggle: .english)
                == .fixed(.english))
    }
}
```

`Tests/CoreTests/LanguagePickerTests.swift`:
```swift
import Foundation
import Testing
@testable import Core

struct LanguagePickerTests {
    private func t(_ text: String, _ language: Language, _ confidence: Double?) -> Transcript {
        Transcript(text: text, locale: language.locale, confidence: confidence, language: language)
    }

    @Test func clearWinnerIsChosen() {
        let picked = LanguagePicker.pick([t("hello", .english, 0.95), t("hallå", .swedish, 0.40)], fallback: .swedish)
        #expect(picked.language == .english)
    }

    @Test func withinMarginUsesFallback() {
        let picked = LanguagePicker.pick([t("hello", .english, 0.80), t("hallå", .swedish, 0.75)], fallback: .swedish)
        #expect(picked.language == .swedish)
    }

    @Test func emptyCandidateIsIgnored() {
        let picked = LanguagePicker.pick([t("", .english, 0.99), t("hej", .swedish, 0.30)], fallback: .english)
        #expect(picked.language == .swedish)
    }

    @Test func nilConfidenceRanksBelowAnyValue() {
        let picked = LanguagePicker.pick([t("hello", .english, nil), t("hej", .swedish, 0.30)], fallback: .english)
        #expect(picked.language == .swedish)
    }

    @Test func allEmptyReturnsAnEmptyTranscript() {
        let picked = LanguagePicker.pick([t("", .english, 0.9), t("", .swedish, 0.9)], fallback: .swedish)
        #expect(picked.text.isEmpty)
    }

    @Test func languageHelpers() {
        #expect(Language.english.other == .swedish)
        #expect(Language.swedish.locale.identifier == "sv_SE")
        #expect(Language.swedish.badge == "SV")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter "LanguageRouterTests|LanguagePickerTests"`
Expected: compile FAIL — `LanguageRouter`, `LanguagePicker`, `Language` not found.

- [ ] **Step 3: Implement the types**

`Sources/Core/Language.swift`:
```swift
import Foundation

public enum Language: String, Sendable, CaseIterable, Codable {
    case english
    case swedish

    public var other: Language { self == .english ? .swedish : .english }

    public var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .swedish: Locale(identifier: "sv_SE")
        }
    }

    public var displayName: String {
        switch self {
        case .english: "English"
        case .swedish: "Svenska"
        }
    }

    public var flag: String {
        switch self {
        case .english: "🇬🇧"
        case .swedish: "🇸🇪"
        }
    }

    /// Short label for the HUD.
    public var badge: String {
        switch self {
        case .english: "EN"
        case .swedish: "SV"
        }
    }
}

/// Which language(s) one dictation should be transcribed in.
public enum LanguageChoice: Sendable, Equatable {
    case fixed(Language)
    case automatic
}

public enum LanguageMode: String, Sendable, CaseIterable, Codable {
    case autoDetect
    case toggle
    case perLanguageHotkeys

    public var displayName: String {
        switch self {
        case .autoDetect: "Auto-detect"
        case .toggle: "Toggle"
        case .perLanguageHotkeys: "Per-language hotkeys"
        }
    }
}

public enum SpeechEngine: String, Sendable, CaseIterable, Codable {
    case apple
    case parakeet

    public var displayName: String {
        switch self {
        case .apple: "Apple SpeechAnalyzer"
        case .parakeet: "Parakeet"
        }
    }
}

/// What the dictation pipeline is asked to do. Produced from hotkey events by `CommandMapper`.
public enum DictationCommand: Sendable, Equatable {
    case start(LanguageChoice)
    case finish
    case cancel
}
```

Replace `Sources/Core/Transcript.swift` with:
```swift
import Foundation

public struct Transcript: Sendable, Equatable {
    public var text: String
    public var locale: Locale
    public var confidence: Double?
    public var language: Language?

    public init(text: String, locale: Locale, confidence: Double? = nil, language: Language? = nil) {
        self.text = text
        self.locale = locale
        self.confidence = confidence
        self.language = language
    }
}
```

`Sources/Core/LanguageRouter.swift`:
```swift
/// Decides which language a dictation uses, from the mode and whether ⇧ was held with fn.
public enum LanguageRouter {
    public static func choice(mode: LanguageMode, shifted: Bool,
                              primary: Language, toggle: Language) -> LanguageChoice {
        switch mode {
        case .autoDetect: .automatic
        case .toggle: .fixed(toggle)
        case .perLanguageHotkeys: .fixed(shifted ? primary.other : primary)
        }
    }
}
```

`Sources/Core/LanguagePicker.swift`:
```swift
/// Chooses the best transcript among per-language attempts of the same audio.
public enum LanguagePicker {
    public static let minimumMargin: Double = 0.15

    public static func pick(_ candidates: [Transcript], fallback: Language) -> Transcript {
        let spoken = candidates.filter { !$0.text.isEmpty }
        guard !spoken.isEmpty else {
            return candidates.first ?? Transcript(text: "", locale: fallback.locale, language: fallback)
        }
        let ranked = spoken.sorted { ($0.confidence ?? -1) > ($1.confidence ?? -1) }
        guard ranked.count > 1 else { return ranked[0] }
        let margin = (ranked[0].confidence ?? -1) - (ranked[1].confidence ?? -1)
        if margin >= minimumMargin { return ranked[0] }
        return ranked.first { $0.language == fallback } ?? ranked[0]
    }
}
```

- [ ] **Step 4: Migrate M1 `.english` users to `.fixed(.english)`**

In `Sources/SpeechToText/AppleTranscriber.swift` replace the `switch language { case .english: … }` body of `makeSession` with:
```swift
        switch language {
        case .fixed(.english), .automatic:
            return try await AppleTranscriptionSession.start(module: Self.makeModule(), locale: Self.english)
        case .fixed(.swedish):
            throw TranscriptionError.unsupportedLocale("sv_SE")
        }
```
(Task 4 replaces this with real Swedish support.)

In `Sources/Dictation/DictationController.swift` change `transcriber.makeSession(language: .english)` to `transcriber.makeSession(language: .fixed(.english))`.

In `Tests/SpeechToTextTests/AppleTranscriberTests.swift` replace both `makeSession(language: .english)` with `makeSession(language: .fixed(.english))`.

In `Tests/DictationTests/DictationControllerTests.swift` replace `#expect(transcriber.languages == [.english])` with `#expect(transcriber.languages == [.fixed(.english)])`.

- [ ] **Step 5: Run the whole suite**

Run: `cd SecureWisprKit && swift test 2>&1 | grep -E "error:|✘|Test run with"`
Expected: no `error:` or `✘`; LanguageRouterTests (6 cases) and LanguagePickerTests (6) pass alongside the 35 M1 tests.

- [ ] **Step 6: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(core): language types, router and confidence picker"
```

---

### Task 2: Hotkey — ⇧ awareness, taps, reset (minor c)

**Files:**
- Modify: `SecureWisprKit/Sources/Core/Protocols.swift` (HotkeyEvent), `SecureWisprKit/Sources/Hotkey/FnKeyStateMachine.swift`, `SecureWisprKit/Sources/Hotkey/FnHotkeyMonitor.swift`
- Modify (compile fix only): `SecureWisprKit/Sources/Dictation/DictationController.swift`, `SecureWisprKit/Tests/DictationTests/DictationControllerTests.swift`, `SecureWispr/AppModel.swift` — Task 3 replaces these properly
- Test: `SecureWisprKit/Tests/HotkeyTests/FnKeyStateMachineTests.swift` (rewrite)

**Interfaces:**
- Consumes: `HotkeyEvent` (Core).
- Produces:
  - `enum HotkeyEvent: Sendable, Equatable { case pressed(shifted: Bool), released, tapped(shifted: Bool), cancelled }`
  - `enum KeyInput: Equatable { case flagsChanged(fnDown: Bool, shift: Bool, time: TimeInterval); case keyDown(time: TimeInterval) }`
  - `FnKeyStateMachine.handle(_:) -> HotkeyEvent?`, `mutating func reset() -> Bool` (true if a hold was in progress)

- [ ] **Step 1: Rewrite the tests**

Replace `Tests/HotkeyTests/FnKeyStateMachineTests.swift` with:
```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter FnKeyStateMachineTests`
Expected: compile FAIL — `flagsChanged(fnDown:shift:time:)`, `.pressed(shifted:)`, `reset()` don't exist.

- [ ] **Step 3: Change `HotkeyEvent` in `Sources/Core/Protocols.swift`**

```swift
public enum HotkeyEvent: Sendable, Equatable {
    /// fn went down; `shifted` = ⇧ was held at that moment.
    case pressed(shifted: Bool)
    /// fn went up after the minimum hold, uninterrupted.
    case released
    /// fn went up before the minimum hold (accidental tap, or a deliberate quick tap).
    case tapped(shifted: Bool)
    /// Another key went down while fn was held (fn+arrow etc.).
    case cancelled
}
```

- [ ] **Step 4: Update the state machine**

Replace the body of `Sources/Hotkey/FnKeyStateMachine.swift` with:
```swift
import Core
import Foundation

public enum KeyInput: Equatable {
    case flagsChanged(fnDown: Bool, shift: Bool, time: TimeInterval)
    case keyDown(time: TimeInterval)
}

/// Turns raw fn / key events into push-to-talk events.
/// - fn down → `.pressed(shifted:)` (recording starts immediately).
/// - fn up after ≥ `minimumHold` → `.released`; sooner → `.tapped(shifted:)`.
/// - any key down while fn is held → `.cancelled` once; the later fn up is then silent.
///   ⇧ is a modifier (flagsChanged), so it never counts as "another key".
public struct FnKeyStateMachine {
    public var minimumHold: TimeInterval = 0.25
    private var pressedAt: TimeInterval?
    private var shifted = false
    private var interrupted = false

    public init() {}

    public mutating func handle(_ input: KeyInput) -> HotkeyEvent? {
        switch input {
        case .flagsChanged(fnDown: true, shift: let shift, time: let time):
            // fn went DOWN.
            guard pressedAt == nil else { return nil }
            pressedAt = time
            shifted = shift
            interrupted = false
            return .pressed(shifted: shift)

        case .keyDown:
            // Another key was pressed.
            guard pressedAt != nil, !interrupted else { return nil }
            interrupted = true
            return .cancelled

        case .flagsChanged(fnDown: false, shift: _, time: let time):
            // fn went UP.
            guard let start = pressedAt else { return nil }
            pressedAt = nil
            if interrupted { return nil }
            return time - start < minimumHold ? .tapped(shifted: shifted) : .released
        }
    }

    /// Forget any hold in progress (used when the event tap was disabled and events may
    /// have been missed). Returns true if a hold was in progress.
    public mutating func reset() -> Bool {
        defer {
            pressedAt = nil
            shifted = false
            interrupted = false
        }
        return pressedAt != nil && !interrupted
    }
}
```

- [ ] **Step 5: Update the monitor**

In `Sources/Hotkey/FnHotkeyMonitor.swift`:

Change `receive` to take a `shiftFlag` and reset on re-enable:
```swift
    fileprivate func receive(type: CGEventType, keyCode: Int64, fnFlag: Bool, shiftFlag: Bool, time: TimeInterval) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Events were lost while disabled; a missed fn-up would leave us stuck.
            if machine.reset() { continuation.yield(.cancelled) }
            Self.log.notice("event tap was disabled by the system; re-enabled and reset")
        case .flagsChanged:
            guard keyCode == Self.fnKeyCode else { return }
            feed(.flagsChanged(fnDown: fnFlag, shift: shiftFlag, time: time))
        case .keyDown:
            feed(.keyDown(time: time))
        default:
            break
        }
    }
```

In `fnTapCallback`, add the shift flag:
```swift
        let fnFlag = event.flags.contains(.maskSecondaryFn)
        let shiftFlag = event.flags.contains(.maskShift)
        let time = TimeInterval(event.timestamp) / 1_000_000_000
        MainActor.assumeIsolated {
            monitor.receive(type: type, keyCode: keyCode, fnFlag: fnFlag, shiftFlag: shiftFlag, time: time)
        }
```

- [ ] **Step 6: Keep the rest compiling (temporary shims, replaced in Task 3)**

In `Sources/Dictation/DictationController.swift` `handle(_:)`, change the case patterns:
```swift
        case .pressed:
```
stays (matches any payload);
```swift
        case .cancelled, .tapped:
```
replaces `case .cancelled:`.

In `Tests/DictationTests/DictationControllerTests.swift`, replace every `controller.handle(.pressed)` with `controller.handle(.pressed(shifted: false))`.

In `SecureWispr/AppModel.swift` nothing changes (it forwards `event` untouched).

- [ ] **Step 7: Run tests**

Run: `cd SecureWisprKit && swift test 2>&1 | grep -E "error:|✘|Test run with"`
Expected: FnKeyStateMachineTests 10/10 pass; no `✘` anywhere.

- [ ] **Step 8: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(hotkey): shift-aware fn events, quick taps, reset after tap re-enable"
```

---

### Task 3: Commands, mapper, provider, release tail (minors b, d)

**Files:**
- Create: `SecureWisprKit/Sources/Dictation/CommandMapper.swift`
- Modify: `SecureWisprKit/Sources/Dictation/DictationController.swift` (full replacement below), `SecureWispr/AppModel.swift` (compile fix: build with provider + mapper)
- Test: `SecureWisprKit/Tests/DictationTests/CommandMapperTests.swift`, `SecureWisprKit/Tests/DictationTests/DictationControllerTests.swift` (full replacement below), `SecureWisprKit/Tests/DictationTests/Fakes.swift` (FakeTranscriber transcript language)

**Interfaces:**
- Consumes: `DictationCommand`, `LanguageChoice`, `LanguageRouter`, `LanguageMode`, `Language`, `HotkeyEvent` (Core).
- Produces:
  - `struct HotkeyContext: Sendable, Equatable { mode: LanguageMode; primary: Language; toggle: Language; canStart: Bool; init(mode:primary:toggle:canStart:) }`
  - `struct MappedHotkey: Equatable { command: DictationCommand?; newToggleLanguage: Language? }`
  - `enum CommandMapper { static func map(_ event: HotkeyEvent, context: HotkeyContext) -> MappedHotkey }`
  - `DictationController.init(audio:transcriber:cleaner:injector:contextProvider:maxDuration:noticeDuration:releaseTail:)` where `transcriber: @escaping @MainActor () -> any Transcriber`
  - `DictationController.handle(_ command: DictationCommand)`
  - `DictationController.currentChoice: LanguageChoice?` (choice of the running/last dictation)
  - `DictationController.onLanguageDetected: (@MainActor (Language) -> Void)?` — called after a successful `.automatic` dictation, after state returns to `.idle`

- [ ] **Step 1: Write the mapper tests**

`Tests/DictationTests/CommandMapperTests.swift`:
```swift
import Core
import Testing
@testable import Dictation

struct CommandMapperTests {
    private func ctx(_ mode: LanguageMode, canStart: Bool = true) -> HotkeyContext {
        HotkeyContext(mode: mode, primary: .english, toggle: .swedish, canStart: canStart)
    }

    @Test func pressStartsWithRoutedLanguage() {
        #expect(CommandMapper.map(.pressed(shifted: true), context: ctx(.perLanguageHotkeys))
                == MappedHotkey(command: .start(.fixed(.swedish)), newToggleLanguage: nil))
    }

    @Test func pressIsDroppedWhenCannotStart() {
        #expect(CommandMapper.map(.pressed(shifted: false), context: ctx(.autoDetect, canStart: false))
                == MappedHotkey(command: nil, newToggleLanguage: nil))
    }

    @Test func releaseAndCancelPassEvenWithoutPermissions() {
        #expect(CommandMapper.map(.released, context: ctx(.autoDetect, canStart: false)).command == .finish)
        #expect(CommandMapper.map(.cancelled, context: ctx(.autoDetect, canStart: false)).command == .cancel)
        #expect(CommandMapper.map(.tapped(shifted: false), context: ctx(.autoDetect, canStart: false)).command == .cancel)
    }

    @Test func shiftTapFlipsToggleLanguageInToggleMode() {
        #expect(CommandMapper.map(.tapped(shifted: true), context: ctx(.toggle))
                == MappedHotkey(command: .cancel, newToggleLanguage: .english))
    }

    @Test func shiftTapDoesNothingSpecialInOtherModes() {
        #expect(CommandMapper.map(.tapped(shifted: true), context: ctx(.autoDetect)).newToggleLanguage == nil)
        #expect(CommandMapper.map(.tapped(shifted: true), context: ctx(.perLanguageHotkeys)).newToggleLanguage == nil)
    }

    @Test func plainTapNeverFlips() {
        #expect(CommandMapper.map(.tapped(shifted: false), context: ctx(.toggle)).newToggleLanguage == nil)
    }
}
```

- [ ] **Step 2: Update fakes**

In `Tests/DictationTests/Fakes.swift`, add a mutable box (closures in Swift 6 tests mutate it instead of capturing a `var`):
```swift
@MainActor
final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}
```
Then change `FakeSession` so its transcript carries a language, and add `language`:
```swift
@MainActor
final class FakeSession: TranscriptionSession {
    var result: Result<String, FakeError> = .success("hello world")
    var language: Language? = .english
    var finishDelay: Duration = .zero
    private(set) var appended: [[Float]] = []
    private(set) var cancelled = false

    func append(_ chunk: AudioChunk) { appended.append(chunk.samples) }

    func finish() async throws -> Transcript {
        if finishDelay > .zero { try await Task.sleep(for: finishDelay) }
        return Transcript(text: try result.get(), locale: Locale(identifier: "en_US"), language: language)
    }

    func cancel() { cancelled = true }
}
```

- [ ] **Step 3: Replace the controller tests**

Replace `Tests/DictationTests/DictationControllerTests.swift` with:
```swift
import Core
import Testing
@testable import Dictation

@MainActor
struct DictationControllerTests {
    let audio = FakeAudio()
    let transcriber = FakeTranscriber()
    let cleaner = FakeCleaner()
    let injector = FakeInjector()

    func makeController(maxDuration: Duration = .seconds(300), releaseTail: Duration = .zero,
                        provider: (@MainActor () -> any Transcriber)? = nil) -> DictationController {
        let transcriber = transcriber
        return DictationController(
            audio: audio, transcriber: provider ?? { transcriber }, cleaner: cleaner, injector: injector,
            contextProvider: { DictationContext(appBundleID: "com.apple.TextEdit") },
            maxDuration: maxDuration, noticeDuration: .seconds(60), releaseTail: releaseTail
        )
    }

    let en = DictationCommand.start(.fixed(.english))

    @Test func happyPathTranscribesCleansAndInjects() async {
        let controller = makeController()
        let recorder = StateRecorder()
        controller.onChange = { state, _ in recorder.record(state) }

        controller.handle(en)
        #expect(controller.state == .listening)
        audio.emit([0.1, 0.2])
        audio.emit([0.3])
        controller.handle(.finish)
        await controller.currentTask?.value

        #expect(transcriber.session.appended == [[0.1, 0.2], [0.3]])
        #expect(transcriber.languages == [.fixed(.english)])
        #expect(cleaner.contexts == [DictationContext(appBundleID: "com.apple.TextEdit")])
        #expect(injector.injected == ["cleaned: hello world"])
        #expect(recorder.states == [.listening, .transcribing, .cleaning, .injecting, .idle])
        #expect(controller.lastLatency != nil)
    }

    @Test func startPassesLanguageChoiceToTranscriber() async {
        let controller = makeController()
        controller.handle(.start(.automatic))
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(transcriber.languages == [.automatic])
        #expect(controller.currentChoice == .automatic)
    }

    @Test func automaticDictationReportsDetectedLanguageAfterIdle() async {
        transcriber.session.language = .swedish
        let controller = makeController()
        let detected = Box<[Language]>([])
        let stateAtCallback = Box<DictationController.State?>(nil)
        controller.onLanguageDetected = { [unowned controller] language in
            detected.value.append(language)
            stateAtCallback.value = controller.state
        }
        controller.handle(.start(.automatic))
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(detected.value == [.swedish])
        #expect(stateAtCallback.value == .idle)
    }

    @Test func fixedDictationDoesNotReportDetectedLanguage() async {
        let controller = makeController()
        let called = Box(false)
        controller.onLanguageDetected = { _ in called.value = true }
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(!called.value)
    }

    @Test func transcriberIsChosenAtStartNotAtFinish() async {
        let other = FakeTranscriber()
        let useOther = Box(false)
        let first = transcriber
        let controller = makeController(provider: { useOther.value ? other : first })
        controller.handle(en)
        useOther.value = true                // user switches engine mid-hold
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(first.languages.count == 1)
        #expect(other.languages.isEmpty)
        #expect(injector.injected == ["cleaned: hello world"])
    }

    @Test func releaseTailKeepsCapturingBriefly() async throws {
        let controller = makeController(releaseTail: .milliseconds(150))
        controller.handle(en)
        audio.emit([0.1])
        controller.handle(.finish)
        try await Task.sleep(for: .milliseconds(30))
        audio.emit([0.9])                    // the last syllable, after fn-up
        await controller.currentTask?.value
        #expect(transcriber.session.appended == [[0.1], [0.9]])
    }

    @Test func levelsAreTrackedForTheWaveform() async {
        let controller = makeController()
        controller.handle(en)
        audio.emitLevel(0.5)
        audio.emitLevel(0.7)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controller.levels == [0.5, 0.7])
        controller.handle(.finish)
        await controller.currentTask?.value
    }

    @Test func cancelDiscardsAudioAndInjectsNothing() async {
        let controller = makeController()
        controller.handle(en)
        audio.emit([0.1])
        controller.handle(.cancel)
        await controller.currentTask?.value
        #expect(controller.state == .idle)
        #expect(injector.injected.isEmpty)
        #expect(transcriber.session.cancelled)
    }

    @Test func emptyTranscriptFailsWithNoSpeech() async {
        transcriber.session.result = .success("")
        let controller = makeController()
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(controller.state == .failed(.noSpeech))
        #expect(injector.injected.isEmpty)
    }

    @Test func transcriberErrorFails() async {
        transcriber.session.result = .failure(FakeError())
        let controller = makeController()
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        guard case .failed(.transcription) = controller.state else {
            Issue.record("expected transcription failure, got \(controller.state)")
            return
        }
    }

    @Test func secureInputFailsWithSecureInput() async {
        injector.error = .secureInputActive
        let controller = makeController()
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(controller.state == .failed(.secureInput))
    }

    @Test func microphoneFailureFailsImmediately() {
        audio.failOnStart = true
        let controller = makeController()
        controller.handle(en)
        guard case .failed(.audio) = controller.state else {
            Issue.record("expected audio failure, got \(controller.state)")
            return
        }
    }

    @Test func startWhileBusyIsIgnored() async {
        transcriber.session.finishDelay = .milliseconds(100)
        let controller = makeController()
        controller.handle(en)
        controller.handle(.finish)
        controller.handle(en)
        await controller.currentTask?.value
        #expect(audio.startCount == 1)
        #expect(injector.injected.count == 1)
        #expect(controller.state == .idle)
    }

    @Test func canStartAgainAfterFailure() async {
        transcriber.session.result = .success("")
        let controller = makeController()
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(controller.state == .failed(.noSpeech))
        controller.handle(en)
        #expect(controller.state == .listening)
        #expect(audio.startCount == 2)
    }

    @Test func audioBeforeSessionReadyIsStillTranscribed() async {
        transcriber.makeDelay = .milliseconds(80)
        let controller = makeController()
        controller.handle(en)
        audio.emit([0.1])
        audio.emit([0.2])
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(transcriber.session.appended == [[0.1], [0.2]])
        #expect(injector.injected == ["cleaned: hello world"])
    }

    @Test func showsPreparingModelWhenTranscriberIsNotReady() async {
        transcriber.isReady = false
        let controller = makeController()
        let recorder = StateRecorder()
        controller.onChange = { state, _ in recorder.record(state) }
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(recorder.states.contains(.preparingModel))
    }

    @Test func maxDurationAutoFinishes() async throws {
        let controller = makeController(maxDuration: .milliseconds(50))
        controller.handle(en)
        audio.emit([0.4])
        try await Task.sleep(for: .milliseconds(150))
        await controller.currentTask?.value
        #expect(injector.injected == ["cleaned: hello world"])
        #expect(controller.state == .idle)
    }

    @Test func finishOrCancelWhenIdleIsIgnored() {
        let controller = makeController()
        controller.handle(.finish)
        controller.handle(.cancel)
        #expect(controller.state == .idle)
        #expect(audio.startCount == 0)
    }

    @Test func strayCancelAndStartRightAfterFinishCannotStartSecondRecording() async {
        transcriber.makeDelay = .milliseconds(80)
        let controller = makeController()
        controller.handle(en)
        audio.emit([0.1])
        controller.handle(.finish)
        controller.handle(.cancel)
        controller.handle(en)
        await controller.currentTask?.value
        #expect(audio.startCount == 1)
        #expect(injector.injected == ["cleaned: hello world"])
        #expect(controller.state == .idle)
    }

    @Test func captureEndingUnexpectedlyFinishesDictation() async throws {
        let controller = makeController()
        controller.handle(en)
        audio.emit([0.3])
        audio.stop()
        try await Task.sleep(for: .milliseconds(50))
        await controller.currentTask?.value
        #expect(injector.injected == ["cleaned: hello world"])
        #expect(controller.state == .idle)
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter "CommandMapperTests|DictationControllerTests"`
Expected: compile FAIL — `HotkeyContext`, `CommandMapper`, `handle(DictationCommand)`, `releaseTail`, `onLanguageDetected` not found.

- [ ] **Step 5: Implement the mapper**

`Sources/Dictation/CommandMapper.swift`:
```swift
import Core

/// Settings + permission state needed to interpret a hotkey event.
public struct HotkeyContext: Sendable, Equatable {
    public var mode: LanguageMode
    public var primary: Language
    public var toggle: Language
    /// False while a required permission is missing. Only blocks *starting* (minor d).
    public var canStart: Bool

    public init(mode: LanguageMode, primary: Language, toggle: Language, canStart: Bool) {
        self.mode = mode
        self.primary = primary
        self.toggle = toggle
        self.canStart = canStart
    }
}

public struct MappedHotkey: Equatable {
    public var command: DictationCommand?
    /// Set when a quick fn+⇧ tap in Toggle mode flips the language.
    public var newToggleLanguage: Language?

    public init(command: DictationCommand?, newToggleLanguage: Language?) {
        self.command = command
        self.newToggleLanguage = newToggleLanguage
    }
}

public enum CommandMapper {
    public static func map(_ event: HotkeyEvent, context: HotkeyContext) -> MappedHotkey {
        switch event {
        case .pressed(let shifted):
            guard context.canStart else { return MappedHotkey(command: nil, newToggleLanguage: nil) }
            let choice = LanguageRouter.choice(mode: context.mode, shifted: shifted,
                                               primary: context.primary, toggle: context.toggle)
            return MappedHotkey(command: .start(choice), newToggleLanguage: nil)
        case .released:
            return MappedHotkey(command: .finish, newToggleLanguage: nil)
        case .cancelled:
            return MappedHotkey(command: .cancel, newToggleLanguage: nil)
        case .tapped(let shifted):
            let flip = shifted && context.mode == .toggle ? context.toggle.other : nil
            return MappedHotkey(command: .cancel, newToggleLanguage: flip)
        }
    }
}
```

- [ ] **Step 6: Replace the controller**

Replace `Sources/Dictation/DictationController.swift` with:
```swift
import Core
import Foundation

/// Runs one dictation at a time: start → audio → transcription → cleanup → injection.
/// Only this type mutates pipeline state; UI observes it through `onChange`.
@MainActor
public final class DictationController {
    public enum State: Equatable, Sendable {
        case idle
        case listening
        case preparingModel
        case transcribing
        case cleaning
        case injecting
        case failed(DictationFailure)
    }

    public static let levelHistory = 24
    private static let log = Log.logger("Dictation")

    public private(set) var state: State = .idle { didSet { notify() } }
    public private(set) var levels: [Float] = [] { didSet { notify() } }
    public private(set) var lastLatency: Duration?
    public private(set) var currentTask: Task<Void, Never>?
    public private(set) var currentChoice: LanguageChoice?
    public var onChange: (@MainActor (State, [Float]) -> Void)?
    public var onLanguageDetected: (@MainActor (Language) -> Void)?

    private let audio: any AudioSource
    private let transcriberProvider: @MainActor () -> any Transcriber
    private let cleaner: any TextCleaner
    private let injector: any TextInjector
    private let contextProvider: @MainActor () -> DictationContext
    private let maxDuration: Duration
    private let noticeDuration: Duration
    private let releaseTail: Duration

    private var activeTranscriber: (any Transcriber)?
    private var context = DictationContext()
    private var sessionTask: Task<any TranscriptionSession, Error>?
    private var levelTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?

    public init(
        audio: any AudioSource,
        transcriber: @escaping @MainActor () -> any Transcriber,
        cleaner: any TextCleaner,
        injector: any TextInjector,
        contextProvider: @escaping @MainActor () -> DictationContext = { DictationContext() },
        maxDuration: Duration = .seconds(300),
        noticeDuration: Duration = .milliseconds(1_500),
        releaseTail: Duration = .milliseconds(150)
    ) {
        self.audio = audio
        self.transcriberProvider = transcriber
        self.cleaner = cleaner
        self.injector = injector
        self.contextProvider = contextProvider
        self.maxDuration = maxDuration
        self.noticeDuration = noticeDuration
        self.releaseTail = releaseTail
    }

    public func handle(_ command: DictationCommand) {
        switch command {
        case .start(let choice):
            guard canStart else { return }
            startListening(choice)
        case .finish:
            guard state == .listening else { return }
            // Leave .listening synchronously so a stray cancel/start arriving while
            // the pipeline runs can't cancel or restart it.
            state = (activeTranscriber?.isReady ?? true) ? .transcribing : .preparingModel
            currentTask = Task { await finishDictation() }
        case .cancel:
            guard state == .listening else { return }
            cancelListening()
        }
    }

    private var canStart: Bool {
        switch state {
        case .idle, .failed: true
        default: false
        }
    }

    private func startListening(_ choice: LanguageChoice) {
        resetTask?.cancel()
        context = contextProvider()
        let capture: AudioCapture
        do {
            capture = try audio.start()
        } catch {
            fail(.audio(String(describing: error)))
            return
        }
        currentChoice = choice
        // Chosen once per dictation: changing engine in Settings mid-hold affects the next one.
        let transcriber = transcriberProvider()
        activeTranscriber = transcriber
        state = .listening

        // The chunk stream buffers while the session is being created, so audio
        // captured before the transcriber is ready is still delivered, in order.
        sessionTask = Task { [weak self] in
            let session = try await transcriber.makeSession(language: choice)
            for await chunk in capture.chunks { session.append(chunk) }
            // Stream ended while still listening: the recorder stopped on its own
            // (e.g. audio device change). Transcribe what we have.
            if self?.state == .listening {
                Self.log.notice("audio capture ended unexpectedly; finishing dictation")
                self?.handle(.finish)
            }
            return session
        }
        levelTask = Task { [weak self] in
            for await level in capture.levels { self?.pushLevel(level) }
        }
        timeoutTask = Task { [weak self, maxDuration] in
            try? await Task.sleep(for: maxDuration)
            guard !Task.isCancelled else { return }
            Self.log.notice("max dictation length reached; auto-finishing")
            self?.handle(.finish)
        }
    }

    private func finishDictation() async {
        let releasedAt = ContinuousClock.now
        timeoutTask?.cancel()
        // Keep recording briefly: people release fn on the last syllable (minor b).
        if releaseTail > .zero { try? await Task.sleep(for: releaseTail) }
        stopCapture()
        guard let sessionTask else { return }
        self.sessionTask = nil

        let transcript: Transcript
        do {
            let session = try await sessionTask.value
            state = .transcribing
            transcript = try await session.finish()
        } catch {
            fail(.transcription(String(describing: error)))
            return
        }
        guard !transcript.text.isEmpty else {
            fail(.noSpeech)
            return
        }
        Self.log.debug("transcript: \(transcript.text, privacy: .private)")

        do {
            state = .cleaning
            let cleaned = try await cleaner.clean(transcript.text, context: context)
            state = .injecting
            try await injector.inject(cleaned)
        } catch InjectionError.secureInputActive {
            fail(.secureInput)
            return
        } catch {
            fail(.injection(String(describing: error)))
            return
        }
        let latency = ContinuousClock.now - releasedAt
        lastLatency = latency
        Self.log.info("release→inject \(latency.formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        state = .idle
        if currentChoice == .automatic, let language = transcript.language {
            onLanguageDetected?(language)
        }
    }

    private func cancelListening() {
        stopCapture()
        let pending = sessionTask
        sessionTask = nil
        pending?.cancel()
        state = .idle
        currentTask = Task {
            if let session = try? await pending?.value { session.cancel() }
        }
    }

    private func stopCapture() {
        timeoutTask?.cancel()
        timeoutTask = nil
        audio.stop()
        levelTask?.cancel()
        levelTask = nil
        levels = []
    }

    private func pushLevel(_ level: Float) {
        var next = levels
        next.append(level)
        if next.count > Self.levelHistory { next.removeFirst(next.count - Self.levelHistory) }
        levels = next
    }

    private func fail(_ failure: DictationFailure) {
        Self.log.error("dictation failed: \(String(describing: failure), privacy: .public)")
        state = .failed(failure)
        resetTask = Task { [weak self, noticeDuration] in
            try? await Task.sleep(for: noticeDuration)
            guard !Task.isCancelled, let self, case .failed = self.state else { return }
            self.state = .idle
        }
    }

    private func notify() {
        onChange?(state, levels)
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter "CommandMapperTests|DictationControllerTests"`
Expected: CommandMapperTests 6/6, DictationControllerTests 21/21 PASS.

- [ ] **Step 8: Keep the app compiling**

In `SecureWispr/AppModel.swift`:
- change the controller construction's `transcriber: transcriber,` to `transcriber: { [transcriber] in transcriber },`
- replace the hotkey loop body
```swift
                guard missingPermissions.isEmpty else { continue }
                controller.handle(event)
```
with
```swift
                let mapped = CommandMapper.map(event, context: HotkeyContext(
                    mode: .autoDetect, primary: .english, toggle: .english,
                    canStart: missingPermissions.isEmpty))
                if let command = mapped.command { controller.handle(command) }
```
(Task 9 replaces the hard-coded context with settings.)

Run: `xcodebuild -project SecureWispr.xcodeproj -scheme SecureWispr -configuration Debug -derivedDataPath build -allowProvisioningUpdates build 2>&1 | grep -E "error:|\*\* BUILD"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add SecureWisprKit SecureWispr/AppModel.swift
git commit -m "feat(dictation): command-driven controller, hotkey mapper, release tail"
```

---

### Task 4: Apple Swedish + confidence + session cleanup (minor a)

**Files:**
- Create: `SecureWisprKit/Sources/SpeechToText/AppleModule.swift`
- Modify: `SecureWisprKit/Sources/SpeechToText/AppleSpeechAssets.swift`, `AppleTranscriptionSession.swift`, `AppleTranscriber.swift` (full replacements below)
- Test: `SecureWisprKit/Tests/SpeechToTextTests/AppleTranscriberTests.swift` (add Swedish tests), `SecureWisprKit/Tests/InjectionTests/PasteboardInjectorTests.swift` (add å ä ö test)

**Interfaces:**
- Consumes: `Language`, `LanguageChoice`, `Transcript(text:locale:confidence:language:)`, `TranscriptionError`, `PCMConverter`.
- Produces:
  - `struct AppleModule { let language: Language; let module: any SpeechModule; let collect: @Sendable () async throws -> [AttributedString]; static func make(_ language: Language) -> AppleModule }`
  - `AppleTranscriptionSession.start(language: Language) async throws -> AppleTranscriptionSession` (internal)
  - `AppleTranscriber.init(fallbackLanguage: @escaping @MainActor () -> Language = { .english })` (fallback is used in Task 5)

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SpeechToTextTests/AppleTranscriberTests.swift` inside the struct (and change `spokenSamples` to take a voice):

Replace the helper signature and `say` arguments:
```swift
    private func spokenSamples(_ text: String, voice: String = "Samantha") throws -> [Float] {
```
```swift
        say.arguments = ["-v", voice, "-o", url.path, text]
```

Add a feeding helper and tests:
```swift
    private func transcribe(_ samples: [Float], _ choice: LanguageChoice,
                            transcriber: AppleTranscriber = AppleTranscriber()) async throws -> Transcript {
        let session = try await transcriber.makeSession(language: choice)
        for start in stride(from: 0, to: samples.count, by: 1_600) {
            session.append(AudioChunk(samples: Array(samples[start..<min(start + 1_600, samples.count)])))
        }
        return try await session.finish()
    }

    @Test(.timeLimit(.minutes(2)))
    func transcribesSpokenSwedish() async throws {
        let samples = try spokenSamples("Kan du skicka rapporten till mig innan lunch imorgon", voice: "Alva")
        let transcript = try await transcribe(samples, .fixed(.swedish))
        #expect(transcript.text.lowercased().contains("rapporten"))
        #expect(transcript.language == .swedish)
        #expect(transcript.locale.identifier == "sv_SE")
        #expect((transcript.confidence ?? 0) > 0.5)
    }

    @Test(.timeLimit(.minutes(2)))
    func englishTranscriptCarriesConfidenceAndLanguage() async throws {
        let samples = try spokenSamples("Can you send me the quarterly report before lunch tomorrow")
        let transcript = try await transcribe(samples, .fixed(.english))
        #expect(transcript.language == .english)
        #expect((transcript.confidence ?? 0) > 0.5)
    }

    @Test func transcriberIsReadyOnlyAfterBothLanguagesPrepared() async throws {
        let transcriber = AppleTranscriber()
        #expect(!transcriber.isReady)
        try await transcriber.prepare()
        #expect(transcriber.isReady)
    }
```

Append to `Tests/InjectionTests/PasteboardInjectorTests.swift` inside `PasteboardInjectorTests`:
```swift
    @Test func pastesSwedishCharactersExactly() async throws {
        pasteboard.clearContents()
        let sender = RecordingKeySender(pasteboard: pasteboard)
        let text = "Hej! Kan du skicka rapporten – på fredag? Åsa, Ärla & Örjan."
        try await injector(sender).inject(text)
        #expect(sender.seenAtPaste == [text])
    }
```

- [ ] **Step 2: Run tests to verify the Swedish ones fail**

Run: `cd SecureWisprKit && swift test --filter "AppleTranscriberTests|pastesSwedishCharactersExactly"`
Expected: `transcribesSpokenSwedish` FAILS (throws `unsupportedLocale("sv_SE")` from the Task 1 shim); `englishTranscriptCarriesConfidenceAndLanguage` FAILS (`language` is nil); `pastesSwedishCharactersExactly` PASSES (pins existing behavior).

- [ ] **Step 3: Implement AppleModule**

`Sources/SpeechToText/AppleModule.swift`:
```swift
import Core
import Foundation
import Speech

/// One configured Apple speech module plus a way to collect its final results.
/// English uses SpeechTranscriber; Swedish uses DictationTranscriber (SpeechTranscriber has no sv_SE).
struct AppleModule {
    let language: Language
    let module: any SpeechModule
    let collect: @Sendable () async throws -> [AttributedString]

    static func make(_ language: Language) -> AppleModule {
        switch language {
        case .english:
            let module = SpeechTranscriber(
                locale: language.locale, transcriptionOptions: [], reportingOptions: [],
                attributeOptions: [.transcriptionConfidence]
            )
            let results = module.results
            return AppleModule(language: language, module: module) {
                var texts: [AttributedString] = []
                for try await result in results { texts.append(result.text) }
                return texts
            }
        case .swedish:
            let module = DictationTranscriber(
                locale: language.locale, contentHints: [.shortForm], transcriptionOptions: [.punctuation],
                reportingOptions: [], attributeOptions: [.transcriptionConfidence]
            )
            let results = module.results
            return AppleModule(language: language, module: module) {
                var texts: [AttributedString] = []
                for try await result in results { texts.append(result.text) }
                return texts
            }
        }
    }

    /// Joined text and mean per-run confidence (nil if the model reported none).
    static func summarize(_ texts: [AttributedString]) -> (text: String, confidence: Double?) {
        let text = texts.map { String($0.characters) }
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        var confidences: [Double] = []
        for attributed in texts {
            for run in attributed.runs {
                if let confidence = run.transcriptionConfidence { confidences.append(confidence) }
            }
        }
        let mean = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
        return (text, mean)
    }
}
```

- [ ] **Step 4: Generalize assets and session (with minor a)**

Replace `Sources/SpeechToText/AppleSpeechAssets.swift`:
```swift
import Core
import Speech

enum AppleSpeechAssets {
    private static let log = Log.logger("SpeechToText")

    /// Ensures the on-device model for `module` is installed, downloading it if needed.
    static func ensureInstalled(_ module: any SpeechModule, locale: Locale) async throws {
        switch await AssetInventory.status(forModules: [module]) {
        case .installed:
            return
        case .unsupported:
            throw TranscriptionError.unsupportedLocale(locale.identifier)
        case .supported, .downloading:
            log.info("installing speech assets for \(locale.identifier, privacy: .public)")
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
        @unknown default:
            return
        }
    }
}
```

Replace `Sources/SpeechToText/AppleTranscriptionSession.swift`:
```swift
import AVFoundation
import Core
import Speech

/// One push-to-talk utterance streamed into a SpeechAnalyzer for one language.
@MainActor
final class AppleTranscriptionSession: TranscriptionSession {
    private let language: Language
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let converter: PCMConverter
    private let collector: Task<[AttributedString], Error>

    private init(language: Language, analyzer: SpeechAnalyzer,
                 input: AsyncStream<AnalyzerInput>.Continuation,
                 converter: PCMConverter, collector: Task<[AttributedString], Error>) {
        self.language = language
        self.analyzer = analyzer
        self.input = input
        self.converter = converter
        self.collector = collector
    }

    static func start(language: Language) async throws -> AppleTranscriptionSession {
        let apple = AppleModule.make(language)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [apple.module]) else {
            throw TranscriptionError.noCompatibleAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [apple.module])
        try await analyzer.prepareToAnalyze(in: format)

        let collector = Task<[AttributedString], Error> { try await apple.collect() }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        do {
            try await analyzer.start(inputSequence: stream)
            return AppleTranscriptionSession(
                language: language, analyzer: analyzer, input: continuation,
                converter: try PCMConverter(from: .speech16kMono, to: format), collector: collector
            )
        } catch {
            // Don't leak the collector or the analyzer (minor a).
            continuation.finish()
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    func append(_ chunk: AudioChunk) {
        guard let buffer = AVAudioPCMBuffer.speech(samples: chunk.samples),
              let converted = try? converter.convert(buffer) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    func finish() async throws -> Transcript {
        input.finish()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            cancel()   // minor a
            throw error
        }
        let summary = AppleModule.summarize(try await collector.value)
        return Transcript(text: summary.text, locale: language.locale,
                          confidence: summary.confidence, language: language)
    }

    func cancel() {
        input.finish()
        collector.cancel()
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}
```

- [ ] **Step 5: Replace the transcriber**

Replace `Sources/SpeechToText/AppleTranscriber.swift`:
```swift
import Core
import Speech

/// Apple's on-device SpeechAnalyzer: English (SpeechTranscriber), Swedish (DictationTranscriber),
/// or both in parallel for automatic detection.
@MainActor
public final class AppleTranscriber: Transcriber {
    private static let log = Log.logger("SpeechToText")

    public private(set) var isReady = false
    private var preparation: Task<Void, Error>?
    let fallbackLanguage: @MainActor () -> Language

    public init(fallbackLanguage: @escaping @MainActor () -> Language = { .english }) {
        self.fallbackLanguage = fallbackLanguage
    }

    /// Installs assets for both languages.
    public func prepare() async throws {
        if isReady { return }
        if let preparation { return try await preparation.value }
        let task = Task<Void, Error> {
            for language in Language.allCases {
                try await AppleSpeechAssets.ensureInstalled(AppleModule.make(language).module,
                                                            locale: language.locale)
            }
        }
        preparation = task
        do {
            try await task.value
            isReady = true
        } catch {
            preparation = nil
            Self.log.error("speech preparation failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        try await prepare()
        switch language {
        case .fixed(let fixed):
            return try await AppleTranscriptionSession.start(language: fixed)
        case .automatic:
            // Task 5 replaces this with AutoDetectSession.
            return try await AppleTranscriptionSession.start(language: fallbackLanguage())
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter "AppleTranscriberTests|PasteboardInjectorTests"`
Expected: AppleTranscriberTests 5/5 PASS (incl. Swedish and confidence), PasteboardInjectorTests 6/6 PASS.

- [ ] **Step 7: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(stt): Swedish via DictationTranscriber, confidence, cleanup on session errors"
```

---

### Task 5: Auto-detect session

**Files:**
- Create: `SecureWisprKit/Sources/SpeechToText/AutoDetectSession.swift`
- Modify: `SecureWisprKit/Sources/SpeechToText/AppleTranscriber.swift` (`.automatic` branch)
- Test: `SecureWisprKit/Tests/SpeechToTextTests/AutoDetectSessionTests.swift`, `SecureWisprKit/Tests/SpeechToTextTests/AppleTranscriberTests.swift` (auto-detect integration)

**Interfaces:**
- Consumes: `LanguagePicker.pick`, `TranscriptionSession`, `AppleTranscriptionSession.start(language:)`, `AppleTranscriber.fallbackLanguage`.
- Produces: `@MainActor final class AutoDetectSession: TranscriptionSession { init(sessions: [any TranscriptionSession], fallback: Language) }` (internal)

- [ ] **Step 1: Write the failing tests**

`Tests/SpeechToTextTests/AutoDetectSessionTests.swift`:
```swift
import Core
import Foundation
import Testing
@testable import SpeechToText

struct StubError: Error {}

@MainActor
final class StubSession: TranscriptionSession {
    let outcome: Result<Transcript, StubError>
    private(set) var appended: [[Float]] = []
    private(set) var cancelled = false
    init(_ outcome: Result<Transcript, StubError>) { self.outcome = outcome }
    func append(_ chunk: AudioChunk) { appended.append(chunk.samples) }
    func finish() async throws -> Transcript { try outcome.get() }
    func cancel() { cancelled = true }
}

@MainActor
struct AutoDetectSessionTests {
    private func t(_ text: String, _ language: Language, _ confidence: Double) -> Transcript {
        Transcript(text: text, locale: language.locale, confidence: confidence, language: language)
    }

    @Test func fansOutAudioToEverySession() {
        let a = StubSession(.success(t("a", .english, 0.9)))
        let b = StubSession(.success(t("b", .swedish, 0.1)))
        let session = AutoDetectSession(sessions: [a, b], fallback: .english)
        session.append(AudioChunk(samples: [0.5]))
        #expect(a.appended == [[0.5]])
        #expect(b.appended == [[0.5]])
    }

    @Test func picksTheMoreConfidentLanguage() async throws {
        let session = AutoDetectSession(sessions: [
            StubSession(.success(t("can do we get up", .english, 0.40))),
            StubSession(.success(t("kan du skicka", .swedish, 0.78))),
        ], fallback: .english)
        #expect(try await session.finish().language == .swedish)
    }

    @Test func oneFailingBranchUsesTheOther() async throws {
        let session = AutoDetectSession(sessions: [
            StubSession(.failure(StubError())),
            StubSession(.success(t("kan du skicka", .swedish, 0.30))),
        ], fallback: .english)
        #expect(try await session.finish().language == .swedish)
    }

    @Test func allBranchesFailingThrows() async {
        let session = AutoDetectSession(sessions: [
            StubSession(.failure(StubError())), StubSession(.failure(StubError())),
        ], fallback: .english)
        await #expect(throws: StubError.self) { try await session.finish() }
    }

    @Test func cancelCancelsEverySession() {
        let a = StubSession(.success(t("a", .english, 0.9)))
        let b = StubSession(.success(t("b", .swedish, 0.9)))
        AutoDetectSession(sessions: [a, b], fallback: .english).cancel()
        #expect(a.cancelled && b.cancelled)
    }
}
```

Append to `Tests/SpeechToTextTests/AppleTranscriberTests.swift` inside the struct:
```swift
    @Test(.timeLimit(.minutes(2)))
    func autoDetectPicksEnglishForEnglishSpeech() async throws {
        let samples = try spokenSamples("Can you send me the quarterly report before lunch tomorrow")
        let transcript = try await transcribe(samples, .automatic,
                                              transcriber: AppleTranscriber(fallbackLanguage: { .swedish }))
        #expect(transcript.language == .english)
        #expect(transcript.text.lowercased().contains("quarterly report"))
    }

    @Test(.timeLimit(.minutes(2)))
    func autoDetectPicksSwedishForSwedishSpeech() async throws {
        let samples = try spokenSamples("Kan du skicka rapporten till mig innan lunch imorgon", voice: "Alva")
        let transcript = try await transcribe(samples, .automatic,
                                              transcriber: AppleTranscriber(fallbackLanguage: { .english }))
        #expect(transcript.language == .swedish)
        #expect(transcript.text.lowercased().contains("rapporten"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter "AutoDetectSessionTests|autoDetect"`
Expected: compile FAIL — `AutoDetectSession` not found.

- [ ] **Step 3: Implement**

`Sources/SpeechToText/AutoDetectSession.swift`:
```swift
import Core

/// Runs the same audio through one session per language and keeps the most confident result.
@MainActor
final class AutoDetectSession: TranscriptionSession {
    private static let log = Log.logger("SpeechToText")
    private let sessions: [any TranscriptionSession]
    private let fallback: Language

    init(sessions: [any TranscriptionSession], fallback: Language) {
        self.sessions = sessions
        self.fallback = fallback
    }

    func append(_ chunk: AudioChunk) {
        for session in sessions { session.append(chunk) }
    }

    func finish() async throws -> Transcript {
        let outcomes = await withTaskGroup(of: Result<Transcript, any Error>.self) { group in
            for session in sessions {
                group.addTask {
                    do { return .success(try await session.finish()) } catch { return .failure(error) }
                }
            }
            var all: [Result<Transcript, any Error>] = []
            for await outcome in group { all.append(outcome) }
            return all
        }
        var transcripts: [Transcript] = []
        var firstError: (any Error)?
        for outcome in outcomes {
            switch outcome {
            case .success(let transcript): transcripts.append(transcript)
            case .failure(let error):
                Self.log.error("auto-detect branch failed: \(String(describing: error), privacy: .public)")
                firstError = firstError ?? error
            }
        }
        if transcripts.isEmpty, let firstError { throw firstError }
        return LanguagePicker.pick(transcripts, fallback: fallback)
    }

    func cancel() {
        for session in sessions { session.cancel() }
    }
}
```

In `Sources/SpeechToText/AppleTranscriber.swift` replace the `.automatic` case:
```swift
        case .automatic:
            let english = try await AppleTranscriptionSession.start(language: .english)
            let swedish: AppleTranscriptionSession
            do {
                swedish = try await AppleTranscriptionSession.start(language: .swedish)
            } catch {
                english.cancel()
                throw error
            }
            return AutoDetectSession(sessions: [english, swedish], fallback: fallbackLanguage())
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter "AutoDetectSessionTests|AppleTranscriberTests"`
Expected: AutoDetectSessionTests 5/5, AppleTranscriberTests 7/7 PASS.

- [ ] **Step 5: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(stt): auto-detect English vs Swedish by confidence"
```

---

### Task 6: Preferences (persisted settings)

**Files:**
- Modify: `SecureWisprKit/Package.swift`
- Create: `SecureWisprKit/Sources/Preferences/SettingsStore.swift`
- Test: `SecureWisprKit/Tests/PreferencesTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `SpeechEngine`, `LanguageMode`, `Language` (Core).
- Produces: `@MainActor @Observable final class SettingsStore { init(defaults: UserDefaults = .standard); var engine: SpeechEngine; var languageMode: LanguageMode; var primaryLanguage: Language; var toggleLanguage: Language; var lastDetectedLanguage: Language }`

- [ ] **Step 1: Add targets**

In `Package.swift` add `"Preferences"` to the library product's targets, and:
```swift
        .target(name: "Preferences", dependencies: ["Core"]),
        .testTarget(name: "PreferencesTests", dependencies: ["Preferences"]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/PreferencesTests/SettingsStoreTests.swift`:
```swift
import Core
import Foundation
import Testing
@testable import Preferences

@MainActor
struct SettingsStoreTests {
    let defaults = UserDefaults(suiteName: "SecureWisprTests-\(UUID().uuidString)")!

    @Test func defaultsMatchTheSpec() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.engine == .apple)
        #expect(store.languageMode == .autoDetect)
        #expect(store.primaryLanguage == .english)
        #expect(store.toggleLanguage == .english)
        #expect(store.lastDetectedLanguage == .english)
    }

    @Test func valuesPersistAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        store.engine = .parakeet
        store.languageMode = .perLanguageHotkeys
        store.primaryLanguage = .swedish
        store.toggleLanguage = .swedish
        store.lastDetectedLanguage = .swedish

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.engine == .parakeet)
        #expect(reloaded.languageMode == .perLanguageHotkeys)
        #expect(reloaded.primaryLanguage == .swedish)
        #expect(reloaded.toggleLanguage == .swedish)
        #expect(reloaded.lastDetectedLanguage == .swedish)
    }

    @Test func corruptValuesFallBackToDefaults() {
        defaults.set("banana", forKey: "engine")
        defaults.set(42, forKey: "languageMode")
        let store = SettingsStore(defaults: defaults)
        #expect(store.engine == .apple)
        #expect(store.languageMode == .autoDetect)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter SettingsStoreTests`
Expected: compile FAIL — `SettingsStore` not found.

- [ ] **Step 4: Implement**

`Sources/Preferences/SettingsStore.swift`:
```swift
import Core
import Foundation
import Observation

/// User settings, persisted in UserDefaults. Unknown or corrupt stored values fall back to defaults.
@MainActor @Observable
public final class SettingsStore {
    private enum Key {
        static let engine = "engine"
        static let languageMode = "languageMode"
        static let primaryLanguage = "primaryLanguage"
        static let toggleLanguage = "toggleLanguage"
        static let lastDetectedLanguage = "lastDetectedLanguage"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var engine: SpeechEngine { didSet { defaults.set(engine.rawValue, forKey: Key.engine) } }
    public var languageMode: LanguageMode { didSet { defaults.set(languageMode.rawValue, forKey: Key.languageMode) } }
    public var primaryLanguage: Language { didSet { defaults.set(primaryLanguage.rawValue, forKey: Key.primaryLanguage) } }
    public var toggleLanguage: Language { didSet { defaults.set(toggleLanguage.rawValue, forKey: Key.toggleLanguage) } }
    public var lastDetectedLanguage: Language {
        didSet { defaults.set(lastDetectedLanguage.rawValue, forKey: Key.lastDetectedLanguage) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func read<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        engine = read(Key.engine, SpeechEngine.apple)
        languageMode = read(Key.languageMode, LanguageMode.autoDetect)
        primaryLanguage = read(Key.primaryLanguage, Language.english)
        toggleLanguage = read(Key.toggleLanguage, Language.english)
        lastDetectedLanguage = read(Key.lastDetectedLanguage, Language.english)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter SettingsStoreTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(preferences): persisted engine and language settings"
```

---

### Task 7: Parakeet engine (FluidAudio)

**Files:**
- Modify: `SecureWisprKit/Package.swift`
- Create: `SecureWisprKit/Sources/Parakeet/SpeechRecognizerBackend.swift`, `LanguageGuess.swift`, `ParakeetSession.swift`, `ParakeetTranscriber.swift`, `ParakeetModelStore.swift`
- Test: `SecureWisprKit/Tests/ParakeetTests/ParakeetTests.swift`, `SecureWisprKit/Tests/ParakeetTests/ParakeetModelStoreTests.swift`

**Interfaces:**
- Consumes: `Transcriber`, `TranscriptionSession`, `Transcript`, `AudioChunk`, `LanguageChoice`, `Core.Language`.
- Produces:
  - `protocol SpeechRecognizerBackend: Sendable { func transcribe(_ samples: [Float]) async throws -> String }`
  - `protocol ModelDownloader: Sendable { func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws; func exists(at directory: URL) -> Bool }`
  - `struct FluidAudioDownloader: ModelDownloader`
  - `@MainActor @Observable final class ParakeetModelStore { enum Status: Equatable { notDownloaded, downloading(Double), ready, failed(String) }; private(set) var status; let directory: URL; var isInstalled: Bool; static var defaultDirectory: URL; init(directory:downloader:); func download(); func cancelDownload(); func remove() }`
  - `@MainActor final class ParakeetTranscriber: Transcriber { init(store: ParakeetModelStore); init(store:loader:) }`
  - `enum ParakeetError: Error, Equatable { case modelNotInstalled }`

- [ ] **Step 1: Add the dependency and targets**

In `Package.swift`, add after `platforms:`:
```swift
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.17.7"),
    ],
```
Add `"Parakeet"` to the library product's targets, and:
```swift
        .target(name: "Parakeet", dependencies: [
            "Core", .product(name: "FluidAudio", package: "FluidAudio"),
        ]),
        .testTarget(name: "ParakeetTests", dependencies: ["Parakeet"]),
```

Run: `cd SecureWisprKit && swift package resolve 2>&1 | tail -2`
Expected: FluidAudio fetched (no error).

- [ ] **Step 2: Write the failing tests**

`Tests/ParakeetTests/ParakeetTests.swift`:
```swift
import AVFoundation
import Core
import Foundation
import Testing
@testable import Parakeet

final class FakeBackend: SpeechRecognizerBackend, @unchecked Sendable {
    var text = "Kan du skicka rapporten till mig innan lunch imorgon?"
    var receivedCounts: [Int] = []
    func transcribe(_ samples: [Float]) async throws -> String {
        receivedCounts.append(samples.count)
        return text
    }
}

@MainActor
struct ParakeetTests {
    @Test func guessesSwedishAndEnglish() {
        #expect(LanguageGuess.detect("Kan du skicka rapporten till mig innan lunch imorgon") == .swedish)
        #expect(LanguageGuess.detect("Can you send me the quarterly report before lunch") == .english)
        #expect(LanguageGuess.detect("") == nil)
    }

    @Test func sessionTranscribesBufferedAudioAndDetectsLanguage() async throws {
        let backend = FakeBackend()
        let session = ParakeetSession(backend: backend)
        session.append(AudioChunk(samples: Array(repeating: 0.1, count: 16_000)))
        session.append(AudioChunk(samples: Array(repeating: 0.1, count: 8_000)))
        let transcript = try await session.finish()
        #expect(backend.receivedCounts == [24_000])
        #expect(transcript.language == .swedish)
        #expect(transcript.locale.identifier == "sv_SE")
        #expect(transcript.text.hasPrefix("Kan du"))
    }

    @Test func shortAudioIsPaddedToOneSecond() async throws {
        let backend = FakeBackend()
        let session = ParakeetSession(backend: backend)
        session.append(AudioChunk(samples: Array(repeating: 0.1, count: 4_000)))
        _ = try await session.finish()
        #expect(backend.receivedCounts == [16_000])
    }

    @Test func noAudioGivesEmptyTranscriptWithoutCallingBackend() async throws {
        let backend = FakeBackend()
        let transcript = try await ParakeetSession(backend: backend).finish()
        #expect(transcript.text.isEmpty)
        #expect(backend.receivedCounts.isEmpty)
    }

    @Test func cancelledSessionDoesNotTranscribe() async throws {
        let backend = FakeBackend()
        let session = ParakeetSession(backend: backend)
        session.append(AudioChunk(samples: [0.1]))
        session.cancel()
        let transcript = try await session.finish()
        #expect(transcript.text.isEmpty)
        #expect(backend.receivedCounts.isEmpty)
    }

    @Test func transcriberRefusesWhenModelMissing() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        let transcriber = ParakeetTranscriber(store: store, loader: { _ in FakeBackend() })
        await #expect(throws: ParakeetError.modelNotInstalled) { try await transcriber.prepare() }
        #expect(!transcriber.isReady)
    }

    @Test func transcriberLoadsAndMakesSessions() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true))
        let transcriber = ParakeetTranscriber(store: store, loader: { _ in FakeBackend() })
        try await transcriber.prepare()
        #expect(transcriber.isReady)
        let session = try await transcriber.makeSession(language: .fixed(.english))   // choice ignored
        session.append(AudioChunk(samples: Array(repeating: 0.1, count: 16_000)))
        #expect(try await session.finish().language == .swedish)
    }

    @Test func removingModelMakesTranscriberNotReady() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true))
        let transcriber = ParakeetTranscriber(store: store, loader: { _ in FakeBackend() })
        try await transcriber.prepare()
        store.remove()
        #expect(!transcriber.isReady)
    }

    @Test(.enabled(if: FluidAudioDownloader().exists(at: ParakeetModelStore.defaultDirectory)),
          .timeLimit(.minutes(3)))
    func realParakeetTranscribesEnglish() async throws {
        let transcriber = ParakeetTranscriber(store: ParakeetModelStore())
        try await transcriber.prepare()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pk-\(UUID().uuidString).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Samantha", "-o", url.path, "hello world this is a test"]
        try say.run()
        say.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFileReader.samples16k(url)
        let session = try await transcriber.makeSession(language: .automatic)
        session.append(AudioChunk(samples: file))
        let transcript = try await session.finish()
        #expect(transcript.text.lowercased().contains("hello world"))
    }
}

enum AVAudioFileReader {
    static func samples16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return try PCMConverter(from: file.processingFormat, to: .speech16kMono).convert(buffer).floatSamples
    }
}
```

`Tests/ParakeetTests/ParakeetModelStoreTests.swift`:
```swift
import Core
import Foundation
import Testing
@testable import Parakeet

struct DownloadFailed: Error {}

final class FakeDownloader: ModelDownloader, @unchecked Sendable {
    var installed: Bool
    var fail = false
    var delay: Duration = .zero
    init(installed: Bool) { self.installed = installed }

    func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: directory.appendingPathComponent("part.bin"))
        progress(0.5)
        if delay > .zero { try await Task.sleep(for: delay) }
        if fail { throw DownloadFailed() }
        installed = true
        progress(1)
    }

    func exists(at directory: URL) -> Bool { installed }
}

@MainActor
struct ParakeetModelStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pk-\(UUID().uuidString)")

    private func waitWhileDownloading(_ store: ParakeetModelStore) async throws {
        for _ in 0..<200 {
            if case .downloading = store.status { try await Task.sleep(for: .milliseconds(10)) } else { return }
        }
    }

    @Test func startsReadyWhenModelExists() {
        #expect(ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true)).status == .ready)
    }

    @Test func partialFilesAreNotInstalled() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: dir.appendingPathComponent("x.bin"))
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        #expect(store.status == .notDownloaded)
        #expect(!store.isInstalled)
    }

    @Test func successfulDownloadBecomesReady() async throws {
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        store.download()
        try await waitWhileDownloading(store)
        #expect(store.status == .ready)
        #expect(store.isInstalled)
    }

    @Test func failedDownloadCleansUpAndReportsFailure() async throws {
        let downloader = FakeDownloader(installed: false)
        downloader.fail = true
        let store = ParakeetModelStore(directory: dir, downloader: downloader)
        store.download()
        try await waitWhileDownloading(store)
        guard case .failed = store.status else {
            Issue.record("expected failed, got \(store.status)")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func cancelledDownloadReturnsToNotDownloaded() async throws {
        let downloader = FakeDownloader(installed: false)
        downloader.delay = .seconds(5)
        let store = ParakeetModelStore(directory: dir, downloader: downloader)
        store.download()
        try await Task.sleep(for: .milliseconds(50))
        store.cancelDownload()
        try await waitWhileDownloading(store)
        #expect(store.status == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func removeDeletesTheModel() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true))
        store.remove()
        #expect(store.status == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter "ParakeetTests|ParakeetModelStoreTests"`
Expected: compile FAIL — Parakeet types not found.

- [ ] **Step 4: Implement backend and language guess**

`Sources/Parakeet/SpeechRecognizerBackend.swift`:
```swift
import FluidAudio
import Foundation

/// The speech-to-text call Parakeet sessions need; FluidAudio in the app, a fake in tests.
public protocol SpeechRecognizerBackend: Sendable {
    func transcribe(_ samples: [Float]) async throws -> String
}

/// FluidAudio's Parakeet TDT v3 on the Neural Engine.
final class FluidAudioBackend: SpeechRecognizerBackend {
    private let manager: AsrManager

    init(manager: AsrManager) { self.manager = manager }

    static func load(from directory: URL) async throws -> FluidAudioBackend {
        let models = try await AsrModels.load(from: directory, version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        return FluidAudioBackend(manager: manager)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        var state = TdtDecoderState.make()
        return try await manager.transcribe(samples, decoderState: &state).text
    }
}
```

`Sources/Parakeet/LanguageGuess.swift`:
```swift
import Core
import NaturalLanguage

/// Parakeet doesn't report the language it heard, so infer it from the text (on-device).
enum LanguageGuess {
    static func detect(_ text: String) -> Core.Language? {
        guard !text.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .swedish]
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .english?: return .english
        case .swedish?: return .swedish
        default: return nil
        }
    }
}
```

- [ ] **Step 5: Implement session and transcriber**

`Sources/Parakeet/ParakeetSession.swift`:
```swift
import Core
import Foundation

/// Parakeet is batch: buffer the utterance, transcribe it on finish.
@MainActor
final class ParakeetSession: TranscriptionSession {
    /// FluidAudio needs at least one second of audio.
    static let minimumSamples = Int(AudioChunk.sampleRate)

    private let backend: any SpeechRecognizerBackend
    private var samples: [Float] = []
    private var cancelled = false

    init(backend: any SpeechRecognizerBackend) {
        self.backend = backend
    }

    func append(_ chunk: AudioChunk) {
        guard !cancelled else { return }
        samples.append(contentsOf: chunk.samples)
    }

    func finish() async throws -> Transcript {
        guard !cancelled, !samples.isEmpty else {
            return Transcript(text: "", locale: Locale(identifier: "und"))
        }
        var audio = samples
        if audio.count < Self.minimumSamples {
            audio += Array(repeating: 0, count: Self.minimumSamples - audio.count)
        }
        let text = try await backend.transcribe(audio).trimmingCharacters(in: .whitespacesAndNewlines)
        let language = LanguageGuess.detect(text)
        return Transcript(text: text, locale: language?.locale ?? Locale(identifier: "und"),
                          confidence: nil, language: language)
    }

    func cancel() {
        cancelled = true
        samples = []
    }
}
```

`Sources/Parakeet/ParakeetTranscriber.swift`:
```swift
import Core
import Foundation

public enum ParakeetError: Error, Equatable {
    case modelNotInstalled
}

/// Parakeet TDT 0.6B v3. Detects the language itself, so the LanguageChoice is ignored.
/// Never downloads: `prepare()` only loads an installed model.
@MainActor
public final class ParakeetTranscriber: Transcriber {
    private let store: ParakeetModelStore
    private let loader: @MainActor (URL) async throws -> any SpeechRecognizerBackend
    private var backend: (any SpeechRecognizerBackend)?

    public var isReady: Bool { backend != nil && store.isInstalled }

    public convenience init(store: ParakeetModelStore) {
        self.init(store: store, loader: { try await FluidAudioBackend.load(from: $0) })
    }

    init(store: ParakeetModelStore, loader: @escaping @MainActor (URL) async throws -> any SpeechRecognizerBackend) {
        self.store = store
        self.loader = loader
    }

    public func prepare() async throws {
        guard store.isInstalled else {
            backend = nil
            throw ParakeetError.modelNotInstalled
        }
        if backend == nil { backend = try await loader(store.directory) }
    }

    public func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        try await prepare()
        guard let backend else { throw ParakeetError.modelNotInstalled }
        return ParakeetSession(backend: backend)
    }
}
```

- [ ] **Step 6: Implement the model store**

`Sources/Parakeet/ParakeetModelStore.swift`:
```swift
import Core
import FluidAudio
import Foundation
import Observation

public protocol ModelDownloader: Sendable {
    func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws
    func exists(at directory: URL) -> Bool
}

/// Downloads Parakeet TDT v3 from Hugging Face via FluidAudio. The only network access in the app.
public struct FluidAudioDownloader: ModelDownloader {
    public init() {}

    public func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await AsrModels.download(to: directory, version: .v3,
                                         progressHandler: { progress($0.fractionCompleted) })
    }

    public func exists(at directory: URL) -> Bool {
        AsrModels.modelsExist(at: directory, version: .v3)
    }
}

@MainActor @Observable
public final class ParakeetModelStore {
    public enum Status: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    private static let log = Log.logger("Parakeet")

    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("SecureWispr/Models/parakeet-tdt-0.6b-v3", isDirectory: true)
    }

    public private(set) var status: Status
    public let directory: URL
    @ObservationIgnored private let downloader: any ModelDownloader
    @ObservationIgnored private var task: Task<Void, Never>?

    public var isInstalled: Bool { status == .ready }

    public init(directory: URL = ParakeetModelStore.defaultDirectory,
                downloader: any ModelDownloader = FluidAudioDownloader()) {
        self.directory = directory
        self.downloader = downloader
        status = downloader.exists(at: directory) ? .ready : .notDownloaded
    }

    /// Starts a download. Only ever called from the Settings "Download" button.
    public func download() {
        switch status {
        case .ready, .downloading: return
        case .notDownloaded, .failed: break
        }
        status = .downloading(0)
        let directory = directory
        let downloader = downloader
        task = Task { [weak self] in
            do {
                try await downloader.download(to: directory) { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.status else { return }
                        self.status = .downloading(fraction)
                    }
                }
                try Task.checkCancellation()
                guard downloader.exists(at: directory) else { throw CocoaError(.fileReadCorruptFile) }
                self?.status = .ready
                Self.log.info("parakeet model downloaded")
            } catch {
                try? FileManager.default.removeItem(at: directory)
                if Task.isCancelled || error is CancellationError {
                    self?.status = .notDownloaded
                } else {
                    Self.log.error("parakeet download failed: \(String(describing: error), privacy: .public)")
                    self?.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    public func cancelDownload() {
        task?.cancel()
    }

    public func remove() {
        task?.cancel()
        try? FileManager.default.removeItem(at: directory)
        status = .notDownloaded
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter "ParakeetTests|ParakeetModelStoreTests"`
Expected: ParakeetTests 8 pass + `realParakeetTranscribesEnglish` skipped (model not downloaded); ParakeetModelStoreTests 6/6 pass. No network access occurs (fakes only).

- [ ] **Step 8: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(parakeet): optional Parakeet engine via FluidAudio with explicit download"
```

---

### Task 8: HUD language badge

**Files:**
- Modify: `SecureWisprKit/Sources/HUD/HUDContent.swift`, `SecureWisprKit/Sources/HUD/HUDView.swift`

**Interfaces:**
- Produces: `HUDContent.listening(levels: [Float], badge: String)` (replaces `listening(levels:)`).

- [ ] **Step 1: Change the content case**

In `Sources/HUD/HUDContent.swift` replace `case listening(levels: [Float])` with:
```swift
    case listening(levels: [Float], badge: String)
```

- [ ] **Step 2: Show the badge**

In `Sources/HUD/HUDView.swift` replace the listening case:
```swift
            case .listening(let levels, let badge):
                HStack(spacing: 10) {
                    Text(badge)
                        .font(.caption2.weight(.bold).monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    WaveformView(levels: levels)
                }
```

- [ ] **Step 3: Build**

Run: `cd SecureWisprKit && swift build 2>&1 | grep -E "error|Build complete"`
Expected: `Build complete!` (the app target is updated in Task 9).

- [ ] **Step 4: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(hud): language badge while listening"
```

---

### Task 9: App wiring, Settings UI, menu (minors d, e)

**Files:**
- Modify: `SecureWispr/AppModel.swift`, `SecureWispr/MenuContent.swift`, `SecureWispr/SettingsView.swift`, `SecureWispr/SecureWisprApp.swift` (full replacements below)

**Interfaces:**
- Consumes: `SettingsStore` (Preferences), `ParakeetModelStore`, `ParakeetTranscriber` (Parakeet), `AppleTranscriber(fallbackLanguage:)`, `CommandMapper`, `HotkeyContext`, `DictationController(transcriber:)`, `onLanguageDetected`, `currentChoice`, `HUDContent.listening(levels:badge:)`.
- Produces: the runnable app.

- [ ] **Step 1: Replace `SecureWispr/AppModel.swift`**

```swift
import AppKit
import Audio
import Cleanup
import Core
import Dictation
import HUD
import Hotkey
import Injection
import Observation
import Parakeet
import Preferences
import SpeechToText

@MainActor @Observable
final class AppModel {
    private static let log = Log.logger("App")

    let settings: SettingsStore
    let parakeetStore: ParakeetModelStore
    private(set) var missingPermissions: [Permission] = []
    private(set) var dictationState: DictationController.State = .idle

    @ObservationIgnored private let hud = HUDPanelController()
    @ObservationIgnored private let hotkey = FnHotkeyMonitor()
    @ObservationIgnored private let apple: AppleTranscriber
    @ObservationIgnored private let parakeet: ParakeetTranscriber
    @ObservationIgnored private var controller: DictationController!
    @ObservationIgnored private var hotkeyTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var hotkeyFailureLogged = false
    @ObservationIgnored private var badge = "AUTO"

    init() {
        // Build dependencies as locals first: reading self.* before every stored
        // property is initialized is a compile error.
        let settings = SettingsStore()
        let store = ParakeetModelStore()
        self.settings = settings
        parakeetStore = store
        apple = AppleTranscriber(fallbackLanguage: { settings.lastDetectedLanguage })
        parakeet = ParakeetTranscriber(store: store)
        controller = DictationController(
            audio: MicrophoneRecorder(),
            transcriber: { [weak self] in self?.activeTranscriber() ?? AppleTranscriber() },
            cleaner: PassthroughCleaner(),
            injector: PasteboardInjector(),
            contextProvider: {
                DictationContext(appBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            }
        )
        controller.onChange = { [weak self] state, levels in
            guard let self else { return }
            if dictationState != state { dictationState = state }
            if state != .idle { flashTask?.cancel() }
            hud.show(hudContent(for: state, levels: levels))
        }
        controller.onLanguageDetected = { [weak self] language in
            guard let self else { return }
            settings.lastDetectedLanguage = language
            flash("\(language.flag) \(language.displayName)", for: .milliseconds(800))
        }
    }

    func start() {
        for permission in Permission.allCases where !permission.isGranted {
            permission.request()
        }
        Task { [apple] in try? await apple.prepare() }
        warmUpParakeetIfSelected()
        // TCC has no change notification, so keep polling (cheap) to notice grants and revocations.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshPermissions()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: Engines

    /// True when Parakeet is selected but can't be used right now.
    var parakeetUnavailable: Bool {
        settings.engine == .parakeet && !parakeet.isReady
    }

    private func activeTranscriber() -> any Transcriber {
        guard settings.engine == .parakeet else { return apple }
        if parakeet.isReady { return parakeet }
        warmUpParakeetIfSelected()
        return apple
    }

    func warmUpParakeetIfSelected() {
        guard settings.engine == .parakeet, parakeetStore.isInstalled, !parakeet.isReady else { return }
        Task { [parakeet] in
            do { try await parakeet.prepare() } catch {
                Self.log.error("parakeet load failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: Language

    func switchToggleLanguage() {
        settings.toggleLanguage = settings.toggleLanguage.other
        flash("\(settings.toggleLanguage.flag) \(settings.toggleLanguage.displayName)", for: .seconds(1))
    }

    var languageStatus: String {
        if settings.engine == .parakeet && parakeet.isReady { return "Parakeet · automatic language" }
        return switch settings.languageMode {
        case .autoDetect: "Auto-detect (English / Svenska)"
        case .toggle: "Toggle: \(settings.toggleLanguage.displayName)"
        case .perLanguageHotkeys:
            "fn: \(settings.primaryLanguage.displayName) · fn+⇧: \(settings.primaryLanguage.other.displayName)"
        }
    }

    private func badgeText(for choice: LanguageChoice) -> String {
        if settings.engine == .parakeet && parakeet.isReady { return "AUTO" }
        return switch choice {
        case .automatic: "AUTO"
        case .fixed(let language): language.badge
        }
    }

    // MARK: Menu bar

    var menuBarSymbol: String {
        if !missingPermissions.isEmpty { return "exclamationmark.triangle" }
        return switch dictationState {
        case .listening: "mic.fill"
        case .preparingModel, .transcribing, .cleaning, .injecting: "ellipsis"
        case .idle, .failed: "waveform"
        }
    }

    var statusLine: String {
        if !missingPermissions.isEmpty { return "Setup needed" }
        return switch dictationState {
        case .idle: "Ready — hold fn to dictate"
        case .listening: "Listening…"
        case .preparingModel: "Downloading speech model…"
        case .transcribing, .cleaning, .injecting: "Transcribing…"
        case .failed(let failure): failure.message
        }
    }

    // MARK: Hotkey

    private func refreshPermissions() {
        let missing = Permission.allCases.filter { !$0.isGranted }
        if missing != missingPermissions { missingPermissions = missing }
        if !missing.contains(.inputMonitoring) && !hotkey.isRunning {
            startHotkey()
        }
    }

    private func startHotkey() {
        do {
            try hotkey.start()
        } catch {
            if !hotkeyFailureLogged {   // minor e: once per launch
                hotkeyFailureLogged = true
                Self.log.error("could not start fn event tap: \(String(describing: error), privacy: .public)")
            }
            return
        }
        hotkeyTask = Task { [weak self] in
            guard let self else { return }
            for await event in hotkey.events { handle(event) }
        }
    }

    private func handle(_ event: HotkeyEvent) {
        let context = HotkeyContext(
            mode: settings.languageMode, primary: settings.primaryLanguage,
            toggle: settings.toggleLanguage, canStart: missingPermissions.isEmpty   // minor d
        )
        let mapped = CommandMapper.map(event, context: context)
        if let command = mapped.command {
            if case .start(let choice) = command { badge = badgeText(for: choice) }
            controller.handle(command)
        }
        if mapped.newToggleLanguage != nil { switchToggleLanguage() }
    }

    // MARK: HUD

    private func flash(_ text: String, for duration: Duration) {
        flashTask?.cancel()
        hud.show(.message(text))
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, dictationState == .idle else { return }
            hud.show(.hidden)
        }
    }

    private func hudContent(for state: DictationController.State, levels: [Float]) -> HUDContent {
        switch state {
        case .idle: .hidden
        case .listening: .listening(levels: levels, badge: badge)
        case .preparingModel: .working("Downloading speech model…")
        case .transcribing, .cleaning, .injecting: .working("Transcribing…")
        case .failed(let failure): .message(failure.message)
        }
    }
}
```

- [ ] **Step 2: Replace `SecureWispr/MenuContent.swift`**

```swift
import SwiftUI

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Text(model.statusLine)
        Text(model.languageStatus)
        if model.settings.languageMode == .toggle && !model.parakeetUnavailable {
            Button("Switch to \(model.settings.toggleLanguage.other.displayName)") {
                model.switchToggleLanguage()
            }
        }
        if model.parakeetUnavailable {
            Text("Parakeet unavailable — using Apple")
        }
        if !model.missingPermissions.isEmpty {
            Divider()
            ForEach(model.missingPermissions) { permission in
                Button("Allow \(permission.title) \(permission.reason)…") {
                    permission.openSettings()
                }
            }
        }
        Divider()
        Text("Tip: Keyboard settings ▸ “Press 🌐 key to” ▸ Do Nothing")
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Button("Quit SecureWispr") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
```

- [ ] **Step 3: Replace `SecureWispr/SettingsView.swift`**

```swift
import Core
import Parakeet
import Preferences
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Speech engine") {
                Picker("Engine", selection: $settings.engine) {
                    ForEach(SpeechEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: settings.engine) { model.warmUpParakeetIfSelected() }
                ParakeetCard(store: model.parakeetStore) { model.warmUpParakeetIfSelected() }
                if model.parakeetUnavailable {
                    Text("Parakeet is selected but not ready — Apple is used until it is.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Language") {
                Picker("Mode", selection: $settings.languageMode) {
                    ForEach(LanguageMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                switch settings.languageMode {
                case .autoDetect:
                    Text("Each dictation is transcribed in English and Svenska; the more confident result is used.")
                        .font(.caption).foregroundStyle(.secondary)
                case .toggle:
                    Picker("Current language", selection: $settings.toggleLanguage) {
                        ForEach(Language.allCases, id: \.self) { Text("\($0.flag) \($0.displayName)").tag($0) }
                    }
                    Text("Quick-tap fn+⇧ to switch.").font(.caption).foregroundStyle(.secondary)
                case .perLanguageHotkeys:
                    Picker("fn dictates in", selection: $settings.primaryLanguage) {
                        ForEach(Language.allCases, id: \.self) { Text("\($0.flag) \($0.displayName)").tag($0) }
                    }
                    Text("fn+⇧ dictates in \(settings.primaryLanguage.other.displayName).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Push-to-talk") {
                LabeledContent("Dictate", value: "Hold fn, speak, release")
                LabeledContent("Cleanup", value: "Off (arrives in M3)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }
}

private struct ParakeetCard: View {
    let store: ParakeetModelStore
    let onReady: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Parakeet TDT 0.6B v3")
                Text("On-device, 25 languages. Downloaded from Hugging Face only when you click Download.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch store.status {
            case .notDownloaded:
                Button("Download") { store.download() }
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 90)
                Button("Cancel") { store.cancelDownload() }
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Remove") { store.remove() }
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                Button("Retry") { store.download() }
            }
        }
        .onChange(of: store.status) { if store.status == .ready { onReady() } }
    }
}
```

- [ ] **Step 4: Pass the model to Settings**

In `SecureWispr/SecureWisprApp.swift` replace
```swift
        Settings {
            SettingsView()
        }
```
with
```swift
        Settings {
            SettingsView(model: model)
        }
```

- [ ] **Step 5: Build the app**

Run: `xcodebuild -project SecureWispr.xcodeproj -scheme SecureWispr -configuration Debug -derivedDataPath build -allowProvisioningUpdates build 2>&1 | grep -E "error:|\*\* BUILD"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Full package suite**

Run: `cd SecureWisprKit && swift test 2>&1 | grep -E "error:|✘|Test run with"`
Expected: no `✘`.

- [ ] **Step 7: Relaunch and smoke-test**

Run: `pkill -x SecureWispr; open build/Build/Products/Debug/SecureWispr.app`
Expected: menu shows "Auto-detect (English / Svenska)"; Settings shows Engine, Language and the Parakeet card with a Download button.

- [ ] **Step 8: Commit**

```bash
git add SecureWispr SecureWisprKit
git commit -m "feat(app): language modes, engine selection, Parakeet card in Settings"
```

---

### Task 10: M2 acceptance (manual, with the user)

- [ ] **Step 1: Auto-detect with your voice.** Mode Auto-detect: dictate 5 Swedish and 5 English sentences in TextEdit. Expected: ≥ 9 of 10 in the right language; the HUD flashes 🇸🇪/🇬🇧 after each.
- [ ] **Step 2: Toggle.** Mode Toggle: quick-tap fn+⇧ → HUD flashes the new language; badge shows SV/EN while dictating; menu "Switch to…" also works.
- [ ] **Step 3: Per-language hotkeys.** Primary English: fn → English, fn+⇧ → Swedish; change primary to Svenska → reversed.
- [ ] **Step 4: Parakeet.** Engine Parakeet with model absent → menu says "Parakeet unavailable — using Apple" and dictation still works. Download → progress → Ready; dictate SV and EN (badge AUTO). Remove → back to Apple fallback.
- [ ] **Step 5: Network.** In Activity Monitor ▸ Network, SecureWispr shows traffic only while Download is running.
- [ ] **Step 6: Latency.** `log stream --predicate 'subsystem == "SecureWispr" AND category == "Dictation"' --info` while dictating ~10 s in Auto-detect: `release→inject` < 1000 ms (includes the 150 ms tail).
- [ ] **Step 7: Commit / tag**

```bash
git commit --allow-empty -m "chore: M2 acceptance passed"
git tag v0.2-m2
```
