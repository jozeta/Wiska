# Changelog

All notable changes to Wiska are listed here, newest first.

Releases follow the project's git tags. Entries were reconstructed from the commit history.

## [Unreleased]

- Meetings: a short interruption in the middle of someone's turn now gets its own line ("Speaker 2 (over Speaker 1)") instead of disappearing into their turn, and split-second flicker between voices no longer produces tiny empty turns
- Update Sparkle 2.10.1, swift-transformers 1.3.5 and FluidAudio 0.18.2. FluidAudio fixes speech recognition returning nothing on M1/M4 with macOS 27.0.1, and meeting speaker detection now notices people talking over each other (shown as "over" in the transcript when it starts a new turn)
- Ignore macOS, Claude Code and secret files
- Add CLAUDE.md with project guidance for Claude Code
- Add CI workflow, Dependabot config, security policy

## [1.4.2] - 2026-10-23

- fix(release): zip without extended attributes (no ._ files beside the app that an unzipper could leave in the bundle and break its seal), and refuse a zip that has them
- perf+fix: quicker dictation and several bugs
- chore: version 1.4.2 (and a timing test with room for a busy machine)

## [1.4.1] - 2026-10-14

- feat(meetings): the speaker model is downloaded in Settings → Models only; the Meeting window shows a warning while it's missing, nothing once it's there
- fix(setup): the Screen & System Audio Recording step also raises macOS's "bypass the private window picker" question (by capturing once) and is ticked only once it's answered, so it doesn't pop up when the first meeting starts
- test(swedish-it): opt-in probes of Swedish speech with English IT terms: every engine on a real recording, KB-Whisper with an initial prompt (optional, unused by the app), and model repair of misheard terms
- feat(cleanup): Swedish dictation repairs misheard English IT terms ("Gira" → "Jira", "kubenetesklustret" → "Kubernetes-klustret"): the cleanup prompt lists the terms, and the guard accepts a term written in place of a misheard word but never a real word turned into one, nor terms added out of nowhere
- feat(cleanup): a misheard word that isn't a real word may be repaired into any close word, listed IT term or not ("Posgres" → "Postgres"); more terms listed (Postgres, Terraform, Kafka, Sentry, Confluence…)
- chore: version 1.4.1

## [1.4.0] - 2026-10-14

