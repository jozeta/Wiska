# SecureWispr M1 Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu-bar app where holding `fn`, speaking English, and releasing pastes the transcribed text at the cursor, with a live waveform HUD — fully on-device.

**Architecture:** An Xcode app target (Shell: menu bar, Settings, wiring, permissions) links a local Swift package `SecureWisprKit` whose modules each own one component (Hotkey, Audio, SpeechToText, Cleanup, Injection, HUD) plus `Dictation` (the pipeline state machine). Modules depend only on `Core` (shared types + protocols); only the app target wires concrete types together. Audio is streamed into the transcriber while the user speaks, so release only finalizes the tail.

**Tech Stack:** Swift 6.2 (language mode 6), SwiftUI + AppKit, AVFoundation (`AVAudioEngine`, `AVAudioConverter`), Speech (`SpeechAnalyzer` + `SpeechTranscriber`), CoreGraphics event taps, Swift Testing, Xcode 27 / macOS 27 SDK.

**Spec:** `docs/superpowers/specs/2026-10-08-securewispr-m1-skeleton-design.md`

## Global Constraints

- Deployment target: macOS 26.0 (`.macOS("26.0")` in the package; `MACOSX_DEPLOYMENT_TARGET = 26.0` in the app).
- App is **not sandboxed**; hardened runtime **on**; entitlement `com.apple.security.device.audio-input` only.
- Bundle identifier: `com.zeta.SecureWispr`. `LSUIElement = YES` (menu-bar only, no Dock icon).
- Package modules depend only on `Core`. Never import one component module from another.
- No network calls in M1. Speech assets are installed by the OS via `AssetInventory`.
- Logging: `Logger(subsystem: "SecureWispr", category: …)`; transcript text only ever interpolated with `privacy: .private`.
- Push-to-talk key: hold `fn` (keycode 63). Holds shorter than 250 ms cancel. Any other key down while held cancels.
- Max dictation length: 5 minutes, then auto-release.
- Pasteboard restore delay: 300 ms; restore only if `changeCount` is still ours. Text written with `org.nspasteboard.TransientType` and `org.nspasteboard.ConcealedType` markers.
- Secure input active → do not paste, do not leave text on the pasteboard; HUD says "Can't type here".
- M1 language: English (`en_US`) via `SpeechTranscriber` only.
- Package commands run from `SecureWisprKit/`: `swift build`, `swift test`.

## Review Focus

1. **fn pressed again while the previous dictation is still transcribing** → the press is ignored; no second recording starts, the first finishes normally. (Test: Task 6 `pressWhileBusyIsIgnored`.)
2. **Very quick utterance on cold start** (release before the speech session finished creating) → audio captured before the session existed is still transcribed, in order. (Test: Task 6 `audioBeforeSessionReadyIsStillTranscribed`.)
3. **Clipboard held non-text data** (an image or a custom type) → it is restored byte-for-byte after the paste. (Test: Task 5 `restoresNonTextContentExactly`.)
4. **Holding fn past the 5-minute cap** → recording stops and what was captured is transcribed and pasted, not lost. (Test: Task 6 `maxDurationAutoReleases`.)
5. **Microphone device changes mid-session** (AirPods connect/disconnect) → current dictation ends gracefully with what was captured; the next dictation works on the new device. (Manual check: Task 9 step 4; handled by `MicrophoneRecorder` rebuilding its engine on `AVAudioEngineConfigurationChange`.)

---

## File Structure

```
SecureWispr/                               repo root
  .gitignore                               + build/, Local.xcconfig
  Local.xcconfig.example                   DEVELOPMENT_TEAM template (committed)
  Local.xcconfig                           your team id (git-ignored)
  SecureWispr.xcodeproj/project.pbxproj    app target, links SecureWisprKit
  SecureWispr/                             app target sources (Shell)
    SecureWisprApp.swift                   @main, MenuBarExtra + Settings scenes
    AppModel.swift                         wires components, permission polling, HUD sync
    Permissions.swift                      Permission enum + checks/requests/settings links
    MenuContent.swift                      menu-bar menu UI
    SettingsView.swift                     placeholder settings pane
    SecureWispr.entitlements
  SecureWisprKit/
    Package.swift
    Sources/
      Core/          AudioChunk, Transcript, DictationContext, Protocols, Errors, PCMConverter, Log
      Hotkey/        FnKeyStateMachine (pure), FnHotkeyMonitor (CGEventTap)
      Audio/         Levels (pure), MicrophoneRecorder (AVAudioEngine)
      SpeechToText/  AppleTranscriber, AppleTranscriptionSession, AppleSpeechAssets
      Cleanup/       PassthroughCleaner
      Injection/     PasteboardSnapshot, PasteboardInjector, CGEventKeySender
      Dictation/     DictationController, DictationFailure
      HUD/           HUDContent, HUDView, WaveformView, HUDPanelController
    Tests/
      CoreTests/ HotkeyTests/ AudioTests/ SpeechToTextTests/ CleanupTests/
      InjectionTests/ DictationTests/
```

> **Note vs. spec §3.3:** `TranscriptionSession.append` takes a Sendable `AudioChunk` (16 kHz mono `[Float]`) instead of `AVAudioPCMBuffer`. Same role, but Sendable for Swift 6 and directly usable by Parakeet in M2. The pipeline controller lives in package module `Dictation` (not the app target) so it is testable with `swift test`.

---

### Task 0: Prerequisites (manual — human does this)

**Files:**
- Create: `Local.xcconfig.example`, `Local.xcconfig`
- Modify: `.gitignore`

- [ ] **Step 1: Create a signing identity.** Xcode → Settings → Accounts → `+` → Apple ID → sign in. Select the "Personal Team" → Manage Certificates → `+` → Apple Development. This gives a stable signature so macOS keeps Microphone/Input Monitoring/Accessibility grants across rebuilds.

- [ ] **Step 2: Find your team id.**

Run: `security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject`
Expected: a subject containing `OU=XXXXXXXXXX` — that 10-character value is the team id.

- [ ] **Step 3: Create the config files.**

`Local.xcconfig.example`:
```
// Copy to Local.xcconfig and fill in your team id (see Task 0 in the M1 plan).
DEVELOPMENT_TEAM = XXXXXXXXXX
```
`Local.xcconfig`: same content with your real team id.

Append to `.gitignore`:
```
build/
Local.xcconfig
```

- [ ] **Step 4: Globe key setting.** System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing**.

- [ ] **Step 5: Commit**

```bash
git add .gitignore Local.xcconfig.example
git commit -m "chore: add signing config template"
```

---

### Task 1: Package scaffold + Core

**Files:**
- Create: `SecureWisprKit/Package.swift`
- Create: `SecureWisprKit/Sources/Core/AudioChunk.swift`, `Transcript.swift`, `DictationContext.swift`, `Protocols.swift`, `Errors.swift`, `PCMConverter.swift`, `Log.swift`
- Test: `SecureWisprKit/Tests/CoreTests/PCMConverterTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (all `public`, module `Core`):
  - `struct AudioChunk: Sendable, Equatable { let samples: [Float]; static let sampleRate: Double = 16_000 }`
  - `enum LanguageChoice: Sendable, Equatable { case english }`
  - `struct Transcript: Sendable, Equatable { text: String; locale: Locale; confidence: Double? }`
  - `struct DictationContext: Sendable, Equatable { appBundleID: String? }`
  - `enum HotkeyEvent: Sendable, Equatable { case pressed, released, cancelled }`
  - `struct AudioCapture: Sendable { chunks: AsyncStream<AudioChunk>; levels: AsyncStream<Float> }`
  - `@MainActor protocol AudioSource: AnyObject { func start() throws -> AudioCapture; func stop() }`
  - `@MainActor protocol Transcriber: AnyObject { var isReady: Bool { get }; func prepare() async throws; func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession }`
  - `@MainActor protocol TranscriptionSession: AnyObject { func append(_ chunk: AudioChunk); func finish() async throws -> Transcript; func cancel() }`
  - `@MainActor protocol TextCleaner { func clean(_ text: String, context: DictationContext) async throws -> String }`
  - `@MainActor protocol TextInjector { func inject(_ text: String) async throws }`
  - `enum AudioError`, `enum TranscriptionError`, `enum InjectionError` (see code)
  - `final class PCMConverter: @unchecked Sendable { init(from: AVAudioFormat, to: AVAudioFormat) throws; func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer }`
  - `extension AVAudioFormat { static let speech16kMono: AVAudioFormat }`
  - `extension AVAudioPCMBuffer { static func speech(samples: [Float]) -> AVAudioPCMBuffer?; var floatSamples: [Float] }`
  - `enum Log { static func logger(_ category: String) -> Logger }`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SecureWisprKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SecureWisprKit", targets: ["Core"]),
    ],
    targets: [
        .target(name: "Core"),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
```

