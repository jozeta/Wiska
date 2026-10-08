# SecureWispr M4 Memory (Dictionary + History) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A personal dictionary (words + replacement rules) that fixes names and terms in both languages, and a private, searchable 7-day dictation history.

**Architecture:** Value types live in `Core`. A pure `DictionaryCorrector` (Cleanup) runs inside `CleanupPipeline` before and after the model; `AppleTranscriber` feeds words to `AnalysisContext.contextualStrings`. The controller emits a `DictationRecord` through a callback; a new `History` module stores records with SwiftData; `Preferences` gains a JSON-backed `DictionaryStore` and a retention setting. The app wires stores, Settings sections and a History window.

**Tech Stack:** Swift 6.2, SwiftData, Speech `AnalysisContext`, Foundation `NSRegularExpression`, SwiftUI `Window`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-08-securewispr-m4-memory-design.md`

## Global Constraints

- The cleanup model never receives the dictionary.
- Dictionary applies at every cleanup level, including Off; applied before the model and again after an accepted rewrite.
- Replacements: case-insensitive, whole words, words separated by spaces/commas.
- Near-miss: entries < 5 letters never fuzzy-match; 5–7 letters → edit distance ≤ 1; ≥ 8 letters → ≤ 2 (letters counted without spaces); first letter must match; whole-word windows only; trailing/leading punctuation of the window kept.
- Dictionary file: `~/Library/Application Support/SecureWispr/dictionary.json`; corrupt file renamed `dictionary.corrupt.json`.
- History store: `~/Library/Application Support/SecureWispr/History.store`; retention `.off/.day/.week/.month/.forever`, default `.week`; purge at launch, hourly, on change; `.off` deletes all and stops recording.
- Record on successful paste (`pasted: true`) and on non-secure paste failure (`pasted: false`); never on secure input, no speech, transcription failure, cancel.
- Never log transcript/record text except `privacy: .private`.
- Package modules depend only on `Core` (Parakeet also FluidAudio); package commands from `SecureWisprKit/`; app build: `xcodebuild -project SecureWispr.xcodeproj -scheme SecureWispr -configuration Debug -derivedDataPath build -allowProvisioningUpdates build`.

## Review Focus

1. **Inflected forms of dictionary words** ("Kvarnholmens", "Stockholms") → left alone, never truncated to the base word. (Test: Task 1 `inflectedFormsAreLeftAlone`.)
2. **Replacement whose written form contains the heard form** ("wispr" → "Secure Wispr") → applying the corrector twice (before and after the model) doesn't produce "Secure Secure Wispr". (Test: Task 1 `replacementIsIdempotentWhenWrittenContainsHeard`.)
3. **Regex special characters in user entries** ("c++", "a.b", "(beta)") → matched literally, no crash. (Test: Task 1 `specialCharactersAreLiteral`.)
4. **Retention shortened** (30 days → 1 day) → older entries disappear immediately, not at the next hourly purge. (Test: Task 6 `applyingShorterRetentionPurgesImmediately`.)
5. **History unavailable or save fails** → dictation still pastes normally. (Test: Task 6 `recordIsIgnoredWhenRetentionIsOff` + the controller callback being fire-and-forget, Task 4 `recordCallbackDoesNotAffectState`.)

---

## File Structure

```
SecureWisprKit/Sources/Core/
  PersonalDictionary.swift      NEW  PersonalDictionary, Replacement, normalized()
  DictationRecord.swift         NEW  DictationRecord, HistoryRetention
  Protocols.swift               MOD  Transcriber.engine (default .apple)
SecureWisprKit/Sources/Cleanup/
  DictionaryCorrector.swift     NEW  replacements + near-miss correction (pure)
  CleanupPipeline.swift         MOD  dictionary provider, applied before/after model
SecureWisprKit/Sources/SpeechToText/
  AppleTranscriber.swift        MOD  vocabulary provider
  AppleTranscriptionSession.swift MOD contextualStrings
SecureWisprKit/Sources/Parakeet/ParakeetTranscriber.swift   MOD engine = .parakeet
SecureWisprKit/Sources/Dictation/DictationController.swift  MOD onDictationFinished
SecureWisprKit/Sources/Preferences/
  DictionaryStore.swift         NEW  JSON-backed observable dictionary
  SettingsStore.swift           MOD  historyRetention
SecureWisprKit/Sources/History/
  HistoryEntry.swift            NEW  SwiftData @Model
  HistoryStore.swift            NEW  add/search/delete/purge/apply(retention:)
SecureWispr/
  AppModel.swift, MenuContent.swift, SettingsView.swift, SecureWisprApp.swift  MOD
  HistoryView.swift             NEW
```

---

### Task 1: Core memory types + DictionaryCorrector

**Files:**
- Create: `SecureWisprKit/Sources/Core/PersonalDictionary.swift`, `SecureWisprKit/Sources/Core/DictationRecord.swift`, `SecureWisprKit/Sources/Cleanup/DictionaryCorrector.swift`
- Test: `SecureWisprKit/Tests/CleanupTests/DictionaryCorrectorTests.swift`, `SecureWisprKit/Tests/CoreTests/MemoryTypesTests.swift`

**Interfaces:**
- Produces (Core, public):
  - `struct Replacement: Codable, Equatable, Sendable, Identifiable { id: UUID; heard: String; written: String; init(id: UUID = UUID(), heard:written:) }`
  - `struct PersonalDictionary: Codable, Equatable, Sendable { words: [String]; replacements: [Replacement]; init(words: [String] = [], replacements: [Replacement] = []); func normalized() -> PersonalDictionary }`
  - `enum HistoryRetention: String, Sendable, CaseIterable, Codable { case off, day, week, month, forever; var displayName: String; func cutoff(now: Date) -> Date? }`
  - `struct DictationRecord: Sendable, Equatable { date, appBundleID, language, engine, rawText, finalText, pasted }`
- Produces (Cleanup): `public enum DictionaryCorrector { static func apply(_ text: String, dictionary: PersonalDictionary) -> String }`

- [ ] **Step 1: Write the failing tests**

`Tests/CleanupTests/DictionaryCorrectorTests.swift`:
```swift
import Core
import Testing
@testable import Cleanup

