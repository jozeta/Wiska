# SecureWispr — M4 Memory (Dictionary + History) Design

Date: 2026-10-08
Status: Draft for review
Builds on: M1, M2, M3 specs (same date)

## 1. Intent

Let SecureWispr learn the user's own words (names, places, product terms) and
keep a short, private history so a dictation pasted into the wrong place can be
rescued.

**Stated by user:** dictionary = words + replacement rules, never fed to the
cleanup model; history kept 7 days by default, configurable.

**Assumed:** dictionary applies at every cleanup level including Off; history
records the raw transcript and the final pasted text; no sync, no export in M4.

**Success:** dictionary terms come out spelled right in both languages for
the user's own dictations (≥ 8 of 10 term occurrences); no correctly
transcribed ordinary word is ever changed into a dictionary term; history
shows the last 7 days, searchable, and Copy restores any entry.

## 2. Verified facts (probed 2026-10-08)

Synthetic speech, `AnalysisContext.contextualStrings[.general] =
["Kvarnholmen", "Ylva Zetterström", "SecureWispr", "Jozeta"]`:

| Engine | Without | With |
|---|---|---|
| DictationTranscriber sv_SE | "…till Ylva, Zetterström och Josef" | "…till Ylva Zetterström och Jozeta" |
| SpeechTranscriber en_US | "…a Kvarnholman report to Iel Vazeterstrom and Lupin secure whisper." | identical (hints ignored) |

Foundation Models given the same vocabulary corrected "Kvarnholman" and
"Iel Vazeterstrom" but also changed a real "Josef" into "Jozeta" and missed
"secure whisper" → rejected as a mechanism.

## 3. Dictionary

### 3.1 Model (`Core`)

```swift
public struct PersonalDictionary: Codable, Equatable, Sendable {
    public var words: [String]                 // "Kvarnholmen", "Ylva Zetterström"
    public var replacements: [Replacement]     // heard → written
}
public struct Replacement: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var heard: String                   // "secure whisper"
    public var written: String                 // "SecureWispr"
}
```

Stored as pretty-printed JSON at
`~/Library/Application Support/SecureWispr/dictionary.json` by
`DictionaryStore` (`Preferences` module), `@Observable`, saved on every change.
Missing or corrupt file → empty dictionary (corrupt file is renamed
`dictionary.corrupt.json`, never silently overwritten). Empty / whitespace
entries are dropped; duplicates (case-insensitive) collapse.

### 3.2 Uses

1. **Transcriber hints:** `AppleTranscriber` sets
   `AnalysisContext.contextualStrings[.general] = words` on every session (both
   languages; English ignores it). Parakeet gets no hints in M4.
2. **`DictionaryCorrector` (pure, `Cleanup` module)**, applied in
   `CleanupPipeline` **before** the model at every level (including Off) and
   **again after** an accepted model rewrite:
   - **Replacements first:** case-insensitive, whole-word match of `heard`
     (words separated by spaces/commas in the transcript) → `written`.
   - **Near-miss words:** for each dictionary word/phrase of *n* words, compare
     with every *n*-word window of the text (punctuation stripped, lowercased,
     diacritics kept). Replace when
     `editDistance ≤ 1` for entries of 5–7 letters, `≤ 2` for ≥ 8 letters
     (letters counted without spaces), entries < 5 letters never fuzzy-match,
     the window isn't already an exact match, and the window's first letter
     equals the entry's first letter. Trailing punctuation of the window is kept.
   - Never applied inside a word (whole-word windows only).
3. **The cleanup model never sees the dictionary.**

## 4. History

### 4.1 Record (`Core`)

```swift
public struct DictationRecord: Sendable, Equatable {
    public var date: Date
    public var appBundleID: String?
    public var language: Language?
    public var engine: SpeechEngine
    public var rawText: String
    public var finalText: String
    public var pasted: Bool          // false = paste failed (kept for rescue)
}
```

### 4.2 Store (`History` module, SwiftData)

- `@Model HistoryEntry` mirrors the record. `HistoryStore` (@MainActor) wraps a
  `ModelContainer` at `~/Library/Application Support/SecureWispr/History.store`
  (in-memory for tests): `add`, `entries(matching:)` newest first,
  `delete`, `deleteAll`, `purge(olderThan:)`.
- Retention (`SettingsStore.historyRetention`): `.off`, `.day`, `.week`
  (default), `.month`, `.forever`. Purge at launch, hourly, and immediately when
  the setting changes; `.off` deletes everything and stops recording.
- Never logged; never leaves the Mac.

### 4.3 Recording

`DictationController.onDictationFinished: (@MainActor (DictationRecord) -> Void)?`
fires after a successful paste (`pasted: true`) and after a paste failure other
than secure input (`pasted: false`). Never on secure input, no-speech,
transcription failure or cancel. The app builds nothing itself; it just stores
the record when retention ≠ `.off`.

### 4.4 History window

Menu bar ▸ "History…" opens a `Window` scene (activated to the front like
Settings): search field (matches raw or final text, case-insensitive), list
newest first showing time, app name, language flag, final text (2 lines),
"⚠ not pasted" badge when `pasted == false`; row actions Copy (final text) and
Delete; toolbar "Clear All" with confirmation.

## 5. Settings

- **Dictionary** section: "Words" list with add field and delete; "Replacements"
  list of heard → written pairs with add and delete; caption explaining that
  words also help Swedish recognition.
- **History** section: retention picker; "Open History…" button.

## 6. Error handling

| Situation | Behavior |
|---|---|
| dictionary.json corrupt | Renamed to dictionary.corrupt.json; empty dictionary; logged |
| SwiftData store fails to open | History disabled for the session (menu item shows "History unavailable"); dictation unaffected; logged |
| Record save fails | Logged; dictation unaffected |

## 7. Testing

- **Unit:** DictionaryCorrector (replacement, multi-word replacement, near-miss
  5–7 / ≥ 8 letters, < 5 letters untouched, "Josef" vs "Jozeta" untouched,
  first-letter rule, punctuation kept, Swedish å ä ö, idempotent),
  DictionaryStore (round trip, corrupt file renamed, dedupe/trim),
  CleanupPipeline applies dictionary at Off and re-applies after model,
  HistoryStore in-memory (add, search raw/final, newest first, purge by age,
  deleteAll), retention mapping, controller emits record on success and paste
  failure but not on secure input / no speech / cancel.
- **Integration:** Swedish `say -v Alva` clip containing "Jozeta" transcribed
  with the word in the dictionary contains "Jozeta".
- **Manual acceptance:** add own names/terms, dictate them in SV and EN, rescue
  an entry from History, switch retention to Off and see history cleared.
