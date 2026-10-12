# Wiska — Dictation themes (design)

The user's brief ("Feature Implementation: Configurable Dictation UI Themes for Wiska") is the
requirement. This note records how it maps onto Wiska and the calls made where the brief left room.

## Architecture

- The dictation engine is untouched. `AppModel` already turns `DictationController.State` plus the
  latest `AudioLevel` and preview into one value, `HUDContent`, and hands it to the HUD. That call
  is the only seam.
- `HUD.DictationPresenter` (protocol): `show(_:hideAfter:)`, `highlight`, `deactivate()`.
  Four conformers: `HUDPanelController` (Notch Dropdown, unchanged), `ExpandedNotchController`,
  `OrbController`, `ClippyController`.
- `HUD.DictationThemeController` owns exactly one live presenter. Switching themes deactivates
  and drops the old one (its windows are closed, its timelines stop), creates the new one and
  replays the last `HUDContent`, so a switch mid-dictation never touches recording, recognition
  or insertion. `AppModel` holds a `DictationThemeController` where it held `HUDPanelController`.
- `HUDContent` gains the detail themes need without a second state machine:
  `.listening(…, isCommand:)` and `.working(text, activity:)` (`transcribing`, `editing`,
  `writing`, `preparing`). Completion = a `.working` followed by `.hidden`.
- `HUD.VoiceEnergy`: a smoothed 0…1 voice energy from the same `AudioLevel` frames the waveform
  uses (same noise gate and compressive curve as `WaveformMotion.loudness`, attack/release
  smoothing). The orb and Clippy read it; nothing opens the microphone again.
- `HUD.FloatingPlacement`: pure clamping of a saved window frame to the screens present now.

## Settings (`SettingsStore`, UserDefaults, stable raw values)

| Key | Type | Default |
|---|---|---|
| `dictationTheme` | `DictationTheme` (`notchDropdown`, `expandedNotch`, `orb`, `clippy`) | `notchDropdown` |
| `orbSize` | Double, 80…240 pt (whole footprint incl. glow) | 140 |
| `orbHighlight` | `Highlight?` (nil = the app's highlight colour) | nil |
| `orbWindowBehavior` / `clippyWindowBehavior` | `FloatingWindowBehavior` (`alwaysOnTop`, `desktop`) | `alwaysOnTop` |
| `orbOrigin` / `clippyOrigin` | window origin in global screen coordinates | nil = default spot |

Unknown or missing values fall back to the defaults, so existing installs keep the Notch Dropdown.

## Rulings

- **Expanded Notch height** = the notch's own height (menu-bar height without a notch), so the
  wings read as part of the notch; the waveform is scaled to fit. Wings are 150 pt each side.
- **Floating themes stay visible while idle** (the brief's idle states), and are click-through
  nowhere except on the orb / character itself, which drags the window. They never activate
  Wiska, so the app being dictated into keeps focus; no click starts dictation.
- **Desktop behavior** = window level just above the desktop icons (`desktopIconWindow + 1`),
  `.stationary`, on every Space: normal app windows cover it; it is not hidden by Mission Control.
  Limitation: macOS has no public "embed in desktop" API, and "Show Desktop" moves windows aside
  rather than revealing it as a desktop item.
- **Clippy** is an original vector drawing (SwiftUI paths): a bent-wire paperclip with eyes and
  brows. No Microsoft artwork is used. Its bubble is a separate click-through child window, so it
  moves with the character and can flip above/below and shift sideways at screen edges.
- **Bubble text** = the existing live preview (`controller.preview`), shown only when
  "Show live preview" is on, cleared when the dictation ends — the same rules as the notch.
- **Reduced motion**: the orb and Clippy hold still while idle and drop particles and bouncing.
