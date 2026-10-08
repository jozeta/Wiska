# Wiska — Per-Language Speech Engines Design

Date: 2026-10-08
Status: Draft for review
Builds on: M1–M5 specs, cleanup pass (main @ bfffe20)

## 1. Intent

Let the user pick the speech engine for each supported language, so each language
gets the engine that suits it.

**Stated by user:** for each language the app supports, choose the engine; an
option to use the same engine for all languages or choose per language. In
Auto-detect with mixed engines: run both, and decide by the language of
Parakeet's text.

**Assumed:** the motivating case is English → Parakeet (fast, as accurate as
Apple) and Swedish → Apple (accurate, uses Dictionary hints). An engine that isn't
ready falls back to Apple, as today. Existing settings carry over unchanged.

**Success:** with English → Parakeet and Swedish → Apple, in every language mode
(including Auto-detect, which the user uses):
- English dictations are as fast as with Parakeet today (~50–160 ms after release);
- Swedish dictations come out of Apple and match its accuracy;
- Settings, the menu status line and History all say which engine was used, and
  agree with what actually ran.

## 2. Verified facts (benchmarked 2026-10-08, synthesized `say` voices)

| | Finish after release | English | Swedish |
|---|---|---|---|
| Parakeet | 46–163 ms | as good as Apple | weaker ("onsra", "gicker genom", "en väntat") |
| Apple, fixed language | 47–313 ms | good | correct on all samples |
| Apple, auto-detect (both languages) | 67–719 ms | good | correct |

- Parakeet ignores the personal Dictionary; Apple Swedish (DictationTranscriber)
  uses it as contextual hints.
- Parakeet doesn't report a language; Wiska guesses it from the text with
  `NLLanguageRecognizer` constrained to English/Swedish (`LanguageGuess`).

## 3. Settings

| Key | Type | Default | Meaning |
|---|---|---|---|
| `engine` (existing) | `SpeechEngine` | `.apple` | The engine in *Same for all* mode |
| `engineMode` (new) | `EngineMode` = `.same` / `.perLanguage` | `.same` | Which of the two applies |
| `englishEngine` (new) | `SpeechEngine` | value of `engine` when first read | English engine in *Per language* mode |
| `swedishEngine` (new) | `SpeechEngine` | value of `engine` when first read | Swedish engine in *Per language* mode |

- Stored per language as separate keys (two languages; no dictionary-in-defaults).
- Missing per-language keys default to the current `engine`, so switching to
  *Per language* starts from what the user already has. The user's current
  `engine = parakeet` keeps working as *Same for all: Parakeet*.
- `SettingsStore.engine(for: Language) -> SpeechEngine` returns the effective
  engine for a language in either mode.

## 4. Choosing the engine: `EngineRouter`

A pure function in `Core` (no I/O, fully unit-tested):

```swift
enum EnginePlan: Equatable {
    case single(SpeechEngine)                   // one engine, given language choice
    case hybrid(apple: Set<Language>)           // Parakeet + Apple sessions for these languages
}

EngineRouter.plan(choice: LanguageChoice,
                  engines: (Language) -> SpeechEngine,
                  parakeetReady: Bool) -> EnginePlan
```

| Language choice | Engines | Parakeet ready | Plan |
|---|---|---|---|
| `.fixed(L)` | engine(L) = Apple | any | `.single(.apple)` |
| `.fixed(L)` | engine(L) = Parakeet | yes | `.single(.parakeet)` |
| `.fixed(L)` | engine(L) = Parakeet | no | `.single(.apple)` |
| `.automatic` | all Apple | any | `.single(.apple)` (today's two-language auto-detect) |
| `.automatic` | all Parakeet | yes | `.single(.parakeet)` |
| `.automatic` | mixed | yes | `.hybrid(apple: languages assigned to Apple)` |
| `.automatic` | any Parakeet | no | `.single(.apple)` |

`AppModel.activeTranscriber()` asks the router and returns the Apple or Parakeet
transcriber, or a `HybridTranscriber` for `.hybrid`. If Parakeet is chosen but not
ready, the app keeps warming it up, as today.

The "not ready" note, the HUD badge and the menu status line use the same router,
so they describe what will actually run:
- "Parakeet is selected but not ready" shows when any language is set to
  Parakeet and it isn't ready;
- the status line names the engines, e.g. "Auto-detect · 🇬🇧 Parakeet · 🇸🇪 Apple".

## 5. Hybrid transcription (Auto-detect, mixed engines)

`HybridTranscriber` (module `Dictation`, which already sees all engines through
the `Transcriber` protocol) makes a `HybridSession`:

- **Start:** one Parakeet session, plus one Apple session per language in
  `apple` (fixed to that language). If an Apple session can't start, the hybrid
  continues with Parakeet only. If Parakeet can't start, it falls back to Apple's
  two-language auto-detect.
- **Append:** every audio chunk goes to all sessions.
- **Finish:**
  1. Finish Parakeet and read the language on its transcript (Parakeet sessions
     already set it with `LanguageGuess`), so the hybrid needs nothing from the
     Parakeet module beyond the `Transcriber` protocol.
  2. No clear guess (empty text or a very short phrase like "ok") → use the
     language of the user's last dictation (`lastDetectedLanguage`, injected as a
     closure like `AppleTranscriber`'s `fallbackLanguage`).
  3. Language assigned to Parakeet → return Parakeet's transcript and cancel the
     Apple sessions without waiting.
  4. Language assigned to Apple → finish that Apple session and return its
     transcript (language set to that language). If it fails or returns empty
     text, return Parakeet's transcript instead.
  5. Parakeet failed → finish the Apple sessions and return the most confident
     one (`LanguagePicker`), as today's auto-detect does.
- **Cancel:** cancels every session.

The transcript records which engine produced it (new `Transcript.engine`), so
History's `engine` field is correct for hybrid dictations instead of always
reading the controller's transcriber.

## 6. Settings UI

"Speech engine" section:

```
Engines        ( Same for all | Per language )
  Same for all:   Engine      [Parakeet ▾]
  Per language:   🇬🇧 English  [Parakeet ▾]
                  🇸🇪 Svenska  [Apple    ▾]
[Parakeet card — download / ready / remove, unchanged]
Parakeet is selected but not ready — Apple is used until it is.   (when relevant)
```

Changing any engine setting warms Parakeet up if it's now in use (existing
`warmUpParakeetIfSelected`, generalised to "used by any language").

## 7. Error handling

- Parakeet not ready → Apple, as today; never blocks a dictation.
- Hybrid: any one engine failing falls back to the other (§5); the dictation only
  fails if every session fails.
- Unknown stored values → defaults (existing `SettingsStore.read` behaviour).

## 8. Testing

- `EngineRouter`: every row of the §4 table.
- `SettingsStore`: per-language keys default to `engine`; `engine(for:)` in both
  modes; persistence round-trip.
- `HybridSession` with fake sessions: English → Parakeet result and Apple
  cancelled; Swedish → Apple result; no guess → last language; Apple fails →
  Parakeet; Parakeet fails → Apple; cancel cancels all; transcript engine set.
- `DictationController`: History records the transcript's engine.
- Real audio (when Parakeet is installed): English → Parakeet, Swedish → Apple,
  with `say` voices Samantha and Alva.
- Manual: the user dictates English and Swedish in Auto-detect with the mixed
  setup and checks History shows the expected engine for each.

## 9. Out of scope

- More languages (the design is per `Language`, so adding one adds a picker row).
- Using Parakeet's own confidence (it doesn't expose one).
- Feeding the Dictionary to Parakeet.
