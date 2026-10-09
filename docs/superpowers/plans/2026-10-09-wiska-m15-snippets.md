# Wiska M15 Voice Snippets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** "insert my signature" (any of nine languages) anywhere in a dictation inserts saved text verbatim.

**Architecture:** Core gets `Snippet` and per-language insert words/possessives in `FormatRules`; Preferences gets a JSON-backed `SnippetStore`. A pure `SnippetExpander` (Cleanup) swaps triggers for placeholder words before cleanup and fills them in after the style; `CleanupPipeline` protects placeholders (placeholder-only lines skip cleanup; model output that loses one is rejected). The app adds a Snippets tab and a Help section.

**Tech Stack:** Swift 6.2, SwiftPM `WiskaKit` (Core, Preferences, Cleanup), Swift Testing, SwiftUI app `Wiska`.

**Spec:** `docs/superpowers/specs/2026-10-09-wiska-m15-snippets-design.md`

## Global Constraints

- Triggers: `<insert word> [possessive] <name|alias>` anywhere; or a whole dictation `[possessive] <name|alias>`. Case-insensitive; punctuation around words ignored.
- Name matching: exact, or one edit for words of ≥ 5 letters, or a plural "s"/"es"; longest name wins.
- Snippet text is inserted verbatim, at every level (Off too) and in every category (Code too); after the style step.
- Single-line snippets inline (keep surrounding punctuation); multi-line snippets on their own line(s).
- Placeholder token: `wiskasnippet<N>` (N from 1).
- Store file: `AppPaths.file("snippets.json")`; unreadable file → moved to `snippets.corrupt.json`, empty list.
- Tests: `cd WiskaKit && swift test`. App build from repo root: `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build build`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Voice-command line breaks ("new line") must survive extraction — the expander works line by line. Pinned by `SnippetExpanderTests.keepsExistingLines`.
2. A model that drops the placeholder must not lose the snippet. Pinned by `CleanupPipelineTests.snippetSurvivesAModelThatDropsIt`.
3. Very casual must not lowercase the snippet. Pinned by `CleanupPipelineTests.snippetKeepsItsCapitalsInVeryCasual`.
4. Email layout must not treat a signature snippet line as the body or sign-off. Pinned by `CleanupPipelineTests.signatureSnippetInEmail`.
5. Ordinary prose with a snippet name must not trigger. Pinned by `SnippetExpanderTests.proseDoesNotTrigger`.

---

### Task 1: Snippet, insert words, SnippetStore

**Files:**
- Create: `WiskaKit/Sources/Core/Snippet.swift`, `WiskaKit/Sources/Preferences/SnippetStore.swift`
- Modify: `WiskaKit/Sources/Core/FormatRules.swift`
- Test: `WiskaKit/Tests/CoreTests/FormatRulesTests.swift`, `WiskaKit/Tests/PreferencesTests/SnippetStoreTests.swift`

**Interfaces:**
- Produces: `struct Snippet: Codable, Equatable, Identifiable, Sendable { id: UUID; name: String; aliases: [String]; text: String; spokenNames: [String] }`; `FormatRules.insertWords: [[String]]`, `FormatRules.possessives: [[String]]` (init params with default `[]`, merged by `FormatRules.merged`); `SnippetStore(url:)` (`@MainActor @Observable`) with `snippets: [Snippet]`, `add(_:)`, `update(_:)`, `remove(id:)`, `static defaultURL`.

- [ ] **Step 1: Write the failing tests**

Append to `FormatRulesTests`:

```swift
    @Test(arguments: Language.allCases)
    func everyLanguageHasInsertWords(language: Language) {
        #expect(!language.formatRules.insertWords.isEmpty)
        #expect(!language.formatRules.possessives.isEmpty)
    }

    @Test func insertWordsMerge() {
        let merged = FormatRules.merged([.english, .swedish])
        #expect(merged.insertWords.contains(["insert"]))
        #expect(merged.insertWords.contains(["infoga"]))
        #expect(merged.possessives.contains(["min"]))
    }
```

