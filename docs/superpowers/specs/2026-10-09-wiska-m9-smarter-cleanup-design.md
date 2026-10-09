# Wiska M9 — Smarter cleanup: style per app and formatting

## Goal

Cleanup that fits where you are typing. A message to a friend reads like a message, an email reads like an email, a terminal gets exactly what you said, and spoken lists, numbers and email greetings come out formatted.

Decided with the user: **app categories** with a style each (not per-app styles); formatting = **lists, email layout, numbers/dates/times, code-safe apps**; approach **A (hybrid)**: the model rewords and writes numbers, deterministic rules do layout and style punctuation.

## 1. Categories and styles

New in Core:

- `AppCategory`: `personal`, `work`, `email`, `code`, `other` (`String` raw values, `CaseIterable`, `Codable`, `displayName`: "Personal messages", "Work chat", "Email", "Code", "Other").
- `WritingStyle`: `formal`, `casual`, `veryCasual` (raw values, `displayName`: "Formal", "Casual", "Very casual", and an `example` sentence for Settings).
- `AppCatalog.category(for bundleID: String?, overrides: [String: AppCategory]) -> AppCategory`: the user's override first, then the built-in list, otherwise `.other` (also for `nil`). Built-in list:
  - personal: `com.apple.MobileSMS`, `net.whatsapp.WhatsApp`, `org.whispersystems.signal-desktop`, `ru.keepcoder.Telegram`, `com.hnc.Discord`
  - work: `com.tinyspeck.slackmacgap`, `com.microsoft.teams2`, `com.microsoft.teams`, `us.zoom.xos`
  - email: `com.apple.mail`, `com.microsoft.Outlook`, `com.readdle.smartemail-Mac`, `it.bloop.airmail2`
  - code: `com.apple.Terminal`, `com.googlecode.iterm2`, `com.apple.dt.Xcode`, `com.microsoft.VSCode`, `com.todesktop.230313mzl4w4u92` (Cursor), `dev.zed.Zed`, `dev.warp.Warp-Stable`, `com.mitchellh.ghostty`
- Default styles: personal → casual, work → casual, email → formal, other → formal. Code has no style (always code-safe).

What a style does to the final text:

- **Formal:** as today — first letter capitalized, ends with `.`, `?`, `!`, `…` or `:` (a `.` is added if missing).
- **Casual:** capitals and inner punctuation kept; a single trailing `.` at the very end of the text is removed. `?`, `!`, `…` stay.
- **Very casual:** like Casual, and everything is lower-cased except the word "I" (English) and words that appear in the personal dictionary (matched case-insensitively, written as the dictionary spells them).