- [ ] **Step 2: Write the Core types**

`Sources/Core/AudioChunk.swift`:
```swift
/// A slice of microphone audio: 16 kHz, mono, Float32 samples in [-1, 1].
public struct AudioChunk: Sendable, Equatable {
    public static let sampleRate: Double = 16_000
    public let samples: [Float]

    public init(samples: [Float]) {
        self.samples = samples
    }
}
```

`Sources/Core/Transcript.swift`:
```swift
import Foundation

/// Which language a dictation should be transcribed in. M2 adds Swedish and auto-detect.
public enum LanguageChoice: Sendable, Equatable {
    case english
}

public struct Transcript: Sendable, Equatable {
    public var text: String
    public var locale: Locale
    public var confidence: Double?

    public init(text: String, locale: Locale, confidence: Double? = nil) {
        self.text = text
        self.locale = locale
        self.confidence = confidence
    }
}
```

`Sources/Core/DictationContext.swift`:
```swift
/// What was in front of the user when they started dictating. Cleanup uses it in M3 (app-aware tone).
public struct DictationContext: Sendable, Equatable {
    public var appBundleID: String?

    public init(appBundleID: String? = nil) {
        self.appBundleID = appBundleID
    }
}
```

`Sources/Core/Protocols.swift`:
```swift
import Foundation

public enum HotkeyEvent: Sendable, Equatable {
    case pressed
    case released
    case cancelled
}

/// Live output of one recording. Both streams finish when the source is stopped.
public struct AudioCapture: Sendable {
    public let chunks: AsyncStream<AudioChunk>
    public let levels: AsyncStream<Float>

    public init(chunks: AsyncStream<AudioChunk>, levels: AsyncStream<Float>) {
        self.chunks = chunks
        self.levels = levels
    }
}

@MainActor
public protocol AudioSource: AnyObject {
    func start() throws -> AudioCapture
    func stop()
}

@MainActor
public protocol Transcriber: AnyObject {
    /// True once models/assets are installed and a session can start without downloading.
    var isReady: Bool { get }
    /// Idempotent warm-up: installs assets if needed.
    func prepare() async throws
    func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession
}

@MainActor
public protocol TranscriptionSession: AnyObject {
    func append(_ chunk: AudioChunk)
    func finish() async throws -> Transcript
    func cancel()
}

@MainActor
public protocol TextCleaner {
    func clean(_ text: String, context: DictationContext) async throws -> String
}

@MainActor
public protocol TextInjector {
    func inject(_ text: String) async throws
}
```

`Sources/Core/Errors.swift`:
```swift
public enum AudioError: Error, Equatable {
    case noInputDevice
    case unsupportedFormat
    case engineFailed(String)
}

public enum TranscriptionError: Error, Equatable {
    case unsupportedLocale(String)
    case noCompatibleAudioFormat
}

public enum InjectionError: Error, Equatable {
    case secureInputActive
    case eventCreationFailed
}
```

`Sources/Core/Log.swift`:
```swift
import os

public enum Log {
    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: "SecureWispr", category: category)
    }
}
```

- [ ] **Step 3: Write the failing PCMConverter tests**

`Tests/CoreTests/PCMConverterTests.swift`:
```swift
import AVFoundation
import Testing
@testable import Core

struct PCMConverterTests {
    @Test func speechBufferRoundTripsSamples() throws {
        let samples: [Float] = [0, 0.25, -0.5, 1]
        let buffer = try #require(AVAudioPCMBuffer.speech(samples: samples))
        #expect(buffer.format.sampleRate == 16_000)
        #expect(buffer.format.channelCount == 1)
        #expect(buffer.floatSamples == samples)
    }

    @Test func downsamples48kStereoTo16kMono() throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let converter = try PCMConverter(from: input, to: .speech16kMono)
        var total = 0
        for _ in 0..<10 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4_800))
            buffer.frameLength = 4_800
            for channel in 0..<2 {
                let data = try #require(buffer.floatChannelData?[channel])
                for i in 0..<4_800 { data[i] = sin(Float(i) * 2 * .pi * 440 / 48_000) * 0.5 }
            }
            let out = try converter.convert(buffer)
            #expect(out.format.channelCount == 1)
            total += Int(out.frameLength)
        }
        // 1 s of 48 kHz in → ~16 000 frames out (converter keeps a little in its filter).
        #expect((15_680...16_000).contains(total))
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter PCMConverterTests`
Expected: compile FAIL — `speech(samples:)`, `PCMConverter` not found.

- [ ] **Step 5: Implement PCMConverter**

