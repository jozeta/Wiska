# SecureWispr — Architecture & M1 Skeleton Design

Date: 2026-10-08
Status: Draft for review

## 1. Intent

A private, fully on-device clone of Wispr Flow for macOS: hold a key, speak
Swedish or English, release, and cleaned-up text appears wherever the cursor is.
Audio and text never leave the machine.

**Stated by user:** push-to-talk dictation; Swift + local models; Apple
SpeechAnalyzer as default engine, Parakeet downloadable in Settings; optional
cleanup model (punctuation, cut filler words); Swedish + English; hold `fn`;
history, personal dictionary, app-aware tone, voice commands, onboarding/stats;
grow into a proper branded macOS app.

**Assumed:** personal daily use first (not App Store), macOS 26+ only (required
by SpeechAnalyzer), developed on Apple M5 Pro / 64 GB / macOS 27.

**Success for the whole product:** release-to-text latency feels instant
(target < 1 s for a 10 s clip), works in any text field, SV and EN both usable
daily, nothing sent over the network except optional model downloads.

## 2. Verified platform facts (probed on target machine, 2026-10-08)

| Capability | English | Swedish |
|---|---|---|
| `SpeechTranscriber` (SpeechAnalyzer module) | supported, installed | **not supported** |
| `DictationTranscriber` (SpeechAnalyzer module) | supported, installed | supported (`sv_SE`), asset download needed |
| Foundation Models (`SystemLanguageModel.default`) | supported | supported |
| Parakeet TDT 0.6B v3 via FluidAudio | supported | supported, auto language detection |

## 3. Architecture

### 3.1 Components

The app is split into six components. Each one is a module in the local Swift
package `SecureWisprKit` (except the Shell, which is the app target plus the
`HUD` module).

| Component | Module | Responsibility |
|---|---|---|
| Shell | app target `SecureWispr` + `HUD` | Menu-bar app, Settings window, `DictationController`, floating waveform HUD while talking |
| Hotkey | `Hotkey` | `CGEventTap` watching `fn`; emits `pressed` / `released` / `cancelled` |
| Audio | `Audio` | Mic capture via `AVAudioEngine`; emits 16 kHz mono buffers and ~30 Hz level samples |
| Speech to text | `SpeechToText` | `Transcriber` protocol; Apple and Parakeet implementations |
| Cleanup | `Cleanup` | Optional `TextCleaner`: punctuation, filler/false-start removal |
| Injection | `Injection` | Put final text at the cursor (pasteboard + synthetic ⌘V, restore pasteboard) |

Rule: modules depend only on protocols in a tiny `Core` module (shared types
like `Transcript`, `DictationContext`), never on each other. Only the Shell
wires concrete implementations together.

### 3.2 Data flow

```
Hotkey ──pressed──► Audio.start ──levels──► HUD waveform
                        │ buffers (streamed live)
                        ▼
                  TranscriptionSession.append
Hotkey ──released─► Audio.stop ─► session.finish() ─► Cleanup ─► Injection
```

Transcription is streamed while the user speaks, so on release only the tail
needs finalizing — this is what keeps latency low.

### 3.3 Key interfaces (Core)

```swift
protocol Transcriber {
    func makeSession(language: LanguageChoice) async throws -> TranscriptionSession
}
protocol TranscriptionSession {
    func append(_ buffer: AVAudioPCMBuffer)
    func finish() async throws -> Transcript      // text, locale, confidence
    func cancel()
}
protocol TextCleaner {
    func clean(_ text: String, context: DictationContext) async throws -> String
}
protocol TextInjector {
    func inject(_ text: String) async throws
}
```

Batch engines (Parakeet) implement the same session by buffering in `append`
and running in `finish`.

### 3.4 Shell: DictationController state machine

`idle → listening → transcribing → cleaning → injecting → idle`, with
`cancelled` and `failed(reason)` returning to `idle`. Only the controller
mutates state; the HUD and menu-bar icon observe it (`@Observable`).

### 3.5 Project structure

```
SecureWispr/
  SecureWispr.xcodeproj         app target: Shell (menu bar, Settings, wiring)
  SecureWispr/                  app sources, Info.plist, entitlements, assets
  SecureWisprKit/               local Swift package
    Sources/Core, Hotkey, Audio, SpeechToText, Cleanup, Injection, HUD
    Tests/…                     `swift test`-runnable unit tests
  docs/superpowers/specs/
```

App is **not sandboxed** (a global `CGEventTap` and posting key events into
other apps are incompatible with the sandbox). Hardened runtime on, signed with
the local development identity so TCC permissions persist across rebuilds.
Deployment target: macOS 26.0.

## 4. Milestones

| # | Milestone | Scope |
|---|---|---|
| **M1** | Skeleton | All six components, thin: hold `fn` → record → Apple `SpeechTranscriber` (en_US) → passthrough cleanup → paste. Waveform HUD. Permission status + prompts in menu. |
| M2 | Bilingual + engines | `DictationTranscriber` sv_SE; language modes (Auto-detect default / Toggle / Per-language hotkeys, `fn` and `fn+⇧`); Parakeet download + selection in Settings; asset download UI |
| M3 | Cleanup | Foundation Models cleaner (toggle, default on); app-aware tone; voice commands ("new line"/"ny rad", "scratch that"); typing fallback for paste-hostile apps |
| M4 | Memory | Dictation history (SwiftData, retention setting); personal dictionary feeding transcriber hints and cleanup prompt |
| M5 | Polish & brand | Onboarding/permission walkthrough, stats, double-tap hands-free lock (off by default), app icon, branded HUD and visual identity |

