# Wiska M18 — KB-Whisper Swedish second pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swedish dictations are re-transcribed on-device by KB-Whisper Large (whisper.cpp), with a safe fallback to the first engine, a download card, and a "Compare on my voice" test.

**Architecture:**
- **Pure pieces go to Core and Dictation:**
  - `BatchRecognizer`, `ResumeOnce` and a generic `ModelRuntime` actor (lifted from M17's `GemmaRuntime`, which then becomes a typealias of it);
  - `SwedishSecondPassTranscriber`, `WhisperOutput`, `VoiceBenchmark`.
  
  All are tested with fakes.
- **A new `Whisper` target** wraps whisper.cpp's official framework. It holds `KBWhisperModelStore`, the `WhisperContext` C wrapper and the `KBWhisperRecognizer` façade.
- **The app** wraps every transcriber in the second pass and adds the card, the toggle and the Compare window.

**Tech Stack:** Swift 6.2, SwiftUI, macOS 26, whisper.cpp `b5454` (prebuilt framework), CryptoKit, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-09-wiska-m18-kb-whisper-design.md`

## Global Constraints

- **The framework:**
  - binary target `whisper`, URL `https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip`;
  - checksum `e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b`;
  - Swift module `whisper` (`import whisper`).
- **The model:**
  - `https://huggingface.co/KBLab/kb-whisper-large/resolve/d5d5984b4d8f7c4847a8ea203f1976285fb28300/ggml-model-q5_0.bin`;
  - SHA-256 `6d2863812d7410322bb7d8647a5c7260761300fa946714c9ed66d22bb30bcb19`, 1,081,140,203 bytes;
  - stored at `AppPaths.supportDirectory/Models/kb-whisper-large/ggml-model-q5_0.bin`;
  - 2 GB of free disk space required.
- **Second pass:**
  - Runs only when the first transcript's language is `.swedish`, `useKBWhisper` is on and the model is ready.
  - The budget is `max(3 s, 25 % of the recording's length)`.
  - It falls back to the first engine's transcript on an error, a timeout or junk.
- **Junk:**
  - empty text;
  - a hallucination phrase the first engine didn't hear: "tack för att du tittade", "tack för att ni tittade", "textning", "undertexter från amara.org", "prenumerera";
  - more than `2 × first engine's words + 4` words.
- **Status texts:** "Not downloaded", "Downloading 42 %", "Ready", "Download failed — try again", "Needs about 2 GB free", "Couldn't load: <reason>".
- **The idle unload** comes after 30 minutes and frees the context.
- **The Compare sentences** (exactly):
  1. "Jag har ett stort hus och en liten trädgård."
  2. "Mötet börjar på torsdag efter lunch i det stora rummet."
  3. "Sju sjösjuka sjömän sköttes av sju sköna sjuksköterskor."
  4. "Johan och Anna åkte till Göteborg för att köpa en ny cykel."
  5. "Kundtjänstmedarbetaren skickade en sammanfattning av arbetsmiljöundersökningen."
- **The recording** is at most 60 s.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Tests:** `swift test --package-path WiskaKit --filter <Suite>` from the repo root. App build: `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build build 2>&1 | grep -E "error:|BUILD SUCCEEDED"`.

**Plan-level decisions:**
- **One runtime for both models:** `GemmaRuntime`'s lifecycle (shared load, generation counter, idle unload, memory release, unload callback) moves to a generic `ModelRuntime<Model>` in Core, used by Gemma and KB-Whisper. `GemmaRuntime` becomes `typealias GemmaRuntime = ModelRuntime<any LoadedModel>`, plus an extension for `generate(...)`. `LocalModelError` becomes a typealias of Core's `ModelRuntimeError`.
- **`ResumeOnce` moves from Cleanup to Core (public),** so Dictation can race the second pass against its budget.
- **A timed-out run keeps going:** whisper.cpp can't be stopped mid-run (no abort callback in M18), so it finishes in the background. Calls to the runtime run one at a time, so a following dictation waits for it. This is accepted and listed in Review Focus.
- **`SpeechEngine.kbWhisper`** is added; the Speech tab pickers use `SpeechEngine.selectable` (`[.apple, .parakeet]`).

## Review Focus

1. **The first Swedish dictation after launch or after an idle unload:**
   - Loading the 1 GB model (~1–2 s) eats into the 3 s budget.
   - Expected: either KB's text or the first engine's text in time, and no hang. `makeSession` (at the fn press) starts the load.
   - Tested in Task 3 (`prepareIsCalledAtSessionStart`).
2. **Silence or one word in Swedish:**
   - Whisper hallucinates "Tack för att du tittade".
   - Expected: the first engine's text (or "No speech" as today).
   - Tested in Task 2 (`hallucinationsAreRejected`) and Task 3.
3. **A long dictation (2 minutes):**
   - The budget grows to 30 s; KB is either in time or falls back.
   - The kept audio is about 7.7 MB.
   - Tested in Task 3 (`budgetGrowsWithLength`).
4. **A dictation that isn't Swedish, or a Swedish one with the toggle off:**
   - Expected: no second pass at all (no load, no delay).
   - Tested in Task 3.
5. **A checksum mismatch or a download interrupted at 60%:**
   - Expected: no file is left behind, and the status is "Download failed — try again" or "Not downloaded" at the next launch.
   - Tested in Task 4.

---

### Task 1: Core — BatchRecognizer, SpeechEngine.kbWhisper, ResumeOnce, the setting

**Files:**
- Create: `WiskaKit/Sources/Core/BatchRecognizer.swift`, `WiskaKit/Sources/Core/ResumeOnce.swift`
- Modify:
  - `WiskaKit/Sources/Core/Language.swift` (`SpeechEngine`)
  - `WiskaKit/Sources/Cleanup/CleanupPipeline.swift` (delete `ResumeOnce`)
  - `WiskaKit/Sources/Preferences/SettingsStore.swift`
  - `Wiska/Settings/SpeechTab.swift` (pickers)
- Test:
  - `WiskaKit/Tests/CoreTests/LanguageTests.swift`
  - `WiskaKit/Tests/PreferencesTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor public protocol BatchRecognizer: AnyObject { var isReady: Bool { get }; func prepare(); func transcribe(_ samples: [Float], language: Language) async throws -> String }`
  - `SpeechEngine.kbWhisper` (`displayName` "KB-Whisper", `shortName` "KB-Whisper")
  - `SpeechEngine.selectable: [SpeechEngine]` (`[.apple, .parakeet]`)
  - `public final class ResumeOnce: Sendable` (`init(_:)`, `resume(_:)`), as today but public
  - `SettingsStore.useKBWhisper: Bool` (default `false`)

- [ ] **Step 1: Write the failing tests**

Add to `LanguageTests` (inside the struct):

```swift
    @Test func kbWhisperIsAnEngineButNotAPickerChoice() {
        #expect(SpeechEngine.kbWhisper.displayName == "KB-Whisper")
        #expect(SpeechEngine.kbWhisper.shortName == "KB-Whisper")
        #expect(SpeechEngine.selectable == [.apple, .parakeet])
    }
```

Add to `SettingsStoreTests`:

```swift
    @Test func useKBWhisperDefaultsOffAndPersists() {
        let store = SettingsStore(defaults: defaults)
        #expect(!store.useKBWhisper)
        store.useKBWhisper = true
        #expect(SettingsStore(defaults: defaults).useKBWhisper)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path WiskaKit --filter "LanguageTests|SettingsStoreTests"`
Expected: FAIL to compile ("has no member 'kbWhisper'", "has no member 'useKBWhisper'").

- [ ] **Step 3: Implement**

In `SpeechEngine`, add `case kbWhisper` after `parakeet`, and `case .kbWhisper: "KB-Whisper"` in both `displayName` and `shortName`. Then add:

```swift
    /// What the per-language engine pickers offer: KB-Whisper is a Swedish second pass, not a choice.
    public static let selectable: [SpeechEngine] = [.apple, .parakeet]
```

`Core/BatchRecognizer.swift`:

```swift
/// A model that transcribes a whole recording at once (KB-Whisper), used after a dictation.
@MainActor
public protocol BatchRecognizer: AnyObject {
    /// Installed and not known to be broken.
    var isReady: Bool { get }
    /// Starts loading in the background (fn press), so the second pass doesn't wait for it.
    func prepare()
    /// The text of `samples` (16 kHz mono) in `language`.
    func transcribe(_ samples: [Float], language: Language) async throws -> String
}
```

`Core/ResumeOnce.swift`: move the `ResumeOnce` class from `CleanupPipeline.swift` here unchanged, but `public final class`, `public init`, `public func resume`, with `import Synchronization` at the top. Delete it from `CleanupPipeline.swift`; Cleanup already imports Core.

`SettingsStore`:
- Add `static let useKBWhisper = "useKBWhisper"` to `Key`.
- Add the property:

```swift
    /// Swedish dictations are re-transcribed by KB-Whisper (when downloaded).
    public var useKBWhisper: Bool { didSet { defaults.set(useKBWhisper, forKey: Key.useKBWhisper) } }
```

- In `init`: `useKBWhisper = defaults.object(forKey: Key.useKBWhisper) as? Bool ?? false`.

`Wiska/Settings/SpeechTab.swift`: replace both `ForEach(SpeechEngine.allCases, …` with `ForEach(SpeechEngine.selectable, …`.

Then fix any other exhaustive `switch` on `SpeechEngine` that the build reports. Look for them with `grep -rn "case .parakeet" WiskaKit/Sources Wiska` and the app build.

- [ ] **Step 4: Run the tests and the app build**

Run: `swift test --package-path WiskaKit --filter "LanguageTests|SettingsStoreTests|CleanupPipelineTests|FoundationModelsEditorTests"`, then the app build.
Expected: all pass; `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit Wiska
git commit -m "feat(core): BatchRecognizer, SpeechEngine.kbWhisper, ResumeOnce in Core, useKBWhisper setting

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: WhisperOutput and VoiceBenchmark (pure)

**Files:**
- Create: `WiskaKit/Sources/Dictation/WhisperOutput.swift`, `WiskaKit/Sources/Dictation/VoiceBenchmark.swift`
- Test: `WiskaKit/Tests/DictationTests/WhisperOutputTests.swift`

**Interfaces:**
- Produces:
  - `enum WhisperOutput { static func accept(_ whisper: String, over primary: String) -> Bool }`
  - `public enum VoiceBenchmark { static let sentences: [String]; static var reference: String; static func wordErrorRate(reference: String, hypothesis: String) -> Double }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Dictation

struct WhisperOutputTests {
    @Test func ordinaryCorrectionsAreAccepted() {
        #expect(WhisperOutput.accept("Jag har ett stort hus.", over: "jag har en stor hus"))
        #expect(WhisperOutput.accept("Hej", over: "hej"))
    }

    @Test func emptyOrMuchLongerIsRejected() {
        #expect(!WhisperOutput.accept("  ", over: "jag har en stor hus"))
        // 2 × 1 + 4 = 6 words allowed for a one-word dictation.
        #expect(!WhisperOutput.accept("Ja och sen gick vi hem till mamma och åt", over: "ja"))
    }

    @Test func hallucinationsAreRejected() {
        #expect(!WhisperOutput.accept("Tack för att du tittade!", over: "tack"))
        #expect(!WhisperOutput.accept("Textning: Amara.org", over: "hm"))
        // Said for real: kept.
        #expect(WhisperOutput.accept("Tack för att du tittade på huset.", over: "tack för att du tittade på huset"))
    }

    @Test func wordErrorRateCountsWordEdits() {
        #expect(VoiceBenchmark.wordErrorRate(reference: "Jag har ett stort hus.", hypothesis: "jag har ett stort hus") == 0)
        #expect(VoiceBenchmark.wordErrorRate(reference: "jag har ett stort hus", hypothesis: "jag har en stor hus") == 0.4)
        #expect(VoiceBenchmark.wordErrorRate(reference: "jag har ett hus", hypothesis: "") == 1)
        #expect(VoiceBenchmark.sentences.count == 5)
        #expect(VoiceBenchmark.sentences[0] == "Jag har ett stort hus och en liten trädgård.")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path WiskaKit --filter WhisperOutputTests`
Expected: FAIL to compile ("cannot find 'WhisperOutput'").

- [ ] **Step 3: Implement**

`WhisperOutput.swift`:

```swift
import Foundation

/// Whether KB-Whisper's text may replace the first engine's: Whisper sometimes invents text
/// on near-silence ("Tack för att du tittade") or runs on.
enum WhisperOutput {
    static let hallucinations = ["tack för att du tittade", "tack för att ni tittade", "textning",
                                 "undertexter från amara.org", "prenumerera"]

    static func accept(_ whisper: String, over primary: String) -> Bool {
        let text = whisper.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let lower = text.lowercased(), heard = primary.lowercased()
        if hallucinations.contains(where: { lower.contains($0) && !heard.contains($0) }) { return false }
        return VoiceBenchmark.words(text).count <= 2 * VoiceBenchmark.words(primary).count + 4
    }
}
```

`VoiceBenchmark.swift`:

```swift
import Foundation

/// Settings → Speech → Compare on my voice: sentences to read, and how far a transcript is from them.
public enum VoiceBenchmark {
    public static let sentences = [
        "Jag har ett stort hus och en liten trädgård.",
        "Mötet börjar på torsdag efter lunch i det stora rummet.",
        "Sju sjösjuka sjömän sköttes av sju sköna sjuksköterskor.",
        "Johan och Anna åkte till Göteborg för att köpa en ny cykel.",
        "Kundtjänstmedarbetaren skickade en sammanfattning av arbetsmiljöundersökningen.",
    ]

    public static var reference: String { sentences.joined(separator: " ") }

    /// Lowercased words; punctuation ignored.
    static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// Word-level edits (substitutions, insertions, deletions) per reference word.
    public static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let ref = words(reference), hyp = words(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        var previous = Array(0...hyp.count)
        for i in 1...ref.count {
            var current = [i] + Array(repeating: 0, count: hyp.count)
            for j in stride(from: 1, through: hyp.count, by: 1) {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return Double(previous[hyp.count]) / Double(ref.count)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path WiskaKit --filter WhisperOutputTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(dictation): WhisperOutput junk check and VoiceBenchmark word error rate

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: SwedishSecondPassTranscriber

**Files:**
- Create: `WiskaKit/Sources/Dictation/SwedishSecondPassTranscriber.swift`
- Test: `WiskaKit/Tests/DictationTests/SwedishSecondPassTests.swift`

**Interfaces:**
- Consumes:
  - `BatchRecognizer`, `ResumeOnce`, `SpeechEngine.kbWhisper` (Task 1)
  - `WhisperOutput.accept` (Task 2)
  - `SessionsTranscriber` and `FakeSession` from the DictationTests fakes
- Produces: `public final class SwedishSecondPassTranscriber: Transcriber`, with `init(primary: any Transcriber, recognizer: any BatchRecognizer, isEnabled: @escaping @MainActor () -> Bool)`.

- [ ] **Step 1: Write the failing tests**

First check how `SessionsTranscriber` exposes its sessions: `grep -n "class SessionsTranscriber" -A25 WiskaKit/Tests/DictationTests/*.swift`. `ScriptFallbackTests` uses `parakeet.sessions[SessionsTranscriber.key(choice)]!.result`.

```swift
import Core
import Testing
@testable import Dictation

@MainActor
final class FakeRecognizer: BatchRecognizer {
    var isReady = true
    var text = "Jag har ett stort hus."
    var error: Error?
    var delay: Duration = .zero
    private(set) var prepared = 0
    private(set) var heard: [[Float]] = []
    func prepare() { prepared += 1 }
    func transcribe(_ samples: [Float], language: Language) async throws -> String {
        heard.append(samples)
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return text
    }
}

@MainActor
struct SwedishSecondPassTests {
    let primary = SessionsTranscriber(.apple)
    let recognizer = FakeRecognizer()

    func run(_ heard: String, language: Language?, enabled: Bool = true,
             samples: Int = 2) async throws -> Transcript {
        let transcriber = SwedishSecondPassTranscriber(primary: primary, recognizer: recognizer, isEnabled: { enabled })
        let session = try await transcriber.makeSession(language: .automatic)
        let fake = primary.sessions[SessionsTranscriber.key(.automatic)]!
        fake.result = .success(heard)
        fake.language = language
        session.append(AudioChunk(samples: Array(repeating: 0.1, count: samples)))
        return try await session.finish()
    }

    @Test func swedishIsRetranscribed() async throws {
        let transcript = try await run("jag har en stor hus", language: .swedish)
        #expect(transcript.text == "Jag har ett stort hus.")
        #expect(transcript.engine == .kbWhisper)
        #expect(transcript.language == .swedish)
        #expect(recognizer.heard == [[0.1, 0.1]])
    }

    @Test func otherLanguagesAndTheSwitchOffAreUntouched() async throws {
        #expect(try await run("hello there", language: .english).text == "hello there")
        #expect(try await run("jag har en stor hus", language: .swedish, enabled: false).text == "jag har en stor hus")
        recognizer.isReady = false
        #expect(try await run("jag har en stor hus", language: .swedish).text == "jag har en stor hus")
        #expect(recognizer.heard.isEmpty)
    }

    @Test func failuresAndJunkKeepTheFirstEngine() async throws {
        recognizer.error = CancellationError()
        #expect(try await run("jag har en stor hus", language: .swedish).text == "jag har en stor hus")
        recognizer.error = nil
        recognizer.text = "Tack för att du tittade!"
        #expect(try await run("hm", language: .swedish).text == "hm")
    }

    @Test func slowSecondPassFallsBackInTime() async throws {
        recognizer.delay = .seconds(10)
        let start = ContinuousClock.now
        let transcript = try await run("jag har en stor hus", language: .swedish)
        #expect(transcript.text == "jag har en stor hus")
        #expect(ContinuousClock.now - start < .seconds(4))
    }

    @Test func budgetGrowsWithLength() {
        #expect(SecondPassSession.budget(forSamples: 16_000 * 5) == .seconds(3))
        #expect(SecondPassSession.budget(forSamples: 16_000 * 120) == .seconds(30))
    }

    /// fn press: the model starts loading while the user speaks — only when it may be used.
    @Test func prepareIsCalledAtSessionStart() async throws {
        _ = try await SwedishSecondPassTranscriber(primary: primary, recognizer: recognizer, isEnabled: { true })
            .makeSession(language: .automatic)
        #expect(recognizer.prepared == 1)
        _ = try await SwedishSecondPassTranscriber(primary: primary, recognizer: recognizer, isEnabled: { false })
            .makeSession(language: .automatic)
        #expect(recognizer.prepared == 1)
    }

    @Test func forwardsReadinessAndEngine() {
        let transcriber = SwedishSecondPassTranscriber(primary: primary, recognizer: recognizer, isEnabled: { true })
        #expect(transcriber.engine == .apple)
        #expect(transcriber.isReady == primary.isReady)
    }
}
```

If `FakeSession.language` or `result` isn't settable as used above, adapt to the fake's real API and ledger it.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path WiskaKit --filter SwedishSecondPassTests`
Expected: FAIL to compile ("cannot find 'SwedishSecondPassTranscriber'").

- [ ] **Step 3: Implement**

```swift
import Core
import Foundation

/// KB-Whisper as a Swedish second pass: the chosen engine transcribes (and previews) as always;
/// when its text is Swedish, KB-Whisper re-transcribes the same recording and its text is used —
/// unless it fails, is too slow, or returns junk.
@MainActor
public final class SwedishSecondPassTranscriber: Transcriber {
    private let primary: any Transcriber
    private let recognizer: any BatchRecognizer
    private let isEnabled: @MainActor () -> Bool

    public init(primary: any Transcriber, recognizer: any BatchRecognizer, isEnabled: @escaping @MainActor () -> Bool) {
        self.primary = primary
        self.recognizer = recognizer
        self.isEnabled = isEnabled
    }

    public var isReady: Bool { primary.isReady }
    public var engine: SpeechEngine { primary.engine }
    public func isReady(for language: Language) -> Bool { primary.isReady(for: language) }
    public func isReady(for choice: LanguageChoice) -> Bool { primary.isReady(for: choice) }
    public func prepare() async throws { try await primary.prepare() }

    public func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        if isEnabled() { recognizer.prepare() }   // load while the user speaks
        return SecondPassSession(primary: try await primary.makeSession(language: language),
                                 recognizer: recognizer, isEnabled: isEnabled)
    }
}

@MainActor
final class SecondPassSession: TranscriptionSession {
    private static let log = Log.logger("Dictation")
    private let primary: any TranscriptionSession
    private let recognizer: any BatchRecognizer
    private let isEnabled: @MainActor () -> Bool
    private var samples: [Float] = []

    init(primary: any TranscriptionSession, recognizer: any BatchRecognizer, isEnabled: @escaping @MainActor () -> Bool) {
        self.primary = primary
        self.recognizer = recognizer
        self.isEnabled = isEnabled
    }

    var preview: AsyncStream<String> { primary.preview }

    func append(_ chunk: AudioChunk) {
        samples += chunk.samples
        primary.append(chunk)
    }

    /// 3 s, or a quarter of the recording for long dictations.
    static func budget(forSamples count: Int) -> Duration {
        .milliseconds(max(3_000, Int(Double(count) / AudioChunk.sampleRate * 250)))
    }

    func finish() async throws -> Transcript {
        let transcript = try await primary.finish()
        guard transcript.language == .swedish, isEnabled(), recognizer.isReady,
              !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return transcript }
        let samples = samples
        let recognizer = recognizer
        let start = ContinuousClock.now
        do {
            let text = try await Self.race(within: Self.budget(forSamples: samples.count)) {
                try await recognizer.transcribe(samples, language: .swedish)
            }
            guard WhisperOutput.accept(text, over: transcript.text) else {
                Self.log.notice("kb-whisper output rejected")
                return transcript
            }
            Self.log.info("kb-whisper in \((ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds])), privacy: .public)")
            var result = transcript
            result.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            result.engine = .kbWhisper
            return result
        } catch {
            Self.log.notice("kb-whisper skipped: \(String(describing: type(of: error)), privacy: .public)")
            return transcript
        }
    }

    func cancel() {
        samples = []
        primary.cancel()
    }

    struct Timeout: Error {}

    /// Whichever finishes first wins; never waits for the model to stop.
    static func race(within limit: Duration, _ work: @escaping @MainActor () async throws -> String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let task = Task { @MainActor in
                do { once.resume(.success(try await work())) } catch { once.resume(.failure(error)) }
            }
            Task {
                try? await Task.sleep(for: limit)
                once.resume(.failure(Timeout()))
                task.cancel()
            }
        }
    }
}
```

Check that `AudioChunk.sampleRate` exists as a `Double` (it's used in `DictationController.record`); if it's an `Int`, convert.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path WiskaKit --filter "SwedishSecondPassTests|ScriptFallbackTests"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(dictation): SwedishSecondPassTranscriber — KB-Whisper re-transcribes Swedish, with fallback

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The generic ModelRuntime, the Whisper target and KBWhisperModelStore

**Files:**
- Create: `WiskaKit/Sources/Core/ModelRuntime.swift`
- Modify:
  - `WiskaKit/Sources/LocalModel/GemmaRuntime.swift` (becomes a typealias plus a `generate` extension)
  - `WiskaKit/Sources/LocalModel/GemmaModel.swift` (uses `ModelRuntimeError` via the typealias)
- Modify: `WiskaKit/Package.swift`
- Create:
  - `WiskaKit/Sources/Whisper/KBWhisperModelStore.swift`
  - `WiskaKit/Sources/Whisper/FileDownloader.swift`
- Test: `WiskaKit/Tests/WhisperTests/KBWhisperModelStoreTests.swift`

**Interfaces:**
- Produces:
  - `public actor ModelRuntime<Model: Sendable>` (Core), with:
    - `init(idleLimit:release:loader:)`
    - `setOnUnload(_:)`, `isLoaded`
    - `load(from:) -> Model`
    - `use<T: Sendable>(from directory: URL, _ body: @Sendable (Model) async throws -> T) async throws -> T`
    - `unload()`
  - `public enum ModelRuntimeError: Error, Equatable { case unavailable, loadFailed(String) }`
  - `typealias GemmaRuntime = ModelRuntime<any LoadedModel>` and `typealias LocalModelError = ModelRuntimeError` (LocalModel)
  - `public protocol FileDownloader: Sendable { func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws }`, implemented by `URLSessionFileDownloader`
  - `@MainActor @Observable public final class KBWhisperModelStore`, with:
    - `Status` and `status`
    - `init(directory:downloader:freeSpace:expectedSHA256:)`
    - `modelFile`, `isInstalled`
    - `download()`, `cancelDownload()`, `remove()`
    - `onDownloaded`, `static let completionMarker`

- [ ] **Step 1: Lift GemmaRuntime into Core's ModelRuntime**

Create `Core/ModelRuntime.swift` with the body of today's `GemmaRuntime`, made generic:
- the actor becomes `public actor ModelRuntime<Model: Sendable>`;
- `typealias Loader = @Sendable (URL) async throws -> Model`;
- `model: Model?`, and `loading: Task<Model, Error>?`;
- every `any LoadedModel` becomes `Model`, and `LocalModelError` becomes `ModelRuntimeError`.

Replace `generate(...)` with:

```swift
    /// Loads if needed, runs `body` on the model, and restarts the idle clock.
    public func use<T: Sendable>(from directory: URL, _ body: @Sendable (Model) async throws -> T) async throws -> T {
        let loaded = try await load(from: directory)
        defer { scheduleUnload() }
        return try await body(loaded)
    }
```

Also add `public enum ModelRuntimeError: Error, Equatable { case unavailable, loadFailed(String) }` in the same file.

`LocalModel/GemmaRuntime.swift` keeps `LoadedModel`, and replaces the actor and `LocalModelError` with:

```swift
import Core
import Foundation

public typealias LocalModelError = ModelRuntimeError
public typealias GemmaRuntime = ModelRuntime<any LoadedModel>

extension ModelRuntime where Model == any LoadedModel {
    public func generate(directory: URL, system: String, prompt: String, maxTokens: Int) async throws -> String {
        try await use(from: directory) { try await $0.respond(system: system, prompt: prompt, maxTokens: maxTokens) }
    }
}
```

Run: `swift test --package-path WiskaKit --filter "GemmaRuntime|GemmaModel"`
Expected: the existing 16 tests still pass. This is a refactor, and those tests are its safety net. If a test calls something like `runtime.load(from:)` whose type changed, adjust only the type, not the behaviour, and ledger it.

- [ ] **Step 2: Add the Whisper target**

In `Package.swift`:
- add `"Whisper"` to the library `targets`;
- add these targets:

```swift
        .binaryTarget(name: "whisper",
                      url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip",
                      checksum: "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"),
        .target(name: "Whisper", dependencies: ["Core", "whisper"]),
        .testTarget(name: "WhisperTests", dependencies: ["Whisper"]),
```

Run: `swift package --package-path WiskaKit resolve 2>&1 | tail -3`
Expected: no error. If SwiftPM rejects the archive layout (the zip nests `build-apple/whisper.xcframework`), ledger the message. Then repackage the xcframework at the zip's root, under `WiskaKit/Frameworks/whisper.xcframework`, and use `.binaryTarget(name: "whisper", path: "Frameworks/whisper.xcframework")`, with the checksum noted in a comment.

- [ ] **Step 3: Write the failing store tests**

```swift
import CryptoKit
import Foundation
import Testing
@testable import Whisper

struct FakeFileDownloader: FileDownloader {
    var contents = Data("ggml".utf8)
    var fails = false
    func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: destination)
        progress(0.5)
        if fails { throw URLError(.networkConnectionLost) }
    }
}

@MainActor
struct KBWhisperModelStoreTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kb-\(UUID().uuidString)")
    let sha = SHA256.hash(data: Data("ggml".utf8)).map { String(format: "%02x", $0) }.joined()

    func store(_ downloader: FakeFileDownloader = FakeFileDownloader(), free: Int64? = nil, sha: String? = nil) -> KBWhisperModelStore {
        KBWhisperModelStore(directory: directory, downloader: downloader, freeSpace: { free }, expectedSHA256: sha ?? self.sha)
    }

    func waitWhileDownloading(_ store: KBWhisperModelStore) async {
        while case .downloading = store.status { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func downloadsVerifiesAndIsReady() async {
        let store = store()
        let done = Box(false)
        store.onDownloaded = { done.value = true }
        store.download()
        await waitWhileDownloading(store)
        #expect(store.status == .ready)
        #expect(done.value)
        #expect(FileManager.default.fileExists(atPath: store.modelFile.path))
        #expect(self.store().isInstalled)
    }

    @Test func checksumMismatchIsRemoved() async {
        let store = store(sha: String(repeating: "0", count: 64))
        store.download()
        await waitWhileDownloading(store)
        #expect(store.status == .failed("Download failed — try again"))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func networkFailureIsRemoved() async {
        let store = store(FakeFileDownloader(fails: true))
        store.download()
        await waitWhileDownloading(store)
        #expect(store.status == .failed("Download failed — try again"))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func notEnoughDiskSpace() {
        let store = store(free: 500_000_000)
        store.download()
        #expect(store.status == .failed("Needs about 2 GB free"))
    }

    @Test func partialDownloadIsRemovedAtLaunch() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: directory.appendingPathComponent("ggml-model-q5_0.bin.partial"))
        #expect(store().status == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func removeDeletesTheModel() async {
        let store = store()
        store.download()
        await waitWhileDownloading(store)
        store.remove()
        #expect(store.status == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func pinnedModelFile() {
        #expect(KBWhisperModelStore.fileURL.absoluteString
                == "https://huggingface.co/KBLab/kb-whisper-large/resolve/d5d5984b4d8f7c4847a8ea203f1976285fb28300/ggml-model-q5_0.bin")
        #expect(KBWhisperModelStore.sha256 == "6d2863812d7410322bb7d8647a5c7260761300fa946714c9ed66d22bb30bcb19")
    }
}

@MainActor final class Box<Value> { var value: Value; init(_ value: Value) { self.value = value } }
```

Run: `swift test --package-path WiskaKit --filter KBWhisperModelStoreTests`
Expected: FAIL to compile ("cannot find 'KBWhisperModelStore'").

- [ ] **Step 4: Implement**

`Whisper/FileDownloader.swift`:

```swift
import Foundation

public protocol FileDownloader: Sendable {
    /// Downloads `url` to `destination`; `progress` goes from 0 to 1.
    func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws
}

public struct URLSessionFileDownloader: FileDownloader {
    public init() {}

    public func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = DownloadProgress(report: progress)
        let (temporary, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let report: @Sendable (Double) -> Void
    init(report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        report(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
```

`Whisper/KBWhisperModelStore.swift`:

```swift
import Core
import CryptoKit
import Foundation
import Observation

/// KB-Whisper Large (KBLab's quantized whisper.cpp file): downloaded on request, checked against
/// its published SHA-256, never half-installed.
@MainActor @Observable
public final class KBWhisperModelStore {
    public enum Status: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    private static let log = Log.logger("Whisper")
    public nonisolated static let fileURL = URL(string:
        "https://huggingface.co/KBLab/kb-whisper-large/resolve/d5d5984b4d8f7c4847a8ea203f1976285fb28300/ggml-model-q5_0.bin")!
    public nonisolated static let sha256 = "6d2863812d7410322bb7d8647a5c7260761300fa946714c9ed66d22bb30bcb19"
    nonisolated static let fileName = "ggml-model-q5_0.bin"
    nonisolated static let completionMarker = ".wiska-complete"
    public nonisolated static let requiredFreeBytes: Int64 = 2_000_000_000

    public nonisolated static var defaultDirectory: URL {
        AppPaths.supportDirectory.appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("kb-whisper-large", isDirectory: true)
    }

    public private(set) var status: Status
    public let directory: URL
    @ObservationIgnored private let downloader: any FileDownloader
    @ObservationIgnored private let freeSpace: @MainActor () -> Int64?
    @ObservationIgnored private let expectedSHA256: String
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Called after a download completes (the toggle is switched on).
    @ObservationIgnored public var onDownloaded: (@MainActor () -> Void)?

    public var isInstalled: Bool { status == .ready }
    public var modelFile: URL { directory.appendingPathComponent(Self.fileName) }

    public init(directory: URL = KBWhisperModelStore.defaultDirectory,
                downloader: any FileDownloader = URLSessionFileDownloader(),
                freeSpace: @escaping @MainActor () -> Int64? = KBWhisperModelStore.availableSpace,
                expectedSHA256: String = KBWhisperModelStore.sha256) {
        self.directory = directory
        self.downloader = downloader
        self.freeSpace = freeSpace
        self.expectedSHA256 = expectedSHA256
        let marker = directory.appendingPathComponent(Self.completionMarker)
        if FileManager.default.fileExists(atPath: marker.path),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent(Self.fileName).path) {
            status = .ready
        } else {
            if FileManager.default.fileExists(atPath: directory.path) {
                Self.log.notice("removing partial kb-whisper download")
                try? FileManager.default.removeItem(at: directory)
            }
            status = .notDownloaded
        }
    }

    public static func availableSpace() -> Int64? {
        let values = try? AppPaths.supportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public func download() {
        switch status {
        case .ready, .downloading: return
        case .notDownloaded, .failed: break
        }
        if let free = freeSpace(), free < Self.requiredFreeBytes {
            status = .failed("Needs about 2 GB free")
            return
        }
        status = .downloading(0)
        let directory = directory
        let downloader = downloader
        let expected = expectedSHA256
        let partial = directory.appendingPathComponent(Self.fileName + ".partial")
        let final = modelFile
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading(let current) = self.status, fraction > current else { return }
                self.status = .downloading(min(fraction, 0.999))
            }
        }
        task = Task { [weak self] in
            do {
                try await downloader.download(from: Self.fileURL, to: partial, progress: report)
                try Task.checkCancellation()
                let actual = try await Task.detached { try Self.sha256(of: partial) }.value
                guard actual == expected else { throw CocoaError(.fileReadCorruptFile) }
                try FileManager.default.moveItem(at: partial, to: final)
                try Data().write(to: directory.appendingPathComponent(Self.completionMarker))
                self?.status = .ready
                Self.log.info("kb-whisper model downloaded")
                self?.onDownloaded?()
            } catch {
                try? FileManager.default.removeItem(at: directory)
                if Task.isCancelled || error is CancellationError {
                    self?.status = .notDownloaded
                } else {
                    Self.log.error("kb-whisper download failed: \(String(describing: error), privacy: .public)")
                    self?.status = .failed("Download failed — try again")
                }
            }
        }
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 8 << 20), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public func cancelDownload() {
        task?.cancel()
    }

    public func remove() {
        task?.cancel()
        try? FileManager.default.removeItem(at: directory)
        status = .notDownloaded
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path WiskaKit --filter "KBWhisperModelStoreTests|GemmaRuntime|GemmaModel"`
Expected: all pass.

- [ ] **Step 6: Download the real model for development** (one time; uses the app's folder)

Add this to the test file, outside the struct:

```swift
/// `WISKA_DOWNLOAD_KB=1 swift test --filter KBWhisperRealDownload`: fetches KB-Whisper Large
/// (1.08 GB) into the app's folder, checked against its SHA-256.
@MainActor
struct KBWhisperRealDownload {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_DOWNLOAD_KB"] == "1"), .timeLimit(.minutes(30)))
    func downloadsKBWhisper() async {
        let store = KBWhisperModelStore()
        store.download()
        while case .downloading = store.status { try? await Task.sleep(for: .seconds(1)) }
        #expect(store.status == .ready)
    }
}
```

Run in the background: `WISKA_DOWNLOAD_KB=1 swift test --package-path WiskaKit --filter KBWhisperRealDownload 2>&1 | tail -3`
Expected: passes; `~/Library/Application Support/Wiska/Models/kb-whisper-large/ggml-model-q5_0.bin` is 1,081,140,203 bytes.

- [ ] **Step 7: Commit**

```bash
git add WiskaKit
git commit -m "feat(whisper): whisper.cpp target, KBWhisperModelStore (SHA-256 checked); ModelRuntime shared with Gemma

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: WhisperContext and KBWhisperRecognizer

**Files:**
- Create:
  - `WiskaKit/Sources/Whisper/WhisperContext.swift`
  - `WiskaKit/Sources/Whisper/KBWhisperRecognizer.swift`
- Test:
  - `WiskaKit/Tests/WhisperTests/KBWhisperRecognizerTests.swift`
  - `WiskaKit/Tests/WhisperTests/KBWhisperRealTests.swift`

**Interfaces:**
- Consumes: `ModelRuntime` (Task 4), `BatchRecognizer` (Task 1), `KBWhisperModelStore` (Task 4).
- Produces:
  - `public protocol WhisperModel: Sendable { func transcribe(_ samples: [Float], language: String) throws -> String }`
  - `final class WhisperContext: WhisperModel`, with `static func load(from file: URL) throws -> any WhisperModel`
  - `@MainActor @Observable public final class KBWhisperRecognizer: BatchRecognizer`, with:
    - `init(store:runtime:)`
    - `isReady`, `isLoaded`, `loadError`
    - `prepare()`, `transcribe(_:language:)`, `remove()`, `unload()`
    - `static func statusText(_:loaded:loadError:)`

- [ ] **Step 1: Write the failing tests**

```swift
import Core
import Foundation
import Testing
@testable import Whisper

struct FakeWhisper: WhisperModel {
    func transcribe(_ samples: [Float], language: String) throws -> String { "\(language): \(samples.count)" }
}

@MainActor
struct KBWhisperRecognizerTests {
    func readyStore() -> KBWhisperModelStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kb-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data("x".utf8).write(to: directory.appendingPathComponent(KBWhisperModelStore.fileName))
        try? Data().write(to: directory.appendingPathComponent(KBWhisperModelStore.completionMarker))
        return KBWhisperModelStore(directory: directory, downloader: FakeFileDownloader(), freeSpace: { nil })
    }

    @Test func transcribesSwedishThroughTheRuntime() async throws {
        let recognizer = KBWhisperRecognizer(store: readyStore(),
                                             runtime: ModelRuntime<any WhisperModel> { _ in FakeWhisper() })
        #expect(recognizer.isReady)
        #expect(try await recognizer.transcribe([0, 0, 0], language: .swedish) == "sv: 3")
        #expect(recognizer.isLoaded)
        await #expect(throws: (any Error).self) { try await recognizer.transcribe([0], language: .english) }
    }

    @Test func loadFailureMakesItUnavailableUntilRemoved() async {
        let recognizer = KBWhisperRecognizer(store: readyStore(), runtime: ModelRuntime<any WhisperModel> { _ in
            throw CocoaError(.fileReadCorruptFile)
        })
        await #expect(throws: (any Error).self) { try await recognizer.transcribe([0], language: .swedish) }
        #expect(!recognizer.isReady)
        #expect(recognizer.loadError != nil)
        recognizer.remove()
        #expect(recognizer.loadError == nil)
    }

    @Test func prepareLoadsInTheBackground() async throws {
        let recognizer = KBWhisperRecognizer(store: readyStore(),
                                             runtime: ModelRuntime<any WhisperModel> { _ in FakeWhisper() })
        recognizer.prepare()
        try await Task.sleep(for: .milliseconds(100))
        #expect(recognizer.isLoaded)
    }

    @Test func statusTexts() {
        #expect(KBWhisperRecognizer.statusText(.notDownloaded, loaded: false, loadError: nil) == "Not downloaded")
        #expect(KBWhisperRecognizer.statusText(.downloading(0.42), loaded: false, loadError: nil) == "Downloading 42 %")
        #expect(KBWhisperRecognizer.statusText(.ready, loaded: false, loadError: nil) == "Ready")
        #expect(KBWhisperRecognizer.statusText(.ready, loaded: true, loadError: nil) == "Loaded")
        #expect(KBWhisperRecognizer.statusText(.ready, loaded: false, loadError: "bad") == "Couldn't load: bad")
        #expect(KBWhisperRecognizer.statusText(.failed("Needs about 2 GB free"), loaded: false, loadError: nil)
                == "Needs about 2 GB free")
    }
}
```

`KBWhisperRealTests.swift`:

```swift
import AVFoundation
import Core
import Foundation
import Testing
@testable import Whisper

/// KB-Whisper on macOS's Swedish voice. `WISKA_REAL_MODEL=1 swift test --filter KBWhisperRealTests`
/// (or through xcodebuild with TEST_RUNNER_WISKA_REAL_MODEL=1). Needs the downloaded model.
@MainActor
struct KBWhisperRealTests {
    nonisolated static var enabled: Bool { ProcessInfo.processInfo.environment["WISKA_REAL_MODEL"] == "1" }

    static func spoken(_ text: String, voice: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wiska-\(UUID().uuidString).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, text]
        try say.run()
        say.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return try PCMConverter(from: file.processingFormat, to: .speech16kMono).convert(buffer).floatSamples
    }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(5)))
    func transcribesSwedish() async throws {
        let recognizer = KBWhisperRecognizer(store: KBWhisperModelStore())
        #expect(recognizer.isReady)
        let samples = try Self.spoken("Jag har ett stort hus och en liten trädgård.", voice: "Alva")
        let start = ContinuousClock.now
        let text = try await recognizer.transcribe(samples, language: .swedish)
        print("KB:", text.debugDescription, ContinuousClock.now - start)
        #expect(text.lowercased().contains("ett stort hus"), "\(text)")
    }
}
```

Run: `swift test --package-path WiskaKit --filter KBWhisperRecognizerTests`
Expected: FAIL to compile ("cannot find 'KBWhisperRecognizer'").

- [ ] **Step 2: Implement**

`Whisper/WhisperContext.swift`:

```swift
import Foundation
import whisper

/// A loaded Whisper model that transcribes one recording at a time.
public protocol WhisperModel: Sendable {
    func transcribe(_ samples: [Float], language: String) throws -> String
}

struct WhisperError: Error, CustomStringConvertible {
    let description: String
}

/// whisper.cpp's context: the GGML file loaded with Metal. Only used from its runtime actor,
/// one call at a time (whisper_full isn't safe in parallel on one context).
final class WhisperContext: WhisperModel, @unchecked Sendable {
    private let context: OpaquePointer

    static func load(from file: URL) throws -> any WhisperModel {
        whisper_log_set({ _, _, _ in }, nil)   // whisper.cpp logs every layer by default
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true
        guard let context = whisper_init_from_file_with_params(file.path, params) else {
            throw WhisperError(description: "the model file couldn't be loaded")
        }
        return WhisperContext(context: context)
    }

    private init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    func transcribe(_ samples: [Float], language: String) throws -> String {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.translate = false
        params.no_timestamps = true
        params.suppress_blank = true
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        return try language.withCString { code in
            params.language = code
            let status = samples.withUnsafeBufferPointer { buffer in
                whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
            }
            guard status == 0 else { throw WhisperError(description: "whisper_full returned \(status)") }
            return (0..<whisper_full_n_segments(context))
                .compactMap { whisper_full_get_segment_text(context, $0).map { String(cString: $0) } }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
```

The `WhisperContext.load` used as the runtime's `Loader` must be `async throws`. The recognizer wraps it as `{ try WhisperContext.load(from: $0) }`.

`Whisper/KBWhisperRecognizer.swift`:

```swift
import Core
import Foundation
import Observation

/// KB-Whisper as Wiska's Swedish second pass: available once downloaded and loadable.
@MainActor @Observable
public final class KBWhisperRecognizer: BatchRecognizer {
    private static let log = Log.logger("Whisper")

    public let store: KBWhisperModelStore
    @ObservationIgnored private let runtime: ModelRuntime<any WhisperModel>
    public private(set) var isLoaded = false
    public private(set) var loadError: String?
    /// Bumped by remove() and unload(): a load that finishes afterwards is old news.
    @ObservationIgnored private var epoch = 0

    public init(store: KBWhisperModelStore,
                runtime: ModelRuntime<any WhisperModel> = ModelRuntime { file in try WhisperContext.load(from: file) }) {
        self.store = store
        self.runtime = runtime
        let unloaded: @MainActor @Sendable () -> Void = { [weak self] in self?.isLoaded = false }
        Task { await runtime.setOnUnload(unloaded) }
    }

    public var isReady: Bool { store.isInstalled && loadError == nil }

    public func prepare() {
        guard isReady else { return }
        let runtime = runtime
        let file = store.modelFile
        let started = epoch
        Task { [weak self] in
            do {
                _ = try await runtime.load(from: file)
                guard let self, self.epoch == started else { return }
                self.isLoaded = true
            } catch {
                guard let self, self.epoch == started else { return }
                self.failedToLoad(error)
            }
        }
    }

    public func transcribe(_ samples: [Float], language: Language) async throws -> String {
        guard language == .swedish else { throw ModelRuntimeError.unavailable }   // KB-Whisper is Swedish
        guard isReady else { throw ModelRuntimeError.unavailable }
        let started = epoch
        do {
            let text = try await runtime.use(from: store.modelFile) { try $0.transcribe(samples, language: "sv") }
            if epoch == started { isLoaded = true }
            return text
        } catch let error as ModelRuntimeError {
            if epoch == started { failedToLoad(error) }
            throw error
        }
    }

    public func remove() {
        unload()
        loadError = nil
        store.remove()
    }

    public func unload() {
        epoch += 1
        isLoaded = false
        let runtime = runtime
        Task { await runtime.unload() }
    }

    private func failedToLoad(_ error: Error) {
        guard case ModelRuntimeError.loadFailed(let reason) = error else { return }
        Self.log.error("kb-whisper could not load: \(reason, privacy: .public)")
        loadError = reason
        isLoaded = false
    }

    /// The Settings card's status line.
    public static func statusText(_ status: KBWhisperModelStore.Status, loaded: Bool, loadError: String?) -> String {
        switch status {
        case .notDownloaded: "Not downloaded"
        case .downloading(let fraction): "Downloading \(Int(fraction * 100)) %"
        case .failed(let message): message
        case .ready:
            if let loadError { "Couldn't load: \(loadError)" } else if loaded { "Loaded" } else { "Ready" }
        }
    }
}
```

Note: the runtime is given the **model file's URL** (its `load(from:)` parameter is just a URL), not a directory.

- [ ] **Step 3: Run the tests to verify they pass**

Run: `swift test --package-path WiskaKit --filter "KBWhisperRecognizerTests|KBWhisperModelStoreTests"`
Expected: all pass.

- [ ] **Step 4: Run the real model**

Run: `WISKA_REAL_MODEL=1 swift test --package-path WiskaKit --filter KBWhisperRealTests 2>&1 | grep -E "KB:|passed|failed|error"`
Expected: `KB: "Jag har ett stort hus och en liten trädgård."` (or close to it), passing; record the time in the ledger. If it fails because the Metal library can't be found under `swift test`, rerun from `WiskaKit/` with:
`TEST_RUNNER_WISKA_REAL_MODEL=1 xcodebuild test -scheme WiskaKit -destination 'platform=macOS' -derivedDataPath ../build/pkg -only-testing:WhisperTests/KBWhisperRealTests`.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit
git commit -m "feat(whisper): whisper.cpp context (Metal) and KBWhisperRecognizer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: App — wiring, KB-Whisper card, Compare on my voice, Help and README

**Files:**
- Create:
  - `Wiska/Settings/KBWhisperCard.swift`
  - `Wiska/Settings/VoiceCompareView.swift`
- Modify:
  - `Wiska/AppModel.swift`
  - `Wiska/Settings/SpeechTab.swift`
  - `Wiska/Settings/HelpTab.swift`
  - `README.md`

**Interfaces:**
- Consumes:
  - `KBWhisperModelStore` and `KBWhisperRecognizer` (Tasks 4–5)
  - `SwedishSecondPassTranscriber` (Task 3)
  - `VoiceBenchmark` (Task 2)
  - `settings.useKBWhisper` (Task 1)
  - `MicrophoneRecorder` (Audio)

- [ ] **Step 1: Wire AppModel**

Add `import Whisper` and these properties:

```swift
    let kbWhisperStore: KBWhisperModelStore
    let kbWhisper: KBWhisperRecognizer
```

In `init`, next to the Gemma store:

```swift
        let kbWhisperStore = KBWhisperModelStore()
        self.kbWhisperStore = kbWhisperStore
        self.kbWhisper = KBWhisperRecognizer(store: kbWhisperStore)
```

After the controller is created:

```swift
        kbWhisperStore.onDownloaded = { [weak self] in
            self?.settings.useKBWhisper = true
            self?.kbWhisper.prepare()
        }
```

In `transcriber(for:)`, wrap every returned transcriber. Rename the existing switch into `private func baseTranscriber(for choice:)`, then:

```swift
    private func transcriber(for choice: LanguageChoice) -> any Transcriber {
        // Swedish second pass: on only when wanted, Swedish ticked, and the model installed.
        SwedishSecondPassTranscriber(primary: baseTranscriber(for: choice), recognizer: kbWhisper,
                                     isEnabled: { [settings] in settings.useKBWhisper && settings.enabledLanguages.contains(.swedish) })
    }
```

When the toggle is switched off, the model is unloaded: in the Speech tab toggle's setter, call `model.kbWhisper.unload()` when the new value is `false` (Step 2).

Add a helper for the Compare window:

```swift
    /// The engines Compare on my voice can run on a recording, each when installed.
    func voiceEngines() -> [(name: String, transcribe: @MainActor ([Float]) async throws -> String)] {
        var engines: [(name: String, transcribe: @MainActor ([Float]) async throws -> String)] = []
        func viaSession(_ transcriber: any Transcriber) -> @MainActor ([Float]) async throws -> String {
            { samples in
                let session = try await transcriber.makeSession(language: .fixed(.swedish))
                for start in stride(from: 0, to: samples.count, by: 1_600) {
                    session.append(AudioChunk(samples: Array(samples[start..<min(start + 1_600, samples.count)])))
                }
                return try await session.finish().text
            }
        }
        if apple.isReady(for: .swedish) { engines.append(("Apple", viaSession(apple))) }
        if parakeet.isReady { engines.append(("Parakeet", viaSession(parakeet))) }
        if kbWhisper.isReady { engines.append(("KB-Whisper", { [kbWhisper] in try await kbWhisper.transcribe($0, language: .swedish) })) }
        return engines
    }
```

- [ ] **Step 2: The KB-Whisper card**

`KBWhisperCard.swift`:

```swift
import SwiftUI
import Whisper

/// Download, status and use of KB-Whisper (Settings → Speech), shown when Swedish is ticked.
struct KBWhisperCard: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        let store = model.kbWhisperStore
        let recognizer = model.kbWhisper
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("KB-Whisper Large (Swedish)")
                    Text("The National Library of Sweden's Whisper, trained on 50,000 hours of Swedish. Re-transcribes Swedish dictations on this Mac. About 1.1 GB, downloaded from Hugging Face only when you click Download.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(KBWhisperRecognizer.statusText(store.status, loaded: recognizer.isLoaded, loadError: recognizer.loadError))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                switch store.status {
                case .notDownloaded:
                    Button("Download") { store.download() }
                case .downloading(let fraction):
                    ProgressView(value: fraction).frame(width: 90)
                    Button("Cancel") { store.cancelDownload() }
                case .ready:
                    Button(recognizer.loadError == nil ? "Remove" : "Remove and download again") {
                        let retry = recognizer.loadError != nil
                        recognizer.remove()
                        settings.useKBWhisper = false
                        if retry { store.download() }
                    }
                case .failed:
                    Button("Retry") { store.download() }
                }
            }
            if store.isInstalled {
                Toggle("Use KB-Whisper for Swedish", isOn: Binding(get: { settings.useKBWhisper }, set: { on in
                    settings.useKBWhisper = on
                    if on { recognizer.prepare() } else { recognizer.unload() }
                }))
                Text("Swedish dictations are transcribed again by KB-Whisper after you release fn; the live preview still comes from your engine.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
```

In `SpeechTab`, inside the existing `Form`, after the Parakeet section, add (shown only when Swedish is ticked):

```swift
            if model.settings.enabledLanguages.contains(.swedish) {
                Section("Swedish") {
                    KBWhisperCard(model: model)
                    Button("Compare on my voice…") { comparingVoice = true }
                }
            }
```

Add `@State private var comparingVoice = false` to `SpeechTab`, and `.sheet(isPresented: $comparingVoice) { VoiceCompareView(model: model) }` on the `Form`.

- [ ] **Step 3: The Compare on my voice window**

`VoiceCompareView.swift`:

```swift
import Audio
import Core
import Dictation
import SwiftUI

/// Settings → Speech → Compare on my voice: read the sentences once, every installed engine
/// transcribes the same recording. Nothing is stored.
struct VoiceCompareView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = MicrophoneRecorder()
    @State private var samples: [Float] = []
    @State private var recording = false
    @State private var running = false
    @State private var collect: Task<Void, Never>?
    @State private var results: [(name: String, text: String, wer: Double, time: Duration)] = []

    private static let maxSamples = 60 * 16_000

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare on my voice").font(.headline)
            Text("Press Record, read these sentences aloud at your normal pace, then press Stop.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(VoiceBenchmark.sentences.enumerated()), id: \.offset) { index, sentence in
                    Text("\(index + 1). \(sentence)")
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(recording ? "Stop" : "Record") { recording ? stop() : start() }
                    .disabled(running)
                if recording { Text("Recording… \(samples.count / 16_000) s").font(.caption).foregroundStyle(.secondary) }
                if running { ProgressView().controlSize(.small); Text("Transcribing…").font(.caption) }
            }
            List(results, id: \.name) { result in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(result.name).bold()
                        Spacer()
                        Text("\(Int((result.wer * 100).rounded())) % word errors · \(result.time.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(result.text).textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
            HStack {
                Text("Nothing is saved. Lower word errors is better.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { stopRecording(); dismiss() }
            }
        }
        .padding(16)
        .frame(width: 680, height: 600)
        .onDisappear { stopRecording() }
    }

    private func start() {
        samples = []
        results = []
        guard let capture = try? recorder.start() else { return }
        recording = true
        collect = Task { @MainActor in
            for await chunk in capture.chunks {
                samples += chunk.samples
                if samples.count >= Self.maxSamples { stop(); break }
            }
        }
    }

    private func stopRecording() {
        recorder.stop()
        collect?.cancel()
        recording = false
    }

    private func stop() {
        stopRecording()
        guard !samples.isEmpty else { return }
        let recorded = samples
        running = true
        Task { @MainActor in
            for engine in model.voiceEngines() {
                let start = ContinuousClock.now
                let text = (try? await engine.transcribe(recorded)) ?? "(failed)"
                results.append((engine.name, text,
                                VoiceBenchmark.wordErrorRate(reference: VoiceBenchmark.reference, hypothesis: text),
                                ContinuousClock.now - start))
            }
            running = false
        }
    }
}
```

`AudioCapture`'s chunk stream property is named `chunks`; confirm with `grep -n "struct AudioCapture" -A6 WiskaKit/Sources/Core/Protocols.swift` and adjust the name if it differs.

- [ ] **Step 4: Help and README**

In `HelpTab`, in the "Dictating" section, add `tip("Swedish", "Download KB-Whisper in Settings → Speech: Swedish dictations are re-transcribed by the National Library of Sweden's model for fewer mishearings. Compare on my voice shows how each engine does with your voice.")`.

In the README feature list, after the "Local model" bullet:

```markdown
- **KB-Whisper for Swedish (optional)** — download the National Library of Sweden's Whisper (1.1 GB) in Settings → Speech; Swedish dictations are re-transcribed by it for fewer mishearings. *Compare on my voice…* measures each engine on your own reading.
```

- [ ] **Step 5: Build, run the full suite and check by hand**

Run the app build: expect `** BUILD SUCCEEDED **`. Fix any exhaustive `switch` over `SpeechEngine` the build reports, for example in the menu status line.

Run: `swift test --package-path WiskaKit 2>&1 | grep -E "✘ Test [a-zA-Z]|Test run with"`
Expected: no `✘` apart from the known Parakeet Danish issue.

Relaunch the app (`pkill -x Wiska; sleep 1; open build/Build/Products/Debug/Wiska.app`). The model from Task 4 is found, so the card shows Ready. Switch the toggle on, open Compare on my voice…, and check that the window opens, lists the installed engines, and doesn't crash with an empty recording (Record, then Stop at once). Ledger what you saw. The user does the real reading.

- [ ] **Step 6: Commit**

```bash
git add Wiska README.md
git commit -m "feat(app): KB-Whisper card and Swedish second pass, Compare on my voice

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
