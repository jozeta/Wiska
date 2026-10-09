# Wiska M18 — KB-Whisper: a Swedish second pass

## Goal

Fewer Swedish mishearings ("en stor hus" for "ett stort hus", "gömma" for "Gemma") by re-transcribing Swedish dictations with KB-Whisper — the National Library of Sweden's Whisper, trained on 50,000+ hours of Swedish — on-device.

Decided with the user: **KB-Whisper Large** (quantized, 1.08 GB); used **whenever a dictation turns out to be Swedish** (auto-detect or a fixed Swedish) as a second pass over the same recording; compared through a **read-aloud test in Settings**; whisper.cpp with KBLab's official GGML file.

## 1. Behaviour

- **Settings → Speech → KB-Whisper card** (shown when Swedish is ticked): **Download (1.08 GB)**, **Remove**, a status line ("Not downloaded", "Downloading 42 %", "Ready", "Download failed — try again", "Needs about 2 GB free", "Couldn't load: <reason>"), and a toggle **Use KB-Whisper for Swedish** (switched on when a download finishes; off by default).
- **Second pass:** dictation works as today — the current engine gives the live preview and the language. When the finished transcript is Swedish, the toggle is on and the model is installed, KB-Whisper transcribes the same recording (language forced to Swedish, no timestamps, no translation) and its text replaces the first engine's. Then cleanup etc. as today. English and the other languages are untouched.
- **Fallback to the first engine's text** when KB-Whisper fails, exceeds its time budget (max(3 s, 25 % of the recording's length)), or returns junk: empty text, a known Whisper hallucination ("Tack för att du tittade", "Tack för att ni tittade", "Textning", "Undertexter från Amara.org", "Prenumerera"), or more than twice the first engine's word count plus 4.
- History records the engine as KB-Whisper; the menu-bar engine label shows it for Swedish dictations it handled.
- **Memory:** loaded on the first fn press while the toggle is on and Swedish is ticked; unloaded (and memory freed) after 30 minutes without a dictation.
- **Compare on my voice…** (Settings → Speech): a window shows five Swedish sentences; **Record** / **Stop** (max 60 s) captures one reading; each installed engine — Apple (Swedish), Parakeet (if downloaded), KB-Whisper (if downloaded) — transcribes the same recording; a table shows each engine's text, word error rate against the sentences (lowercased, punctuation ignored) and time. Nothing is stored. The sentences:
  1. "Jag har ett stort hus och en liten trädgård."
  2. "Mötet börjar på torsdag efter lunch i det stora rummet."
  3. "Sju sjösjuka sjömän sköttes av sju sköna sjuksköterskor."
  4. "Johan och Anna åkte till Göteborg för att köpa en ny cykel."
  5. "Kundtjänstmedarbetaren skickade en sammanfattning av arbetsmiljöundersökningen."

## 2. Components

- **Package:** binary target `whisper` — `https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip`, checksum `e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b`; new target `Whisper` (depends on `Core`, `whisper`) and `WhisperTests`.
  - `KBWhisperModelStore` (`@MainActor @Observable`): file `ggml-model-q5_0.bin` from `KBLab/kb-whisper-large` at revision `d5d5984b4d8f7c4847a8ea203f1976285fb28300`, expected SHA-256 `6d2863812d7410322bb7d8647a5c7260761300fa946714c9ed66d22bb30bcb19`, 1,081,140,203 bytes; into `AppPaths.supportDirectory/Models/kb-whisper-large`; statuses as above; disk check (2 GB free); completion marker; partial or mismatching files removed; injectable downloader.
  - `WhisperRuntime` (actor): loads the GGML file with Metal (`whisper_init_from_file_with_params`, `use_gpu = true`), `transcribe(_ samples: [Float], language: String) async throws -> String` (`whisper_full` with greedy sampling, `language = "sv"`, `translate = false`, `no_timestamps = true`, `print_*` off), joins segments; one load shared by concurrent calls; generation counter so an unload during a load discards it; idle unload after 30 min frees the context (`whisper_free`).
  - `KBWhisperRecognizer`: façade (`isReady`, `prepare()`, `transcribe`) implementing Core's `BatchRecognizer`.
- **Core:** `protocol BatchRecognizer: AnyObject { @MainActor var isReady: Bool; @MainActor func prepare(); func transcribe(_ samples: [Float], language: Language) async throws -> String }`; `SpeechEngine.kbWhisper` (display "KB-Whisper", short "KB"), excluded from the per-language engine pickers (`SpeechEngine.selectable`).
- **Dictation:** `SwedishSecondPassTranscriber(primary:recognizer:isEnabled:)` (a `Transcriber` wrapper like `ScriptFallbackTranscriber`): its session forwards chunks and keeps a copy, exposes the primary's preview, and on `finish()` applies the rule above; `prepare()` also prepares the recognizer when enabled. `WhisperOutput.accept(_ whisper: String, over primary: String) -> Bool` (pure). `VoiceBenchmark`: the five sentences, `reference` text, `wordErrorRate(reference:hypothesis:) -> Double` (word-level edit distance / reference words).
- **Preferences:** `SettingsStore.useKBWhisper: Bool` (default `false`).
- **App:** Speech tab card + toggle + **Compare on my voice…** window; `AppModel` wraps every transcriber from `transcriber(for:)` in `SwedishSecondPassTranscriber`; store `onDownloaded` turns the toggle on; Help tip; README.

## 3. Errors

- Download: network/HTTP failure or checksum mismatch → "Download failed — try again", file removed; not enough disk → "Needs about 2 GB free".
- Load failure → "Couldn't load: <reason>" on the card; the second pass is skipped (first engine's text) until Remove and download again.
- Dictation: any KB-Whisper failure, timeout or junk → the first engine's transcript; the user always gets text.

## 4. Testing

- `WhisperTests` (fakes): store statuses, disk check, checksum mismatch, partial file removal; runtime shared load, unload-during-load, idle unload (injected loader).
- `DictationTests`: second pass only for Swedish, only when enabled and ready; preview is the primary's; error/timeout/junk → primary text; engine recorded as `.kbWhisper`; `WhisperOutput.accept` cases; `wordErrorRate` cases.
- `PreferencesTests`: `useKBWhisper` default and persistence.
- Real model (gated, Xcode): KB-Whisper on macOS's Swedish voice reading "Jag har ett stort hus och en liten trädgård." returns text containing "ett stort hus".

## Out of scope

Other KB-Whisper sizes or the Strict/Subtitle variants; KB-Whisper as a primary/streaming engine; storing benchmark recordings; update checks for the model.
