# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Wiska is private, on-device dictation for macOS 26+ on Apple Silicon: hold **fn**, speak,
release, and cleaned-up text is pasted at the cursor. It supports nine languages, Apple Speech or
NVIDIA Parakeet, optional KB-Whisper (Swedish) and Gemma models, per-app styles, voice commands,
edit-by-voice (fn+⌃), file transcription, meeting recording, history and Sparkle auto-updates.

## Commands

```sh
xcodebuild -downloadComponent MetalToolchain      # once; MLX, whisper.cpp and the Orb shader need it
cp Local.xcconfig.example Local.xcconfig          # once; set DEVELOPMENT_TEAM (Local.xcconfig is gitignored)

xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build build
open build/Build/Products/Debug/Wiska.app

cd WiskaKit && swift test                         # logic tests
scripts/release.sh NOTES.md                       # Developer ID sign, notarize, zip, write Sparkle appcast.xml
```

Logs: `/usr/bin/log show --last 1h --predicate 'subsystem == "Wiska"' --style compact`.

## Architecture

- `Wiska/`: the app target: SwiftUI menu, onboarding, permissions, login item, history and
  file-transcription views, `Settings/` tabs (General, Speech, Languages, Models, Cleanup,
  Commands, Snippets, Dictionary, Appearance, History, Help).
- `WiskaKit/`: Swift package with all logic, one module per concern: `Core`, `Hotkey`, `Audio`,
  `SpeechToText`, `Parakeet`, `KBWhisper`, `LocalModel`, `Cleanup`, `Injection`, `Dictation`,
  `HUD`, `Preferences`, `History`, `Updates`. Tests in `WiskaKit/Tests/`.
- `docs/superpowers/specs` and `plans`: design notes and per-milestone implementation plans.
  Read the relevant one before changing a feature.

## CI

There is no GitHub Actions CI: WiskaKit needs Xcode 27 / Swift 6.4, and GitHub's hosted macOS
runners only offer Xcode 26.x (Swift 6.3), on which the build crashes. Run `cd WiskaKit && swift test`
locally before pushing. Re-add CI once a runner image ships Xcode 27.

## Rules

- **Privacy is the product.** No network requests except user-requested model downloads and
  the update check. The log must never contain dictated text, selections or cursor context: only
  counts, timings, engine/language and error types.
- **Cleanup must never answer or invent.** Model-based cleanup output goes through
  `CleanupGuard`; keep that check on every rewriter path (Apple Intelligence and local Gemma).
- Terminals and code editors get verbatim output (no rewriting); see `AppCategory` /
  `StyleFinisher`.
- Voice commands and punctuation words must work in every supported language. Add test cases
  for each language when changing `VoiceCommands`.
- Put new logic in `WiskaKit` with tests; keep the app target thin.
- Never commit `Local.xcconfig` or signing material.

## App standards

This repo follows the app standards in `~/Desktop/code/tools/standards/STANDARDS.md` (rule IDs,
severities; decisions and waivers in `.claude-standards`). `claude-check --repo .` checks it.
Lint with `swiftlint lint` (`brew install swiftlint`): errors must be fixed, warnings are listed.
