# SecureWispr — M2 Bilingual + Engines Design

Date: 2026-10-08
Status: Draft for review
Builds on: `2026-10-08-securewispr-m1-skeleton-design.md` (architecture, module rules, M1 behavior)

## 1. Intent

Make SecureWispr usable daily in **Swedish and English**, with the language
chosen the way the user prefers, and let the user optionally switch the speech
engine to **Parakeet** by downloading it from Settings.

**Stated by user:** Apple SpeechAnalyzer stays the default engine; Parakeet is
downloadable in Settings; language modes Auto-detect, Toggle, and Per-language
hotkeys, all selectable in Settings; Toggle switches via menu bar + quick fn+⇧
tap; Parakeet downloads only on an explicit button press; fold M1 review minors
a–e into M2.

**Assumed:** Auto-detect is the default mode; English is the default primary
language; the user dictates one language per utterance (mid-sentence
code-switching is out of scope).

**Success:** In each mode the right language is transcribed; Auto-detect picks
correctly on ≥ 9 of 10 of the user's own sentences (5 SV + 5 EN); release-to-text
stays < 1 s with Apple engine for a ~10 s utterance; Parakeet can be downloaded,
used and removed from Settings; no network access other than the Parakeet
download button.

## 2. Verified facts (probed on the dev machine, 2026-10-08)

Synthetic speech (`say -v Samantha` / `say -v Alva`), mean `transcriptionConfidence`:

| Clip | SpeechTranscriber en_US | DictationTranscriber en_US | DictationTranscriber sv_SE |
|---|---|---|---|
| English sentence | **0.978** (correct) | 0.984 | 0.273 (wrong) |
| Swedish sentence | 0.404 (gibberish) | 0.534 | **0.777** (correct, punctuated) |

Each pass took 0.1–0.5 s. Swedish `DictationTranscriber` assets are now
installed. Conclusion: SpeechTranscriber(en) + DictationTranscriber(sv) with a
confidence comparison separates the languages with a wide margin.

FluidAudio (Apache-2.0, SPM `github.com/FluidInference/FluidAudio`, v0.12.x):
`AsrModels.downloadAndLoad(version: .v3)`, `AsrManager.loadModels`,
`AsrManager.transcribe([Float])` on 16 kHz mono; returns text and detected
language. Parakeet TDT 0.6B v3 weights are MIT/Apache-2.0.

## 3. Settings

New `Settings` model, persisted in `UserDefaults` (suite: standard), observed by
the app and passed into the pipeline as plain values.

| Key | Type | Values | Default |
|---|---|---|---|
| `engine` | `SpeechEngine` | `.apple`, `.parakeet` | `.apple` |
| `languageMode` | `LanguageMode` | `.autoDetect`, `.toggle`, `.perLanguageHotkeys` | `.autoDetect` |
| `primaryLanguage` | `Language` | `.english`, `.swedish` | `.english` |
| `toggleLanguage` | `Language` | current language in Toggle mode | `.english` |
| `lastDetectedLanguage` | `Language` | Auto-detect tie-break | `.english` |

Unknown/corrupt stored values fall back to defaults.

Settings window (SwiftUI `Form`, grouped):
- **Engine:** picker Apple / Parakeet. Parakeet row shows a model card:
  `Not downloaded — Download (≈ N MB)` → `Downloading… NN%` (with Cancel) →
  `Ready — Remove`; `Failed — Retry` with the error text. Choosing Parakeet
  while not downloaded keeps the choice but shows "Download required".
- **Language:** mode picker; primary-language picker (shown for Per-language
  hotkeys; for Toggle it shows the current language with a switch).
- **Push-to-talk:** read-only description of fn / fn+⇧ behavior for the selected mode.

Menu bar: shows current mode/language (e.g. "Auto-detect", "Toggle: Svenska")
and, in Toggle mode, a "Switch to English/Svenska" item.

## 4. Hotkeys and language routing

### 4.1 Hotkey events (changed)

`FnKeyStateMachine` additionally tracks whether ⇧ was held at fn-down:

```swift
public enum HotkeyEvent: Sendable, Equatable {
    case pressed(shifted: Bool)   // fn down (shifted = ⇧ held at that moment)
    case released                 // fn up after ≥ minimumHold, uninterrupted
    case tapped(shifted: Bool)    // fn up before minimumHold (was: .cancelled)
    case cancelled                // another key went down while fn held
}
```

- ⇧ itself does **not** count as "another key" (it arrives as `flagsChanged`, not `keyDown`).
- `FnHotkeyMonitor` resets the state machine whenever it re-enables a disabled
  tap (minor c), and tracks ⇧ from the `maskShift` flag on fn's `flagsChanged`.

### 4.2 Language routing (new, pure)

```swift
public enum Language: String, Sendable, CaseIterable { case english, swedish }
public enum LanguageChoice: Sendable, Equatable { case fixed(Language), automatic }

public enum LanguageRouter {
    static func choice(mode: LanguageMode, shifted: Bool,
                       primary: Language, toggle: Language) -> LanguageChoice
}
```

| Mode | fn | fn+⇧ |
|---|---|---|
| Auto-detect | `.automatic` | `.automatic` |
| Toggle | `.fixed(toggle)` | `.fixed(toggle)` |
| Per-language hotkeys | `.fixed(primary)` | `.fixed(other(primary))` |