`Sources/Core/PCMConverter.swift`:
```swift
import AVFoundation

public extension AVAudioFormat {
    /// The pipeline's canonical format: 16 kHz mono Float32, non-interleaved.
    static let speech16kMono = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: AudioChunk.sampleRate, channels: 1, interleaved: false
    )!
}

public extension AVAudioPCMBuffer {
    static func speech(samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: .speech16kMono, frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    /// First channel as Float samples (empty for non-float formats).
    var floatSamples: [Float] {
        guard let channel = floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(frameLength)))
    }
}

/// Streaming sample-rate / channel / sample-format converter. Not thread-safe:
/// use each instance from one thread at a time (the audio tap, or the main actor).
public final class PCMConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let ratio: Double

    public init(from input: AVAudioFormat, to output: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: input, to: output) else {
            throw AudioError.unsupportedFormat
        }
        self.converter = converter
        self.outputFormat = output
        self.ratio = output.sampleRate / input.sampleRate
    }

    public func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw AudioError.unsupportedFormat
        }
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw AudioError.engineFailed(error.localizedDescription) }
        return output
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter PCMConverterTests`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(core): add shared types, protocols and PCM converter"
```

---

### Task 2: Hotkey (fn state machine + event tap)

> 👤 **Human contribution point:** `FnKeyStateMachine.handle(_:)` is the feel of the whole app — when a hold counts, when it's a shortcut. Tests below define the contract; the human writes the ~15-line body. Executors: create the file with the signature and a `fatalError("TODO(human)")` body, run the tests to show them failing, then **stop and ask the human** to implement it before continuing.

**Files:**
- Modify: `SecureWisprKit/Package.swift`
- Create: `SecureWisprKit/Sources/Hotkey/FnKeyStateMachine.swift`, `SecureWisprKit/Sources/Hotkey/FnHotkeyMonitor.swift`
- Test: `SecureWisprKit/Tests/HotkeyTests/FnKeyStateMachineTests.swift`

**Interfaces:**
- Consumes: `HotkeyEvent`, `Log` from Core.
- Produces:
  - `enum KeyInput: Equatable { case flagsChanged(fnDown: Bool, time: TimeInterval); case keyDown(time: TimeInterval) }`
  - `struct FnKeyStateMachine { var minimumHold: TimeInterval = 0.25; mutating func handle(_ input: KeyInput) -> HotkeyEvent? }`
  - `@MainActor final class FnHotkeyMonitor { let events: AsyncStream<HotkeyEvent>; var isRunning: Bool; func start() throws }`
  - `enum HotkeyError: Error { case tapCreationFailed }`

- [ ] **Step 1: Add targets to `Package.swift`**

```swift
    products: [
        .library(name: "SecureWisprKit", targets: ["Core", "Hotkey"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Hotkey", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "HotkeyTests", dependencies: ["Hotkey"]),
    ]
```

- [ ] **Step 2: Write the failing tests**

`Tests/HotkeyTests/FnKeyStateMachineTests.swift`:
```swift
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
```

- [ ] **Step 3: Create the state machine with the signature only**

`Sources/Hotkey/FnKeyStateMachine.swift`:
```swift
import Core
import Foundation

public enum KeyInput: Equatable {
    case flagsChanged(fnDown: Bool, time: TimeInterval)
    case keyDown(time: TimeInterval)
}

/// Turns raw fn / key events into push-to-talk events.
/// - fn down → `.pressed` (recording starts immediately).
/// - fn up after ≥ `minimumHold` → `.released`; sooner → `.cancelled` (accidental tap).
/// - any key down while fn is held → `.cancelled` once (user is doing fn+arrow etc.);
///   the later fn up is then silent.
public struct FnKeyStateMachine {
    public var minimumHold: TimeInterval = 0.25
    private var pressedAt: TimeInterval?
    private var interrupted = false

    public init() {}

    public mutating func handle(_ input: KeyInput) -> HotkeyEvent? {
        fatalError("TODO(human): implement push-to-talk rules")
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter FnKeyStateMachineTests`
Expected: FAIL (crash on `fatalError`). **Stop here and ask the human to implement `handle(_:)`.** Reference implementation if the human asks for one:

```swift
    public mutating func handle(_ input: KeyInput) -> HotkeyEvent? {
        switch input {
        case .flagsChanged(fnDown: true, time: let time):
            guard pressedAt == nil else { return nil }
            pressedAt = time
            interrupted = false
            return .pressed
        case .keyDown:
            guard pressedAt != nil, !interrupted else { return nil }
            interrupted = true
            return .cancelled
        case .flagsChanged(fnDown: false, time: let time):
            guard let start = pressedAt else { return nil }
            pressedAt = nil
            if interrupted { return nil }
            return time - start < minimumHold ? .cancelled : .released
        }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter FnKeyStateMachineTests`
Expected: PASS (7 tests).

- [ ] **Step 6: Write the event-tap monitor** (system integration; verified manually in Task 9)

`Sources/Hotkey/FnHotkeyMonitor.swift`:
```swift
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

    fileprivate func receive(type: CGEventType, event: CGEvent) {
        let time = TimeInterval(event.timestamp) / 1_000_000_000
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Self.log.notice("event tap was disabled by the system; re-enabled")
        case .flagsChanged:
            guard event.getIntegerValueField(.keyboardEventKeycode) == Self.fnKeyCode else { return }
            feed(.flagsChanged(fnDown: event.flags.contains(.maskSecondaryFn), time: time))
        case .keyDown:
            feed(.keyDown(time: time))
        default:
            break
        }
    }

    private func feed(_ input: KeyInput) {
        if let event = machine.handle(input) { continuation.yield(event) }
    }
}

/// C callback. The tap's run-loop source is on the main run loop, so we are on the main thread.
private func fnTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let monitor = Unmanaged<FnHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { monitor.receive(type: type, event: event) }
    }
    return Unmanaged.passUnretained(event)
}
```

- [ ] **Step 7: Build**

Run: `cd SecureWisprKit && swift build && swift test --filter HotkeyTests`
Expected: build succeeds, 7 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(hotkey): fn push-to-talk state machine and event tap"
```

---

### Task 3: Audio (levels + microphone recorder)

**Files:**
- Modify: `SecureWisprKit/Package.swift`
- Create: `SecureWisprKit/Sources/Audio/Levels.swift`, `SecureWisprKit/Sources/Audio/MicrophoneRecorder.swift`
- Test: `SecureWisprKit/Tests/AudioTests/LevelsTests.swift`

**Interfaces:**
- Consumes: `AudioSource`, `AudioCapture`, `AudioChunk`, `AudioError`, `PCMConverter`, `AVAudioFormat.speech16kMono`, `floatSamples`, `Log` from Core.
- Produces:
  - `enum Levels { static func rms(_ samples: [Float]) -> Float; static func normalized(rms: Float) -> Float }` (0…1, −50 dB floor)
  - `@MainActor final class MicrophoneRecorder: AudioSource { init() }`

- [ ] **Step 1: Add targets to `Package.swift`**

Add `"Audio"` to the library product's `targets` array, and to `targets:`:
```swift
        .target(name: "Audio", dependencies: ["Core"]),
        .testTarget(name: "AudioTests", dependencies: ["Audio"]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/AudioTests/LevelsTests.swift`:
```swift
import Testing
@testable import Audio

struct LevelsTests {
    @Test func rmsOfEmptyIsZero() {
        #expect(Levels.rms([]) == 0)
    }

    @Test func rmsOfFullScaleSquareIsOne() {
        #expect(Levels.rms([1, -1, 1, -1]) == 1)
    }

    @Test func normalizedMapsDecibelsLinearlyFromMinus50() {
        #expect(Levels.normalized(rms: 0) == 0)
        #expect(Levels.normalized(rms: 1) == 1)
        #expect(abs(Levels.normalized(rms: 0.01) - 0.2) < 0.0001)   // −40 dB
        #expect(Levels.normalized(rms: 2) == 1)                     // clamped
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter LevelsTests`
Expected: compile FAIL — `Levels` not found.

- [ ] **Step 4: Implement Levels**

`Sources/Audio/Levels.swift`:
```swift
import Foundation

/// Loudness helpers for the HUD waveform.
public enum Levels {
    static let floorDecibels: Float = -50

    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumOfSquares / Float(samples.count)).squareRoot()
    }

    /// Maps RMS to 0…1 on a decibel scale: floorDecibels → 0, 0 dBFS → 1.
    public static func normalized(rms: Float) -> Float {
        let decibels = 20 * log10(max(rms, 1e-7))
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter LevelsTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Write the microphone recorder** (hardware; verified manually in Task 9)

`Sources/Audio/MicrophoneRecorder.swift`:
```swift
import AVFoundation
import Core

/// Captures the default input device, converted to 16 kHz mono, as an `AudioCapture`.
@MainActor
public final class MicrophoneRecorder: AudioSource {
    private static let log = Log.logger("Audio")

    private var engine = AVAudioEngine()
    private var chunkContinuation: AsyncStream<AudioChunk>.Continuation?
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var configObserver: NSObjectProtocol?

    public init() {
        observeConfigurationChanges()
    }

    public func start() throws -> AudioCapture {
        stop()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioError.noInputDevice }

        let converter = try PCMConverter(from: format, to: .speech16kMono)
        let (chunks, chunkContinuation) = AsyncStream.makeStream(of: AudioChunk.self)
        let (levels, levelContinuation) = AsyncStream.makeStream(
            of: Float.self, bufferingPolicy: .bufferingNewest(8)
        )
        input.installTap(
            onBus: 0, bufferSize: 1_024, format: format,
            block: Self.makeTapBlock(converter: converter, chunks: chunkContinuation, levels: levelContinuation)
        )
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioError.engineFailed(error.localizedDescription)
        }
        self.chunkContinuation = chunkContinuation
        self.levelContinuation = levelContinuation
        return AudioCapture(chunks: chunks, levels: levels)
    }

    public func stop() {
        guard chunkContinuation != nil else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        chunkContinuation?.finish()
        levelContinuation?.finish()
        chunkContinuation = nil
        levelContinuation = nil
    }

    /// Built in a nonisolated context on purpose: the tap block runs on a realtime audio
    /// thread, and a closure formed inside this @MainActor class would inherit main-actor
    /// isolation and trap at runtime under Swift 6.
    private nonisolated static func makeTapBlock(
        converter: PCMConverter,
        chunks: AsyncStream<AudioChunk>.Continuation,
        levels: AsyncStream<Float>.Continuation
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let converted = try? converter.convert(buffer) else { return }
            let samples = converted.floatSamples
            guard !samples.isEmpty else { return }
            chunks.yield(AudioChunk(samples: samples))
            levels.yield(Levels.normalized(rms: Levels.rms(samples)))
        }
    }

    /// Device changes (AirPods connect, mic unplugged) invalidate the engine's format.
    /// End the current capture with what we have and rebuild the engine for next time.
    private func observeConfigurationChanges() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Self.log.notice("audio configuration changed; rebuilding engine")
                self.stop()
                self.engine = AVAudioEngine()
            }
        }
    }
}
```

- [ ] **Step 7: Build**

Run: `cd SecureWisprKit && swift build && swift test --filter AudioTests`
Expected: build succeeds, 3 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(audio): microphone capture at 16 kHz with waveform levels"
```

---

### Task 4: SpeechToText (Apple SpeechAnalyzer, English)

**Files:**
- Modify: `SecureWisprKit/Package.swift`
- Create: `SecureWisprKit/Sources/SpeechToText/AppleSpeechAssets.swift`, `AppleTranscriber.swift`, `AppleTranscriptionSession.swift`
- Test: `SecureWisprKit/Tests/SpeechToTextTests/AppleTranscriberTests.swift`

**Interfaces:**
- Consumes: `Transcriber`, `TranscriptionSession`, `LanguageChoice`, `Transcript`, `AudioChunk`, `TranscriptionError`, `PCMConverter`, `AVAudioPCMBuffer.speech(samples:)`, `Log` from Core.
- Produces: `@MainActor final class AppleTranscriber: Transcriber { init(); var isReady: Bool; func prepare() async throws; func makeSession(language:) async throws -> any TranscriptionSession }`

- [ ] **Step 1: Add targets to `Package.swift`**

Add `"SpeechToText"` to the library product, and:
```swift
        .target(name: "SpeechToText", dependencies: ["Core"]),
        .testTarget(name: "SpeechToTextTests", dependencies: ["SpeechToText"]),
```

- [ ] **Step 2: Write the failing integration test**