Each milestone after M1 gets its own spec → plan → implementation cycle.

### 4.1 Language modes (M2, recorded here for architectural fit)

- **Auto-detect (default):** two Apple sessions run in parallel on the same
  buffers — `SpeechTranscriber(en_US)` and `DictationTranscriber(sv_SE)`; the
  higher-confidence transcript wins. Implemented as a composite `Transcriber`,
  so the controller is unaware of it.
- **Toggle:** one active language, switched from menu bar/shortcut; HUD shows SV/EN.
- **Per-language hotkeys:** `fn` = primary language, `fn+⇧` = the other.
- When Parakeet is the selected engine, language mode is ignored (it auto-detects).

## 5. M1 detailed design

### 5.1 Scope

In: menu-bar app; hold-`fn` capture; mic recording; English transcription with
`SpeechTranscriber(en_US)`; `PassthroughCleaner`; pasteboard injection; waveform
HUD; permission checks for Microphone, Input Monitoring, Accessibility with
"Open System Settings" actions in the menu; minimal Settings window (placeholder
pane showing engine = Apple, language = English).

Out (later milestones): Swedish, Parakeet, cleanup model, history, dictionary,
onboarding flow, branding, double-tap lock.

### 5.2 Component behavior

**Hotkey.** Listen-only `CGEventTap` on `flagsChanged` + `keyDown`. `fn` pressed
= `maskSecondaryFn` set with keycode 63. Rules:
- Holds shorter than 250 ms → `cancelled` (accidental tap).
- Any other `keyDown` while `fn` is held → `cancelled` (user is using an fn
  shortcut such as fn+arrow).
- On `tapDisabledByTimeout` / `tapDisabledByUserInput` → re-enable the tap.
- User must set System Settings → Keyboard → "Press 🌐 to" → Do Nothing; the
  menu shows a hint about this.

**Audio.** `AVAudioEngine` input tap; convert to 16 kHz mono Float32 with
`AVAudioConverter`; deliver buffers to the active session; compute RMS level
per buffer, published ~30 Hz to the HUD. Engine prepared at launch, started on
`pressed` to keep start-up latency low. Hard cap of 5 minutes per dictation.

**Speech to text.** `AppleTranscriber` builds a `SpeechAnalyzer` with
`SpeechTranscriber(locale: en_US)`, feeds an `AsyncStream<AnalyzerInput>` from
`append`, and on `finish()` calls `finalizeAndFinishThroughEndOfInput()` and
concatenates final results. Before first use, verifies assets via
`AssetInventory` and installs if missing.

**Cleanup.** `PassthroughCleaner` returns input trimmed of surrounding
whitespace. The real cleaner lands in M3 behind the same protocol.

**Injection.** `PasteboardInjector`:
1. Snapshot all general-pasteboard items and types.
2. Write text plus `org.nspasteboard.TransientType` and
   `org.nspasteboard.ConcealedType` markers so clipboard managers ignore it.
3. Post ⌘V via `CGEvent` (keycode 9, `.maskCommand`).
4. After ~300 ms, restore the snapshot only if `changeCount` is still ours.

**HUD.** Borderless, non-activating `NSPanel` (never steals focus), bottom
center of the screen that contains the frontmost window, showing a live
waveform from level samples while listening and a spinner while
transcribing/injecting. Plain styling in M1; branded in M5.

### 5.3 Error handling

| Situation | Behavior |
|---|---|
| Missing Microphone / Input Monitoring / Accessibility | Menu-bar icon shows warning badge; menu lists missing permission with "Open System Settings"; dictation disabled until granted |
| Event tap disabled by system | Re-enable automatically; log it |
| Speech assets not installed | Trigger install on launch; HUD shows "Downloading speech model…" if user dictates before done |
| Empty transcript (silence) | Nothing injected; HUD briefly shows "No speech detected" |
| Secure input active (`IsSecureEventInputEnabled`, e.g. password field) | Do not inject and do not leave it on the pasteboard (privacy); text is discarded; HUD shows "Can't type here" |
| Transcriber throws | State → `failed`; HUD shows short error; logged |
| Hold > 5 min | Auto-release: stop and transcribe what was captured |

Logging via `os.Logger` (subsystem `SecureWispr`). Transcript text is logged
only with `.private` privacy, so it is redacted in system logs.

### 5.4 Testing

- **Unit (`swift test`, no app launch):**
  - `DictationController` state machine with fake Hotkey/Audio/Transcriber/
    Cleaner/Injector: happy path, short-tap cancel, fn-shortcut cancel,
    empty transcript, transcriber failure, secure-input refusal.
  - Audio: RMS level calculation; resampling produces 16 kHz mono.
  - Injection: snapshot/restore round-trip on a private named `NSPasteboard`;
    restore skipped when `changeCount` changed.
- **Integration:** `AppleTranscriber` transcribes a fixture generated with
  `say -o hello.aiff "hello world this is a test"`; assert it contains "hello world".
- **Manual checklist (M1 acceptance):** dictate into TextEdit, Safari text
  field, Slack/Messages, Terminal, VS Code; verify fn+arrow does not trigger;
  verify clipboard contents are restored; verify HUD never steals focus.

### 5.5 M1 acceptance criteria

1. Holding `fn`, saying an English sentence, and releasing types it into the
   focused app in TextEdit, a browser, and Terminal.
2. Release-to-text < 1 s for a ~10 s utterance on the dev machine.
3. Prior clipboard content is intact afterwards.
4. Missing permissions are clearly reported in the menu with a path to fix.
5. `swift test` passes for `SecureWisprKit`.