Create `WiskaKit/Tests/PreferencesTests/SnippetStoreTests.swift`:

```swift
import Core
import Foundation
import Testing
@testable import Preferences

@MainActor
struct SnippetStoreTests {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("snippets-\(UUID().uuidString).json")

    @Test func addsUpdatesRemovesAndPersists() {
        let store = SnippetStore(url: url)
        let snippet = Snippet(name: "signature", aliases: ["signatur"], text: "Best regards,\nJohan")
        store.add(snippet)
        var edited = snippet
        edited.text = "Cheers,\nJohan"
        store.update(edited)
        #expect(SnippetStore(url: url).snippets == [edited])
        store.remove(id: snippet.id)
        #expect(SnippetStore(url: url).snippets.isEmpty)
    }

    @Test func corruptFileIsSetAside() throws {
        try Data("not json".utf8).write(to: url)
        #expect(SnippetStore(url: url).snippets.isEmpty)
        let aside = url.deletingLastPathComponent().appendingPathComponent("snippets.corrupt.json")
        #expect(FileManager.default.fileExists(atPath: aside.path))
    }

    @Test func spokenNamesSkipBlanks() {
        let snippet = Snippet(name: " Address ", aliases: ["", "adress"], text: "x")
        #expect(snippet.spokenNames == ["Address", "adress"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter "FormatRulesTests|SnippetStoreTests"`
Expected: FAIL — compile errors (`insertWords`, `SnippetStore`, `Snippet` unknown).

- [ ] **Step 3: Implement**

```swift
// WiskaKit/Sources/Core/Snippet.swift
import Foundation

/// Saved text inserted by voice ("insert my signature").
public struct Snippet: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// What you say ("signature").
    public var name: String
    /// Other spoken names ("signatur", "sign-off").
    public var aliases: [String]
    /// Inserted exactly as written; may span lines.
    public var text: String

    public init(id: UUID = UUID(), name: String, aliases: [String] = [], text: String) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.text = text
    }

    /// The name and aliases, trimmed, without empty ones.
    public var spokenNames: [String] {
        ([name] + aliases).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
```

`FormatRules.swift`: add properties

```swift
    /// "insert", "infoga": the word that asks for a snippet.
    public var insertWords: [[String]]
    /// "my", "min/mitt/mina": optional between the insert word and the snippet's name.
    public var possessives: [[String]]
```