`Tests/SpeechToTextTests/AppleTranscriberTests.swift`:
```swift
import AVFoundation
import Core
import Foundation
import Speech
import Testing
@testable import SpeechToText

@MainActor
struct AppleTranscriberTests {
    /// Speaks `text` with the system voice into a temp AIFF and returns 16 kHz mono samples.
    private func spokenSamples(_ text: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("securewispr-\(UUID().uuidString).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, text]
        try say.run()
        say.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: buffer)
        return try PCMConverter(from: file.processingFormat, to: .speech16kMono).convert(buffer).floatSamples
    }

    @Test(.enabled(if: SpeechTranscriber.isAvailable), .timeLimit(.minutes(2)))
    func transcribesSpokenEnglish() async throws {
        let samples = try spokenSamples("hello world this is a test")
        let transcriber = AppleTranscriber()
        let session = try await transcriber.makeSession(language: .english)
        // Feed in 100 ms chunks, like the microphone does.
        for start in stride(from: 0, to: samples.count, by: 1_600) {
            session.append(AudioChunk(samples: Array(samples[start..<min(start + 1_600, samples.count)])))
        }
        let transcript = try await session.finish()
        #expect(transcript.text.lowercased().contains("hello world"))
        #expect(transcript.locale.identifier.hasPrefix("en"))
        #expect(transcriber.isReady)
    }

    @Test(.enabled(if: SpeechTranscriber.isAvailable), .timeLimit(.minutes(1)))
    func silenceGivesEmptyText() async throws {
        let session = try await AppleTranscriber().makeSession(language: .english)
        session.append(AudioChunk(samples: Array(repeating: 0, count: 16_000)))
        let transcript = try await session.finish()
        #expect(transcript.text.isEmpty)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd SecureWisprKit && swift test --filter AppleTranscriberTests`
Expected: compile FAIL — `AppleTranscriber` not found.

- [ ] **Step 4: Implement assets helper**

`Sources/SpeechToText/AppleSpeechAssets.swift`:
```swift
import Core
import Speech

enum AppleSpeechAssets {
    private static let log = Log.logger("SpeechToText")

    /// Ensures the on-device model for `module` is installed, downloading it if needed.
    static func ensureInstalled(_ module: SpeechTranscriber, locale: Locale) async throws {
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

- [ ] **Step 5: Implement the session**

`Sources/SpeechToText/AppleTranscriptionSession.swift`:
```swift
import AVFoundation
import Core
import Speech

/// One push-to-talk utterance streamed into a SpeechAnalyzer.
@MainActor
final class AppleTranscriptionSession: TranscriptionSession {
    private let locale: Locale
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let converter: PCMConverter
    private let collector: Task<String, Error>

    private init(locale: Locale, analyzer: SpeechAnalyzer,
                 input: AsyncStream<AnalyzerInput>.Continuation,
                 converter: PCMConverter, collector: Task<String, Error>) {
        self.locale = locale
        self.analyzer = analyzer
        self.input = input
        self.converter = converter
        self.collector = collector
    }

    static func start(module: SpeechTranscriber, locale: Locale) async throws -> AppleTranscriptionSession {
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriptionError.noCompatibleAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: format)

        let results = module.results
        let collector = Task<String, Error> {
            var parts: [String] = []
            for try await result in results {
                parts.append(String(result.text.characters))
            }
            return parts.joined(separator: " ")
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: stream)
        return AppleTranscriptionSession(
            locale: locale, analyzer: analyzer, input: continuation,
            converter: try PCMConverter(from: .speech16kMono, to: format), collector: collector
        )
    }

    func append(_ chunk: AudioChunk) {
        guard let buffer = AVAudioPCMBuffer.speech(samples: chunk.samples),
              let converted = try? converter.convert(buffer) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    func finish() async throws -> Transcript {
        input.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = try await collector.value
        return Transcript(text: text, locale: locale)
    }

    func cancel() {
        input.finish()
        collector.cancel()
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}
```

- [ ] **Step 6: Implement the transcriber**

`Sources/SpeechToText/AppleTranscriber.swift`:
```swift
import Core
import Speech

/// Apple's on-device SpeechAnalyzer. M1: English via SpeechTranscriber.
/// (M2 adds Swedish via DictationTranscriber — SpeechTranscriber has no sv_SE.)
@MainActor
public final class AppleTranscriber: Transcriber {
    private static let english = Locale(identifier: "en_US")
    private static let log = Log.logger("SpeechToText")

    public private(set) var isReady = false
    private var preparation: Task<Void, Error>?

    public init() {}

    public func prepare() async throws {
        if isReady { return }
        if let preparation { return try await preparation.value }
        let task = Task<Void, Error> {
            try await AppleSpeechAssets.ensureInstalled(Self.makeModule(), locale: Self.english)
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
        case .english:
            return try await AppleTranscriptionSession.start(module: Self.makeModule(), locale: Self.english)
        }
    }

    private static func makeModule() -> SpeechTranscriber {
        SpeechTranscriber(locale: english, preset: .transcription)
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter AppleTranscriberTests`
Expected: PASS (2 tests). If `silenceGivesEmptyText` yields a stray token (e.g. "."), relax that expectation to `transcript.text.count < 3` and note it in the commit message — the controller treats empty text as "No speech detected".

- [ ] **Step 8: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(stt): stream audio into Apple SpeechAnalyzer (English)"
```

---

### Task 5: Cleanup (passthrough) + Injection (pasteboard)

**Files:**
- Modify: `SecureWisprKit/Package.swift`
- Create: `SecureWisprKit/Sources/Cleanup/PassthroughCleaner.swift`
- Create: `SecureWisprKit/Sources/Injection/PasteboardSnapshot.swift`, `PasteboardInjector.swift`, `CGEventKeySender.swift`
- Test: `SecureWisprKit/Tests/CleanupTests/PassthroughCleanerTests.swift`, `SecureWisprKit/Tests/InjectionTests/PasteboardInjectorTests.swift`

**Interfaces:**
- Consumes: `TextCleaner`, `TextInjector`, `DictationContext`, `InjectionError`, `Log` from Core.
- Produces:
  - `struct PassthroughCleaner: TextCleaner { init() }`
  - `struct PasteboardSnapshot: Equatable { static func capture(_: NSPasteboard) -> Self; func restore(to: NSPasteboard) }`
  - `@MainActor protocol KeySender { func sendPaste() throws }`
  - `struct CGEventKeySender: KeySender { init() }`
  - `@MainActor final class PasteboardInjector: TextInjector { init(pasteboard: NSPasteboard = .general, keySender: any KeySender = CGEventKeySender(), restoreDelay: Duration = .milliseconds(300), isSecureInputActive: @escaping @MainActor () -> Bool = { IsSecureEventInputEnabled() }) }`

- [ ] **Step 1: Add targets to `Package.swift`**

Add `"Cleanup", "Injection"` to the library product, and:
```swift
        .target(name: "Cleanup", dependencies: ["Core"]),
        .target(name: "Injection", dependencies: ["Core"]),
        .testTarget(name: "CleanupTests", dependencies: ["Cleanup"]),
        .testTarget(name: "InjectionTests", dependencies: ["Injection"]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/CleanupTests/PassthroughCleanerTests.swift`:
```swift
import Core
import Testing
@testable import Cleanup

@MainActor
struct PassthroughCleanerTests {
    @Test func trimsSurroundingWhitespaceOnly() async throws {
        let cleaned = try await PassthroughCleaner().clean("  hello, um, world \n", context: DictationContext())
        #expect(cleaned == "hello, um, world")
    }
}
```

`Tests/InjectionTests/PasteboardInjectorTests.swift`:
```swift
import AppKit
import Testing
@testable import Core
@testable import Injection

@MainActor
final class RecordingKeySender: KeySender {
    let pasteboard: NSPasteboard
    var onPaste: (NSPasteboard) -> Void = { _ in }
    private(set) var seenAtPaste: [String?] = []
    private(set) var transientAtPaste: [Bool] = []

    init(pasteboard: NSPasteboard) { self.pasteboard = pasteboard }

    func sendPaste() throws {
        seenAtPaste.append(pasteboard.string(forType: .string))
        transientAtPaste.append(pasteboard.types?.contains(.init("org.nspasteboard.TransientType")) ?? false)
        onPaste(pasteboard)
    }
}

@MainActor
struct PasteboardInjectorTests {
    let pasteboard = NSPasteboard(name: .init("SecureWisprTests-\(UUID().uuidString)"))

    private func injector(_ sender: RecordingKeySender, secure: Bool = false) -> PasteboardInjector {
        PasteboardInjector(pasteboard: pasteboard, keySender: sender,
                           restoreDelay: .milliseconds(20), isSecureInputActive: { secure })
    }

    @Test func pastesTextThenRestoresPreviousClipboard() async throws {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        let sender = RecordingKeySender(pasteboard: pasteboard)

        try await injector(sender).inject("dictated text")

        #expect(sender.seenAtPaste == ["dictated text"])
        #expect(sender.transientAtPaste == [true])
        #expect(pasteboard.string(forType: .string) == "previous")
    }

    @Test func skipsRestoreWhenSomethingElseWroteToClipboard() async throws {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        let sender = RecordingKeySender(pasteboard: pasteboard)
        sender.onPaste = { pb in
            pb.clearContents()
            pb.setString("copied by user", forType: .string)
        }

        try await injector(sender).inject("dictated text")

        #expect(pasteboard.string(forType: .string) == "copied by user")
    }

    @Test func refusesSecureInputAndLeavesClipboardUntouched() async throws {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        let sender = RecordingKeySender(pasteboard: pasteboard)

        await #expect(throws: InjectionError.secureInputActive) {
            try await injector(sender, secure: true).inject("secret")
        }
        #expect(sender.seenAtPaste.isEmpty)
        #expect(pasteboard.string(forType: .string) == "previous")
    }

    @Test func restoresNonTextContentExactly() async throws {
        let custom = NSPasteboard.PasteboardType("com.example.custom")
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(Data("custom".utf8), forType: custom)
        pasteboard.writeObjects([item])
        let before = PasteboardSnapshot.capture(pasteboard)

        try await injector(RecordingKeySender(pasteboard: pasteboard)).inject("text")

        #expect(PasteboardSnapshot.capture(pasteboard) == before)
        #expect(pasteboard.data(forType: .png) == png)
    }

    @Test func emptyClipboardStaysEmptyAfterPaste() async throws {
        pasteboard.clearContents()
        try await injector(RecordingKeySender(pasteboard: pasteboard)).inject("text")
        #expect(pasteboard.string(forType: .string) == nil)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter "PassthroughCleanerTests|PasteboardInjectorTests"`
Expected: compile FAIL — types not found.

- [ ] **Step 4: Implement the cleaner**

`Sources/Cleanup/PassthroughCleaner.swift`:
```swift
import Core
import Foundation

/// M1 cleaner: no model, just trims. M3 replaces it with a Foundation Models cleaner.
public struct PassthroughCleaner: TextCleaner {
    public init() {}

    public func clean(_ text: String, context: DictationContext) async throws -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 5: Implement snapshot, key sender, injector**

`Sources/Injection/PasteboardSnapshot.swift`:
```swift
import AppKit

/// A byte-for-byte copy of every item and type on a pasteboard.
public struct PasteboardSnapshot: Equatable {
    let items: [[NSPasteboard.PasteboardType: Data]]

    @MainActor
    public static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        return PasteboardSnapshot(items: items)
    }

    @MainActor
    public func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        })
    }
}
```

`Sources/Injection/CGEventKeySender.swift`:
```swift
import CoreGraphics
import Core