struct DictionaryCorrectorTests {
    private func fix(_ text: String, words: [String] = [], _ replacements: [(String, String)] = []) -> String {
        DictionaryCorrector.apply(text, dictionary: PersonalDictionary(
            words: words, replacements: replacements.map { Replacement(heard: $0.0, written: $0.1) }))
    }

    @Test func replacementsAreCaseInsensitiveWholeWords() {
        #expect(fix("please loop in Secure whisper today", [("secure whisper", "SecureWispr")])
                == "please loop in SecureWispr today")
        #expect(fix("secure, whisper", [("secure whisper", "SecureWispr")]) == "SecureWispr")
        #expect(fix("insecure whispering", [("secure whisper", "SecureWispr")]) == "insecure whispering")
    }

    @Test func nearMissIsCorrected() {
        #expect(fix("send the Kvarnholman report", words: ["Kvarnholmen"]) == "send the Kvarnholmen report")
    }

    @Test func punctuationAroundTheWordIsKept() {
        #expect(fix("to Kvarnholman.", words: ["Kvarnholmen"]) == "to Kvarnholmen.")
        #expect(fix("(Kvarnholman),", words: ["Kvarnholmen"]) == "(Kvarnholmen),")
    }

    @Test func multiWordEntries() {
        #expect(fix("send to Ylva Zeterström now", words: ["Ylva Zetterström"]) == "send to Ylva Zetterström now")
    }

    @Test func casingIsFixed() {
        #expect(fix("ask jozeta", words: ["Jozeta"]) == "ask Jozeta")
    }

    @Test func distantRealNamesAreNotTouched() {
        #expect(fix("ask Josef today", words: ["Jozeta"]) == "ask Josef today")
    }

    @Test func shortEntriesNeverFuzzyMatch() {
        #expect(fix("Anne said hi", words: ["Anna"]) == "Anne said hi")
    }

    @Test func firstLetterMustMatch() {
        #expect(fix("Carlsson called", words: ["Karlsson"]) == "Carlsson called")
    }

    @Test func distanceLimitsDependOnLength() {
        #expect(fix("Kvarnholmn", words: ["Kvarnholmen"]) == "Kvarnholmen")       // 11 letters, 1 edit
        #expect(fix("Kvarnhalman", words: ["Kvarnholmen"]) == "Kvarnholmen")      // 2 edits allowed
        #expect(fix("Kvorrhalman", words: ["Kvarnholmen"]) == "Kvorrhalman")      // 4 edits: no
        #expect(fix("Jozita", words: ["Jozeta"]) == "Jozeta")                     // 6 letters, 1 edit
        #expect(fix("Josita", words: ["Jozeta"]) == "Josita")                     // 2 edits: no
    }

    @Test func inflectedFormsAreLeftAlone() {
        #expect(fix("på Kvarnholmens kontor", words: ["Kvarnholmen"]) == "på Kvarnholmens kontor")
        #expect(fix("Stockholms stad", words: ["Stockholm"]) == "Stockholms stad")
    }

    @Test func replacementIsIdempotentWhenWrittenContainsHeard() {
        let once = fix("try wispr now", [("wispr", "Secure Wispr")])
        #expect(once == "try Secure Wispr now")
        #expect(fix(once, [("wispr", "Secure Wispr")]) == "try Secure Wispr now")
    }

    @Test func specialCharactersAreLiteral() {
        #expect(fix("I write c plus plus", [("c plus plus", "C++")]) == "I write C++")
        #expect(fix("version a.b (beta) ships", [("(beta)", "β")]) == "version a.b β ships")
    }

    @Test func applyingTwiceChangesNothing() {
        let dictionary = ["Kvarnholmen", "Ylva Zetterström"]
        let once = fix("Kvarnholman och Ylva Zeterström", words: dictionary)
        #expect(fix(once, words: dictionary) == once)
    }

    @Test func emptyDictionaryChangesNothing() {
        #expect(fix("hello Kvarnholman") == "hello Kvarnholman")
    }
}
```

`Tests/CoreTests/MemoryTypesTests.swift`:
```swift
import Foundation
import Testing
@testable import Core

struct MemoryTypesTests {
    @Test func normalizedTrimsDropsEmptiesAndDedupes() {
        let dictionary = PersonalDictionary(
            words: ["  Kvarnholmen ", "kvarnholmen", "", "Jozeta"],
            replacements: [Replacement(heard: " secure whisper ", written: "SecureWispr"),
                           Replacement(heard: "", written: "x"),
                           Replacement(heard: "Secure Whisper", written: "Other")]
        ).normalized()
        #expect(dictionary.words == ["Kvarnholmen", "Jozeta"])
        #expect(dictionary.replacements.map(\.heard) == ["secure whisper"])
    }

