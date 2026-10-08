# Per-Language Speech Engines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick Apple or Parakeet per language (or one engine for all), including a hybrid Auto-detect that uses Parakeet for English and Apple for Swedish.

**Architecture:** A pure `EngineRouter` in `Core` turns settings + the dictation's `LanguageChoice` + Parakeet readiness into an `EnginePlan`. `DictationController` passes the choice to its transcriber provider, and `AppModel` resolves the plan to the Apple transcriber, the Parakeet transcriber, or a new `HybridTranscriber` (module `Dictation`) whose session runs Parakeet plus Apple sessions and picks by the language of Parakeet's text.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, SwiftPM package `WiskaKit` (macOS 26+), FluidAudio 0.17.7 (Parakeet), Apple SpeechAnalyzer.

**Spec:** `docs/superpowers/specs/2026-10-08-wiska-per-language-engines-design.md`

## Global Constraints

- Settings keys: existing `engine`; new `engineMode` (`same` / `perLanguage`, default `same`), `englishEngine`, `swedishEngine` (default: current value of `engine`).
- An engine that isn't ready falls back to Apple; a dictation never blocks on Parakeet.
- Hybrid only for `LanguageChoice.automatic` with mixed engines and Parakeet ready.
- No clear language from Parakeet's text → the user's last dictation language (`lastDetectedLanguage`).
- History records the engine that produced the text (`Transcript.engine`).
- Commands: package tests `cd WiskaKit && swift test`; app build `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build -quiet build` from the repo root.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A very short hybrid dictation ("ok", "ja") where Parakeet's language guess is nil → must use the last dictation's language and its engine, not fail (Task 4, `noLanguageGuessUsesLastLanguage`).
2. Parakeet hears silence (empty text) in a hybrid dictation → fall to the last language's engine; if that's empty too, the controller's existing "No speech detected" applies (Task 4, `emptyParakeetUsesFallbackLanguageEngine`).
3. Parakeet chosen for one language but not downloaded → everything runs on Apple and the "not ready" note shows (Task 1 router rows; Task 5 `parakeetUnavailable`).
4. fn+other key cancels a hybrid dictation → every session is cancelled, nothing keeps running (Task 4, `cancelCancelsEverySession`).
5. ⇧ pressed just after fn switches language mid-hold → the new choice reaches the provider, so a fixed language gets its own engine (Task 3, `switchLanguagePassesTheNewChoiceToTheProvider`).

---

## File Structure

| File | Responsibility |
|---|---|
| `WiskaKit/Sources/Core/Language.swift` (modify) | `SpeechEngine.shortName`, new `EngineMode` |
| `WiskaKit/Sources/Core/Transcript.swift` (modify) | `engine: SpeechEngine?` |
| `WiskaKit/Sources/Core/EngineRouter.swift` (create) | `EnginePlan`, `EngineRouter.plan` |
| `WiskaKit/Sources/Preferences/SettingsStore.swift` (modify) | new keys, `engine(for:)`, `usesParakeet` |
| `WiskaKit/Sources/Dictation/DictationController.swift` (modify) | provider takes `LanguageChoice`; record uses `transcript.engine` |
| `WiskaKit/Sources/Dictation/HybridTranscriber.swift` (create) | `HybridTranscriber`, `HybridSession` |
| `Wiska/AppModel.swift` (modify) | routing, status line, warm-up, unavailability |
| `Wiska/SettingsView.swift`, `Wiska/MenuContent.swift` (modify) | engine UI |
| `WiskaKit/Package.swift` (modify) | `ParakeetTests` also depends on `SpeechToText`, `Dictation` (real-audio test) |

---

### Task 1: Core — engine router and transcript engine

**Files:**
- Create: `WiskaKit/Sources/Core/EngineRouter.swift`
- Modify: `WiskaKit/Sources/Core/Language.swift` (after `SpeechEngine`), `WiskaKit/Sources/Core/Transcript.swift`
- Test: `WiskaKit/Tests/CoreTests/EngineRouterTests.swift` (create)

**Interfaces:**
- Produces: `public enum EngineMode: String { case same, perLanguage }` with `displayName`; `SpeechEngine.shortName` ("Apple"/"Parakeet"); `public enum EnginePlan: Equatable { case single(SpeechEngine); case hybrid(apple: Set<Language>) }`; `EngineRouter.plan(choice: LanguageChoice, engines: (Language) -> SpeechEngine, parakeetReady: Bool) -> EnginePlan`; `Transcript.engine: SpeechEngine?` (init param `engine: SpeechEngine? = nil`, last).

- [ ] **Step 1: Write the failing tests**