@MainActor
public protocol KeySender {
    func sendPaste() throws
}

/// Posts ⌘V to the frontmost app. Requires Accessibility permission.
public struct CGEventKeySender: KeySender {
    private static let vKeyCode: CGKeyCode = 9   // physical V position; same on ANSI and Swedish ISO

    public init() {}

    public func sendPaste() throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        else { throw InjectionError.eventCreationFailed }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
```

`Sources/Injection/PasteboardInjector.swift`:
```swift
import AppKit
import Carbon.HIToolbox
import Core

/// Puts text at the cursor by pasting, then puts the user's clipboard back.
@MainActor
public final class PasteboardInjector: TextInjector {
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let log = Log.logger("Injection")

    private let pasteboard: NSPasteboard
    private let keySender: any KeySender
    private let restoreDelay: Duration
    private let isSecureInputActive: @MainActor () -> Bool

    public init(
        pasteboard: NSPasteboard = .general,
        keySender: any KeySender = CGEventKeySender(),
        restoreDelay: Duration = .milliseconds(300),
        isSecureInputActive: @escaping @MainActor () -> Bool = { IsSecureEventInputEnabled() }
    ) {
        self.pasteboard = pasteboard
        self.keySender = keySender
        self.restoreDelay = restoreDelay
        self.isSecureInputActive = isSecureInputActive
    }

    public func inject(_ text: String) async throws {
        guard !isSecureInputActive() else { throw InjectionError.secureInputActive }

        let snapshot = PasteboardSnapshot.capture(pasteboard)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.transientType)
        item.setData(Data(), forType: Self.concealedType)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        let ourChangeCount = pasteboard.changeCount

        do {
            try keySender.sendPaste()
        } catch {
            snapshot.restore(to: pasteboard)
            throw error
        }

        // The target app reads the pasteboard asynchronously after ⌘V; wait before restoring.
        try? await Task.sleep(for: restoreDelay)
        if pasteboard.changeCount == ourChangeCount {
            snapshot.restore(to: pasteboard)
        } else {
            Self.log.info("clipboard changed during paste; not restoring")
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter "PassthroughCleanerTests|PasteboardInjectorTests"`
Expected: PASS (6 tests).

- [ ] **Step 7: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(injection): paste at cursor with clipboard restore; passthrough cleanup"
```

---

### Task 6: Dictation controller (pipeline state machine)

**Files:**
- Modify: `SecureWisprKit/Package.swift`
- Create: `SecureWisprKit/Sources/Dictation/DictationController.swift`, `SecureWisprKit/Sources/Dictation/DictationFailure.swift`
- Test: `SecureWisprKit/Tests/DictationTests/Fakes.swift`, `SecureWisprKit/Tests/DictationTests/DictationControllerTests.swift`

**Interfaces:**
- Consumes: every protocol and type in Core.
- Produces:
  - `enum DictationFailure: Equatable { case noSpeech, secureInput, audio(String), transcription(String), injection(String); var message: String }`
  - `@MainActor final class DictationController` with:
    - `enum State: Equatable { case idle, listening, preparingModel, transcribing, cleaning, injecting, failed(DictationFailure) }`
    - `private(set) var state: State`, `private(set) var levels: [Float]`, `static let levelHistory = 24`
    - `private(set) var lastLatency: Duration?` (release → injected)
    - `var onChange: (@MainActor (State, [Float]) -> Void)?`
    - `private(set) var currentTask: Task<Void, Never>?` (await in tests)
    - `init(audio:transcriber:cleaner:injector:contextProvider:maxDuration:noticeDuration:)`
    - `func handle(_ event: HotkeyEvent)`

- [ ] **Step 1: Add targets to `Package.swift`**

Add `"Dictation"` to the library product, and:
```swift
        .target(name: "Dictation", dependencies: ["Core"]),
        .testTarget(name: "DictationTests", dependencies: ["Dictation"]),
```

- [ ] **Step 2: Write the fakes**

`Tests/DictationTests/Fakes.swift`:
```swift
import Core
import Foundation
@testable import Dictation

/// Records distinct consecutive states (a class, so @MainActor closures can mutate it under Swift 6).
@MainActor
final class StateRecorder {
    private(set) var states: [DictationController.State] = []
    func record(_ state: DictationController.State) {
        if states.last != state { states.append(state) }
    }
}

@MainActor
final class FakeAudio: AudioSource {
    var startCount = 0
    var failOnStart = false
    private var chunks: AsyncStream<AudioChunk>.Continuation?
    private var levels: AsyncStream<Float>.Continuation?

    func start() throws -> AudioCapture {
        startCount += 1
        if failOnStart { throw AudioError.noInputDevice }
        let (c, cc) = AsyncStream.makeStream(of: AudioChunk.self)
        let (l, lc) = AsyncStream.makeStream(of: Float.self)
        chunks = cc
        levels = lc
        return AudioCapture(chunks: c, levels: l)
    }

    func emit(_ samples: [Float]) { chunks?.yield(AudioChunk(samples: samples)) }
    func emitLevel(_ level: Float) { levels?.yield(level) }

    func stop() {
        chunks?.finish()
        levels?.finish()
    }
}

struct FakeError: Error {}

@MainActor
final class FakeSession: TranscriptionSession {
    var result: Result<String, FakeError> = .success("hello world")
    var finishDelay: Duration = .zero
    private(set) var appended: [[Float]] = []
    private(set) var cancelled = false

    func append(_ chunk: AudioChunk) { appended.append(chunk.samples) }

    func finish() async throws -> Transcript {
        if finishDelay > .zero { try await Task.sleep(for: finishDelay) }
        return Transcript(text: try result.get(), locale: Locale(identifier: "en_US"))
    }

    func cancel() { cancelled = true }
}

@MainActor
final class FakeTranscriber: Transcriber {
    let session = FakeSession()
    var isReady = true
    var makeDelay: Duration = .zero
    private(set) var languages: [LanguageChoice] = []

    func prepare() async throws {}

    func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        languages.append(language)
        if makeDelay > .zero { try await Task.sleep(for: makeDelay) }
        return session
    }
}

@MainActor
final class FakeCleaner: TextCleaner {
    private(set) var contexts: [DictationContext] = []

    func clean(_ text: String, context: DictationContext) async throws -> String {
        contexts.append(context)
        return "cleaned: \(text)"
    }
}

@MainActor
final class FakeInjector: TextInjector {
    var error: InjectionError?
    private(set) var injected: [String] = []

    func inject(_ text: String) async throws {
        if let error { throw error }
        injected.append(text)
    }
}
```

- [ ] **Step 3: Write the failing tests**

`Tests/DictationTests/DictationControllerTests.swift`:
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

    func makeController(maxDuration: Duration = .seconds(300)) -> DictationController {
        DictationController(
            audio: audio, transcriber: transcriber, cleaner: cleaner, injector: injector,
            contextProvider: { DictationContext(appBundleID: "com.apple.TextEdit") },
            maxDuration: maxDuration, noticeDuration: .seconds(60)
        )
    }

    @Test func happyPathTranscribesCleansAndInjects() async {
        let controller = makeController()
        let recorder = StateRecorder()
        controller.onChange = { state, _ in recorder.record(state) }

        controller.handle(.pressed)
        #expect(controller.state == .listening)
        audio.emit([0.1, 0.2])
        audio.emit([0.3])
        controller.handle(.released)
        await controller.currentTask?.value

        #expect(transcriber.session.appended == [[0.1, 0.2], [0.3]])
        #expect(transcriber.languages == [.english])
        #expect(cleaner.contexts == [DictationContext(appBundleID: "com.apple.TextEdit")])
        #expect(injector.injected == ["cleaned: hello world"])
        #expect(recorder.states == [.listening, .transcribing, .cleaning, .injecting, .idle])
        #expect(controller.lastLatency != nil)
    }

    @Test func levelsAreTrackedForTheWaveform() async {
        let controller = makeController()
        controller.handle(.pressed)
        audio.emitLevel(0.5)
        audio.emitLevel(0.7)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controller.levels == [0.5, 0.7])
        controller.handle(.released)
        await controller.currentTask?.value
    }