Quick taps: in **Toggle** mode, `.tapped(shifted: true)` flips `toggleLanguage`
and the HUD flashes "🇸🇪 Svenska" / "🇬🇧 English" for 1 s. Every other tap is a
no-op (the controller discards it like M1's short-hold cancel).

### 4.3 Controller commands (changed)

`DictationController.handle` takes commands instead of hotkey events, so it is
unaware of modes:

```swift
public enum DictationCommand: Sendable, Equatable {
    case start(LanguageChoice)
    case finish
    case cancel
}
```

The app maps: `pressed(s)` → `start(router(...))`; `released` → `finish`;
`tapped`/`cancelled` → `cancel` (+ toggle flip as above). Permission gating
applies only to `start` (minor d).

## 5. Engines

### 5.1 Apple engine

`AppleTranscriber.makeSession(language:)`:
- `.fixed(.english)` → `SpeechTranscriber(en_US)` session (M1 behavior).
- `.fixed(.swedish)` → `DictationTranscriber(sv_SE, contentHints: [.shortForm],
  transcriptionOptions: [.punctuation])` session.
- `.automatic` → `AutoDetectSession` wrapping one English and one Swedish
  session; `append` fans each chunk out to both; `finish` awaits both
  concurrently and returns `LanguagePicker.pick`.

Both Apple sessions request `attributeOptions: [.transcriptionConfidence]` and
set `Transcript.confidence` to the mean confidence over result runs (nil if none).

`prepare()` installs assets for both modules (en_US SpeechTranscriber, sv_SE
DictationTranscriber); `isReady` is true when both are installed.

### 5.2 LanguagePicker (new, pure)

```swift
enum LanguagePicker {
    static let minimumMargin = 0.15
    static func pick(_ candidates: [Transcript], fallback: Language) -> Transcript
}
```

- Ignore candidates with empty text.
- If one candidate remains, return it.
- Highest confidence wins if it beats the runner-up by ≥ `minimumMargin`.
- Otherwise return the candidate whose language is `fallback`.
- A candidate with `confidence == nil` ranks below any with a value.

The app passes `lastDetectedLanguage` as `fallback` and stores the winner's
language back into it after each successful auto-detect dictation.

`Transcript` gains `language: Language?` (set by every engine; Parakeet maps its
detected code, unknown codes → nil).

### 5.3 Parakeet engine (new module `Parakeet`, depends on Core + FluidAudio)

- `ParakeetModelStore` (@MainActor, observable state):
  `notDownloaded | downloading(progress: Double) | ready | failed(String)`;
  `download()`, `cancelDownload()`, `remove()`, `isInstalled`. Models live in
  `~/Library/Application Support/SecureWispr/Models/parakeet-tdt-0.6b-v3/`
  (FluidAudio's download directory parameter if it has one; otherwise its
  default cache, and Remove deletes that directory). Only `download()` touches
  the network.
- `ParakeetTranscriber: Transcriber` — `isReady` = model loaded;
  `prepare()` loads from disk (never downloads; throws `.modelNotInstalled`).
  Sessions buffer `[Float]` in `append`, call `transcribe` in `finish`, ignore
  the `LanguageChoice`, and report detected language.
- FluidAudio is wrapped behind a small `SpeechRecognizerBackend` protocol so
  sessions are unit-testable with a fake.

### 5.4 Engine selection and fallback

The app builds the controller with a transcriber **provider** closure
(`@MainActor () -> any Transcriber`) evaluated at each `start`:
- `engine == .parakeet` and model ready → Parakeet.
- `engine == .parakeet` and not ready/failed to load → Apple, and the menu shows
  "Parakeet unavailable — using Apple".
- otherwise Apple.

## 6. HUD

- `HUDContent.listening(levels:badge:)` — badge text `EN`, `SV` or `AUTO`
  (Parakeet: `AUTO`).
- `HUDContent.working(_:)` unchanged ("Transcribing…").
- After an **Auto-detect** dictation is pasted, the HUD shows the winning
  language ("🇸🇪 Svenska" / "🇬🇧 English") for 0.8 s, so a wrong pick is noticed
  immediately. The winner is only known once both branches finish, which is why
  it is shown after pasting rather than while transcribing.
- `HUDContent.message(_:)` is reused for both the winner flash and the toggle
  flash ("🇸🇪 Svenska").

Note: M1's `LanguageChoice.english` becomes `.fixed(.english)`; `Transcript`
gains `language`.

## 7. M1 review minors folded in

| # | Fix |
|---|---|
| a | `AppleTranscriptionSession` cancels collector and analyzer if `start` or `finalize` throws |
| b | Release tail: on `finish`, keep capturing 150 ms before stopping the recorder |
| c | `FnHotkeyMonitor` resets `FnKeyStateMachine` when re-enabling a disabled tap |
| d | Only `start` is blocked by missing permissions; `finish`/`cancel` always pass |
| e | Hotkey start failure logged once per launch; permission poll comment fixed |

## 8. Error handling

| Situation | Behavior |
|---|---|
| Swedish assets missing at dictation time (Apple, SV or Auto) | Same as M1: install on launch; `.preparingModel` state shows "Downloading speech model…" |
| One Auto-detect branch throws | Use the other branch's transcript; log the error |
| Both branches empty | "No speech detected" (M1 behavior) |
| Parakeet download fails / cancelled | Card shows Failed/Not downloaded; engine stays selected; Apple used meanwhile |
| Parakeet model fails to load | Fallback to Apple + menu notice; logged |
| Corrupt/unknown settings values | Defaults |

## 9. Testing

- **Unit:** `LanguageRouter` (3 modes × shifted), `LanguagePicker` (clear win,
  within margin → fallback, empty texts, nil confidence), `FnKeyStateMachine`
  (shift at fn-down, `tapped(shifted:)`, ⇧ not interrupting, reset), settings
  round-trip + corrupt values, `AutoDetectSession` with fake sessions
  (fan-out, one branch failing), Parakeet session with fake backend, controller
  with commands (incl. minor d gating in app mapping helper), release tail (b)
  with fake audio, session cleanup on error (a).
- **Integration (real Apple models):** Swedish clip via `say -v Alva` through
  `.fixed(.swedish)`; Auto-detect picks EN for the English clip and SV for the
  Swedish clip. Parakeet integration test runs only when the model is installed.
- **Manual acceptance:** user's own voice: each mode with SV and EN; Auto-detect
  on 5 SV + 5 EN sentences (≥ 9 correct); toggle via fn+⇧ tap and menu;
  Parakeet download → dictate SV/EN → Remove; network check that nothing is
  fetched except during Download.