    @Test func retentionCutoffs() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(HistoryRetention.forever.cutoff(now: now) == nil)
        #expect(HistoryRetention.week.cutoff(now: now) == now.addingTimeInterval(-7 * 86_400))
        #expect(HistoryRetention.off.cutoff(now: now) == now)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter "DictionaryCorrectorTests|MemoryTypesTests"`
Expected: compile FAIL — `PersonalDictionary`, `DictionaryCorrector` not found.

- [ ] **Step 3: Implement the Core types**

`Sources/Core/PersonalDictionary.swift`:
```swift
import Foundation

/// A spoken form and how the user wants it written ("secure whisper" → "SecureWispr").
public struct Replacement: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var heard: String
    public var written: String

    public init(id: UUID = UUID(), heard: String, written: String) {
        self.id = id
        self.heard = heard
        self.written = written
    }
}

/// The user's own words and replacement rules.
public struct PersonalDictionary: Codable, Equatable, Sendable {
    public var words: [String]
    public var replacements: [Replacement]

    public init(words: [String] = [], replacements: [Replacement] = []) {
        self.words = words
        self.replacements = replacements
    }

    /// Trimmed, without empty entries, first occurrence wins for case-insensitive duplicates.
    public func normalized() -> PersonalDictionary {
        var seenWords = Set<String>()
        let words = self.words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seenWords.insert($0.lowercased()).inserted }
        var seenHeard = Set<String>()
        let replacements = self.replacements.compactMap { replacement -> Replacement? in
            let heard = replacement.heard.trimmingCharacters(in: .whitespacesAndNewlines)
            let written = replacement.written.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !heard.isEmpty, !written.isEmpty, seenHeard.insert(heard.lowercased()).inserted else { return nil }
            return Replacement(id: replacement.id, heard: heard, written: written)
        }
        return PersonalDictionary(words: words, replacements: replacements)
    }
}
```

`Sources/Core/DictationRecord.swift`:
```swift
import Foundation

/// How long dictation history is kept.
public enum HistoryRetention: String, Sendable, CaseIterable, Codable {
    case off
    case day
    case week
    case month
    case forever

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .day: "1 day"
        case .week: "7 days"
        case .month: "30 days"
        case .forever: "Forever"
        }
    }

    /// Entries older than this are deleted; nil keeps everything.
    public func cutoff(now: Date) -> Date? {
        switch self {
        case .off: now
        case .day: now.addingTimeInterval(-86_400)
        case .week: now.addingTimeInterval(-7 * 86_400)
        case .month: now.addingTimeInterval(-30 * 86_400)
        case .forever: nil
        }
    }
}

/// One finished dictation, as kept in history.
public struct DictationRecord: Sendable, Equatable {
    public var date: Date
    public var appBundleID: String?
    public var language: Language?
    public var engine: SpeechEngine
    public var rawText: String
    public var finalText: String
    /// False when pasting failed — kept so the text can be rescued.
    public var pasted: Bool

    public init(date: Date, appBundleID: String?, language: Language?, engine: SpeechEngine,
                rawText: String, finalText: String, pasted: Bool) {
        self.date = date
        self.appBundleID = appBundleID
        self.language = language
        self.engine = engine
        self.rawText = rawText
        self.finalText = finalText
        self.pasted = pasted
    }
}
```

- [ ] **Step 4: Implement DictionaryCorrector**

`Sources/Cleanup/DictionaryCorrector.swift`:
```swift
import Core
import Foundation

/// Applies the user's dictionary to text: explicit replacements, then conservative
/// near-miss correction of dictionary words. Pure and idempotent.
public enum DictionaryCorrector {
    public static func apply(_ text: String, dictionary: PersonalDictionary) -> String {
        var result = text
        for replacement in dictionary.replacements {
            result = replace(replacement, in: result)
        }
        // Longest entries first so "Ylva Zetterström" wins over a shorter overlapping entry.
        for entry in dictionary.words.sorted(by: { $0.count > $1.count }) {
            result = correctNearMisses(of: entry, in: result)
        }
        return result
    }

    // MARK: Replacements

    private static func phrasePattern(_ phrase: String) -> String {
        let words = phrase.split(whereSeparator: \.isWhitespace)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        // \b only makes sense next to word characters; use look-arounds so "(beta)" and "c++" work.
        return "(?<![\\p{L}\\p{N}])" + words.joined(separator: "[\\s,]+") + "(?![\\p{L}\\p{N}])"
    }

    private static func replace(_ replacement: Replacement, in text: String) -> String {
        guard let heard = try? NSRegularExpression(pattern: phrasePattern(replacement.heard),
                                                   options: [.caseInsensitive]),
              let written = try? NSRegularExpression(
                pattern: NSRegularExpression.escapedPattern(for: replacement.written), options: [.caseInsensitive])
        else { return text }
        let full = NSRange(text.startIndex..., in: text)
        // Matches that sit inside an existing occurrence of the written form are left alone,
        // so applying twice never yields "Secure Secure Wispr".
        let protected = written.matches(in: text, range: full).map(\.range)
        var result = text
        for match in heard.matches(in: text, range: full).reversed() {
            let inside = protected.contains { NSLocationInRange(match.range.location, $0) }
            guard !inside, let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement.written)
        }
        return result
    }

    // MARK: Near misses

    static func maxDistance(for entry: String) -> Int? {
        let letters = entry.filter { !$0.isWhitespace }.count
        switch letters {
        case ..<5: return nil
        case 5...7: return 1
        default: return 2
        }
    }

    private static func correctNearMisses(of entry: String, in text: String) -> String {
        guard let limit = maxDistance(for: entry) else { return text }
        let entryWords = entry.split(whereSeparator: \.isWhitespace).count
        let entryLower = entry.lowercased()
        guard let tokenRegex = try? NSRegularExpression(pattern: "\\S+") else { return text }
        let tokens = tokenRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
        guard tokens.count >= entryWords else { return text }

        var edits: [(Range<String.Index>, String)] = []
        var index = 0
        while index + entryWords <= tokens.count {
            let window = tokens[index..<(index + entryWords)]
            let span = window.first!.lowerBound..<window.last!.upperBound
            let raw = String(text[span])
            let leading = String(raw.prefix(while: { $0.isPunctuation }))
            let trailing = String(raw.reversed().prefix(while: { $0.isPunctuation }).reversed())
            let core = String(raw.dropFirst(leading.count).dropLast(trailing.count))
            let coreLower = core.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()

            if !core.isEmpty, core != entry,
               coreLower.first == entryLower.first,
               !(coreLower.hasPrefix(entryLower) && coreLower != entryLower),   // inflection: "Kvarnholmens"
               editDistance(coreLower, entryLower) <= limit {
                edits.append((span, leading + entry + trailing))
                index += entryWords
            } else {
                index += 1
            }
        }
        var result = text
        for (range, replacement) in edits.reversed() {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    /// Levenshtein distance over characters.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[b.count]
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter "DictionaryCorrectorTests|MemoryTypesTests"`
Expected: DictionaryCorrectorTests 14/14, MemoryTypesTests 2/2 PASS.

- [ ] **Step 6: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(memory): dictionary and record types, dictionary corrector"
```

---

### Task 2: Dictionary in the cleanup pipeline

**Files:**
- Modify: `SecureWisprKit/Sources/Cleanup/CleanupPipeline.swift`
- Test: `SecureWisprKit/Tests/CleanupTests/CleanupPipelineTests.swift`

**Interfaces:**
- Consumes: `DictionaryCorrector.apply`, `PersonalDictionary`.
- Produces: `CleanupPipeline.init(level:rewriter:dictionary:timeout:)` with `dictionary: @escaping @MainActor () -> PersonalDictionary = { PersonalDictionary() }`.

- [ ] **Step 1: Write the failing tests**

Append inside `CleanupPipelineTests`:
```swift
    func pipeline(_ level: CleanupLevel, dictionary: PersonalDictionary) -> CleanupPipeline {
        CleanupPipeline(level: { level }, rewriter: rewriter, dictionary: { dictionary }, timeout: .seconds(5))
    }