    @Test func cancelledDiscardsAudioAndInjectsNothing() async {
        let controller = makeController()
        controller.handle(.pressed)
        audio.emit([0.1])
        controller.handle(.cancelled)
        await controller.currentTask?.value

        #expect(controller.state == .idle)
        #expect(injector.injected.isEmpty)
        #expect(transcriber.session.cancelled)
    }

    @Test func emptyTranscriptFailsWithNoSpeech() async {
        transcriber.session.result = .success("")
        let controller = makeController()
        controller.handle(.pressed)
        controller.handle(.released)
        await controller.currentTask?.value

        #expect(controller.state == .failed(.noSpeech))
        #expect(injector.injected.isEmpty)
    }

    @Test func transcriberErrorFails() async {
        transcriber.session.result = .failure(FakeError())
        let controller = makeController()
        controller.handle(.pressed)
        controller.handle(.released)
        await controller.currentTask?.value

        guard case .failed(.transcription) = controller.state else {
            Issue.record("expected transcription failure, got \(controller.state)")
            return
        }
    }

    @Test func secureInputFailsWithSecureInput() async {
        injector.error = .secureInputActive
        let controller = makeController()
        controller.handle(.pressed)
        controller.handle(.released)
        await controller.currentTask?.value

        #expect(controller.state == .failed(.secureInput))
    }

    @Test func microphoneFailureFailsImmediately() {
        audio.failOnStart = true
        let controller = makeController()
        controller.handle(.pressed)
        guard case .failed(.audio) = controller.state else {
            Issue.record("expected audio failure, got \(controller.state)")
            return
        }
    }

    @Test func pressWhileBusyIsIgnored() async {
        transcriber.session.finishDelay = .milliseconds(100)
        let controller = makeController()
        controller.handle(.pressed)
        controller.handle(.released)
        controller.handle(.pressed)          // user presses again while transcribing
        await controller.currentTask?.value

        #expect(audio.startCount == 1)
        #expect(injector.injected.count == 1)
        #expect(controller.state == .idle)
    }

    @Test func canStartAgainAfterFailure() async {
        transcriber.session.result = .success("")
        let controller = makeController()
        controller.handle(.pressed)
        controller.handle(.released)
        await controller.currentTask?.value
        #expect(controller.state == .failed(.noSpeech))

        controller.handle(.pressed)
        #expect(controller.state == .listening)
        #expect(audio.startCount == 2)
    }

    @Test func audioBeforeSessionReadyIsStillTranscribed() async {
        transcriber.makeDelay = .milliseconds(80)
        let controller = makeController()
        controller.handle(.pressed)
        audio.emit([0.1])
        audio.emit([0.2])
        controller.handle(.released)         // before makeSession returned
        await controller.currentTask?.value

        #expect(transcriber.session.appended == [[0.1], [0.2]])
        #expect(injector.injected == ["cleaned: hello world"])
    }

    @Test func showsPreparingModelWhenTranscriberIsNotReady() async {
        transcriber.isReady = false
        let controller = makeController()
        let recorder = StateRecorder()
        controller.onChange = { state, _ in recorder.record(state) }
        controller.handle(.pressed)
        controller.handle(.released)
        await controller.currentTask?.value

        #expect(recorder.states.contains(.preparingModel))
    }

    @Test func maxDurationAutoReleases() async throws {
        let controller = makeController(maxDuration: .milliseconds(50))
        controller.handle(.pressed)
        audio.emit([0.4])
        try await Task.sleep(for: .milliseconds(150))
        await controller.currentTask?.value

        #expect(injector.injected == ["cleaned: hello world"])
        #expect(controller.state == .idle)
    }