```swift
// WiskaKit/Tests/CoreTests/EngineRouterTests.swift
import Testing
@testable import Core

struct EngineRouterTests {
    private func engines(en: SpeechEngine, sv: SpeechEngine) -> (Language) -> SpeechEngine {
        { $0 == .english ? en : sv }
    }

    @Test func fixedLanguageUsesItsEngine() {
        let mixed = engines(en: .parakeet, sv: .apple)
        #expect(EngineRouter.plan(choice: .fixed(.english), engines: mixed, parakeetReady: true) == .single(.parakeet))
        #expect(EngineRouter.plan(choice: .fixed(.swedish), engines: mixed, parakeetReady: true) == .single(.apple))
    }

    @Test func parakeetNotReadyFallsBackToApple() {
        let mixed = engines(en: .parakeet, sv: .apple)
        #expect(EngineRouter.plan(choice: .fixed(.english), engines: mixed, parakeetReady: false) == .single(.apple))
        #expect(EngineRouter.plan(choice: .automatic, engines: mixed, parakeetReady: false) == .single(.apple))
        #expect(EngineRouter.plan(choice: .automatic, engines: engines(en: .parakeet, sv: .parakeet),
                                  parakeetReady: false) == .single(.apple))
    }

    @Test func automaticWithOneEngineUsesIt() {
        #expect(EngineRouter.plan(choice: .automatic, engines: engines(en: .apple, sv: .apple),
                                  parakeetReady: true) == .single(.apple))
        #expect(EngineRouter.plan(choice: .automatic, engines: engines(en: .parakeet, sv: .parakeet),
                                  parakeetReady: true) == .single(.parakeet))
    }

    @Test func automaticWithMixedEnginesIsHybrid() {
        #expect(EngineRouter.plan(choice: .automatic, engines: engines(en: .parakeet, sv: .apple),
                                  parakeetReady: true) == .hybrid(apple: [.swedish]))
        #expect(EngineRouter.plan(choice: .automatic, engines: engines(en: .apple, sv: .parakeet),
                                  parakeetReady: true) == .hybrid(apple: [.english]))
    }

    @Test func transcriptEngineDefaultsToNil() {
        #expect(Transcript(text: "a", locale: .current).engine == nil)
        #expect(Transcript(text: "a", locale: .current, engine: .parakeet).engine == .parakeet)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter EngineRouterTests`
Expected: build error — `EngineRouter` / `engine:` not found.

- [ ] **Step 3: Implement**

`WiskaKit/Sources/Core/Language.swift` — add to `SpeechEngine`, and add `EngineMode` after it:

```swift
    /// For compact UI: the menu status line and per-language rows.
    public var shortName: String {
        switch self {
        case .apple: "Apple"
        case .parakeet: "Parakeet"
        }
    }
}

/// Whether one engine serves every language, or each language has its own.
public enum EngineMode: String, Sendable, CaseIterable, Codable {
    case same
    case perLanguage

    public var displayName: String {
        switch self {
        case .same: "Same for all"
        case .perLanguage: "Per language"
        }
    }
}
```

`WiskaKit/Sources/Core/Transcript.swift` — add the property and init parameter:

```swift
public struct Transcript: Sendable, Equatable {
    public var text: String
    public var locale: Locale
    public var confidence: Double?
    public var language: Language?
    /// Which engine produced the text, when the session knows (hybrid sessions set it).
    public var engine: SpeechEngine?

    public init(text: String, locale: Locale, confidence: Double? = nil, language: Language? = nil,
                engine: SpeechEngine? = nil) {
        self.text = text
        self.locale = locale
        self.confidence = confidence
        self.language = language
        self.engine = engine
    }
}
```

`WiskaKit/Sources/Core/EngineRouter.swift`:

```swift
/// Which engine(s) transcribe one dictation.
public enum EnginePlan: Equatable, Sendable {
    case single(SpeechEngine)
    /// Auto-detect with mixed engines: Parakeet plus an Apple session for each of these languages.
    case hybrid(apple: Set<Language>)
}

/// Turns the per-language engine settings into a plan for one dictation. Pure.
public enum EngineRouter {
    public static func plan(choice: LanguageChoice, engines: (Language) -> SpeechEngine,
                            parakeetReady: Bool) -> EnginePlan {
        func usable(_ engine: SpeechEngine) -> SpeechEngine {
            engine == .parakeet && !parakeetReady ? .apple : engine
        }
        switch choice {
        case .fixed(let language):
            return .single(usable(engines(language)))
        case .automatic:
            let chosen = Language.allCases.map { usable(engines($0)) }
            if let first = chosen.first, chosen.allSatisfy({ $0 == first }) { return .single(first) }
            return .hybrid(apple: Set(Language.allCases.filter { usable(engines($0)) == .apple }))
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd WiskaKit && swift test --filter EngineRouterTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add WiskaKit/Sources/Core WiskaKit/Tests/CoreTests/EngineRouterTests.swift
git commit -m "feat(core): engine router, engine mode, transcript engine

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Preferences — per-language engine settings

**Files:**
- Modify: `WiskaKit/Sources/Preferences/SettingsStore.swift`
- Test: `WiskaKit/Tests/PreferencesTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `EngineMode` (Task 1).
- Produces: `SettingsStore.engineMode: EngineMode`, `englishEngine: SpeechEngine`, `swedishEngine: SpeechEngine`, `func engine(for: Language) -> SpeechEngine`, `var usesParakeet: Bool`.

