# Wiska M17 — Local language model (Gemma 4 E4B via MLX) and grammar fixing

## Goal

An optional on-device model, downloaded on request, that improves on Apple Intelligence for cleanup and command mode: real grammar fixes, better Swedish (and other non-English) text, smarter edits and writing — and that works on Macs without Apple Intelligence.

Decided with the user: all four goals; a separate **Fix grammar** switch; ~1–2 s response; MLX in-process; **Gemma 4 E4B** (`mlx-community/gemma-4-e4b-it-4bit`, 5.2 GB); an in-app comparison with Apple Intelligence.

## 1. Behaviour

- **Settings → Cleanup → Language model:** picker *Apple Intelligence* / *Gemma 4 E4B (on this Mac)*.
  - A Gemma card (like the Parakeet card): **Download (5.2 GB)** with progress, **Remove**, a status line ("Not downloaded", "Downloading 42 %", "Ready", "Loaded", "Couldn't load: <reason>", "Download failed — try again"). When a download finishes, Gemma is selected.
  - Picking Gemma before downloading starts the download.
  - No update checks for the Gemma model in M17.
- **What Gemma does:** cleanup rewriting (Light, Polished) and command mode (edit with a selection, write with nothing selected).
- **Fallback:** Gemma chosen but not downloaded, not loadable, erroring or over its time budget → Apple Intelligence (if available) → rule cleanup (cleanup) or today's failure message (command mode). Apple chosen but unavailable and Gemma downloaded → Gemma.
- **Fix grammar** (Settings → Cleanup, on by default): at Light and Polished both models are told to fix grammar mistakes ("He go to the store yesterday and buyed some milk." → "He went to the store yesterday and bought some milk."; "Jag har en stort hus" → "Jag har ett stort hus"). Off: Light stays word-faithful as today.
- **Memory:** Gemma (~5 GB) loads on the first fn press (prewarm) while it's selected, stays loaded, and unloads after 30 minutes without a dictation or command.
- **Compare models…** (Settings → Cleanup): a window that runs the benchmark cases (§4) through Apple Intelligence and Gemma (each only if available) and shows a table: case, each model's output, ✓/✗, time. A **Run** button; results aren't stored.
- **Messages:** "Command mode needs Apple Intelligence" becomes "Command mode needs a language model" (shown when neither model is available).
- Logs name which model handled a dictation and its time; never the text.

## 2. Components