    let memory = PersonalDictionary(words: ["Kvarnholmen"],
                                    replacements: [Replacement(heard: "secure whisper", written: "SecureWispr")])

    @Test func dictionaryAppliesEvenWhenCleanupIsOff() async throws {
        let out = try await clean("um the Kvarnholman launch of secure whisper", pipeline(.off, dictionary: memory))
        #expect(out == "um the Kvarnholmen launch of SecureWispr")
    }

    @Test func modelSeesCorrectedText() async throws {
        rewriter.transform = { $0 }
        _ = try await clean("the Kvarnholman launch of secure whisper", pipeline(.polished, dictionary: memory))
        #expect(rewriter.calls == ["the Kvarnholmen launch of SecureWispr"])
    }

    @Test func dictionaryIsReappliedAfterTheModel() async throws {
        rewriter.transform = { _ in "The Kvarnholman launch of SecureWispr." }   // model "undid" a spelling
        let out = try await clean("the kvarnholmen launch of secure whisper", pipeline(.polished, dictionary: memory))
        #expect(out == "The Kvarnholmen launch of SecureWispr.")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter CleanupPipelineTests`
Expected: compile FAIL — extra argument `dictionary` in call.

- [ ] **Step 3: Implement**

In `Sources/Cleanup/CleanupPipeline.swift`:

Add a stored property after `private let timeout: Duration`:
```swift
    private let dictionary: @MainActor () -> PersonalDictionary
```
Replace the initializer with:
```swift
    public init(level: @escaping @MainActor () -> CleanupLevel, rewriter: any TextRewriter,
                dictionary: @escaping @MainActor () -> PersonalDictionary = { PersonalDictionary() },
                timeout: Duration = CleanupPipeline.defaultTimeout) {
        self.level = level
        self.rewriter = rewriter
        self.dictionary = dictionary
        self.timeout = timeout
    }
```
Replace `clean(_:context:)` with:
```swift
    public func clean(_ text: String, context: DictationContext) async throws -> String {
        let level = level()
        let dictionary = dictionary()
        // The dictionary is spelling, not cleanup: it applies at every level.
        let corrected = DictionaryCorrector.apply(VoiceCommands.apply(text), dictionary: dictionary)
        guard level != .off else { return corrected }
        let deadline = ContinuousClock.now + timeout
        var cleaned: [String] = []
        for segment in corrected.components(separatedBy: "\n") {
            cleaned.append(await cleanSegment(segment, level: level, dictionary: dictionary, deadline: deadline))
        }
        return cleaned.joined(separator: "\n")
    }
```
Change the `cleanSegment` signature to
```swift
    private func cleanSegment(_ raw: String, level: CleanupLevel, dictionary: PersonalDictionary,
                              deadline: ContinuousClock.Instant) async -> String {
```
and its `.accept` case to
```swift
            case .accept:
                // The model never sees the dictionary; re-apply so it can't undo the user's spellings.
                return Self.finishSentence(DictionaryCorrector.apply(output, dictionary: dictionary))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter CleanupPipelineTests`
Expected: all CleanupPipelineTests PASS (previous 17 + 3).

- [ ] **Step 5: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(cleanup): apply personal dictionary before and after the model"
```

---

### Task 3: Transcriber vocabulary hints + engine identity

**Files:**
- Modify: `SecureWisprKit/Sources/Core/Protocols.swift`, `SecureWisprKit/Sources/SpeechToText/AppleTranscriber.swift`, `SecureWisprKit/Sources/SpeechToText/AppleTranscriptionSession.swift`, `SecureWisprKit/Sources/Parakeet/ParakeetTranscriber.swift`
- Test: `SecureWisprKit/Tests/SpeechToTextTests/AppleTranscriberTests.swift`

**Interfaces:**
- Produces:
  - `Transcriber.engine: SpeechEngine { get }` with default `.apple` (extension); `ParakeetTranscriber.engine == .parakeet`
  - `AppleTranscriber.init(fallbackLanguage:vocabulary:installer:)` with `vocabulary: @escaping @MainActor () -> [String] = { [] }`
  - `AppleTranscriptionSession.start(language: Language, vocabulary: [String])`

- [ ] **Step 1: Write the failing test**

Append inside `AppleTranscriberTests`:
```swift
    @Test(.timeLimit(.minutes(2)))
    func swedishUsesTheDictionaryAsHints() async throws {
        let samples = try spokenSamples("Skicka rapporten om Kvarnholmen till Ylva Zetterström och Jozeta",
                                        voice: "Alva")
        let transcriber = AppleTranscriber(vocabulary: { ["Kvarnholmen", "Ylva Zetterström", "Jozeta"] })
        let transcript = try await transcribe(samples, .fixed(.swedish), transcriber: transcriber)
        #expect(transcript.text.contains("Jozeta"), "\(transcript.text)")
        #expect(transcriber.engine == .apple)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SecureWisprKit && swift test --filter swedishUsesTheDictionaryAsHints`
Expected: compile FAIL — `vocabulary:` argument / `engine` not found.

- [ ] **Step 3: Implement**

In `Sources/Core/Protocols.swift`, add inside `protocol Transcriber` (after `var isReady`):
```swift
    /// Which engine this is (for history).
    var engine: SpeechEngine { get }
```
and after the protocol:
```swift
public extension Transcriber {
    var engine: SpeechEngine { .apple }
}
```

In `Sources/Parakeet/ParakeetTranscriber.swift`, add inside the class:
```swift
    public var engine: SpeechEngine { .parakeet }
```

In `Sources/SpeechToText/AppleTranscriber.swift`:
- add a stored property `private let vocabulary: @MainActor () -> [String]`
- change the initializer to:
```swift
    public init(fallbackLanguage: @escaping @MainActor () -> Language = { .english },
                vocabulary: @escaping @MainActor () -> [String] = { [] },
                installer: @escaping @MainActor (Language) async throws -> Void = AppleTranscriber.installAssets) {
        self.fallbackLanguage = fallbackLanguage
        self.vocabulary = vocabulary
        self.installer = installer
    }
```
- in `makeSession`, pass the words to every `AppleTranscriptionSession.start` call:
```swift
        let words = vocabulary()
```
as the first line of `makeSession`, and `AppleTranscriptionSession.start(language: X, vocabulary: words)` for each of the three calls.

In `Sources/SpeechToText/AppleTranscriptionSession.swift`, change the start signature to
```swift
    static func start(language: Language, vocabulary: [String]) async throws -> AppleTranscriptionSession {
```
and right after `let analyzer = SpeechAnalyzer(modules: [apple.module])` add:
```swift
        if !vocabulary.isEmpty {
            // Honoured by DictationTranscriber (Swedish); SpeechTranscriber ignores it (probed).
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter "AppleTranscriberTests|ParakeetTests"`
Expected: PASS (AppleTranscriberTests 9).

- [ ] **Step 5: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(stt): dictionary words as Swedish recognition hints; engine identity"
```

---

### Task 4: Controller emits dictation records

**Files:**
- Modify: `SecureWisprKit/Sources/Dictation/DictationController.swift`
- Test: `SecureWisprKit/Tests/DictationTests/DictationControllerTests.swift`

**Interfaces:**
- Consumes: `DictationRecord`, `Transcriber.engine`.
- Produces: `DictationController.onDictationFinished: (@MainActor (DictationRecord) -> Void)?`

- [ ] **Step 1: Write the failing tests**

Append inside `DictationControllerTests`:
```swift
    func recording(_ controller: DictationController) -> Box<[DictationRecord]> {
        let records = Box<[DictationRecord]>([])
        controller.onDictationFinished = { records.value.append($0) }
        return records
    }

    @Test func successfulDictationIsRecorded() async {
        let controller = makeController()
        let records = recording(controller)
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(records.value.count == 1)
        let record = records.value[0]
        #expect(record.rawText == "hello world")
        #expect(record.finalText == "cleaned: hello world")
        #expect(record.pasted)
        #expect(record.appBundleID == "com.apple.TextEdit")
        #expect(record.language == .english)
        #expect(record.engine == .apple)
    }

    @Test func failedPasteIsRecordedForRescue() async {
        injector.error = .eventCreationFailed
        let controller = makeController()
        let records = recording(controller)
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(records.value.map(\.pasted) == [false])
        #expect(records.value.first?.finalText == "cleaned: hello world")
    }

    @Test func secureInputNoSpeechAndCancelAreNotRecorded() async {
        let controller = makeController()
        let records = recording(controller)

        injector.error = .secureInputActive
        controller.handle(en); controller.handle(.finish); await controller.currentTask?.value

        injector.error = nil
        transcriber.session.result = .success("")
        controller.handle(en); controller.handle(.finish); await controller.currentTask?.value

        controller.handle(en); controller.handle(.cancel); await controller.currentTask?.value
        #expect(records.value.isEmpty)
    }

    @Test func recordCallbackDoesNotAffectState() async {
        let controller = makeController()
        controller.onDictationFinished = { _ in }
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(controller.state == .idle)
        #expect(injector.injected == ["cleaned: hello world"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter DictationControllerTests`
Expected: compile FAIL — `onDictationFinished` not found.

- [ ] **Step 3: Implement**

In `Sources/Dictation/DictationController.swift`:

Add after `public var onLanguageDetected …`:
```swift
    /// A finished dictation (pasted, or paste failed) for history. Never for secure input.
    public var onDictationFinished: (@MainActor (DictationRecord) -> Void)?
```

In `finishDictation()`, replace the block from `do {\n            state = .cleaning` through the closing of its `catch { fail(.injection…) return }` with:
```swift
        var finalText = ""
        do {
            state = .cleaning
            finalText = try await cleaner.clean(transcript.text, context: context)
            // Voice commands can remove everything ("scratch that" alone): nothing to paste.
            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail(.noSpeech)
                return
            }
            state = .injecting
            try await injector.inject(finalText)
        } catch InjectionError.secureInputActive {
            fail(.secureInput)
            return
        } catch {
            if !finalText.isEmpty { record(transcript, finalText, pasted: false) }
            fail(.injection(String(describing: error)))
            return
        }
        record(transcript, finalText, pasted: true)
```
Add the helper method above `cancelListening()`:
```swift
    private func record(_ transcript: Transcript, _ finalText: String, pasted: Bool) {
        onDictationFinished?(DictationRecord(
            date: Date(), appBundleID: context.appBundleID, language: transcript.language,
            engine: activeTranscriber?.engine ?? .apple, rawText: transcript.text,
            finalText: finalText, pasted: pasted))
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter DictationControllerTests`
Expected: all PASS (previous 22 + 4).

- [ ] **Step 5: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(dictation): emit dictation records for history"
```

---

### Task 5: DictionaryStore + retention setting

**Files:**
- Create: `SecureWisprKit/Sources/Preferences/DictionaryStore.swift`
- Modify: `SecureWisprKit/Sources/Preferences/SettingsStore.swift`
- Test: `SecureWisprKit/Tests/PreferencesTests/DictionaryStoreTests.swift`, `SecureWisprKit/Tests/PreferencesTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor @Observable public final class DictionaryStore { init(url: URL = DictionaryStore.defaultURL); nonisolated static var defaultURL: URL; private(set) var dictionary: PersonalDictionary; func addWord(_:); func removeWords(at: IndexSet); func addReplacement(heard:written:); func removeReplacement(id: UUID) }`
  - `SettingsStore.historyRetention: HistoryRetention` (default `.week`, key `"historyRetention"`)

- [ ] **Step 1: Write the failing tests**

`Tests/PreferencesTests/DictionaryStoreTests.swift`:
```swift
import Core
import Foundation
import Testing
@testable import Preferences

@MainActor
struct DictionaryStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dict-\(UUID().uuidString)")
    var url: URL { dir.appendingPathComponent("dictionary.json") }

    @Test func startsEmptyWithoutAFile() {
        #expect(DictionaryStore(url: url).dictionary == PersonalDictionary())
    }

    @Test func editsPersistAcrossInstances() {
        let store = DictionaryStore(url: url)
        store.addWord("  Kvarnholmen ")
        store.addWord("kvarnholmen")
        store.addWord("Jozeta")
        store.addReplacement(heard: "secure whisper", written: "SecureWispr")
        store.removeWords(at: IndexSet(integer: 1))

        let reloaded = DictionaryStore(url: url)
        #expect(reloaded.dictionary.words == ["Kvarnholmen"])
        #expect(reloaded.dictionary.replacements.map(\.written) == ["SecureWispr"])

        reloaded.removeReplacement(id: reloaded.dictionary.replacements[0].id)
        #expect(DictionaryStore(url: url).dictionary.replacements.isEmpty)
    }

    @Test func corruptFileIsKeptAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        let store = DictionaryStore(url: url)
        #expect(store.dictionary == PersonalDictionary())
        let aside = dir.appendingPathComponent("dictionary.corrupt.json")
        #expect(try String(contentsOf: aside, encoding: .utf8) == "{not json")
    }
}
```

Append inside `SettingsStoreTests`:
```swift
    @Test func historyRetentionDefaultsToAWeekAndPersists() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.historyRetention == .week)
        store.historyRetention = .month
        #expect(SettingsStore(defaults: defaults).historyRetention == .month)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter "DictionaryStoreTests|historyRetention"`
Expected: compile FAIL — `DictionaryStore`, `historyRetention` not found.

- [ ] **Step 3: Implement**

`Sources/Preferences/DictionaryStore.swift`:
```swift
import Core
import Foundation
import Observation

/// The personal dictionary, stored as readable JSON so it can be backed up or edited by hand.
@MainActor @Observable
public final class DictionaryStore {
    private static let log = Log.logger("Preferences")

    public nonisolated static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("SecureWispr/dictionary.json")
    }

    public private(set) var dictionary: PersonalDictionary
    @ObservationIgnored private let url: URL

    public init(url: URL = DictionaryStore.defaultURL) {
        self.url = url
        dictionary = Self.load(from: url)
    }

    public func addWord(_ word: String) {
        update { $0.words.append(word) }
    }

    public func removeWords(at offsets: IndexSet) {
        update { $0.words.remove(atOffsets: offsets) }
    }

    public func addReplacement(heard: String, written: String) {
        update { $0.replacements.append(Replacement(heard: heard, written: written)) }
    }

    public func removeReplacement(id: UUID) {
        update { $0.replacements.removeAll { $0.id == id } }
    }

    private func update(_ change: (inout PersonalDictionary) -> Void) {
        var next = dictionary
        change(&next)
        dictionary = next.normalized()
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(dictionary).write(to: url, options: .atomic)
        } catch {
            Self.log.error("could not save dictionary: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> PersonalDictionary {
        guard let data = try? Data(contentsOf: url) else { return PersonalDictionary() }
        do {
            return try JSONDecoder().decode(PersonalDictionary.self, from: data).normalized()
        } catch {
            // Never overwrite a file we couldn't read: keep it aside for the user.
            let aside = url.deletingLastPathComponent().appendingPathComponent("dictionary.corrupt.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            log.error("dictionary.json unreadable; moved to dictionary.corrupt.json")
            return PersonalDictionary()
        }
    }
}
```

In `Sources/Preferences/SettingsStore.swift`:
- `Key`: add `static let historyRetention = "historyRetention"`
- property: `public var historyRetention: HistoryRetention { didSet { defaults.set(historyRetention.rawValue, forKey: Key.historyRetention) } }`
- `init`: `historyRetention = Self.read(defaults, Key.historyRetention, HistoryRetention.week)`

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter "DictionaryStoreTests|SettingsStoreTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(preferences): JSON dictionary store and history retention setting"
```

---

### Task 6: History store (SwiftData)

**Files:**
- Modify: `SecureWisprKit/Package.swift`
- Create: `SecureWisprKit/Sources/History/HistoryEntry.swift`, `SecureWisprKit/Sources/History/HistoryStore.swift`
- Test: `SecureWisprKit/Tests/HistoryTests/HistoryStoreTests.swift`

**Interfaces:**
- Consumes: `DictationRecord`, `HistoryRetention`, `Language`, `SpeechEngine`.
- Produces:
  - `public struct HistoryItem: Identifiable, Sendable, Equatable { id: PersistentIdentifier; record: DictationRecord }`
  - `@MainActor @Observable public final class HistoryStore { init(inMemory: Bool = false, url: URL = HistoryStore.defaultURL) throws; var revision: Int; func add(_ record: DictationRecord, retention: HistoryRetention); func items(matching query: String) -> [HistoryItem]; func delete(_ id: PersistentIdentifier); func deleteAll(); func apply(retention: HistoryRetention, now: Date = Date()) }`

- [ ] **Step 1: Add targets**

In `Package.swift` add `"History"` to the library product's targets, and:
```swift
        .target(name: "History", dependencies: ["Core"]),
        .testTarget(name: "HistoryTests", dependencies: ["History"]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/HistoryTests/HistoryStoreTests.swift`:
```swift
import Core
import Foundation
import Testing
@testable import History

@MainActor
struct HistoryStoreTests {
    let store = try! HistoryStore(inMemory: true)
    let now = Date()

    func record(_ text: String, ageDays: Double = 0, pasted: Bool = true) -> DictationRecord {
        DictationRecord(date: now.addingTimeInterval(-ageDays * 86_400), appBundleID: "com.apple.TextEdit",
                        language: .swedish, engine: .apple, rawText: "öh \(text)", finalText: text, pasted: pasted)
    }

    @Test func addsAndListsNewestFirst() {
        store.add(record("first", ageDays: 2), retention: .forever)
        store.add(record("second", ageDays: 1), retention: .forever)
        #expect(store.items(matching: "").map(\.record.finalText) == ["second", "first"])
    }

    @Test func searchMatchesRawOrFinalTextCaseInsensitively() {
        store.add(record("Skicka rapporten"), retention: .forever)
        store.add(record("Something else"), retention: .forever)
        #expect(store.items(matching: "RAPPORT").map(\.record.finalText) == ["Skicka rapporten"])
        #expect(store.items(matching: "öh").count == 2)
    }

    @Test func roundTripsAllFields() {
        let original = record("hej", pasted: false)
        store.add(original, retention: .forever)
        let stored = store.items(matching: "").first?.record
        #expect(stored?.language == .swedish)
        #expect(stored?.engine == .apple)
        #expect(stored?.pasted == false)
        #expect(stored?.appBundleID == "com.apple.TextEdit")
        #expect(stored?.rawText == "öh hej")
    }

    @Test func recordIsIgnoredWhenRetentionIsOff() {
        store.add(record("secret"), retention: .off)
        #expect(store.items(matching: "").isEmpty)
    }

    @Test func applyingShorterRetentionPurgesImmediately() {
        store.add(record("old", ageDays: 10), retention: .forever)
        store.add(record("recent", ageDays: 0.5), retention: .forever)
        store.apply(retention: .day, now: now)
        #expect(store.items(matching: "").map(\.record.finalText) == ["recent"])
    }

    @Test func retentionOffDeletesEverything() {
        store.add(record("a"), retention: .forever)
        store.apply(retention: .off, now: now)
        #expect(store.items(matching: "").isEmpty)
    }

    @Test func deleteOneAndDeleteAll() {
        store.add(record("a"), retention: .forever)
        store.add(record("b"), retention: .forever)
        let first = store.items(matching: "")[0]
        store.delete(first.id)
        #expect(store.items(matching: "").count == 1)
        store.deleteAll()
        #expect(store.items(matching: "").isEmpty)
    }

    @Test func revisionChangesOnEveryMutation() {
        let start = store.revision
        store.add(record("a"), retention: .forever)
        store.deleteAll()
        #expect(store.revision == start + 2)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd SecureWisprKit && swift test --filter HistoryStoreTests`
Expected: compile FAIL — `HistoryStore` not found.

- [ ] **Step 4: Implement**

`Sources/History/HistoryEntry.swift`:
```swift
import Core
import Foundation
import SwiftData

@Model
final class HistoryEntry {
    var date: Date
    var appBundleID: String?
    var languageRaw: String?
    var engineRaw: String
    var rawText: String
    var finalText: String
    var pasted: Bool

    init(_ record: DictationRecord) {
        date = record.date
        appBundleID = record.appBundleID
        languageRaw = record.language?.rawValue
        engineRaw = record.engine.rawValue
        rawText = record.rawText
        finalText = record.finalText
        pasted = record.pasted
    }

    var record: DictationRecord {
        DictationRecord(date: date, appBundleID: appBundleID,
                        language: languageRaw.flatMap(Language.init(rawValue:)),
                        engine: SpeechEngine(rawValue: engineRaw) ?? .apple,
                        rawText: rawText, finalText: finalText, pasted: pasted)
    }
}
```

`Sources/History/HistoryStore.swift`:
```swift
import Core
import Foundation
import Observation
import SwiftData

public struct HistoryItem: Identifiable, Sendable, Equatable {
    public let id: PersistentIdentifier
    public let record: DictationRecord
}

/// Private, local dictation history. Failures are logged and never affect dictation.
@MainActor @Observable
public final class HistoryStore {
    private static let log = Log.logger("History")

    public nonisolated static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("SecureWispr/History.store")
    }

    /// Bumped on every change so SwiftUI views re-query.
    public private(set) var revision = 0
    @ObservationIgnored private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(inMemory: Bool = false, url: URL = HistoryStore.defaultURL) throws {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            configuration = ModelConfiguration(url: url)
        }
        container = try ModelContainer(for: HistoryEntry.self, configurations: configuration)
    }

    public func add(_ record: DictationRecord, retention: HistoryRetention) {
        guard retention != .off else { return }
        context.insert(HistoryEntry(record))
        save()
    }

    public func items(matching query: String) -> [HistoryItem] {
        let descriptor = FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let entries = (try? context.fetch(descriptor)) ?? []
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return entries
            .filter { trimmed.isEmpty
                || $0.finalText.localizedCaseInsensitiveContains(trimmed)
                || $0.rawText.localizedCaseInsensitiveContains(trimmed) }
            .map { HistoryItem(id: $0.persistentModelID, record: $0.record) }
    }

    public func delete(_ id: PersistentIdentifier) {
        guard let entry = context.model(for: id) as? HistoryEntry else { return }
        context.delete(entry)
        save()
    }

    public func deleteAll() {
        do { try context.delete(model: HistoryEntry.self) } catch {
            Self.log.error("could not clear history: \(error.localizedDescription, privacy: .public)")
        }
        save()
    }

    /// Deletes entries the retention setting no longer allows (all of them for `.off`).
    public func apply(retention: HistoryRetention, now: Date = Date()) {
        guard let cutoff = retention.cutoff(now: now) else { return }
        if retention == .off { return deleteAll() }
        let descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.date < cutoff })
        for entry in (try? context.fetch(descriptor)) ?? [] { context.delete(entry) }
        save()
    }

    private func save() {
        do { try context.save() } catch {
            Self.log.error("could not save history: \(error.localizedDescription, privacy: .public)")
        }
        revision += 1
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd SecureWisprKit && swift test --filter HistoryStoreTests`
Expected: 8/8 PASS.

- [ ] **Step 6: Commit**

```bash
git add SecureWisprKit
git commit -m "feat(history): SwiftData dictation history with retention"
```

---

### Task 7: App wiring, Settings sections, History window

**Files:**
- Modify: `SecureWispr/AppModel.swift`, `SecureWispr/MenuContent.swift`, `SecureWispr/SettingsView.swift`, `SecureWispr/SecureWisprApp.swift`
- Create: `SecureWispr/HistoryView.swift`

**Interfaces:**
- Consumes: `DictionaryStore`, `HistoryStore`, `SettingsStore.historyRetention`, `CleanupPipeline(dictionary:)`, `AppleTranscriber(vocabulary:)`, `DictationController.onDictationFinished`.
- Produces: `AppModel.dictionaryStore`, `AppModel.history: HistoryStore?`, the "history" window.

- [ ] **Step 1: AppModel wiring**

In `SecureWispr/AppModel.swift`:
- add `import History`
- add stored properties next to `settings`:
```swift
    let dictionaryStore: DictionaryStore
    let history: HistoryStore?
    @ObservationIgnored private var retentionTask: Task<Void, Never>?
```
- at the start of `init`, after `let store = ParakeetModelStore()`:
```swift
        let dictionaryStore = DictionaryStore()
        self.dictionaryStore = dictionaryStore
        do {
            history = try HistoryStore()
        } catch {
            Self.log.error("history unavailable: \(error.localizedDescription, privacy: .public)")
            history = nil
        }
```
- change the Apple transcriber construction to:
```swift
        apple = AppleTranscriber(fallbackLanguage: { settings.lastDetectedLanguage },
                                 vocabulary: { dictionaryStore.dictionary.words })
```
- change the cleaner argument to:
```swift
            cleaner: CleanupPipeline(level: { settings.cleanupLevel }, rewriter: rewriter,
                                     dictionary: { dictionaryStore.dictionary }),
```
- after the `controller.onLanguageDetected = …` block add:
```swift
        controller.onDictationFinished = { [weak self] record in
            guard let self else { return }
            history?.add(record, retention: settings.historyRetention)
        }
```
- at the end of `start()` add:
```swift
        applyRetention()
        retentionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3_600))
                self?.applyRetention()
            }
        }
```
- add:
```swift
    func applyRetention() {
        history?.apply(retention: settings.historyRetention)
    }
```

- [ ] **Step 2: History window**

`SecureWispr/HistoryView.swift`:
```swift
import AppKit
import Core
import History
import SwiftUI

struct HistoryView: View {
    let store: HistoryStore?
    @State private var query = ""
    @State private var confirmClear = false

    var body: some View {
        Group {
            if let store {
                list(store)
            } else {
                ContentUnavailableView("History unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text("The history database could not be opened."))
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func list(_ store: HistoryStore) -> some View {
        let _ = store.revision   // re-query when the store changes
        let items = store.items(matching: query)
        return List(items) { item in
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.record.date, style: .time).font(.caption).foregroundStyle(.secondary)
                        Text(item.record.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        if let language = item.record.language { Text(language.flag).font(.caption) }
                        if let app = appName(item.record.appBundleID) {
                            Text(app).font(.caption).foregroundStyle(.secondary)
                        }
                        if !item.record.pasted {
                            Label("not pasted", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Text(item.record.finalText).lineLimit(2).textSelection(.enabled)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.record.finalText, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help("Copy")
                Button(role: .destructive) { store.delete(item.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Delete")
            }
            .padding(.vertical, 2)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No dictations yet" : "No matches",
                                       systemImage: "clock.arrow.circlepath")
            }
        }
        .searchable(text: $query, prompt: "Search history")
        .toolbar {
            Button("Clear All", role: .destructive) { confirmClear = true }
                .disabled(items.isEmpty && query.isEmpty)
        }
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { store.deleteAll() }
        }
    }

    private func appName(_ bundleID: String?) -> String? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path)
    }
}
```

In `SecureWispr/SecureWisprApp.swift`, add a scene after `MenuBarExtra { … }`:
```swift
        Window("Dictation History", id: "history") {
            HistoryView(store: model.history)
        }
```

- [ ] **Step 3: Menu item**

In `SecureWispr/MenuContent.swift`:
- add `@Environment(\.openWindow) private var openWindow` next to `openSettings`
- before the `Button("Settings…")` add:
```swift
        Button("History…") {
            NSApp.activate()
            openWindow(id: "history")
        }
        .keyboardShortcut("y")
```

- [ ] **Step 4: Settings sections**

In `SecureWispr/SettingsView.swift`, insert before `Section("Push-to-talk")`:
```swift
            DictionarySection(store: model.dictionaryStore)
            Section("History") {
                Picker("Keep history", selection: $settings.historyRetention) {
                    ForEach(HistoryRetention.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: settings.historyRetention) { model.applyRetention() }
                Text("Stored only on this Mac. Off deletes all history immediately.")
                    .font(.caption).foregroundStyle(.secondary)
            }
```
and append at the end of the file:
```swift
private struct DictionarySection: View {
    let store: DictionaryStore
    @State private var newWord = ""
    @State private var heard = ""
    @State private var written = ""

    var body: some View {
        Section("Dictionary") {
            Text("Names and terms you use. Words also help Swedish recognition; replacements fix anything that's consistently misheard.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(store.dictionary.words.enumerated()), id: \.offset) { index, word in
                HStack {
                    Text(word)
                    Spacer()
                    Button(role: .destructive) { store.removeWords(at: IndexSet(integer: index)) } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Add word (e.g. Kvarnholmen)", text: $newWord)
                    .onSubmit(addWord)
                Button("Add", action: addWord).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(store.dictionary.replacements) { replacement in
                HStack {
                    Text("“\(replacement.heard)” → \(replacement.written)")
                    Spacer()
                    Button(role: .destructive) { store.removeReplacement(id: replacement.id) } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Heard", text: $heard)
                TextField("Write as", text: $written)
                Button("Add") {
                    store.addReplacement(heard: heard, written: written)
                    heard = ""
                    written = ""
                }
                .disabled(heard.trimmingCharacters(in: .whitespaces).isEmpty
                          || written.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addWord() {
        store.addWord(newWord)
        newWord = ""
    }
}
```
Add `import Preferences` at the top of `SettingsView.swift` if not present.

- [ ] **Step 5: Build, test, relaunch**

Run: `xcodebuild -project SecureWispr.xcodeproj -scheme SecureWispr -configuration Debug -derivedDataPath build -allowProvisioningUpdates build 2>&1 | grep -E "error:|\*\* BUILD"`
Expected: `** BUILD SUCCEEDED **`

Run: `cd SecureWisprKit && swift test 2>&1 | grep -E "error:|✘|Test run with"`
Expected: no `✘`.

Run: `pkill -x SecureWispr; open build/Build/Products/Debug/SecureWispr.app`
Expected: menu has "History…"; Settings has Dictionary and History sections.

- [ ] **Step 6: Commit**

```bash
git add SecureWispr
git commit -m "feat(app): dictionary and history in Settings, History window"
```

---

### Task 8: M4 acceptance (manual, with the user)

- [ ] **Step 1: Dictionary.** Add 3–5 of your own names/terms (incl. one Swedish place, one multi-word name) and one replacement for something consistently misheard. Dictate each in SV and EN: ≥ 8 of 10 occurrences spelled right; no ordinary word swapped for a dictionary term.
- [ ] **Step 2: History.** Dictate a few things, open History (⌘Y from the menu): newest first, search works, Copy restores text, Delete removes one, Clear All empties.
- [ ] **Step 3: Rescue.** Dictate into a password field (refused — not in history), then a normal one (in history).
- [ ] **Step 4: Retention.** Switch to Off → history empties immediately and new dictations aren't recorded; back to 7 days.
- [ ] **Step 5: Commit / tag**

```bash
git commit --allow-empty -m "chore: M4 acceptance passed"
git tag v0.4-m4
```