- wip(meetings): speaker diarization (FluidAudio, 14 MB model), speaker turns and naming helpers, meeting notes (summary, decisions, action items; long meetings in parts) — UI for naming and the speaker-model download still to do
- feat(meetings): name the speakers after a meeting (one row each with a sample line; transcript and notes follow), Identify speakers / Write notes switches with the 14 MB speaker model's download in the window and in Settings → Models, progress for both steps; notes tidied of trailing spaces; live tests for diarization and notes (opt-in)
- feat(setup): optional Screen & System Audio Recording step (only for meetings) with Allow…; not counted as setup needed
- feat(setup): Screen & System Audio Recording right under Accessibility
- test: hands-free silence test keeps sending quiet levels until the silence is noticed (flaky under load)
- feat(menu): an icon on every menu row, grouped with dividers (status, dictation settings, permissions, your dictations, files and meetings, setup, the app)
- fix(menu): show the icons (menus show only a label's title unless told otherwise)
- feat(meetings): overlapping voices are transcribed once (for whoever was talking; the other is marked "over" them), long turns split at a pause, shorter pieces so you and the call interleave in order, and the call leaking into the microphone (no headphones) is left out of your lines
- feat(meetings): speakers told apart by FluidAudio's offline pipeline (community-1 + VBx, 21 MB; ~3% of speech under the wrong person on real meetings vs ~29% for the streaming one), and a People on the call hint (Auto, 1–8); opt-in tuning harness comparing pipelines and settings on generated conversations
- fix(meetings): the call leaking into the microphone is removed reliably (keep what's clearly your voice, judged against the typical leak level, instead of silencing only long leak stretches); speakers told apart with FluidAudio's accuracy settings so short replies get a voice; opt-in demo of a whole business call through the pipeline
- chore: version 1.4.0

## [1.3.3] - 2026-10-14

- fix(permissions): Allow always asks macOS for Input Monitoring and Accessibility (asking is what lists Wiska in System Settings), and opens System Settings too when it has asked before — after a reset or a signing change Wiska was missing from the list
- fix(setup): ask for Accessibility before Input Monitoring — macOS judges the fn listener's request through Accessibility and refuses it without a prompt while Accessibility is off; the log shows the audio length (it was redacted as private)
- feat(setup): Input Monitoring has no Allow button — it follows Accessibility from the next launch; once Microphone and Accessibility are allowed while Wiska runs and the fn listener still isn't, Wiska asks once to restart and restarts itself; the menu offers the same restart
- test: the max-length test waits for the limit to fire instead of 150 ms
- chore: version 1.3.3

## [1.3.2] - 2026-10-13

- fix(release): the signed app keeps no designated requirement from the development certificate — 1.3.1 didn't meet its own, so macOS couldn't give it Accessibility or Input Monitoring; the script now checks the requirement names the team and is met; log each menu opening; version 1.3.2

## [1.3.1] - 2026-10-13

- feat(release): sign with Developer ID (secure timestamp, hardened runtime, inside out) and notarize with notarytool, staple the ticket and check Gatekeeper accepts it before writing the appcast
- chore: version 1.3.1 — notarized; README: no more Gatekeeper warning, permissions asked once more after the signing change

## [1.3.0] - 2026-10-13

- feat(release): release notes in the update window — scripts/release.sh NOTES.md embeds the Markdown notes in the appcast and uses them for the GitHub release
- feat(voice commands): "delete last sentence" / "undo that" remove the sentence before them, and punctuation said aloud (comma, full stop, question and exclamation mark, colon, semicolon) in all nine languages; ambiguous words (period, punto, punt…) only at the end, nouns after a determiner and decimal commas stay words
- feat(files): Clean up for transcribed recordings — paragraph by paragraph in sentence chunks, with the dictation models and dictionary and a minute per chunk; recordings skip voice commands, snippets and list formatting; a paragraph per ~2-minute piece
- feat(dictionary): learn from corrections — for a minute after a paste Wiska watches the field (Accessibility, in memory) and offers a misheard name or term the user fixes as a dictionary suggestion (Add / Dismiss in Settings → Dictionary); ordinary word swaps, rewrites and edits outside the pasted text don't count; only the word pair is stored
- fix(dictation): a level frame already on its way when listening stops no longer brings the waveform back; the waveform test waits for its frame instead of 20 ms
- feat: Record Meeting… — records a call's audio and the microphone with ScreenCaptureKit, then writes a timed transcript split into You and Others (each side cut at its pauses, silence skipped, optional cleanup); the audio is deleted after transcribing; asks for Screen & System Audio Recording with a link to System Settings
- chore: version 1.3.0
- fix(release): the release-notes check accepts the description tag's format attribute

## [1.2.0] - 2026-10-13

- feat(logging): a log line per dictation step (engine, language, word counts, timings), why a command's answer was rejected, which way the selection was read, launch settings and permission changes; Log.summary logs an error's type and case, never its description; README: reading the log
- feat(models): Settings → Models → Memory: how long Gemma and KB-Whisper stay loaded unused (5, 10, 30, 60 minutes or until Wiska quits; default 10), applied to the model in memory right away
- perf(themes): the orb and Clippy stop drawing while their window is fully covered or off screen (Desktop behaviour behind app windows): idle Clippy went from ~5% CPU to 0 when covered
- fix(commands): writing at the cursor asks once more, with a firmer instruction, when the answer only repeated the surrounding text (both Apple Intelligence and Gemma) instead of failing with "Couldn't write"
- feat(history): Stats → Speed: typical (median) time from releasing fn to the text, per speech engine, split into transcription, cleanup and paste; each dictation now records its timings (older entries read 0 and are left out)
- feat: paste the last dictation again, from the menu or a global shortcut (Settings → General: ⌃⌥V by default, ⌥⌘V, ⌃⌥⌘V or off); falls back to the newest History entry after a relaunch, refuses password fields
- feat(help): Copy diagnostics — Wiska's version, settings, missing permissions and its log since launch (notice level and up, private values redacted) on the clipboard for a bug report
- feat: Transcribe Audio File… (menu) — a recording up to three hours (m4a, mp3, wav, aiff, caf, video soundtracks) to text with the dictation engine settings, cut into ~2-minute pieces at quiet moments for progress; copy or save as .txt; nothing kept in History
- fix: slow blocking work (reading the log for diagnostics, decoding an audio file) runs on a dispatch queue, not Swift's cooperative threads, which it starved; tests no longer depend on a 50 ms window or heavy main-actor sample math
- feat(updates): Wiska updates itself with Sparkle 2.10 from GitHub releases (daily check, Check for Updates… in the menu, an "Update to …" item when a check finds one in the background, Settings → General → Updates); updates are EdDSA-signed and install without the Gatekeeper warning; scripts/release.sh builds, signs (incl. Sparkle's helpers) and writes the appcast
- chore: version 1.2.0

## [1.1.0] - 2026-10-12

- feat(settings): dictation theme settings — theme, orb size/colour/behavior, positions; invalid values fall back
- feat(hud): dictation themes — Expanded Notch, Magical Orb and Clippy behind one presenter; switching hands the current dictation over
- feat(appearance): Settings ▸ Appearance picks the dictation theme (live previews), with orb size/colour/behavior and Clippy behavior; AppModel drives the theme controller
- fix(themes): idle orb/Clippy always drop back to the slow pace, Clippy's bubble is laid out once not per audio frame and draws its own shadow, the Expanded Notch waveform settles instead of being swapped
- fix(appearance): notch previews take their scaled size, so the theme cards stay in their columns
- feat(themes): Clippy size slider, follow-the-pointer eyes and a centred bubble tail; a livelier orb (voice-driven twin aura, 3D rings, lightning) using the highlight colour — one colour picker, hidden for Clippy
- feat(themes): the orb sings with the voice — aura, sparks and lightning follow its pitch bands; slower sparks and rings, calmer lightning, a slow breath and no lightning when idle; Clippy fidgets discreetly when idle
- feat(orb): a ball of plasma fire (Metal shader) — slow, dim and breathing when idle, fed by the voice's loudness and pitch bands, roaring and glowing when busy
- feat(orb): more like fire — outward-licking flame tongues, flicker, a heat colour ramp and rising embers; a clearer, quicker idle pulse; calmer flames and sparks while busy
- feat(orb): no embers; a stronger idle pulse, a much stronger response to the voice, livelier flames idle and busy
- feat(orb): three wavy borders floating round the fire, a stronger idle pulse, and the voice flares the fire far more
- feat(orb): faint wavy borders at rest that brighten with the voice; states cross-fade instead of jumping (red errors fade too); smoother idle frame rate
- feat(orb): size slider runs 120–480 pt (Clippy keeps 80–240), shows the size in points; the Settings preview stops growing at 280 pt
- feat(clippy): five idle tricks about once a minute (spin, nap with z's, cartwheel, dance, trampoline), a livelier idle in between, and a happier, bouncier listener
- feat(clippy): five more tricks (peekaboo, jelly, moonwalk, dizzy, hiccups), idle faces (angry, happy, questioning, pondering, surprised, smug), tricks and faces while following the pointer; fix the listening bounce jumping about (voice-driven speed on a huge clock) and show the calm idle in Settings
- docs: README covers the dictation themes (Notch Dropdown, Expanded Notch, Magical Orb, Clippy) with new screenshots; live preview and build notes brought up to date
- chore: version 1.1.0

## [1.0.0] - 2026-10-10

- test: settings and migration tests no longer leave files in ~/Library/Preferences
- test: keep throwaway UserDefaults suites in the temp folder
- fix(hotkey): ⇧ pressed just after fn still counts
- fix(speech): auto-detect carries on with one language if the other can't start
- fix(parakeet): live ready state, free memory on Remove, steady progress, size text
- fix(cleanup): keep real quotes, legit repeats and "you"; tidy model output
- fix(injection): restored clipboard keeps its format order
- fix(history): no crash on deleting a purged entry; prompt expiry; faster stats
- fix(hud): explicit error state; quick hide → show → hide no longer cuts short
- fix(onboarding): open once per launch; prompt or Settings, never both
- fix(dictation): a cancelled recording can't finish the one that replaced it
- fix(hotkey): let ⇧ key events through to the fn state machine
- docs: per-language speech engines design
- docs: per-language engines implementation plan
- feat(core): engine router, engine mode, transcript engine
- feat(settings): engine mode and per-language engines
- feat(dictation): transcriber chosen per language choice; history records the real engine
- feat(dictation): hybrid transcriber for auto-detect with mixed engines
- feat(app): per-language engine routing, status line and Settings UI
- test(parakeet): hybrid picks Parakeet for English and Apple for Swedish on real audio
- fix(dictation): hybrid's Apple fallback is recorded as Apple; pin English hybrid latency
- fix(engines): stable per-language picks, precise hybrid readiness, quieter Parakeet failures
- docs: M6 look & settings design
- docs: M6 look & settings implementation plan
- feat(core): highlight colour presets and setting
- feat(hud): capsule exactly as wide as the notch; reveal maths
- feat(hud): glide-down capsule and highlight colours
- feat(app): highlight colour in History, Onboarding and the capsule
- feat(settings): tabbed Settings, Appearance with colour presets, launch at login
- fix(m6): capsule size fixed by layout, scrolling dictionary lists, live login status and History colour
- docs: M7 languages design
- docs: M7 languages implementation plan
- feat(languages): nine languages, engine per language, Apple module per language
- fix(languages): engine router chooses among ticked languages (default English + Svenska)
- feat(cleanup): word lists per language
- feat(cleanup): rules and model instructions follow the spoken language
- feat(languages): ticked languages drive settings, hotkeys and engine routing
- feat(speech): transcribers work over the ticked languages; real audio for seven new languages
- test(parakeet): real-audio Parakeet tests take turns on the Neural Engine
- feat(history): language stats for any number of languages
- feat(settings): My languages list (up to five); auto-detect verified on real audio
- fix(languages): downloads never hold up installed languages; safe slot release; per-language spell check
- docs(spec): M8 hands-free dictation and live preview
- docs(plan): M8 hands-free and live preview
- docs(m8): preview scrolls like a ticker inside the notch; Settings switch names the notch
- feat(hotkey): double-tap fn locks hands-free; fn tap finishes, Esc cancels
- feat(dictation): lockHandsFree command and SilenceWatch
- feat(speech): sessions report the words heard so far (Apple volatile results)
- feat(dictation): hands-free dictations finish after a stretch of silence
- feat(dictation): controller exposes the live preview while listening
- feat(hud): live preview ticker under the waveform; lock mark when hands-free
- feat(settings): hands-free silence and live preview settings; wire M8 into the app
- fix(hands-free): double-tap locks in the app; ⇧ alone no longer finishes
- fix(hands-free): the 🌐 key-down after a real fn tap no longer breaks the double-tap; clearer, smoother preview
- feat(hud): preview glides at an even, dampened speed; pixel-snapped; roomier spacing
- feat(hud): preview is a news ticker — every word slides in from the right
- feat(hud): preview fades in on the right like it fades out on the left; text sits centred
- style(hud): preview text 2 pt closer to the waveform
- style(hud): waveform 2 pt closer to the notch; preview text 1 pt closer to the waveform
- style(hud): livelier waveform — flat in silence, speech spans 3–28 pt with emphasised peaks
- feat(hud): live, dramatic waveform — reacts in ~30 ms, ripples while you speak, flat in silence
- feat(waveform): bars driven by real audio — pitch bands, noise gate, compressive loudness
- style(hud): waveform spans the notch — 32 thin bars, one pitch band each
- docs(m9): smarter cleanup design — app categories, styles, formatting
- docs(m9): implementation plan
- feat(core): app categories, writing styles and the built-in app catalog
- feat(core): list, greeting and sign-off words per language; ordinals and percent may become digits
- feat(cleanup): spoken lists become numbered lines
- feat(cleanup): email greeting and sign-off on their own lines
- feat(cleanup): formal, casual and very casual finishing; code-safe output
- feat(cleanup): style per app category, lists, email layout, code-safe; the model writes numbers as digits
- feat(settings): styles per category, app category overrides, recent apps
- feat(app): category per dictation from the front app; Styles and Apps in Settings → Cleanup
- fix(cleanup): greeting names stop at "I" and need name words; lists never span sentences or ordinary uses of a marker; line-by-line emails get their layout
- fix: Apple re-transcribes Parakeet text in a non-Latin alphabet; front app comes from Accessibility, not the cached frontmostApplication
- feat(cleanup): in Code apps, misheard "get/kit <git command>" becomes git
- docs(m10): command mode design — edit selected text by voice
- docs(m10): implementation plan
- feat(core): command-mode events, commands, selection/editor protocols and failures
- feat(hotkey): fn+⌃ marks the hold as a command
- feat(dictation): commands edit the selection and paste it; no cleanup, no history
- feat(injection): read the selection via Accessibility, else ⌘C with the clipboard restored
- feat(cleanup): on-device editor for command mode
- feat(app): command mode wired — ⌘ Edit badge, Editing…, gesture listed in Settings
- fix(command): keep the selection's surrounding whitespace; 600-word cap with a timeout that grows with length; the time limit never waits on the model
- fix(hud): the command badge reads ⌃ Edit, matching the Control key of the gesture
- docs(m11): richer History design — filters, stats over time, raw vs cleaned
- docs(m11): implementation plan
- feat(history): filters by app, language, period and pasted
- feat(history): word diff between what was heard and what was pasted
- feat(history): report for the Stats tab — totals, words over time, top apps, languages
- feat(app): History gets filters, a raw-vs-cleaned view and a Stats tab
- fix(history): daily bars survive clock changes at midnight; only the row header toggles the diff, so its text stays selectable
- style(history): the window keeps the same 12 pt margin at its bottom as at its sides
- feat: "After dictation" setting — insert into the app, or copy to the clipboard only
- docs: README and MIT license; Settings gets a Help tab with examples and troubleshooting
- docs(m13): Parakeet model update checks design
- docs(m13): implementation plan
- feat(parakeet): read the model repo's revision; the store records which revision it downloaded
- feat(parakeet): model update checker — on demand or when due, never downloads by itself
- feat(settings): model update interval and last check
- feat(app): Parakeet update status, Check now and Download update; automatic checks; menu item
- fix(parakeet): after a relaunch the card says when it last checked instead of claiming "Up to date"
- fix(hud): a dictation started while the capsule is still hiding starts with one row
- fix(hud): no blink between the taps of a double-tap — the capsule waits 0.45 s before hiding after a quick tap
- fix(cleanup): a capitalised pronoun after a sign-off word is not a name ("Danke Ihnen")
- fix(cleanup): Very casual keeps acronyms and multi-word dictionary entries
- fix(cleanup): ordinals that are everyday words (andra, anden, secondo, segundo) no longer count as spoken numbers
- fix(injection): an unanswered ⌘C leaves the clipboard untouched, and a copy that lands late is undone
- fix(command): a command in a password field says "Can't type here" without reading anything
- fix(command): a quoted selection keeps its quotes after an edit
- fix(command): the selection is fenced in the prompt so instructions inside it are only text
- fix(command): a refused edit says Apple Intelligence won't edit it; a full context is "Selection too long"
- fix(history): one Filter menu (with app icons) and Clear All in its own menu; vanished filters reset; Today rolls over at midnight; languages split bar in Stats
- fix(history): the menu's "This week" counts the same 7 calendar days as Stats
- fix(parakeet): updates compare only the installed model files; an update records what was downloaded; a failed automatic check keeps a newer result
- fix(parakeet): Parakeet reloads after any download; Download update says it replaces the model; README update wording
- fix(command): VS Code's whole-line copy (nothing selected) counts as no selection
- fix: review of the cleanup pass — Wiska's own clipboard writes stop the late-copy watch; a conflict block keeps its markers; multi-word entries match whole words; menu-size app icons; quiet re-check after an update; one announcement per set of model files
- docs(m15): voice snippets design
- docs(m15): implementation plan
- feat(core): snippets, insert words per language, snippet store
- feat(cleanup): snippet expander — triggers become placeholders, filled in verbatim
- feat(cleanup): snippets are inserted verbatim at every level and in every app
- feat(app): Snippets tab, Help section, snippets wired into cleanup
- fix(snippets): a snippet ending in punctuation keeps exactly its own; edits save as you type; abandoned empty snippets are removed
- feat(snippets): redo — "When I say <phrase> → Insert <text>" with exact phrases, clear cards with warnings, a Try it box and a how-to
- fix(snippets): every card shows a "When I say" field, also for snippets without a phrase yet
- fix(snippets): the phrase and Try it fields are real bordered text fields with placeholders, not row labels
- style(settings): wider window (700 pt); Help and Snippets get 720 pt of height
- style(settings): resizable Settings window; the snippet how-to moves to Help
- fix(settings): the Settings window is really resizable (styleMask), min 560 × 420
- style(settings): a fixed 700 × 780 Settings window instead of the resize attempt
- docs(m16): command mode part 2 design — writing with context, saved commands
- docs(m16): implementation plan — command mode part 2
- refactor(core): PhraseMatcher — phrase matching shared by snippets and saved commands
- feat(core): saved commands and CommandResolver (phrase first, extra words as "Also: …")
- feat(injection): read the text around the cursor (1,500 characters each side) for writing
- feat(cleanup): FoundationModelsEditor.write — new text for the cursor, with the surrounding text as context
- feat(dictation): fn+⌃ with nothing selected writes at the cursor; saved commands resolve the instruction
- feat(preferences): CommandStore — commands.json, seeded with the four defaults
- feat(app): Commands tab, Help on writing and saved commands, "Writing…" status
- fix(cleanup): a model that repeats the text around the cursor doesn't paste it twice
- fix(injection): no ⌘C when the field reports nothing selected (no beep, no whole-line copy)
- fix(injection): read only the text around the cursor, with a 0.5 s Accessibility timeout
- fix(commands): a command counts only alone or before a comma/"and" — "fix the second sentence…" is used as said
- fix(cleanup): written text never starts with the context's closing fence (">>> I'll be there")
- docs(m17): local language model (Gemma 4 E4B via MLX) and grammar fixing — design
- docs(m17): implementation plan — local model (Gemma 4 E4B), Fix grammar, Compare models
- feat(cleanup): shared cleanup prompts with a Fix grammar line
- feat(cleanup): the guard's grammar mode — near words aren't new, Light keeps ≥ 80 %
- refactor(cleanup): EditPrompts — edit/write prompts and post-processing shared by every model
- feat(preferences): language model choice (Apple / Gemma) and Fix grammar (on)
- feat(cleanup): LocalRewriter and LocalEditor — any local model, same prompts as Apple's
- feat(cleanup): switch between Gemma and Apple Intelligence, retrying the other on failure
- feat(cleanup): ModelBenchmark — 15 grammar, cleanup, edit and write checks for any model
- feat(local-model): GemmaModelStore — download from Hugging Face on request, disk check, no partial installs
- feat(local-model): GemmaRuntime (shared load, 30 min idle unload), MLX adapter, GemmaModel
- feat(app): Gemma in Settings → Cleanup (download, Fix grammar, Compare models), wired to cleanup and commands
- fix(local-model): unload frees memory, a stale load is dropped, the model loads early again after an idle unload
- fix(local-model): downloaded file names can't escape the model folder
- docs(m18): KB-Whisper Swedish second pass — design
- docs(m18): implementation plan — KB-Whisper Swedish second pass
- feat(core): BatchRecognizer, SpeechEngine.kbWhisper, ResumeOnce in Core, useKBWhisper setting
- feat(dictation): WhisperOutput junk check and VoiceBenchmark word error rate
- feat(dictation): SwedishSecondPassTranscriber — KB-Whisper re-transcribes Swedish, with fallback
- feat(whisper): whisper.cpp target, KBWhisperModelStore (SHA-256 checked); ModelRuntime shared with Gemma
- feat(whisper): whisper.cpp context (Metal) and KBWhisperRecognizer
- feat(app): KB-Whisper card and Swedish second pass, Compare on my voice
- fix(core): model calls take turns, and a cancelled request never runs (no parallel whisper_full)
- fix(app): look for embedded frameworks in Contents/Frameworks (whisper.framework failed to load at launch)
- fix(downloads): progress is reported while downloading (it stayed at 0 % until done)
- fix(kb-whisper): no load or kept audio when it can't be used, short clips padded, cancel during checksum, timer cancelled
- fix(gemma): unclosed thinking dropped, cancel isn't retried on Apple, stricter near words, Try again after a load error, download end reported
- fix(commands): badge says Edit/Write, document's own [cursor] defused, context for text without spaces, tolerant decoding, dated corrupt-file copies, one save for empty commands
- fix(snippets): blank line before a signature snippet in email, sign-off before a snippet recognised, spacing around snippets kept
- fix(app): Edit/Write badge, Gemma loads for commands and the picker returns to Apple after a failed download, Try again, Compare stops on close, KB-Whisper card stays reachable and unloads, mic error shown, menu shows KB-Whisper; unique corrupt-file names
- fix(commands tab): Try it finds a command whose text equals the input, one save on close, says when a damaged file was set aside
- style(hud): command badge reads Edit / Write / Command, without ⌃
- fix(cleanup-2 review): no crash cancelling a download as it starts, do/does and go/goes are near again, no leading or doubled blank line before a signature
- refactor(models): the update checker moves to Core behind UpdatableModelStore (Parakeet conforms)
- feat(gemma): update checks like Parakeet's — remembers the installed version, Check now, Download update, hourly check when due
- feat(models): KB-Whisper update checks (newest version, published SHA-256), pickers offer only downloaded models, removing Parakeet resets its choices
- feat(settings): Models tab — every model's download, removal and update check in one place; Speech and Cleanup offer only downloaded models
- docs: public README — download link, the security warning explained, screenshots; version 1.0.0

## [0.5-m5] - 2026-10-08

- Add M5 Wiska rename, brand, onboarding and stats design spec
- Add M5 Wiska rename, brand, onboarding and stats implementation plan
- chore: rename SecureWispr to Wiska (project, package, bundle id, paths)
- feat(preferences): one-time migration of SecureWispr data and settings
- feat: record spoken duration with each dictation
- feat(history): weekly dictation stats and menu-line formatting
- feat(hud): notch capsule placement
- feat(hud): Midnight Aurora notch capsule
- feat(brand): Midnight Aurora app icon and menu-bar mark
- feat(preferences): onboarding checklist state and flags
- feat(app): Wiska onboarding checklist, weekly stats, migration on launch
- fix(hud): language flash continues from the shrinking capsule instead of snapping
- chore: M5 acceptance passed

## [0.4-m4] - 2026-10-08

- Add M4 dictionary + history design spec
- Add M4 dictionary + history implementation plan
- feat(memory): dictionary and record types, dictionary corrector
- feat(cleanup): apply personal dictionary before and after the model
- feat(stt): dictionary words as Swedish recognition hints; engine identity
- feat(dictation): emit dictation records for history
- feat(preferences): JSON dictionary store and history retention setting
- feat(history): SwiftData dictation history with retention
- feat(app): dictionary and history in Settings, History window
- fix: review findings — dictionary never turns real words into names, case-only rules, speed
- chore: M4 acceptance passed

## [0.3-m3] - 2026-10-08

- Add M3 cleanup design spec
- Add M3 cleanup implementation plan
- feat(cleanup): cleanup levels, prewarm hook, voice commands
- feat(cleanup): rule-based cleaner and model-output guard
- feat(cleanup): guarded, time-boxed cleanup pipeline
- feat(cleanup): Foundation Models rewriter with level-specific instructions
- feat: prewarm cleanup on start; persisted cleanup level
- feat(app): cleanup level in Settings and menu bar
- fix: review findings — voice commands ignore prose, answers rejected, tighter budget
- chore: M3 acceptance passed

## [0.2-m2] - 2026-10-08

- Add M2 bilingual + engines design spec
- Add M2 bilingual + engines implementation plan
- feat(core): language types, router and confidence picker
- feat(hotkey): shift-aware fn events, quick taps, reset after tap re-enable
- feat(dictation): command-driven controller, hotkey mapper, release tail
- feat(stt): Swedish via DictationTranscriber, confidence, cleanup on session errors
- feat(stt): auto-detect English vs Swedish by confidence
- feat(preferences): persisted engine and language settings
- feat(parakeet): optional Parakeet engine via FluidAudio with explicit download
- feat(hud): language badge while listening
- feat(app): language modes, engine selection, Parakeet card in Settings
- fix: review findings — Parakeet stays offline, removes the right folder, survives partial downloads
- fix(parakeet): use FluidAudio's own model folder name; real-model test needs a completed install
- fix(app): bring Settings window to the front from the menu bar
- chore: M2 acceptance passed

## [m1-skeleton] - 2026-10-08

- Add architecture and M1 skeleton design spec
- Add M1 skeleton implementation plan
- chore: add signing config template
- chore: ignore superpowers workspace
- feat(core): add shared types, protocols and PCM converter
- feat(hotkey): fn push-to-talk state machine and event tap
- feat(audio): microphone capture at 16 kHz with waveform levels
- feat(stt): stream audio into Apple SpeechAnalyzer (English)
- feat(injection): paste at cursor with clipboard restore; passthrough cleanup
- feat(dictation): pipeline controller with streaming, cancel, timeout and failures
- feat(hud): non-activating waveform panel
- feat(app): menu-bar shell wiring the dictation pipeline
- fix: review findings — no double recording, graceful audio device changes, safe mic prompt
- chore: M1 acceptance passed
