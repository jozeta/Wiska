# Wiska M8 — Hands-free dictation and live preview

## Goal

Dictate without holding fn, and see the words as they are heard. Hold-to-talk stays exactly as it is.

## 1. Hands-free gesture

Decided with the user: **double-tap fn** starts; **an fn tap finishes, Esc cancels**.

`FnKeyStateMachine` (Hotkey) gains a locked state:

- A *quick tap* is fn down → up in under `minimumHold` (0.25 s), uninterrupted. It still emits `.tapped(shifted:)` as today.
- **Arming:** a plain (un-shifted) quick tap arms the machine until `doubleTapWindow` (0.4 s) after its fn up.
- **Second press:** an fn down while armed emits `.pressed(shifted:)` as usual (recording starts at once, so no audio is lost). The ⇧ state of this press picks the language exactly as for a hold.
- **Lock:** if that second press is itself a quick tap, its fn up emits the new `HotkeyEvent.locked` instead of `.tapped`. The machine is now *locked*. If the second press is held past `minimumHold`, it is an ordinary hold (`.released` on fn up).
- **While locked:**
  - fn down: nothing.
  - fn up (any duration): `.released` (finish), and the machine unlocks.
  - Esc key down (key code 53): `.cancelled`, and the machine unlocks.
  - Any other key down, and ⇧: ignored. Keys still reach the frontmost app; Wiska never swallows them.
- A ⇧-tap (fn+⇧ quick tap) never arms, so fn+⇧ taps keep moving to the next language in Toggle mode.
- `KeyInput.keyDown` carries the key code (`keyDown(keyCode: Int64, time:)`); `FnHotkeyMonitor` passes it through.
- `unlock()`: the app calls it when the dictation ends for any other reason (silence stop, 5-minute cap, failure, audio device loss) so the next fn press starts a fresh dictation instead of "finishing" one that's gone.
- `reset()` (event tap was disabled) also clears the locked state and returns true when a dictation was locked or held.

`CommandMapper` maps `.locked` → `DictationCommand.lockHandsFree`. The controller ignores it unless `.listening`; when listening it marks the dictation hands-free and starts the silence watch.

The HUD shows a small lock glyph next to the language badge while hands-free.

## 2. Silence stop

- `SilenceWatch` (Dictation): a value type fed `(level: Float, time: TimeInterval)` from the microphone level stream (0…1, `Levels.normalized`). Levels at or above `speechThreshold` (0.3 ≈ −35 dBFS) count as speech and reset the clock. Once the level has stayed below the threshold for `timeout` seconds, it reports *stop* once.
- Only hands-free dictations are watched; hold-to-talk never auto-stops on silence.
- On *stop* the controller finishes (pastes what was said). A dictation with no speech ends exactly like an empty hold today.
- The existing 5-minute cap (`maxDuration`) still applies to every dictation.
- Setting **Settings → General → Hands-free → "Finish after silence"**: Off, 10 s, 30 s (default), 1 min, 2 min. Stored as seconds (0 = Off) under the key `"handsFreeSilence"`. Read when hands-free starts.

## 3. Live preview

Decided with the user: **one line under the waveform**; **Parakeet shows only the waveform**.

- `TranscriptionSession` gains `var preview: AsyncStream<String> { get }`, defaulting to an empty finished stream.
- **Apple:** `AppleModule` asks for volatile results (`.volatileResults`). Each session yields its text so far — all finalized segments plus the current volatile segment, whitespace-normalized — whenever it changes. The final transcript keeps using finalized results only, so pasted text is unchanged.
- **Parakeet:** no preview (the default empty stream).
- **Auto-detect (Apple `AutoDetectSession`) and hybrid sessions:** the preview follows one session: the language detected last time (`lastDetectedLanguage`) if it is running, otherwise the first running session. The final text is still chosen by the usual judging at the end.
- **Controller:** while `.listening`, forwards the session's preview to `onPreview(String)`. The preview resets to empty on start, language switch, and when the dictation leaves `.listening`.
- **HUD:** `HUDContent.listening` gains `preview: String` and `handsFree: Bool`. When the preview is non-empty, the panel shows one extra text line under the waveform, in the secondary text colour. The line scrolls inside the notch bar like a ticker: the text sits on one line anchored to the right edge, new words slide in from the right (animated), older words move out past the left edge, and the left edge fades out instead of showing "…". The text never widens the panel. The panel stays exactly notch-wide; it grows to the two-row height when the first words arrive (animated with the existing spring) and never shrinks back during that dictation.
- Setting **Settings → General → "Show live preview in the notch"** (shown / hidden): on by default (key `"livePreview"`). When off, no preview is requested from the session and the HUD stays as today.

## 4. Testing

Unit (Swift Testing):
- State machine: a double-tap locks; a slow second press is a hold; a second press after the window is a fresh start; an fn+⇧ first tap doesn't arm; ⇧ on the second press is passed through; in locked mode fn up finishes, Esc cancels, other keys are ignored; `unlock()` and `reset()` clear the lock.
- Mapper: `.locked` → `.lockHandsFree`.
- `SilenceWatch`: stops after the timeout of quiet; speech resets the clock; it reports once; a timeout of 0 never stops.
- Controller: `lockHandsFree` outside `.listening` is ignored; hands-free plus silence finishes and pastes; hold-to-talk with silence doesn't finish; the preview is forwarded and cleared; with the preview off the session's preview isn't forwarded.
- Auto-detect preview follows the preferred language's session.
- HUD layout: the two-row height applies only with a preview.

Real audio (serialized behind `RealAudioGate`): an Apple session's preview yields text before `finish()` returns.

## Out of scope

Editing text in the preview; a preview for Parakeet; a silence stop for hold-to-talk; changing the double-tap window in Settings.