- [ ] **Step 1: Write the failing tests** (append inside `SettingsStoreTests`)

```swift
    @Test func perLanguageEnginesStartFromTheCurrentEngine() {
        defaults.set("parakeet", forKey: "engine")
        let store = SettingsStore(defaults: defaults)
        #expect(store.engineMode == .same)
        #expect(store.englishEngine == .parakeet)
        #expect(store.swedishEngine == .parakeet)
    }

    @Test func engineForLanguageFollowsTheMode() {
        let store = SettingsStore(defaults: defaults)
        store.engine = .parakeet
        store.englishEngine = .parakeet
        store.swedishEngine = .apple
        #expect(store.engine(for: .swedish) == .parakeet)   // same for all
        store.engineMode = .perLanguage
        #expect(store.engine(for: .english) == .parakeet)
        #expect(store.engine(for: .swedish) == .apple)
    }

    @Test func usesParakeetWhenAnyLanguageDoes() {
        let store = SettingsStore(defaults: defaults)
        #expect(!store.usesParakeet)
        store.engineMode = .perLanguage
        store.swedishEngine = .parakeet
        #expect(store.usesParakeet)
    }

    @Test func engineSettingsPersist() {
        let store = SettingsStore(defaults: defaults)
        store.engineMode = .perLanguage
        store.englishEngine = .parakeet
        store.swedishEngine = .apple
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.engineMode == .perLanguage)
        #expect(reloaded.englishEngine == .parakeet)
        #expect(reloaded.swedishEngine == .apple)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter SettingsStoreTests`
Expected: build error — `engineMode` not found.

- [ ] **Step 3: Implement** in `SettingsStore.swift`

Add keys to `Key`:

```swift
        static let engineMode = "engineMode"
        static let englishEngine = "englishEngine"
        static let swedishEngine = "swedishEngine"
```

Add properties after `engine`:

```swift
    public var engineMode: EngineMode { didSet { defaults.set(engineMode.rawValue, forKey: Key.engineMode) } }
    public var englishEngine: SpeechEngine { didSet { defaults.set(englishEngine.rawValue, forKey: Key.englishEngine) } }
    public var swedishEngine: SpeechEngine { didSet { defaults.set(swedishEngine.rawValue, forKey: Key.swedishEngine) } }

    /// The engine a language uses in the current mode.
    public func engine(for language: Language) -> SpeechEngine {
        guard engineMode == .perLanguage else { return engine }
        return switch language {
        case .english: englishEngine
        case .swedish: swedishEngine
        }
    }

    /// True when any language is set to Parakeet (so it should be loaded).
    public var usesParakeet: Bool {
        Language.allCases.contains { engine(for: $0) == .parakeet }
    }
```

In `init`, after `engine = ...`:

```swift
        engineMode = Self.read(defaults, Key.engineMode, EngineMode.same)
        // Unset per-language engines start from the engine the user already has.
        englishEngine = Self.read(defaults, Key.englishEngine, engine)
        swedishEngine = Self.read(defaults, Key.swedishEngine, engine)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd WiskaKit && swift test --filter SettingsStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit/Sources/Preferences/SettingsStore.swift WiskaKit/Tests/PreferencesTests/SettingsStoreTests.swift
git commit -m "feat(settings): engine mode and per-language engines

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Dictation — provider gets the language choice; record the real engine

**Files:**
- Modify: `WiskaKit/Sources/Dictation/DictationController.swift` (init, `startListening`, `record`)
- Modify: `WiskaKit/Tests/DictationTests/DictationControllerTests.swift`, `WiskaKit/Tests/DictationTests/Fakes.swift`
- Modify: `Wiska/AppModel.swift:63` (provider closure, temporary adapter until Task 5)

**Interfaces:**
- Consumes: `Transcript.engine` (Task 1).
- Produces: `DictationController.init(audio:transcriber: @escaping @MainActor (LanguageChoice) -> any Transcriber, ...)` — the provider is called with the choice at every start and language switch. History's `DictationRecord.engine = transcript.engine ?? activeTranscriber.engine`.

- [ ] **Step 1: Write the failing tests**

In `Fakes.swift`, give `FakeSession` an engine to report:

```swift
    var engine: SpeechEngine?
    ...
        return Transcript(text: try result.get(), locale: Locale(identifier: "en_US"), language: language,
                          engine: engine)
