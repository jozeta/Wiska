# Wiska M15 — Voice snippets

## Goal

Say "insert my signature" (or "infoga min adress") anywhere in a dictation and get saved text, exactly as written, at that spot.

Decided with the user: snippets trigger **inside any dictation** with an insert word ("insert …"), or when a dictation is **only** the name ("my signature"); ordinary prose ("my address changed") never triggers.

## 1. Behaviour

- **Snippet:** `name` (what you say, e.g. "signature"), `aliases` (other spoken names, e.g. "signatur", "sign-off"), `text` (verbatim, may span lines).
- **Trigger forms** (case-insensitive, punctuation around words ignored):
  - `<insert word> [possessive] <name or alias>` anywhere in the dictation;
  - a dictation that is exactly `[possessive] <name or alias>` (after trimming punctuation).
- **Insert words** and optional **possessives** per language — exact lists in §3 (en "insert" + "my"; sv "infoga" + "min/mitt/mina").
- **Matching names:** exact (case-insensitive) or, for names/aliases of ≥ 5 letters, one edit away (`DictionaryCorrector.editDistance`); a plural "-s" also matches. The longest matching name wins ("mail signature" over "signature").
- **Output:** the snippet text exactly as saved — no cleanup, style, casing, formatting, dictionary — in every category and at every level (including Off and Code).
  - Single-line snippet: replaces the trigger inline ("send it to insert my address" → "Send it to Storgatan 1, 111 22 Stockholm.").
  - Multi-line snippet: on its own line(s); the text before it stays a separate line ("thanks for the help insert my signature" → "Thanks for the help.\nBest regards,\nJohan").
- **No match:** the words stay as said.
- History stores the pasted text (with the snippet).

## 2. Pipeline

`SnippetExpander` (Cleanup):

- `extract(_ text: String, snippets: [Snippet], rules: FormatRules) -> (text: String, slots: [String: Snippet])` replaces each trigger with a placeholder token `wiskasnippetN` (N = 1…; a word that no language uses and the guard treats as an ordinary word). For a multi-line snippet the placeholder is surrounded by `\n`, so it is its own line.
- `fill(_ text: String, slots:) -> String` replaces each placeholder (case-insensitive) by the snippet text. For a multi-line snippet, punctuation the cleanup attached to its placeholder line (`.`) is dropped; a single-line snippet keeps the sentence's punctuation around it.

`CleanupPipeline.clean` order:

1. Voice commands.
2. **Snippet extract.**
3. Dictionary, then Off / Code / per-line cleanup and formatters as today. A line that is only a placeholder is passed through untouched (no model, rule cleaner, list, email or style). Model output that lost or altered a placeholder is rejected (rule cleanup for that line).
4. **Snippet fill** — last, after the style.

The pipeline gets `snippets: @MainActor () -> [Snippet]` (default empty).

## 3. Data

- Core: `struct Snippet: Codable, Equatable, Identifiable, Sendable { id: UUID; name: String; aliases: [String]; text: String }`; `spokenNames` = name + aliases, trimmed, non-empty.
- `FormatRules` gains `insertWords: [[String]]` and `possessives: [[String]]` (phrases, so "il mio" works):
  - en: insert; possessives my
  - sv: infoga, lägg in; min, mitt, mina
  - de: einfügen, füge ein; mein, meine, meinen
  - fr: insérer, insère; mon, ma, mes
  - es: insertar, inserta; mi, mis
  - it: inserisci, inserire; il mio, la mia, mio, mia
  - pt: inserir, insere; o meu, a minha, meu, minha
  - da: indsæt; min, mit, mine
  - nl: invoegen, voeg in; mijn
- Preferences: `SnippetStore` (`@Observable`, JSON at `AppPaths.file("snippets.json")`): `snippets`, `add(_:)`, `update(_:)`, `remove(id:)`; unreadable file → empty, logged.

## 4. Settings and Help

- New tab **Snippets** (after Dictionary): a list (name, first line of text); **+** adds; selecting one edits name, other names (comma-separated), and multi-line text; delete button. Caption: "Say “insert my <name>” — in Swedish “infoga min <name>” — anywhere in a dictation."
- Help tab: a "Snippets" section listing your snippet names with the phrase to say.

## 5. Testing

- Matching: "insert my signature"; Swedish "infoga min signatur" with alias "signatur"; whole-dictation "my address"; one typo ("signatur" for "signature"); plural; longest name wins; "my address changed" doesn't trigger; unknown name stays text.
- Placement: single-line inline; multi-line on its own lines; snippet at start/end.
- Pipeline (fake rewriter): Very casual leaves the snippet's capitals; Code and Off insert it; a model that drops the placeholder → rule cleanup, snippet still inserted; lists/email formatting don't touch snippet lines.
- `SnippetStore` round-trip and corrupt file.

## Out of scope

Snippet variables (date, clipboard); per-app snippets; importing/exporting snippets.