    @Test func releaseWhenIdleIsIgnored() {
        let controller = makeController()
        controller.handle(.released)
        controller.handle(.cancelled)
        #expect(controller.state == .idle)
        #expect(audio.startCount == 0)
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter DictationControllerTests`
Expected: compile FAIL — `DictationController` not found.

- [ ] **Step 5: Implement failure type**

`Sources/Dictation/DictationFailure.swift`:
```swift
public enum DictationFailure: Equatable, Sendable {
    case noSpeech
    case secureInput
    case audio(String)
    case transcription(String)
    case injection(String)

    /// Short text for the HUD.
    public var message: String {
        switch self {
        case .noSpeech: "No speech detected"
        case .secureInput: "Can't type here"
        case .audio: "Microphone unavailable"
        case .transcription: "Couldn't transcribe"
        case .injection: "Couldn't insert text"
        }
    }
}
```

- [ ] **Step 6: Implement the controller**

`Sources/Dictation/DictationController.swift`:
```swift
import Core
import Foundation

/// Runs one dictation at a time: hotkey → audio → transcription → cleanup → injection.
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
    public var onChange: (@MainActor (State, [Float]) -> Void)?

    private let audio: any AudioSource
    private let transcriber: any Transcriber
    private let cleaner: any TextCleaner
    private let injector: any TextInjector
    private let contextProvider: @MainActor () -> DictationContext
    private let maxDuration: Duration
    private let noticeDuration: Duration

    private var context = DictationContext()
    private var sessionTask: Task<any TranscriptionSession, Error>?
    private var levelTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?

    public init(
        audio: any AudioSource,
        transcriber: any Transcriber,
        cleaner: any TextCleaner,
        injector: any TextInjector,
        contextProvider: @escaping @MainActor () -> DictationContext = { DictationContext() },
        maxDuration: Duration = .seconds(300),
        noticeDuration: Duration = .milliseconds(1_500)
    ) {
        self.audio = audio
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.injector = injector
        self.contextProvider = contextProvider
        self.maxDuration = maxDuration
        self.noticeDuration = noticeDuration
    }

    public func handle(_ event: HotkeyEvent) {
        switch event {
        case .pressed:
            guard canStart else { return }
            startListening()
        case .released:
            guard state == .listening else { return }
            currentTask = Task { await finishDictation() }
        case .cancelled:
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

    private func startListening() {
        resetTask?.cancel()
        context = contextProvider()
        let capture: AudioCapture
        do {
            capture = try audio.start()
        } catch {
            fail(.audio(String(describing: error)))
            return
        }
        levels = []
        state = .listening

        // The chunk stream buffers while the session is being created, so audio
        // captured before the transcriber is ready is still delivered, in order.
        let transcriber = transcriber
        sessionTask = Task {
            let session = try await transcriber.makeSession(language: .english)
            for await chunk in capture.chunks { session.append(chunk) }
            return session
        }
        levelTask = Task { [weak self] in
            for await level in capture.levels { self?.pushLevel(level) }
        }
        timeoutTask = Task { [weak self, maxDuration] in
            try? await Task.sleep(for: maxDuration)
            guard !Task.isCancelled else { return }
            Self.log.notice("max dictation length reached; auto-releasing")
            self?.handle(.released)
        }
    }

    private func finishDictation() async {
        let releasedAt = ContinuousClock.now
        stopCapture()
        guard let sessionTask else { return }
        self.sessionTask = nil
        if !transcriber.isReady { state = .preparingModel }

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
        levelTask = nil
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

Run: `cd SecureWisprKit && swift test --filter DictationControllerTests`
Expected: PASS (13 tests).

- [ ] **Step 8: Run the whole package suite**

Run: `cd SecureWisprKit && swift test`
Expected: all tests PASS.

- [ ] **Step 9: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(dictation): pipeline controller with streaming, cancel, timeout and failures"
```

---

### Task 7: HUD (waveform panel)

**Files:**
- Modify: `SecureWisprKit/Package.swift`
- Create: `SecureWisprKit/Sources/HUD/HUDContent.swift`, `HUDView.swift`, `WaveformView.swift`, `HUDPanelController.swift`

**Interfaces:**
- Consumes: nothing from other modules (pure UI; depends on Core only for the rule, imports nothing from it).
- Produces:
  - `enum HUDContent: Equatable { case hidden; case listening(levels: [Float]); case working(String); case message(String) }`
  - `@MainActor final class HUDPanelController { init(); func show(_ content: HUDContent) }`

- [ ] **Step 1: Add target to `Package.swift`**

Add `"HUD"` to the library product, and:
```swift
        .target(name: "HUD", dependencies: ["Core"]),
```

- [ ] **Step 2: Write the HUD**

`Sources/HUD/HUDContent.swift`:
```swift
import Observation

public enum HUDContent: Equatable, Sendable {
    case hidden
    case listening(levels: [Float])
    case working(String)
    case message(String)
}

@MainActor @Observable
final class HUDModel {
    var content: HUDContent = .hidden
}
```

`Sources/HUD/WaveformView.swift`:
```swift
import SwiftUI

/// Bars for the most recent loudness samples; newest on the right.
struct WaveformView: View {
    static let barCount = 24
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(.primary)
                    .frame(width: 3, height: 4 + CGFloat(level(at: index)) * 24)
            }
        }
        .frame(height: 28)
        .animation(.easeOut(duration: 0.08), value: levels)
    }

    private func level(at index: Int) -> Float {
        let offset = Self.barCount - levels.count
        return index >= offset ? levels[index - offset] : 0
    }
}
```

`Sources/HUD/HUDView.swift`:
```swift
import SwiftUI

struct HUDView: View {
    let model: HUDModel

    var body: some View {
        Group {
            switch model.content {
            case .hidden:
                EmptyView()
            case .listening(let levels):
                WaveformView(levels: levels)
            case .working(let text):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(text)
                }
            case .message(let text):
                Text(text)
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

`Sources/HUD/HUDPanelController.swift`:
```swift
import AppKit
import SwiftUI

/// A floating, click-through panel that never takes focus from the app being dictated into.
@MainActor
public final class HUDPanelController {
    private static let size = NSSize(width: 260, height: 60)
    private static let bottomMargin: CGFloat = 90

    private let model = HUDModel()
    private let panel: NSPanel

    public init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
    }

    public func show(_ content: HUDContent) {
        guard model.content != content else { return }
        let wasHidden = model.content == .hidden
        model.content = content
        if content == .hidden {
            panel.orderOut(nil)
            return
        }
        if wasHidden {
            positionOnActiveScreen()
            panel.orderFrontRegardless()
        }
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + Self.bottomMargin))
    }
}
```

- [ ] **Step 3: Build**

Run: `cd SecureWisprKit && swift build`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(hud): non-activating waveform panel"
```

---

### Task 8: App shell (Xcode project, wiring, permissions, menu)

**Files:**
- Create: `SecureWispr.xcodeproj/project.pbxproj`
- Create: `SecureWispr/SecureWisprApp.swift`, `AppModel.swift`, `Permissions.swift`, `MenuContent.swift`, `SettingsView.swift`, `SecureWispr.entitlements`

**Interfaces:**
- Consumes: `FnHotkeyMonitor` (Hotkey), `MicrophoneRecorder` (Audio), `AppleTranscriber` (SpeechToText), `PassthroughCleaner` (Cleanup), `PasteboardInjector` (Injection), `DictationController`, `DictationFailure` (Dictation), `HUDPanelController`, `HUDContent` (HUD), `DictationContext`, `Log` (Core).
- Produces: the runnable `SecureWispr.app`.

- [ ] **Step 1: Create the Xcode project file** (verified to build on this machine on 2026-10-08)

`SecureWispr.xcodeproj/project.pbxproj`:
```
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {
		A10000000000000000000001 /* SecureWispr.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SecureWispr.app; sourceTree = BUILT_PRODUCTS_DIR; };
		A10000000000000000000002 /* SecureWispr */ = {isa = PBXFileSystemSynchronizedRootGroup; path = SecureWispr; sourceTree = "<group>"; };
		A10000000000000000000003 /* SecureWisprKit */ = {isa = PBXFileReference; lastKnownFileType = wrapper; path = SecureWisprKit; sourceTree = "<group>"; };
		A10000000000000000000010 = {isa = PBXGroup; children = (A10000000000000000000002, A10000000000000000000003, A10000000000000000000070, A10000000000000000000011); sourceTree = "<group>"; };
		A10000000000000000000011 /* Products */ = {isa = PBXGroup; children = (A10000000000000000000001); name = Products; sourceTree = "<group>"; };
		A10000000000000000000020 /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
		A10000000000000000000021 /* Frameworks */ = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (A10000000000000000000022); runOnlyForDeploymentPostprocessing = 0; };
		A10000000000000000000022 /* SecureWisprKit in Frameworks */ = {isa = PBXBuildFile; productRef = A10000000000000000000023; };
		A10000000000000000000023 /* SecureWisprKit */ = {isa = XCSwiftPackageProductDependency; productName = SecureWisprKit; };
		A10000000000000000000024 /* Resources */ = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
		A10000000000000000000030 /* SecureWispr */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A10000000000000000000040;
			buildPhases = (A10000000000000000000020, A10000000000000000000021, A10000000000000000000024);
			buildRules = ();
			dependencies = ();
			fileSystemSynchronizedGroups = (A10000000000000000000002);
			name = SecureWispr;
			packageProductDependencies = (A10000000000000000000023);
			productName = SecureWispr;
			productReference = A10000000000000000000001;
			productType = "com.apple.product-type.application";
		};
		A10000000000000000000050 /* Project object */ = {
			isa = PBXProject;
			attributes = {BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 2700; LastUpgradeCheck = 2700; };
			buildConfigurationList = A10000000000000000000041;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (en, Base, sv);
			mainGroup = A10000000000000000000010;
			minimizedProjectReferenceProxies = 1;
			packageReferences = (A10000000000000000000060);
			preferredProjectObjectVersion = 77;
			productRefGroup = A10000000000000000000011;
			projectDirPath = "";
			projectRoot = "";
			targets = (A10000000000000000000030);
		};
		A10000000000000000000060 /* XCLocalSwiftPackageReference "SecureWisprKit" */ = {isa = XCLocalSwiftPackageReference; relativePath = SecureWisprKit; };
		A10000000000000000000070 /* Local.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Local.xcconfig; sourceTree = "<group>"; };
		A10000000000000000000042 /* Debug */ = {isa = XCBuildConfiguration; buildSettings = {
			CODE_SIGN_STYLE = Automatic; CODE_SIGN_ENTITLEMENTS = SecureWispr/SecureWispr.entitlements;
			GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_LSUIElement = YES; INFOPLIST_KEY_CFBundleDisplayName = SecureWispr;
			INFOPLIST_KEY_NSMicrophoneUsageDescription = "SecureWispr listens only while you hold the fn key, and transcribes on this Mac.";
			ENABLE_HARDENED_RUNTIME = YES; MACOSX_DEPLOYMENT_TARGET = 26.0; MARKETING_VERSION = 0.1.0; CURRENT_PROJECT_VERSION = 1;
			PRODUCT_BUNDLE_IDENTIFIER = com.zeta.SecureWispr; PRODUCT_NAME = "$(TARGET_NAME)"; SDKROOT = macosx; SWIFT_VERSION = 6.0;
			}; name = Debug; };
		A10000000000000000000043 /* Release */ = {isa = XCBuildConfiguration; buildSettings = {
			CODE_SIGN_STYLE = Automatic; CODE_SIGN_ENTITLEMENTS = SecureWispr/SecureWispr.entitlements;
			GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_LSUIElement = YES; INFOPLIST_KEY_CFBundleDisplayName = SecureWispr;
			INFOPLIST_KEY_NSMicrophoneUsageDescription = "SecureWispr listens only while you hold the fn key, and transcribes on this Mac.";
			ENABLE_HARDENED_RUNTIME = YES; MACOSX_DEPLOYMENT_TARGET = 26.0; MARKETING_VERSION = 0.1.0; CURRENT_PROJECT_VERSION = 1;
			PRODUCT_BUNDLE_IDENTIFIER = com.zeta.SecureWispr; PRODUCT_NAME = "$(TARGET_NAME)"; SDKROOT = macosx; SWIFT_VERSION = 6.0;
			}; name = Release; };
		A10000000000000000000044 /* Debug */ = {isa = XCBuildConfiguration; baseConfigurationReference = A10000000000000000000070; buildSettings = {
			SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 26.0; ALWAYS_SEARCH_USER_PATHS = NO; ONLY_ACTIVE_ARCH = YES;
			DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
			}; name = Debug; };
		A10000000000000000000045 /* Release */ = {isa = XCBuildConfiguration; baseConfigurationReference = A10000000000000000000070; buildSettings = {
			SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 26.0; ALWAYS_SEARCH_USER_PATHS = NO; SWIFT_COMPILATION_MODE = wholemodule;
			}; name = Release; };
		A10000000000000000000040 = {isa = XCConfigurationList; buildConfigurations = (A10000000000000000000042, A10000000000000000000043); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
		A10000000000000000000041 = {isa = XCConfigurationList; buildConfigurations = (A10000000000000000000044, A10000000000000000000045); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
	};
	rootObject = A10000000000000000000050;
}
```

`SecureWispr/SecureWispr.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.device.audio-input</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 2: Permissions**

`SecureWispr/Permissions.swift`:
```swift
import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics

enum Permission: CaseIterable, Identifiable {
    case microphone
    case inputMonitoring
    case accessibility

    var id: Self { self }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        }
    }

    /// Why we need it, shown in the menu.
    var reason: String {
        switch self {
        case .microphone: "to hear you while fn is held"
        case .inputMonitoring: "to notice the fn key"
        case .accessibility: "to paste text where your cursor is"
        }
    }

    private var settingsAnchor: String {
        switch self {
        case .microphone: "Privacy_Microphone"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .accessibility: "Privacy_Accessibility"
        }
    }

    @MainActor var isGranted: Bool {
        switch self {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .inputMonitoring: CGPreflightListenEventAccess()
        case .accessibility: AXIsProcessTrusted()
        }
    }

    /// Shows the system prompt (first time only; afterwards macOS requires System Settings).
    @MainActor func request() {
        switch self {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    @MainActor func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 3: App model (wiring)**

`SecureWispr/AppModel.swift`:
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
import SpeechToText

@MainActor @Observable
final class AppModel {
    private static let log = Log.logger("App")

    private(set) var missingPermissions: [Permission] = []
    private(set) var dictationState: DictationController.State = .idle

    @ObservationIgnored private let hud = HUDPanelController()
    @ObservationIgnored private let hotkey = FnHotkeyMonitor()
    @ObservationIgnored private let transcriber = AppleTranscriber()
    @ObservationIgnored private let controller: DictationController
    @ObservationIgnored private var hotkeyTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init() {
        controller = DictationController(
            audio: MicrophoneRecorder(),
            transcriber: transcriber,
            cleaner: PassthroughCleaner(),
            injector: PasteboardInjector(),
            contextProvider: {
                DictationContext(appBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            }
        )
        controller.onChange = { [weak self] state, levels in
            guard let self else { return }
            if dictationState != state { dictationState = state }
            hud.show(Self.hudContent(for: state, levels: levels))
        }
    }

    func start() {
        for permission in Permission.allCases where !permission.isGranted {
            permission.request()
        }
        Task { [transcriber] in try? await transcriber.prepare() }
        // TCC has no change notification; poll until everything is granted.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshPermissions()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

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
            Self.log.error("could not start fn event tap: \(String(describing: error), privacy: .public)")
            return
        }
        hotkeyTask = Task { [weak self] in
            guard let self else { return }
            for await event in hotkey.events {
                guard missingPermissions.isEmpty else { continue }
                controller.handle(event)
            }
        }
    }

    static func hudContent(for state: DictationController.State, levels: [Float]) -> HUDContent {
        switch state {
        case .idle: .hidden
        case .listening: .listening(levels: levels)
        case .preparingModel: .working("Downloading speech model…")
        case .transcribing, .cleaning, .injecting: .working("Transcribing…")
        case .failed(let failure): .message(failure.message)
        }
    }
}
```

- [ ] **Step 4: App entry, menu, settings**

`SecureWispr/SecureWisprApp.swift`:
```swift
import SwiftUI

@main
struct SecureWisprApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        model.start()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
        Settings {
            SettingsView()
        }
    }
}
```

`SecureWispr/MenuContent.swift`:
```swift
import SwiftUI

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Text(model.statusLine)
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

`SecureWispr/SettingsView.swift`:
```swift
import SwiftUI

/// M1 placeholder: shows the fixed configuration. Real controls arrive in M2.
struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Speech engine", value: "Apple SpeechAnalyzer (on-device)")
            LabeledContent("Language", value: "English")
            LabeledContent("Push-to-talk", value: "Hold fn")
            LabeledContent("Cleanup", value: "Off (arrives in M3)")
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
    }
}
```

- [ ] **Step 5: Add all modules to the library product**

Confirm `Package.swift`'s product lists every module:
```swift
        .library(name: "SecureWisprKit",
                 targets: ["Core", "Hotkey", "Audio", "SpeechToText", "Cleanup", "Injection", "Dictation", "HUD"]),
```

- [ ] **Step 6: Build the app**

Run: `xcodebuild -project SecureWispr.xcodeproj -scheme SecureWispr -configuration Debug -derivedDataPath build -allowProvisioningUpdates build 2>&1 | grep -E "error|BUILD"`
Expected: `** BUILD SUCCEEDED **`

Run: `codesign -dv build/Build/Products/Debug/SecureWispr.app 2>&1 | grep -E "Authority|TeamIdentifier"`
Expected: `Authority=Apple Development: …` and your team id (not `adhoc`).

- [ ] **Step 7: Launch and grant permissions**

Run: `open build/Build/Products/Debug/SecureWispr.app`
Expected: waveform/⚠ icon in the menu bar; macOS prompts for Microphone, Input Monitoring, Accessibility. Grant each (the menu's "Allow …" items open the right Settings pane). Within ~2 s of granting Input Monitoring the menu reads "Ready — hold fn to dictate".

- [ ] **Step 8: Commit**

```bash
git add SecureWispr.xcodeproj SecureWispr SecureWisprKit/Package.swift
git commit -m "feat(app): menu-bar shell wiring the dictation pipeline"
```

---

### Task 9: M1 acceptance (manual)

**Files:** none (records results in the commit message / PR).

- [ ] **Step 1: Core loop in real apps.** Hold fn, say "This is a test of SecureWispr", release — in TextEdit, a Safari text field, Terminal, VS Code, Messages/Slack. Expected: text appears in each; HUD shows waveform while held, "Transcribing…" briefly, then hides; the target app keeps focus throughout.

- [ ] **Step 2: Latency.** Run `log stream --predicate 'subsystem == "SecureWispr" AND category == "Dictation"' --info` while dictating a ~10 s sentence. Expected: `release→inject` under 1000 ms.

- [ ] **Step 3: Clipboard and safety.**
  - Copy an image in Preview, dictate, then paste with ⌘V → the image pastes (restored).
  - fn+← / fn+→ in a text field → cursor moves, no HUD, no dictation.
  - Quick fn tap → nothing happens.
  - Focus a password field (e.g. a login page), dictate → HUD shows "Can't type here"; ⌘V afterwards does not paste the dictated words.
  - Hold fn in silence for 2 s → "No speech detected".

- [ ] **Step 4: Device change (Review Focus #5).** Start a dictation on the built-in mic, connect/disconnect AirPods mid-sentence, release. Expected: no crash; either the captured part is pasted or "No speech detected". The next dictation works on the new device.

- [ ] **Step 5: Package tests.** Run: `cd SecureWisprKit && swift test` — all PASS.

- [ ] **Step 6: Commit / tag**

```bash
git commit --allow-empty -m "chore: M1 acceptance passed

Latency: <measured> ms for ~10 s utterance. Apps verified: TextEdit, Safari, Terminal, VS Code, Messages."
git tag m1-skeleton
```