```

In `DictationControllerTests.swift`, change the helper signature and its default:

```swift
    func makeController(maxDuration: Duration = .seconds(300), releaseTail: Duration = .zero,
                        provider: (@MainActor (LanguageChoice) -> any Transcriber)? = nil) -> DictationController {
        let transcriber = transcriber
        return DictationController(
            audio: audio, transcriber: provider ?? { _ in transcriber }, cleaner: cleaner, injector: injector,
```

Update the existing call at line 83 to `makeController(provider: { _ in useOther.value ? other : first })`, then add:

```swift
    @Test func switchLanguagePassesTheNewChoiceToTheProvider() async {
        let choices = Box<[LanguageChoice]>([])
        let transcriber = transcriber
        let controller = makeController(provider: { choice in
            choices.value.append(choice)
            return transcriber
        })
        controller.handle(en)
        controller.handle(.switchLanguage(.fixed(.swedish)))
        controller.handle(.cancel)
        await controller.currentTask?.value
        #expect(choices.value == [.fixed(.english), .fixed(.swedish)])
    }

    @Test func recordUsesTheEngineThatProducedTheText() async {
        transcriber.session.engine = .parakeet   // FakeTranscriber itself reports .apple
        let controller = makeController()
        let records = recording(controller)
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(records.value.first?.engine == .parakeet)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter DictationControllerTests`
Expected: build error — closure type mismatch for `transcriber:`.

- [ ] **Step 3: Implement** in `DictationController.swift`

```swift
    private let transcriberProvider: @MainActor (LanguageChoice) -> any Transcriber
    ...
    public init(
        audio: any AudioSource,
        transcriber: @escaping @MainActor (LanguageChoice) -> any Transcriber,
```

In `startListening(_ choice:)`:

```swift
        // Chosen once per dictation, for its language: changing engines mid-hold affects the next one.
        let transcriber = transcriberProvider(choice)
```

In `record(_:_:pasted:)`:

```swift
            engine: transcript.engine ?? activeTranscriber?.engine ?? .apple, rawText: transcript.text,
```

In `Wiska/AppModel.swift`, keep the app compiling until Task 5:

```swift
            transcriber: { [weak self] _ in self?.activeTranscriber() ?? AppleTranscriber() },
```

- [ ] **Step 4: Run tests and build**

Run: `cd WiskaKit && swift test --filter DictationControllerTests` → PASS.
Run (repo root): the app build command from Global Constraints → exit 0.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit/Sources/Dictation WiskaKit/Tests/DictationTests Wiska/AppModel.swift
git commit -m "feat(dictation): transcriber chosen per language choice; history records the real engine

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Dictation — hybrid transcriber

**Files:**
- Create: `WiskaKit/Sources/Dictation/HybridTranscriber.swift`
- Test: `WiskaKit/Tests/DictationTests/HybridTranscriberTests.swift` (create)

**Interfaces:**
- Consumes: `Transcriber`, `TranscriptionSession`, `Transcript.engine`, `LanguagePicker` (Core).
- Produces: `public final class HybridTranscriber: Transcriber` with `public init(parakeet: any Transcriber, apple: any Transcriber, appleLanguages: Set<Language>, fallbackLanguage: @escaping @MainActor () -> Language)`; `HybridSession` (internal). Task 5 builds a `HybridTranscriber` per dictation.

- [ ] **Step 1: Write the failing tests**

```swift
// WiskaKit/Tests/DictationTests/HybridTranscriberTests.swift
import Core
import Foundation
import Testing
@testable import Dictation

/// Returns a fresh FakeSession per language choice, so each engine/language is observable.
@MainActor
final class SessionsTranscriber: Transcriber {
    var isReady = true
    var failToStart: Set<String> = []
    private(set) var sessions: [String: FakeSession] = [:]
    let name: SpeechEngine
    init(_ name: SpeechEngine) { self.name = name }
    var engine: SpeechEngine { name }
    func prepare() async throws {}

    static func key(_ choice: LanguageChoice) -> String {
        switch choice {
        case .automatic: "auto"
        case .fixed(let language): language.rawValue
        }
    }

    func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        let key = Self.key(language)
        if failToStart.contains(key) { throw FakeError() }
        let session = FakeSession()
        sessions[key] = session
        return session
    }
}

@MainActor
struct HybridTranscriberTests {
    let parakeet = SessionsTranscriber(.parakeet)
    let apple = SessionsTranscriber(.apple)

    func hybrid(last: Language = .english) -> HybridTranscriber {
        HybridTranscriber(parakeet: parakeet, apple: apple, appleLanguages: [.swedish],
                          fallbackLanguage: { last })
    }

    func run(_ transcriber: HybridTranscriber, parakeetSays text: String, language: Language?,
             appleSays appleText: String = "Apple svenska") async throws -> Transcript {
        let session = try await transcriber.makeSession(language: .automatic)
        session.append(AudioChunk(samples: [0.1]))
        parakeet.sessions["auto"]?.result = .success(text)
        parakeet.sessions["auto"]?.language = language
        apple.sessions["swedish"]?.result = .success(appleText)
        apple.sessions["swedish"]?.language = .swedish
        return try await session.finish()
    }

    @Test func audioReachesEverySession() async throws {
        let session = try await hybrid().makeSession(language: .automatic)
        session.append(AudioChunk(samples: [0.5]))
        #expect(parakeet.sessions["auto"]?.appended == [[0.5]])
        #expect(apple.sessions["swedish"]?.appended == [[0.5]])
        #expect(apple.sessions["english"] == nil)
    }

    @Test func englishUsesParakeetAndCancelsApple() async throws {
        let transcript = try await run(hybrid(), parakeetSays: "Hello there", language: .english)
        #expect(transcript.text == "Hello there")
        #expect(transcript.engine == .parakeet)
        #expect(apple.sessions["swedish"]?.cancelled == true)
    }

    @Test func swedishUsesApple() async throws {
        let transcript = try await run(hybrid(), parakeetSays: "Hej gicker", language: .swedish)
        #expect(transcript.text == "Apple svenska")
        #expect(transcript.engine == .apple)
        #expect(transcript.language == .swedish)
    }

    @Test func noLanguageGuessUsesLastLanguage() async throws {
        let transcript = try await run(hybrid(last: .swedish), parakeetSays: "ok", language: nil)
        #expect(transcript.engine == .apple)
        #expect(transcript.text == "Apple svenska")
    }

    @Test func emptyParakeetUsesFallbackLanguageEngine() async throws {
        let toEnglish = try await run(hybrid(last: .english), parakeetSays: "", language: nil)
        #expect(toEnglish.text.isEmpty)
        #expect(toEnglish.engine == .parakeet)
    }

    @Test func appleFailingFallsBackToParakeet() async throws {
        let transcriber = hybrid()
        let session = try await transcriber.makeSession(language: .automatic)
        parakeet.sessions["auto"]?.result = .success("Hej gicker")
        parakeet.sessions["auto"]?.language = .swedish
        apple.sessions["swedish"]?.result = .failure(FakeError())
        let transcript = try await session.finish()
        #expect(transcript.text == "Hej gicker")
        #expect(transcript.engine == .parakeet)
    }

    @Test func appleEmptyFallsBackToParakeet() async throws {
        let transcript = try await run(hybrid(), parakeetSays: "Hej gicker", language: .swedish, appleSays: "")
        #expect(transcript.text == "Hej gicker")
        #expect(transcript.engine == .parakeet)
    }

    @Test func parakeetFailingUsesApple() async throws {
        let transcriber = hybrid()
        let session = try await transcriber.makeSession(language: .automatic)
        parakeet.sessions["auto"]?.result = .failure(FakeError())
        apple.sessions["swedish"]?.result = .success("Apple svenska")
        apple.sessions["swedish"]?.language = .swedish
        let transcript = try await session.finish()
        #expect(transcript.text == "Apple svenska")
        #expect(transcript.engine == .apple)
    }

    @Test func everythingFailingThrows() async throws {
        let session = try await hybrid().makeSession(language: .automatic)
        parakeet.sessions["auto"]?.result = .failure(FakeError())
        apple.sessions["swedish"]?.result = .failure(FakeError())
        await #expect(throws: (any Error).self) { _ = try await session.finish() }
    }

    @Test func appleThatCannotStartLeavesParakeet() async throws {
        apple.failToStart = ["swedish"]
        let transcript = try await run(hybrid(), parakeetSays: "Hej gicker", language: .swedish)
        #expect(transcript.text == "Hej gicker")
        #expect(transcript.engine == .parakeet)
    }

    @Test func parakeetThatCannotStartUsesAppleAutoDetect() async throws {
        parakeet.failToStart = ["auto"]
        _ = try await hybrid().makeSession(language: .automatic)
        #expect(apple.sessions["auto"] != nil)
        #expect(apple.sessions["swedish"] == nil)
    }

    @Test func cancelCancelsEverySession() async throws {
        let session = try await hybrid().makeSession(language: .automatic)
        session.cancel()
        #expect(parakeet.sessions["auto"]?.cancelled == true)
        #expect(apple.sessions["swedish"]?.cancelled == true)
    }

    @Test func readyOnlyWhenBothEnginesAre() {
        apple.isReady = false
        #expect(!hybrid().isReady)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd WiskaKit && swift test --filter HybridTranscriberTests`
Expected: build error — `HybridTranscriber` not found.

- [ ] **Step 3: Implement** `WiskaKit/Sources/Dictation/HybridTranscriber.swift`

```swift
import Core

/// Auto-detect with mixed engines: Parakeet hears everything, and an Apple session runs for each
/// language assigned to Apple. The language of Parakeet's text decides whose result is used.
@MainActor
public final class HybridTranscriber: Transcriber {
    private static let log = Log.logger("Dictation")
    private let parakeet: any Transcriber
    private let apple: any Transcriber
    private let appleLanguages: Set<Language>
    private let fallbackLanguage: @MainActor () -> Language

    public init(parakeet: any Transcriber, apple: any Transcriber, appleLanguages: Set<Language>,
                fallbackLanguage: @escaping @MainActor () -> Language) {
        self.parakeet = parakeet
        self.apple = apple
        self.appleLanguages = appleLanguages
        self.fallbackLanguage = fallbackLanguage
    }

    public var isReady: Bool { parakeet.isReady && apple.isReady }
    public var engine: SpeechEngine { .parakeet }

    public func prepare() async throws {
        try await parakeet.prepare()
        try await apple.prepare()
    }

    /// Always automatic: a fixed language never gets a hybrid (see `EngineRouter`).
    public func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        let parakeetSession: any TranscriptionSession
        do {
            parakeetSession = try await parakeet.makeSession(language: .automatic)
        } catch {
            Self.log.error("hybrid: parakeet can't start, using apple auto-detect: \(String(describing: type(of: error)), privacy: .public)")
            return try await apple.makeSession(language: .automatic)
        }
        var appleSessions: [Language: any TranscriptionSession] = [:]
        for language in Language.allCases where appleLanguages.contains(language) {
            do {
                appleSessions[language] = try await apple.makeSession(language: .fixed(language))
            } catch {
                Self.log.error("hybrid: apple \(language.rawValue, privacy: .public) can't start; parakeet only")
            }
        }
        return HybridSession(parakeet: parakeetSession, apple: appleSessions, fallbackLanguage: fallbackLanguage())
    }
}

@MainActor
final class HybridSession: TranscriptionSession {
    private let parakeet: any TranscriptionSession
    private let apple: [Language: any TranscriptionSession]
    private let fallbackLanguage: Language

    init(parakeet: any TranscriptionSession, apple: [Language: any TranscriptionSession], fallbackLanguage: Language) {
        self.parakeet = parakeet
        self.apple = apple
        self.fallbackLanguage = fallbackLanguage
    }

    func append(_ chunk: AudioChunk) {
        parakeet.append(chunk)
        for session in apple.values { session.append(chunk) }
    }

    func finish() async throws -> Transcript {
        // Apple sessions start finishing now, in parallel with Parakeet, so Swedish waits less.
        let appleResults = apple.mapValues { session in Task { try await session.finish() } }

        let heard: Transcript
        do {
            heard = try await parakeet.finish()
        } catch {
            return try await bestApple(appleResults, parakeetError: error)
        }
        var fromParakeet = heard
        fromParakeet.engine = .parakeet
        // No guess (short or empty text): assume the language of the last dictation.
        let language = heard.language ?? fallbackLanguage
        guard let chosen = appleResults[language] else {
            cancelApple(appleResults)
            return fromParakeet
        }
        cancelApple(appleResults.filter { $0.key != language })
        guard var fromApple = try? await chosen.value, !fromApple.text.isEmpty else { return fromParakeet }
        fromApple.engine = .apple
        fromApple.language = language
        return fromApple
    }

    func cancel() {
        parakeet.cancel()
        for session in apple.values { session.cancel() }
    }

    private func cancelApple(_ results: [Language: Task<Transcript, Error>]) {
        for (language, task) in results {
            task.cancel()
            apple[language]?.cancel()
        }
    }

    /// Parakeet failed: the most confident Apple result, like Apple's own auto-detect.
    private func bestApple(_ results: [Language: Task<Transcript, Error>], parakeetError: Error) async throws -> Transcript {
        var transcripts: [Transcript] = []
        for (language, task) in results {
            guard var transcript = try? await task.value else { continue }
            transcript.engine = .apple
            transcript.language = transcript.language ?? language
            transcripts.append(transcript)
        }
        guard !transcripts.isEmpty else { throw parakeetError }
        return LanguagePicker.pick(transcripts, fallback: fallbackLanguage)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd WiskaKit && swift test --filter HybridTranscriberTests`
Expected: PASS (13 tests).

- [ ] **Step 5: Commit**

```bash
git add WiskaKit/Sources/Dictation/HybridTranscriber.swift WiskaKit/Tests/DictationTests/HybridTranscriberTests.swift
git commit -m "feat(dictation): hybrid transcriber for auto-detect with mixed engines

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: App — routing, status, Settings UI

**Files:**
- Modify: `Wiska/AppModel.swift` (provider, `activeTranscriber`, `parakeetUnavailable`, `warmUpParakeetIfSelected`, `languageStatus`, `badgeText`)
- Modify: `Wiska/SettingsView.swift` ("Speech engine" section), `Wiska/MenuContent.swift:15`

**Interfaces:**
- Consumes: `EngineRouter.plan`, `EnginePlan` (Task 1); `SettingsStore.engineMode/englishEngine/swedishEngine/engine(for:)/usesParakeet` (Task 2); provider `(LanguageChoice) -> any Transcriber` (Task 3); `HybridTranscriber` (Task 4).

- [ ] **Step 1: Route in `AppModel.swift`**

Provider (replacing Task 3's adapter):

```swift
            transcriber: { [weak self] choice in self?.transcriber(for: choice) ?? AppleTranscriber() },
```

Replace `activeTranscriber()` with:

```swift
    private func plan(for choice: LanguageChoice) -> EnginePlan {
        EngineRouter.plan(choice: choice, engines: { self.settings.engine(for: $0) },
                          parakeetReady: parakeet.isReady)
    }

    private func transcriber(for choice: LanguageChoice) -> any Transcriber {
        if settings.usesParakeet && !parakeet.isReady { warmUpParakeetIfSelected() }
        switch plan(for: choice) {
        case .single(.apple): return apple
        case .single(.parakeet): return parakeet
        case .hybrid(let appleLanguages):
            return HybridTranscriber(parakeet: parakeet, apple: apple, appleLanguages: appleLanguages,
                                     fallbackLanguage: { [settings] in settings.lastDetectedLanguage })
        }
    }
```

Update the Parakeet checks:

```swift
    /// True when some language is set to Parakeet but it can't be used right now.
    var parakeetUnavailable: Bool {
        settings.usesParakeet && !parakeet.isReady
    }

    func warmUpParakeetIfSelected() {
        guard settings.usesParakeet, parakeetStore.isInstalled, !parakeet.isReady else { return }
```

Status line and badge:

```swift
    var languageStatus: String {
        let mode = switch settings.languageMode {
        case .autoDetect: "Auto-detect"
        case .toggle: "Toggle: \(settings.toggleLanguage.displayName)"
        case .perLanguageHotkeys:
            "fn: \(settings.primaryLanguage.displayName) · fn+⇧: \(settings.primaryLanguage.other.displayName)"
        }
        return "\(mode) · \(engineSummary)"
    }

    /// What will actually run: "Parakeet", or "🇬🇧 Parakeet · 🇸🇪 Apple" per language.
    private var engineSummary: String {
        func usable(_ engine: SpeechEngine) -> SpeechEngine {
            engine == .parakeet && !parakeet.isReady ? .apple : engine
        }
        guard settings.engineMode == .perLanguage else { return usable(settings.engine).shortName }
        return Language.allCases
            .map { "\($0.flag) \(usable(settings.engine(for: $0)).shortName)" }
            .joined(separator: " · ")
    }

    private func badgeText(for choice: LanguageChoice) -> String {
        if case .single(.parakeet) = plan(for: choice) { return "AUTO" }   // Parakeet picks the language itself
        return switch choice {
        case .automatic: "AUTO"
        case .fixed(let language): language.badge
        }
    }
```

In `MenuContent.swift`, the toggle switch no longer depends on Parakeet:

```swift
        if model.settings.languageMode == .toggle {
```

- [ ] **Step 2: Settings UI** — replace the "Speech engine" section in `SettingsView.swift`

```swift
            Section("Speech engine") {
                Picker("Engines", selection: $settings.engineMode) {
                    ForEach(EngineMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                switch settings.engineMode {
                case .same:
                    Picker("Engine", selection: $settings.engine) {
                        ForEach(SpeechEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                case .perLanguage:
                    Picker("\(Language.english.flag) \(Language.english.displayName)", selection: $settings.englishEngine) {
                        ForEach(SpeechEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker("\(Language.swedish.flag) \(Language.swedish.displayName)", selection: $settings.swedishEngine) {
                        ForEach(SpeechEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                ParakeetCard(store: model.parakeetStore) { model.parakeetModelBecameReady() }
                if model.parakeetUnavailable {
                    Text("Parakeet is selected but not ready — Apple is used until it is.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: settings.engine) { model.warmUpParakeetIfSelected() }
            .onChange(of: settings.engineMode) { model.warmUpParakeetIfSelected() }
            .onChange(of: settings.englishEngine) { model.warmUpParakeetIfSelected() }
            .onChange(of: settings.swedishEngine) { model.warmUpParakeetIfSelected() }
```

- [ ] **Step 3: Build and run the full suite**

Run (repo root): the app build command → exit 0.
Run: `cd WiskaKit && swift test` → all pass.

- [ ] **Step 4: Commit**

```bash
git add Wiska
git commit -m "feat(app): per-language engine routing, status line and Settings UI

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Real-audio check and acceptance

**Files:**
- Modify: `WiskaKit/Package.swift` (`ParakeetTests` dependencies)
- Test: `WiskaKit/Tests/ParakeetTests/HybridRealAudioTests.swift` (create)

**Interfaces:**
- Consumes: `HybridTranscriber` (Task 4), `AppleTranscriber` (SpeechToText), `ParakeetTranscriber`, `ParakeetModelStore`, `ParakeetTests.completedInstallPresent`, `AVAudioFileReader.samples16k` (existing test helpers).

- [ ] **Step 1: Let the Parakeet tests reach the other engines** — in `Package.swift`:

```swift
        .testTarget(name: "ParakeetTests", dependencies: ["Parakeet", "SpeechToText", "Dictation"]),
```

- [ ] **Step 2: Write the test**

```swift
// WiskaKit/Tests/ParakeetTests/HybridRealAudioTests.swift
import Core
import Dictation
import Foundation
import SpeechToText
import Testing
@testable import Parakeet

@MainActor
struct HybridRealAudioTests {
    func speak(_ text: String, voice: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hy-\(UUID().uuidString).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, text]
        try say.run()
        say.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: url) }
        return try AVAudioFileReader.samples16k(url)
    }

    func transcribe(_ samples: [Float]) async throws -> Transcript {
        let parakeet = ParakeetTranscriber(store: ParakeetModelStore())
        try await parakeet.prepare()
        let hybrid = HybridTranscriber(parakeet: parakeet, apple: AppleTranscriber(),
                                       appleLanguages: [.swedish], fallbackLanguage: { .english })
        let session = try await hybrid.makeSession(language: .automatic)
        for start in stride(from: 0, to: samples.count, by: 1_600) {
            session.append(AudioChunk(samples: Array(samples[start..<min(start + 1_600, samples.count)])))
        }
        return try await session.finish()
    }

    @Test(.enabled(if: ParakeetTests.completedInstallPresent), .timeLimit(.minutes(3)))
    func englishComesFromParakeet() async throws {
        let transcript = try await transcribe(try speak("Can you send me the quarterly report before lunch tomorrow",
                                                        voice: "Samantha"))
        #expect(transcript.engine == .parakeet)
        #expect(transcript.text.lowercased().contains("quarterly report"))
    }

    @Test(.enabled(if: ParakeetTests.completedInstallPresent), .timeLimit(.minutes(3)))
    func swedishComesFromApple() async throws {
        let transcript = try await transcribe(try speak(
            "Vi gick igenom siffrorna för tredje kvartalet och resultatet ser bättre ut än väntat", voice: "Alva"))
        #expect(transcript.engine == .apple)
        #expect(transcript.language == .swedish)
        #expect(transcript.text.lowercased().contains("gick igenom"))
    }
}
```

- [ ] **Step 3: Run it**

Run: `cd WiskaKit && swift test --filter HybridRealAudioTests`
Expected: PASS (both run, since Parakeet is installed on this Mac).

- [ ] **Step 4: Full suite, app build, relaunch**

Run: `cd WiskaKit && swift test` → all pass. Build the app (Global Constraints command), quit the running Wiska and `open build/Build/Products/Debug/Wiska.app`.

- [ ] **Step 5: Commit**

```bash
git add WiskaKit/Package.swift WiskaKit/Tests/ParakeetTests/HybridRealAudioTests.swift
git commit -m "test(parakeet): hybrid picks Parakeet for English and Apple for Swedish on real audio

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: User acceptance (manual)**

In Settings set Engines → Per language, 🇬🇧 English → Parakeet, 🇸🇪 Svenska → Apple; Language → Auto-detect. Then:
1. Dictate an English sentence and a Swedish sentence; open History and check the engine shown for each (English: Parakeet, Swedish: Apple).
2. The menu status line reads "Auto-detect · 🇬🇧 Parakeet · 🇸🇪 Apple".
3. Switch Engines back to Same for all → Parakeet; dictation behaves as before.