The cleanup **level** (Off / Light / Polished) still decides what is removed; the **style** decides how it looks. **Off is fully raw**: no style, no formatting, in every category (today's behaviour).

## 2. Cleanup order

`CleanupPipeline.clean` runs:

1. Voice commands, then the personal dictionary — every category, every level (as today).
2. If the level is Off: return.
3. **Code category:** no model, no filler removal, no formatting. Remove one trailing `.` that the engine added and lower-case the first character unless the first word is in the dictionary or is "I". Return.
4. Per line (split on `\n`, as today): the model (guarded, time-boxed) for lines longer than 3 words, otherwise or on failure the rule cleaner. The model's instructions gain the style (Section 4) and numbers: *"Write numbers, times, dates and percentages as digits, following \<language\>'s conventions."* Light keeps "do not change any other word" with that one exception.
5. `ListFormatter.format(_:rules:)` on each line.
6. `EmailLayout.format(_:rules:)` on the whole text — Email category only.
7. `StyleFinisher.finish(_:style:dictionary:)` — replaces `finishSentence`. It applies to plain sentences only: lines produced by the list or email formatters keep their own punctuation (a list item gets no added `.`; the greeting line keeps its `,`).

Steps 5–7 are plain string rules (microseconds); the 1 s cleanup budget is unchanged.

## 3. Formatters

New `LanguageRules` fields, filled for all nine languages:

- `listMarkers: [[String]]` — index *n* holds the spoken forms of item *n+1* (each form may be several words), e.g. English `[["first", "firstly", "number one"], ["second", "secondly", "number two"], …]` up to ten; Swedish `[["först", "för det första", "nummer ett"], ["sen", "sedan", "för det andra", "nummer två"], …]`.
- `greetings: Set<String>` — e.g. English `hi, hello, hey, dear`; Swedish `hej, hejsan, hallå, kära`; German `hallo, liebe, lieber, sehr geehrte, sehr geehrter`.
- `signOffs: [[String]]` — e.g. English `best, best regards, kind regards, regards, thanks, thank you, cheers`; Swedish `med vänliga hälsningar, vänliga hälsningar, hälsningar, mvh, tack`.
- `numberWords` gains ordinals (first … thirty-first where the language forms them as words), month names and the percent word, so "the fifth of May" → "5 May" passes the guard.

`LanguageRules.merged` unions the new fields like the existing ones.

**ListFormatter** (one line in, one or more lines out):

- A marker counts only at the start of a clause: the start of the line, or right after `,` `;` `:` `.`.
- A list needs markers for items 1 and 2 at least, in order, each at a clause start, with no skipped number. Item 3+ continue the list while the next number follows.
- Output: text before the first marker (if any) as an intro line ending with `:` (replacing a trailing `,`/`.`); then `1. <item>` per item on its own line; the item's first letter capitalized, its trailing `,` `;` `.` removed. Text after the last item stays in the last item.
- Anything else — one marker, markers out of order, a marker mid-clause ("the first time") — leaves the line untouched.

**EmailLayout** (Email category only, whole text):

- Greeting: the text starts with a greeting word followed by 0–3 name words up to the first `,`, `.` or `!` (or the end of the 4th word). That becomes its own line ending in `,`, followed by a blank line.
- Sign-off: the last sentence starts with a sign-off phrase, optionally followed by 1–3 name words. It becomes: blank line, the phrase capitalized plus `,`, newline, the name (if any).
- A sign-off word anywhere else ("thanks for the update") is not a sign-off. No greeting / no sign-off → that part is untouched.

**StyleFinisher:** as in Section 1, on lines the formatters did not produce.

## 4. Wiring and settings

- `DictationContext` gains `category: AppCategory` (default `.other`); the app's `contextProvider` resolves it with `AppCatalog` and the user's overrides.
- `CleanupPipeline.init` gains `style: @MainActor (AppCategory) -> WritingStyle` (default: the built-in defaults).
- `TextRewriter.rewrite(_:level:language:style:)` and `prewarm(level:)`. Instructions per style: Formal — "Use complete sentences." Casual/Very casual — "Keep the wording plain and conversational; never make it more formal." The prewarmed session is used only when its (level, language = nil, style) matches; otherwise a fresh session (as for per-language sessions today).
- `SettingsStore`:
  - `categoryStyles: [AppCategory: WritingStyle]` (key `"categoryStyles"`, stored as `[String: String]`; missing entries → defaults).
  - `appCategories: [String: AppCategory]` (key `"appCategories"`, `[String: String]`).
  - `recentApps: [String]` (key `"recentApps"`, most recent first, max 12, bundle IDs); updated when a dictation finishes with text.
- Settings → Cleanup gains a **Styles** section: one row per category except Code — picker (Formal / Casual / Very casual) and the style's example in the caption; a Code row reads "Code — exactly what you say (no rewrite)". Below, **Apps**: the recent apps (icon + name via `NSWorkspace`), each with a category picker; changing it writes `appCategories`. A "Reset" button clears the overrides.

## 5. Errors and edge cases

- Unknown or missing bundle ID → Other.
- Formatters never add or drop words except list markers (and never touch text when their pattern isn't fully matched).
- History stores the final formatted text (as today).
- Model unavailable or rejected → rule cleanup, then the same formatters and style; numbers stay as words.
- Lines of ≤ 3 words skip the model (as today), so a lone "three thirty" stays as words.

## 6. Testing

Unit (Swift Testing):

- `AppCatalog`: built-in list, override wins, `nil` → other.
- `ListFormatter`: English and Swedish 3-item lists, intro + list, a single "first" stays prose, markers mid-clause, out-of-order markers, a list in each of the other seven languages (table).
- `EmailLayout`: greeting + sign-off, greeting only, 1- and 3-word names, "thanks for the update" not a sign-off, Swedish email.
- `StyleFinisher`: each style; `?`/`!` kept; Very casual keeps "I" and dictionary spellings; list/email lines untouched.
- `CleanupPipeline` with a fake rewriter: Code skips the model and strips the engine's `.`; the style reaches the rewriter; Off stays raw; the Email category lays out an email.
- `CleanupGuard`: "the fifth of May" → "5 May" and "femte maj" → "5 maj" accepted; digits out of nowhere still rejected.
- `SettingsStore`: the three new settings round-trip, defaults apply.

Real model (serialized, skipped when Apple Intelligence is unavailable): "we meet at three thirty on the fifth of May" becomes digits.

## Out of scope

Per-app styles (beyond categories); bulleted lists; Markdown/rich text; editing the built-in app list; formatting for addresses, phone numbers or currencies.
