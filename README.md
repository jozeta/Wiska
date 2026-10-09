# Wiska

Private, on-device dictation for macOS. Hold **fn**, speak, release — your words appear wherever the cursor is, cleaned up and formatted for the app you're in. Nothing you say leaves your Mac.

## Features

- **Push-to-talk anywhere** — hold fn to dictate into any app; release and the text is pasted at the cursor.
- **Hands-free** — double-tap fn and keep talking; tap fn to finish (or let it stop after a configurable silence). Esc cancels.
- **Live preview** — your words scroll through a notch-shaped capsule under a live waveform while you speak.
- **Nine languages** — English, Svenska, Deutsch, Français, Español, Italiano, Português, Dansk and Nederlands, with auto-detect, a toggle, or a hotkey per language (fn+⇧).
- **Two speech engines** — Apple's on-device speech recognition or NVIDIA Parakeet (runs locally on the Neural Engine), chosen per language.
- **Smart cleanup** — filler words and false starts removed by Apple Intelligence on-device, with a safety check that never lets the model answer or invent text.
- **Styles per app** — Casual in Messages and Slack, Formal in Mail, exactly-what-you-said in terminals and code editors. Spoken lists become numbered lists, emails get their greeting and sign-off on their own lines, and numbers become digits ("three thirty" → 3:30).
- **Voice commands** — "new line", "new paragraph" and "scratch that", in every language.
- **Edit by voice** — select text, hold **fn+⌃**, say "make this more formal" or "translate to Swedish", and the selection is rewritten in place (⌘Z undoes it).
- **Personal dictionary** — names and terms spelled your way, plus custom replacements.
- **History** — search and filter past dictations, see exactly what cleanup changed, and track words per day, time saved, top apps and languages. Kept for as long as you choose (or not at all).
- **Insert or copy** — paste into the active app, or only copy to the clipboard.

## Requirements

- macOS 26 or later on Apple Silicon.
- Apple Intelligence turned on, for cleanup and editing by voice (dictation works without it).
- Permissions: **Microphone** (to hear you) and **Accessibility** (to read the fn key and paste).

## Using Wiska

| Do this | To |
|---|---|
| Hold fn, speak, release | Dictate |
| Hold fn+⇧ | Dictate in your second language |
| Double-tap fn · tap fn | Start / finish hands-free |
| Esc, or any other key while holding fn | Cancel |
| Select text, hold fn+⌃, say an instruction | Edit the selection |

Tip: set **System Settings → Keyboard → "Press 🌐 key to" → Do Nothing**, so fn doesn't also open the emoji picker.

Settings has a **Help** tab with examples, voice commands for each of your languages, and troubleshooting.

## Privacy

Speech recognition, cleanup and editing all run on your Mac. Wiska makes no network requests except downloading speech models when you ask for them (Apple's language assets, or the Parakeet model from Hugging Face) and, if Parakeet is installed, a small check every few days whether a newer Parakeet model exists — turn it off with Settings → Speech → Check for model updates → Never. History is stored locally in `~/Library/Application Support/Wiska` and can be turned off.

## Building from source

1. Install Xcode 26.
2. Copy `Local.xcconfig.example` to `Local.xcconfig` and set your `DEVELOPMENT_TEAM`.
3. Build and run the `Wiska` scheme in `Wiska.xcodeproj`, or from the terminal:

   ```sh
   xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build build
   open build/Build/Products/Debug/Wiska.app
   ```

The app's logic lives in the Swift package `WiskaKit` (modules Core, Hotkey, Audio, SpeechToText, Parakeet, Cleanup, Injection, Dictation, HUD, Preferences, History). Run its tests with:

```sh
cd WiskaKit && swift test
```

Design notes and implementation plans for each milestone are in `docs/superpowers/`.

## License

[MIT](LICENSE) © 2026 Johan Zetterström
