# Wiska — M6 Look & Settings Design

Date: 2026-10-08
Status: Draft for review
Builds on: M1–M5, cleanup pass, per-language engines (main @ 48003a6)

## 1. Intent

Polish how Wiska looks and how its settings are organised, before M7 (languages)
adds more settings.

**Stated by user:** the notch graphics are exactly as wide as the notch, not wider;
a smooth, quick animation so the capsule glides down when the hotkey is pressed; a
user-selectable highlight colour that affects the overall graphics including the
waveform (curated presets); a tab-based Settings window with functions grouped
into the right tabs, no scrolling; a launch-at-login setting. On screens without a
notch the capsule has the same width as the notch.

**Assumed:** the current Aurora (teal → violet) look stays the default; the
menu-bar icon, app icon and error red don't change colour.

**Success:** on the MacBook the capsule never extends past the notch; showing and
hiding glides smoothly with no window resizing; picking a swatch recolours the
capsule (badge, waveform, spinner) and the app's gradient accents immediately; every
Settings tab fits without scrolling; with launch at login on, Wiska is running after
logging out and in.

## 2. Notch capsule

### 2.1 Size and placement (`NotchLayout`)

- **Notch screens:** the panel is exactly the notch's width: `auxRight.minX −
  auxLeft.maxX` (331 pt on the user's MacBook), centred on the notch, height
  `safeTop + contentHeight`. `notchPadding` is removed.
- **Screens without a notch:** same width as the built-in notch when one exists
  (`NotchLayout.referenceWidth`, read from the built-in screen at launch; 331 pt
  fallback if no screen has a notch). The capsule hangs from the top of the visible
  frame (just under the menu bar), square top corners and rounded bottom corners,
  so it reads as the same shape.
- Content height stays 44 pt. Content (badge + 20-bar waveform ≈ 160 pt, or a
  one-line message) is centred and limited to the capsule width minus 16 pt side
  insets; long messages truncate with "…".

### 2.2 Glide animation

- The panel keeps a fixed frame while shown and is never resized by animation.
- Inside it, `HUDView` draws the black shape with an animatable `reveal` (0 → 1):
  the shape's visible height is `insetTop + reveal × contentHeight`, clipped from the
  top, so it grows down out of the notch. Content fades in (`opacity = reveal`) and
  slides down 6 pt as it arrives.
- Show: `reveal` animates to 1 with a spring (response 0.28 s, damping 0.85).
  Hide: `reveal` animates to 0 (ease-in, 0.2 s), then the panel is ordered out —
  only if no show happened meanwhile (the existing generation token).
- A show during a running hide reverses from the current `reveal` (SwiftUI
  animations retarget from the presentation value), replacing
  `HUDTransition.expandStart`.
- Content changes while visible (listening → transcribing → message) cross-fade
  without moving the shape.

## 3. Highlight colour

- `Core`: `public enum Highlight: String, CaseIterable, Codable` —
  `aurora` (default), `ocean`, `sunset`, `rose`, `lime`, `amber`, `mono` — each with
  `displayName` and two sRGB hex stops:

  | Preset | Start | End |
  |---|---|---|
  | Aurora | #3EE6C1 | #8B6CFF |
  | Ocean | #4FD8FF | #3D6BFF |
  | Sunset | #FFB347 | #FF5E8A |
  | Rose | #FF7EB6 | #A86BFF |
  | Lime | #C6F25B | #2FD9A6 |
  | Amber | #FFD25E | #FF8A3D |
  | Mono | #F2F4F7 | #8A93A3 |

- `SettingsStore.highlight: Highlight` (key `highlight`, default `.aurora`).
- `HUD`: `AuroraTheme` gains `start(_:)`, `end(_:)`, `gradient(_:)`; the HUD model
  carries the current highlight. Badge text/background, waveform bar gradient
  (interpolated start → end), and the spinner tint use it.
  `HUDPanelController.highlight` is set by `AppModel` and observed live.
- App: History stats tiles and language bar, Onboarding title and check marks use
  the selected highlight instead of fixed teal/violet.
- Unchanged: menu-bar icon (template image), app icon, `danger` red, text colours.

## 4. Settings window in tabs

A SwiftUI `TabView` in the `Settings` scene, each tab a grouped `Form` sized to its
content (no scrolling at the default size):

| Tab | Symbol | Contents |
|---|---|---|
| General | `gearshape` | Launch at login (+ notes, §5); push-to-talk explanation; permissions status line with "Open Setup…" (opens the onboarding checklist) |
| Speech | `waveform` | Engines (Same for all / Per language and pickers); Parakeet card; "not ready" note |
| Languages | `globe` | Language mode; Toggle language; fn / fn+⇧ languages (M7 adds "My languages" here) |
| Cleanup | `sparkles` | Level, its summary, voice-command hint, Apple Intelligence note |
| Dictionary | `character.book.closed` | Words and replacements (existing section) |
| History | `clock` | Retention, note, "Open History…" |
| Appearance | `paintpalette` | Live preview capsule with animated sample waveform; swatches for each `Highlight` |

The existing `SettingsView` sections move into one view per tab
(`Wiska/Settings/*.swift`) so no file holds the whole window.

## 5. Launch at login

- General tab checkbox bound to `SMAppService.mainApp` (`register()` /
  `unregister()`); its state is read from `SMAppService.mainApp.status` each time
  the tab appears, not stored in UserDefaults (System Settings can change it).
- `.requiresApproval` → note "Approve Wiska in System Settings → Login Items" with
  a button that calls `SMAppService.openSystemSettingsLoginItems()`.
- Registration errors show inline in red under the checkbox.
- When the app runs from outside `/Applications`, a caption says the login item
  points at this copy and to re-enable it after moving Wiska to Applications.

## 6. Error handling

- No notch on any screen → 331 pt reference width.
- Unknown stored `highlight` → `.aurora` (existing `SettingsStore.read`).
- `SMAppService` failures never block anything; the checkbox reverts to the real
  status and the error is shown.

## 7. Testing

- `NotchLayout`: notch screen → width equals the notch, x centred on it; no-notch
  screen → reference width, top edge at `visibleFrame.maxY`, centred; reference
  width fallback 331.
- `Highlight`: every preset has two distinct stops; raw values round-trip;
  `SettingsStore.highlight` defaults to `.aurora` and persists.
- HUD reveal maths (pure helper): visible height for reveal 0, 0.5, 1.
- App build covers the tabs and launch-at-login wiring.
- Manual (user): capsule width against the notch, glide on show/hide/quick
  re-show, each swatch in the preview and a real dictation, every tab without
  scrolling, launch at login after logging out and in.

## 8. Out of scope

- Custom colour picker; light-mode capsule; menu-bar icon tinting.
- Moving the app to /Applications or installer work (Distribution).