- **Package:** new target `LocalModel` (depends on `Core`, `Cleanup`, and `MLXLLM` + `MLXLMCommon` from `https://github.com/ml-explore/mlx-swift-lm`, exact `3.32.3`). Test target `LocalModelTests` uses fakes only (MLX's Metal code needs an Xcode build; `swift test` can't run the real model).
  - `GemmaModelStore` (`@MainActor @Observable`): `status` (`.notDownloaded`, `.downloading(Double)`, `.ready`, `.failed(String)`), `download()`, `remove()`, `isInstalled`; files under `AppPaths` (`Models/gemma-4-e4b-it-4bit`); checks ~6 GB free disk first; partial downloads removed on failure. Downloading goes through an injectable `ModelDownloader` (real one: Hugging Face via mlx-swift-lm's hub support).
  - `GemmaRuntime`: `load()`, `unload()`, idle unload after 30 min, `generate(system: String, prompt: String, maxTokens: Int) async throws -> String` (temperature 0). Behind a `LocalGenerator` protocol so rewriter/editor tests use a fake.
  - `GemmaRewriter: TextRewriter`, `GemmaEditor: TextEditor` — same instructions and post-processing as the Apple versions.
- **Cleanup (shared, model-agnostic):**
  - `CleanupPrompts`: the cleanup instructions (moved from `FoundationModelsRewriter.instructions`) gain a `grammar: Bool` line: "Fix grammar mistakes (verb forms, agreement, articles, word order); keep the meaning and otherwise the words."
  - `EditPrompts`: edit/write instructions, prompts and output post-processing (`rewrap`, fence/marker stripping, `removeEcho`, `mostlyCopies`, `fitToCursor`) moved from `FoundationModelsEditor`, used by both editors.
  - `TextRewriter.rewrite` gains `grammar: Bool`; `TextRewriter` gains `timeout: Duration` (Apple: today's value; Gemma: 1.5× it, 6 s minimum) used by the pipeline's deadline.
  - `CleanupGuard.check(…, grammar: Bool)`: with grammar on, Light keeps ≥ 80 % of required words (instead of 100 %); the new-word limit (20 %) is unchanged.
  - `SwitchingRewriter` / `SwitchingEditor`: pick by `languageModel` and availability; on an error or timeout from the chosen model, retry once with the other available one.
  - `ModelBenchmark`: `cases: [BenchmarkCase]`, `run(rewriter:) / run(editor:) async -> [BenchmarkResult]` (`output`, `passed`, `duration`).
- **Preferences:** `SettingsStore.languageModel: LanguageModelChoice` (`.apple`, `.gemma`; default `.apple`), `fixGrammar: Bool` (default `true`).
- **App:** Cleanup tab — Language model picker, Gemma card, Fix grammar toggle, Compare models… button + window; `AppModel` wiring (store, runtime, switching rewriter/editor, prewarm on fn press, auto-select after download); Help: a "Local model" tip; README.

## 3. Errors

- Download: failure → `.failed("Download failed — try again")`, partial files removed; not enough disk → `.failed("Needs about 6 GB free")` before starting.
- Load: failure (corrupt files, memory) → card shows "Couldn't load: <reason>" with **Remove and download again**; Gemma counts as unavailable (fallback to Apple).
- Dictation: Gemma error/timeout → Apple → rule cleanup; the user always gets text.
- Command mode: same failure messages as M16, with `.editUnavailable` reading "Command mode needs a language model".

## 4. Benchmark cases

Grammar (cleanup, Light, Fix grammar on) — must contain / must not contain:
1. en "He go to the store yesterday and buyed some milk." → contains "went", "bought"; not "buyed".
2. en "I has a apple. Their going to the park." → contains "have an apple", "They're"; not "I has".
3. en "She don't like it, its to late." → contains "doesn't", "too late"; not "don't like".
4. sv "Jag har en stort hus och hon gillar honom bil." → contains "ett stort hus", "hans bil"; not "honom bil".
5. sv "Vi ska köpa en äpple imorgon." → contains "ett äpple"; not "en äpple".
6. sv "Han har inte ätit något mat idag." → contains "någon mat"; not "något mat".
7. de "Ich habe ein großer Hund und er sind sehr nett." → contains "einen großen Hund", "ist"; not "er sind".

Cleanup (Polished):
8. en "um so I think we should uh meet on Tuesday no wait Wednesday" → contains "Wednesday"; not "um", "Tuesday".
9. sv "eh jag tror att vi ska ses på tisdag nej förresten onsdag" → contains "onsdag"; not "eh", "tisdag".
10. en "can you send me the report by Friday" (question kept) → contains "?".

Edit:
11. "hey can u send it asap" + "make this more formal" → not " u ", not "asap".
12. "Vi ses imorgon klockan tre." + "translate to English" → contains "tomorrow"; not "imorgon".
13. "milk eggs bread" + "turn it into a bulleted list" → contains "- " or "• " three times.

Write:
14. context "Hi Johan,\n\nAre you coming tomorrow? It starts at three.\n\nAnna\n\n[cursor]" + "reply that I'll be there" → contains "there"; not "Are you coming", ">>>".
15. context "Hej Johan,\n\nKommer du på mötet imorgon?\n\nAnna\n\n[cursor]" + "svara att jag kommer" → contains "kommer"; not "Kommer du på mötet".

Matching is case-insensitive.

## 5. Testing

- `LocalModelTests` (fakes): store status transitions, disk-space check, failed download cleanup; runtime idle unload (injected clock/short interval); `GemmaRewriter`/`GemmaEditor` prompts and post-processing through a fake generator.
- `CleanupTests`: prompts with/without grammar; guard grammar mode (case 1 passes Light with grammar, rejected without); switching rewriter/editor selection and fallback order; benchmark scoring with fake models; Apple classes still pass their existing tests after the move.
- `PreferencesTests`: new settings defaults and persistence.
- Real model: the Compare window, run on the user's Mac before hand-over (results reported, not asserted in CI).

## Out of scope

Other local models or sizes; update checks for Gemma; streaming output; fine-tuning; using Gemma for transcription.
