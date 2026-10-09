# Wiska M10 — Command mode: edit selected text by voice

## Goal

Select text in any app, hold fn+⌃, say what to change ("make this more formal", "translate to Swedish", "make it shorter", "fix the grammar"), release — the selection is rewritten on-device and replaced. ⌘Z restores the original.

Decided with the user: command mode **edits selected text only** (no writing new text, no answering questions); the gesture is **hold fn + ⌃**; the selection is read with **Accessibility first, ⌘C as fallback**.

## 1. Gesture

- `FnHotkeyMonitor` also passes ⌃ flag changes (key codes 59 and 62); `KeyInput.flagsChanged` gains `control: Bool`.
- `FnKeyStateMachine` emits a new `HotkeyEvent.commandAdded` **once per hold** the first time ⌃ is down while fn is held — at fn down or any time later before fn up.
- Recording still starts at fn down (`.pressed`), so no audio is lost; `commandAdded` only marks the recording as a command.
- fn up finishes (`.released`) and Esc / another key cancels, as for dictation.
- A quick fn+⌃ tap (released before `minimumHold`) does nothing beyond today's tap behaviour; it never arms hands-free.
- Hands-free (double-tap) does not support command mode in M10: ⌃ while locked is ignored.
- ⇧ keeps its language meaning, so fn+⇧+⌃ is a command in the secondary/toggled language.
- `CommandMapper` maps `.commandAdded` → `DictationCommand.makeCommand`. The controller ignores it unless `.listening`.

## 2. Flow on release

For a command recording, `DictationController` on finish:

1. Transcribes the instruction as usual (same engine/language; voice commands and dictionary don't matter — the instruction is never pasted; **no cleanup**).
2. Empty instruction → the existing "No speech detected" path.
3. Reads the selection via `SelectionReader.selectedText()` — after release, so ⌃ is no longer held.
4. Edits via `TextEditor.edit(_:instruction:language:)`.
5. Pastes the result with the existing `TextInjector`; the selection is still selected, so the paste replaces it.

While steps 3–5 run, the HUD shows the working state with "Editing…".

`SelectionReader` (`AXSelectionReader`, Injection module):
- First `kAXFocusedUIElementAttribute` → `kAXSelectedTextAttribute` of the system-wide element. A non-empty result is returned.
- Otherwise: snapshot the pasteboard (`PasteboardSnapshot`), post ⌘C, poll `changeCount` every 20 ms for up to 300 ms, read the string, restore the snapshot. No change or no string → `nil`.
- Whitespace-only selection counts as none.

`TextEditor` (`FoundationModelsEditor`, Cleanup module):
- A fresh `LanguageModelSession` per edit with instructions: *"You edit text. Apply the instruction to the text. Keep the text's language unless the instruction asks for another. Output only the edited text, without quotes or commentary."*
- Prompt: `Instruction: <instruction>\n\nText:\n<selection>`.
- Time limit 10 s (`FoundationModelsEditor.timeout`); temperature 0.
- Output trimmed; wrapping quotes stripped (`CleanupPipeline.stripWrappingQuotes`).
- Errors (`EditError`): `.unavailable` (Apple Intelligence not available), `.tooLong` (selection over 2,000 words — checked before calling the model), `.failed` (timeout, model error/refusal, empty output).

## 3. Errors

New `DictationFailure` cases and HUD messages (nothing is pasted):

| Case | Message |
|---|---|
| `noSelection` | "Select text first" |
| `editUnavailable` | "Command mode needs Apple Intelligence" |
| `selectionTooLong` | "Selection too long" |
| `editFailed` | "Couldn't edit — try again" |

## 4. History and privacy

Commands are **not** stored in History, don't call `onDictationFinished`, and don't update recent apps. The selection never leaves the Mac (on-device model).

## 5. HUD and settings

- `HUDContent.listening` gains `command: Bool`; when true the badge reads "⌃ Edit" (instead of the language) in the highlight colour.
- Working text for commands: "Editing…".
- Settings → General gesture list gains: "Edit: Select text, hold fn+⌃, say what to change". No toggle.

## 6. Testing

Unit (Swift Testing):
- State machine: ⌃ at fn down → `.pressed` then `.commandAdded`; ⌃ later in the hold → `.commandAdded` once; ⌃ without fn → nothing; fn+⌃ quick tap → `.tapped`, no `commandAdded`, doesn't arm; ⌃ while hands-free locked → ignored.
- Mapper: `.commandAdded` → `.makeCommand`.
- Controller (fakes): a command pastes the edited text; the cleaner is not called; `onDictationFinished` is not called; each failure maps to its `DictationFailure`; `makeCommand` outside `.listening` is ignored; a plain hold stays a dictation.
- `AXSelectionReader` ⌘C fallback with a fake pasteboard/key sender: returns the copied text and restores the pasteboard; returns `nil` after 300 ms without a change.
- `FoundationModelsEditor`: `.tooLong` above 2,000 words without calling the model; prompt contains the instruction and the text.

Real model (skipped when Apple Intelligence is unavailable): "make this more formal" on "hey can u send it asap" returns non-empty text that differs from the input and has no standalone "u".

## Out of scope

Writing new text with nothing selected; answering questions; hands-free commands; a command history; custom saved commands.