add init parameters `insertWords: [[String]] = [], possessives: [[String]] = []` (assigned in the body), union them in `merged` (`all.insertWords += rules.insertWords; all.possessives += rules.possessives`; `merged`'s initial value passes `insertWords: [], possessives: []`), and add to each language's `FormatRules(...)` call (after `numberExtras`/`markerBlockers`):

- english: `insertWords: phrases(["insert"]), possessives: phrases(["my"])`
- swedish: `insertWords: phrases(["infoga", "lägg in"]), possessives: phrases(["min", "mitt", "mina"])`
- german: `insertWords: phrases(["einfügen", "füge ein"]), possessives: phrases(["mein", "meine", "meinen"])`
- french: `insertWords: phrases(["insérer", "insère"]), possessives: phrases(["mon", "ma", "mes"])`
- spanish: `insertWords: phrases(["insertar", "inserta"]), possessives: phrases(["mi", "mis"])`
- italian: `insertWords: phrases(["inserisci", "inserire"]), possessives: phrases(["il mio", "la mia", "mio", "mia"])`
- portuguese: `insertWords: phrases(["inserir", "insere"]), possessives: phrases(["o meu", "a minha", "meu", "minha"])`
- danish: `insertWords: phrases(["indsæt"]), possessives: phrases(["min", "mit", "mine"])`
- dutch: `insertWords: phrases(["invoegen", "voeg in"]), possessives: phrases(["mijn"])`

```swift
// WiskaKit/Sources/Preferences/SnippetStore.swift
import Core
import Foundation
import Observation

/// The user's snippets, saved as JSON next to the dictionary.
@MainActor @Observable
public final class SnippetStore {
    private static let log = Log.logger("Preferences")

    public nonisolated static var defaultURL: URL { AppPaths.file("snippets.json") }

    public private(set) var snippets: [Snippet]
    @ObservationIgnored private let url: URL

    public init(url: URL = SnippetStore.defaultURL) {
        self.url = url
        snippets = Self.load(from: url)
    }

    public func add(_ snippet: Snippet) {
        snippets.append(snippet)
        save()
    }

    public func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        save()
    }

    public func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snippets).write(to: url, options: .atomic)
        } catch {
            Self.log.error("could not save snippets: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [Snippet] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([Snippet].self, from: data)
        } catch {
            // Never overwrite a file we couldn't read: keep it aside for the user.
            let aside = url.deletingLastPathComponent().appendingPathComponent("snippets.corrupt.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            log.error("snippets.json unreadable; moved to snippets.corrupt.json")
            return []
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd WiskaKit && swift test --filter "FormatRulesTests|SnippetStoreTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(core): snippets, insert words per language, snippet store"
```

---

### Task 2: SnippetExpander

**Files:**
- Create: `WiskaKit/Sources/Cleanup/SnippetExpander.swift`
- Test: `WiskaKit/Tests/CleanupTests/SnippetExpanderTests.swift`

**Interfaces:**
- Consumes: `Snippet`, `FormatRules.insertWords/possessives` (Task 1); `DictionaryCorrector.editDistance(_:_:limit:)` (existing, internal to Cleanup).
- Produces: `SnippetExpander.extract(_ text: String, snippets: [Snippet], rules: FormatRules) -> (text: String, slots: [String: Snippet])`; `SnippetExpander.fill(_ text: String, slots: [String: Snippet]) -> String`; `SnippetExpander.isPlaceholderLine(_ line: String) -> Bool`; `SnippetExpander.placeholders(in: String) -> Set<String>`.

- [ ] **Step 1: Write the failing test**

```swift
// WiskaKit/Tests/CleanupTests/SnippetExpanderTests.swift
import Core
import Testing
@testable import Cleanup

struct SnippetExpanderTests {
    static let signature = Snippet(name: "signature", aliases: ["signatur"], text: "Best regards,\nJohan")
    static let address = Snippet(name: "address", aliases: ["adress"], text: "Storgatan 1, 111 22 Stockholm")
    static let mailSignature = Snippet(name: "mail signature", text: "— J")
    let english = Language.english.formatRules

    func expand(_ text: String, _ snippets: [Snippet] = [signature, address],
                rules: FormatRules = Language.english.formatRules) -> String {
        let extracted = SnippetExpander.extract(text, snippets: snippets, rules: rules)
        return SnippetExpander.fill(extracted.text, slots: extracted.slots)
    }

    @Test func singleLineSnippetGoesInline() {
        #expect(expand("send it to insert my address") == "send it to Storgatan 1, 111 22 Stockholm")
        #expect(expand("send it to insert my address.") == "send it to Storgatan 1, 111 22 Stockholm.")
    }

    @Test func multiLineSnippetGetsItsOwnLines() {
        #expect(expand("thanks for the help insert my signature") == "thanks for the help\nBest regards,\nJohan")
        #expect(expand("insert my signature") == "Best regards,\nJohan")
    }

    @Test func swedishTrigger() {
        #expect(expand("tack för hjälpen infoga min signatur", rules: Language.swedish.formatRules)
                == "tack för hjälpen\nBest regards,\nJohan")
    }

    @Test func wholeDictationIsTheName() {
        #expect(expand("my address") == "Storgatan 1, 111 22 Stockholm")
        #expect(expand("My address.") == "Storgatan 1, 111 22 Stockholm")
    }

    @Test func proseDoesNotTrigger() {
        #expect(expand("my address changed last week") == "my address changed last week")
        #expect(expand("insert my poem here") == "insert my poem here")
    }

    @Test func closeMishearingsMatch() {
        #expect(expand("insert my signatre") == "Best regards,\nJohan")
        #expect(expand("insert my signatures") == "Best regards,\nJohan")
        #expect(expand("insert addres") == "Storgatan 1, 111 22 Stockholm")
    }

    @Test func longestNameWins() {
        #expect(expand("insert my mail signature", [Self.signature, Self.mailSignature]) == "— J")
    }

    @Test func keepsExistingLines() {
        #expect(expand("first line\nsend it to insert my address") == "first line\nsend it to Storgatan 1, 111 22 Stockholm")
    }

    @Test func placeholderLinesAreRecognised() {
        let extracted = SnippetExpander.extract("thanks insert my signature", snippets: [Self.signature], rules: english)
        #expect(extracted.text == "thanks\nwiskasnippet1")
        #expect(SnippetExpander.isPlaceholderLine("wiskasnippet1"))
        #expect(SnippetExpander.isPlaceholderLine(" Wiskasnippet1. "))
        #expect(!SnippetExpander.isPlaceholderLine("thanks wiskasnippet1"))
        #expect(SnippetExpander.placeholders(in: "Send to Wiskasnippet2.") == ["wiskasnippet2"])
    }

    @Test func noSnippetsLeavesTheTextAlone() {
        #expect(expand("insert my signature", []) == "insert my signature")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WiskaKit && swift test --filter SnippetExpanderTests`
Expected: FAIL — `SnippetExpander` not found.

- [ ] **Step 3: Implement**

```swift
// WiskaKit/Sources/Cleanup/SnippetExpander.swift
import Core
import Foundation

/// Voice snippets: "insert my signature" becomes a placeholder word before cleanup, and the
/// snippet's text replaces it after the style — so nothing ever rewrites the snippet.
enum SnippetExpander {
    static let placeholderStem = "wiskasnippet"

    static func extract(_ text: String, snippets: [Snippet], rules: FormatRules) -> (text: String, slots: [String: Snippet]) {
        let names = snippets.flatMap { snippet in
            snippet.spokenNames.map { (words: words($0), snippet: snippet) }
        }.filter { !$0.words.isEmpty }.sorted { $0.words.count > $1.words.count }
        guard !names.isEmpty else { return (text, [:]) }
        var slots: [String: Snippet] = [:]

        func slot(for snippet: Snippet) -> String {
            let key = "\(placeholderStem)\(slots.count + 1)"
            slots[key] = snippet
            return key
        }

        // Whole dictation: just "[my] address".
        let all = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var rest = all.map(bare)
        if let possessive = rules.possessives.first(where: { rest.starts(with: $0) }) { rest.removeFirst(possessive.count) }
        if let match = names.first(where: { matches(rest[...], $0.words) && rest.count == $0.words.count }) {
            return (slot(for: match.snippet), slots)
        }

        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            var current: [String] = []
            var index = 0
            while index < tokens.count {
                guard let found = trigger(at: index, in: tokens, names: names, rules: rules) else {
                    current.append(tokens[index])
                    index += 1
                    continue
                }
                let key = slot(for: found.snippet)
                if found.snippet.text.contains("\n") {
                    if !current.isEmpty { lines.append(current.joined(separator: " ")) }
                    lines.append(key)
                    current = []
                } else {
                    // Keep the sentence's punctuation after the name ("address." → "<slot>.").
                    let last = tokens[found.end - 1]
                    let trailing = String(last.reversed().prefix { $0.isPunctuation }.reversed())
                    current.append(key + trailing)
                }
                index = found.end
            }
            if !current.isEmpty || tokens.isEmpty { lines.append(current.joined(separator: " ")) }
        }
        return (lines.joined(separator: "\n"), slots)
    }

    static func fill(_ text: String, slots: [String: Snippet]) -> String {
        guard !slots.isEmpty else { return text }
        var result = text
        // Longest keys first, so "wiskasnippet1" doesn't match inside "wiskasnippet10".
        for (key, snippet) in slots.sorted(by: { $0.key.count > $1.key.count }) {
            let lone = "(?im)^[ \\t]*\(key)[.,;:!?]?[ \\t]*$"
            if snippet.text.contains("\n"),
               let regex = try? NSRegularExpression(pattern: lone) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                        withTemplate: NSRegularExpression.escapedTemplate(for: snippet.text))
            }
            if let regex = try? NSRegularExpression(pattern: "(?i)\(key)") {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                        withTemplate: NSRegularExpression.escapedTemplate(for: snippet.text))
            }
        }
        return result
    }

    /// A line that is only a placeholder (cleanup may have capitalised it or added a full stop).
    static func isPlaceholderLine(_ line: String) -> Bool {
        let core = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .punctuationCharacters).lowercased()
        return core.hasPrefix(placeholderStem) && core.dropFirst(placeholderStem.count).allSatisfy(\.isNumber)
            && core.count > placeholderStem.count
    }

    static func placeholders(in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\(placeholderStem)\\d+") else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { text[$0].lowercased() } })
    }

    // MARK: Matching

    private static func trigger(at index: Int, in tokens: [String], names: [(words: [String], snippet: Snippet)],
                                rules: FormatRules) -> (snippet: Snippet, end: Int)? {
        let bareTokens = tokens.map(bare)
        guard let insert = rules.insertWords.first(where: { phrase in
            index + phrase.count <= bareTokens.count && Array(bareTokens[index..<index + phrase.count]) == phrase
        }) else { return nil }
        var start = index + insert.count
        if let possessive = rules.possessives.first(where: { phrase in
            start + phrase.count <= bareTokens.count && Array(bareTokens[start..<start + phrase.count]) == phrase
        }) { start += possessive.count }
        for name in names where start + name.words.count <= bareTokens.count {
            if matches(bareTokens[start..<start + name.words.count], name.words) {
                return (name.snippet, start + name.words.count)
            }
        }
        return nil
    }

    private static func matches(_ spoken: ArraySlice<String>, _ name: [String]) -> Bool {
        guard spoken.count == name.count else { return false }
        return zip(spoken, name).allSatisfy { said, word in
            said == word || said == word + "s" || said == word + "es"
                || (word.count >= 5 && DictionaryCorrector.editDistance(said, word, limit: 1) <= 1)
        }
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { bare(String($0)) }.filter { !$0.isEmpty }
    }

    private static func bare(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
}
```

Note: if `DictionaryCorrector.editDistance` is `private`, change it to `static func` (internal) — it is declared `static func editDistance(_ a: String, _ b: String, limit: Int = .max) -> Int` today.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WiskaKit && swift test --filter SnippetExpanderTests`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(cleanup): snippet expander — triggers become placeholders, filled in verbatim"
```

---

### Task 3: The pipeline inserts snippets

**Files:**
- Modify: `WiskaKit/Sources/Cleanup/CleanupPipeline.swift`
- Test: `WiskaKit/Tests/CleanupTests/CleanupPipelineTests.swift`

**Interfaces:**
- Consumes: Task 2.
- Produces: `CleanupPipeline.init(... snippets: @escaping @MainActor () -> [Snippet] = { [] }, timeout:)` — new parameter placed after `style:`.

- [ ] **Step 1: Write the failing tests** (append inside `CleanupPipelineTests`)

```swift
    static let signature = Snippet(name: "signature", text: "Best regards,\nJohan")
    static let address = Snippet(name: "address", text: "Storgatan 1, 111 22 Stockholm")

    func snippetPipeline(_ level: CleanupLevel = .polished, style: WritingStyle = .formal) -> CleanupPipeline {
        CleanupPipeline(level: { level }, rewriter: rewriter, style: { _ in style },
                        snippets: { [Self.signature, Self.address] }, timeout: .seconds(5))
    }

    @Test func snippetKeepsItsCapitalsInVeryCasual() async throws {
        rewriter.isAvailable = false
        let output = try await snippetPipeline(style: .veryCasual)
            .clean("um send it to insert my address", context: DictationContext(language: .english))
        #expect(output == "send it to Storgatan 1, 111 22 Stockholm")
    }

    @Test func snippetsWorkInCodeAndOff() async throws {
        #expect(try await snippetPipeline().clean("insert my signature", context: DictationContext(category: .code))
                == "Best regards,\nJohan")
        #expect(try await snippetPipeline(.off).clean("thanks insert my signature", context: DictationContext())
                == "thanks\nBest regards,\nJohan")
    }

    @Test func snippetSurvivesAModelThatDropsIt() async throws {
        rewriter.transform = { $0.replacingOccurrences(of: "wiskasnippet1", with: "") + "." }
        let output = try await snippetPipeline()
            .clean("please send the parcel to insert my address today", context: DictationContext(language: .english))
        #expect(output.contains("Storgatan 1, 111 22 Stockholm"), "\(output)")
    }

    @Test func signatureSnippetInEmail() async throws {
        rewriter.transform = { _ in "Hi Anna, the report is done." }
        let output = try await snippetPipeline()
            .clean("hi anna the report is done insert my signature",
                   context: DictationContext(language: .english, category: .email))
        #expect(output == "Hi Anna,\n\nThe report is done.\nBest regards,\nJohan")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter CleanupPipelineTests`
Expected: FAIL — `snippets:` argument unknown.

- [ ] **Step 3: Implement**

In `CleanupPipeline`: stored `private let snippets: @MainActor () -> [Snippet]`; init parameter `snippets: @escaping @MainActor () -> [Snippet] = { [] }` after `style:`, assigned in the body. Then in `clean`:

```swift
        // Snippets first: their text never passes through cleanup (placeholders stand in).
        let extracted = SnippetExpander.extract(VoiceCommands.apply(text, rules: rules), snippets: snippets(),
                                                rules: format)
        let slots = extracted.slots
        // The dictionary is spelling, not cleanup: it applies at every level.
        let corrected = DictionaryCorrector.apply(extracted.text, dictionary: dictionary, isKnownWord: isKnownWord)
        guard level != .off else { return SnippetExpander.fill(corrected, slots: slots) }
        // Code gets exactly what was said: no model, no fillers removed, no sentence shape.
        if context.category == .code {
            return SnippetExpander.fill(StyleFinisher.codeSafe(CodeVocabulary.apply(corrected), dictionary: dictionary),
                                        slots: slots)
        }
```

(replacing the existing `let corrected = …`, `guard level != .off …` and Code lines). In the segment loop, before `cleanSegment`:

```swift
            if SnippetExpander.isPlaceholderLine(segment) {
                // A multi-line snippet's own line: nothing to clean.
                lines.append(FormattedLine(text: segment.trimmingCharacters(in: .whitespaces), isPlain: false))
                continue
            }
```

and the final `return lines.map {…}.joined(separator: "\n")` becomes `return SnippetExpander.fill(lines.map {…}.joined(separator: "\n"), slots: slots)`.

In `cleanSegment`, the `.accept` case first checks the placeholders survived:

```swift
            case .accept:
                // A model that lost or changed a snippet placeholder would lose the snippet.
                guard SnippetExpander.placeholders(in: output).isSuperset(of: SnippetExpander.placeholders(in: segment)) else {
                    Self.log.notice("model output rejected: snippet placeholder lost")
                    return RuleCleaner.clean(segment, rules: rules)
                }
                // The model never sees the dictionary; re-apply so it can't undo the user's spellings.
                return DictionaryCorrector.apply(output, dictionary: dictionary, isKnownWord: isKnownWord)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd WiskaKit && swift test --filter "CleanupTests"`
Expected: PASS — all Cleanup tests.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(cleanup): snippets are inserted verbatim at every level and in every app"
```

---

### Task 4: App — Snippets tab, Help, wiring

**Files:**
- Create: `Wiska/Settings/SnippetsTab.swift`
- Modify: `Wiska/AppModel.swift`, `Wiska/Settings/SettingsView.swift`, `Wiska/Settings/HelpTab.swift`

**Interfaces:**
- Consumes: Tasks 1–3.

- [ ] **Step 1: Wire the store**

`AppModel`: `let snippetStore: SnippetStore`; in `init`, create `let snippetStore = SnippetStore()` next to `dictionaryStore`, assign `self.snippetStore = snippetStore`, and pass `snippets: { snippetStore.snippets }` to `CleanupPipeline(... style: { settings.style(for: $0) }, snippets: { snippetStore.snippets })`.

- [ ] **Step 2: Snippets tab**

```swift
// Wiska/Settings/SnippetsTab.swift
import Core
import Preferences
import SwiftUI

/// Saved texts inserted by voice ("insert my signature").
struct SnippetsTab: View {
    let store: SnippetStore
    @State private var selection: UUID?

    var body: some View {
        Form {
            Section {
                if store.snippets.isEmpty {
                    Text("No snippets yet.").foregroundStyle(.secondary)
                }
                ForEach(store.snippets) { snippet in
                    Button {
                        selection = selection == snippet.id ? nil : snippet.id
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                            Text(snippet.text.components(separatedBy: "\n").first ?? "")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if selection == snippet.id {
                        SnippetEditor(snippet: snippet, store: store) { selection = nil }
                    }
                }
                Button("Add Snippet") {
                    let snippet = Snippet(name: "", text: "")
                    store.add(snippet)
                    selection = snippet.id
                }
            } header: {
                Text("Snippets")
            } footer: {
                Text("Say “insert my <name>” — in Swedish “infoga min <name>” — anywhere in a dictation. The text is inserted exactly as written.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 440)
    }
}

private struct SnippetEditor: View {
    let snippet: Snippet
    let store: SnippetStore
    let close: () -> Void
    @State private var name = ""
    @State private var aliases = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name (what you say)", text: $name)
            TextField("Other names, comma-separated", text: $aliases)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            HStack {
                Button("Delete", role: .destructive) {
                    store.remove(id: snippet.id)
                    close()
                }
                Spacer()
                Button("Done") {
                    var edited = snippet
                    edited.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    edited.aliases = aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    edited.text = text
                    store.update(edited)
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            name = snippet.name
            aliases = snippet.aliases.joined(separator: ", ")
            text = snippet.text
        }
    }
}
```

`SettingsView`: after the Dictionary tab add `Tab("Snippets", systemImage: "text.badge.plus") { SnippetsTab(store: model.snippetStore) }`.

`HelpTab`: after the "Editing selected text" section add

```swift
            Section("Snippets") {
                tip("Insert saved text", "Say “insert my signature” (Swedish: “infoga min signatur”) anywhere in a dictation. Add snippets in the Snippets tab.")
                ForEach(model.snippetStore.snippets.filter { !$0.name.isEmpty }) { snippet in
                    LabeledContent(snippet.name, value: "“insert my \(snippet.name)”")
                }
            }
```

- [ ] **Step 3: Build, full suite, manual check, commit**

Run: `cd WiskaKit && swift test`, then from the repo root `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build build`
Expected: all tests pass (1 known Parakeet Danish issue); `** BUILD SUCCEEDED **`.

Manual: add a "signature" snippet (two lines) and an "address" snippet; dictate "thanks for the help insert my signature" in TextEdit and "send it to insert my address" in Messages.

```bash
git add Wiska
git commit -m "feat(app): Snippets tab, Help section, snippets wired into cleanup"
```
