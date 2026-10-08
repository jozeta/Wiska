# M7 Languages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nine languages (group A), a "My languages" tick list, and every language-specific rule defined per language.

**Architecture:** `Language` grows to nine cases and `LanguageRules` (Core) holds each language's word lists. Cleanup components take rules; the pipeline picks them from the transcript's language. Settings store the ticked set and an engine per language; routers, transcribers and stats work over the ticked set instead of a hard-coded pair.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, Apple Speech (SpeechTranscriber / DictationTranscriber), FluidAudio Parakeet, NaturalLanguage, FoundationModels.

**Spec:** `docs/superpowers/specs/2026-10-08-wiska-m7-languages-design.md`

## Global Constraints

- Language order (display, cycling, storage): english, swedish, german, french, spanish, italian, portuguese, danish, dutch.
- Locales: en_US, sv_SE, de_DE, fr_FR, es_ES, it_IT, pt_PT, da_DK, nl_NL. DictationTranscriber for sv/da/nl, SpeechTranscriber for the rest.
- Word lists: exactly spec §4 (English/Swedish = today's lists, unchanged).
- Settings keys: `languages` (default `["english","swedish"]`), `<raw>Engine` per language, `secondaryLanguage`; never an empty ticked set.
- Rules for unknown language: `LanguageRules.merged(enabledLanguages)`; component defaults `merged([.english, .swedish])`.
- Package tests: `cd WiskaKit && swift test`. App build (repo root): `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build -quiet build`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Portuguese text containing "este"/"em" with Spanish also ticked and the language known → unchanged (Task 2 `spanishFillersNeverTouchPortuguese`, Task 3 pipeline uses the transcript language).
2. The user unticks the language currently used as Toggle / fn / fn+⇧ language → falls back to the first ticked, never crashes or dictates in an unticked language (Task 4 fallback tests).
3. Only English ticked → Toggle switch hidden, Auto-detect runs one Apple session, `next(in:)` returns itself (Task 1 `nextWithOneLanguageIsItself`, Task 5 `automaticWithOneLanguageStartsOneSession`).
4. Ticking a new language whose Apple assets aren't installed yet → "Downloading speech model…" only for that dictation, other languages unaffected (Task 5 `prepareInstallsOnlyTickedLanguages`).
5. Stats with a language that has no dictations → no zero-width segments, percents sum to 100 (Task 6 tests).

---

### Task 1: Nine languages, Apple module choice, engine per language, language guess

**Files:**
- Modify: `WiskaKit/Sources/Core/Language.swift`, `WiskaKit/Sources/SpeechToText/AppleModule.swift`, `WiskaKit/Sources/Preferences/SettingsStore.swift`, `WiskaKit/Sources/Parakeet/LanguageGuess.swift`, `Wiska/Settings/SpeechTab.swift`
- Test: `WiskaKit/Tests/CoreTests/LanguageTests.swift` (create), `WiskaKit/Tests/PreferencesTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces: `Language` cases `german, french, spanish, italian, portuguese, danish, dutch` with `locale/displayName/flag/badge`; `func next(in: [Language]) -> Language`; `var usesDictationTranscriber: Bool` (sv/da/nl); `SettingsStore.engine(for:)` and `setEngine(_:for:)` backed by keys `"\(raw)Engine"`; `englishEngine`/`swedishEngine` removed. `LanguageGuess.detect(_:among:)`. `Language.other` stays until Task 4.

- [ ] **Step 1: Failing tests**

```swift
// WiskaKit/Tests/CoreTests/LanguageTests.swift
import Foundation
import Testing
@testable import Core

struct LanguageTests {
    @Test func nineLanguagesInDisplayOrder() {
        #expect(Language.allCases.map(\.badge) == ["EN", "SV", "DE", "FR", "ES", "IT", "PT", "DA", "NL"])
        #expect(Language.allCases.map(\.locale.identifier)
                == ["en_US", "sv_SE", "de_DE", "fr_FR", "es_ES", "it_IT", "pt_PT", "da_DK", "nl_NL"])
    }

    @Test func nextCyclesThroughTickedLanguages() {
        let ticked: [Language] = [.english, .german, .danish]
        #expect(Language.english.next(in: ticked) == .german)
        #expect(Language.danish.next(in: ticked) == .english)
        #expect(Language.swedish.next(in: ticked) == .german)   // unticked: the next ticked after it
    }

    @Test func nextWithOneLanguageIsItself() {
        #expect(Language.french.next(in: [.french]) == .french)
    }

    @Test func dictationTranscriberOnlyWhereSpeechTranscriberIsMissing() {
        #expect(Language.allCases.filter(\.usesDictationTranscriber) == [.swedish, .danish, .dutch])
    }
}
```

Append to `SettingsStoreTests` (replace `perLanguageEnginesStartFromTheCurrentEngine`, `engineForLanguageFollowsTheMode`, `usesParakeetWhenAnyLanguageDoes`, `engineSettingsPersist`, `perLanguageEnginesAreSavedWhenThatModeIsChosen` with versions using `setEngine`):

```swift
    @Test func perLanguageEnginesStartFromTheCurrentEngine() {
        defaults.set("parakeet", forKey: "engine")
        let store = SettingsStore(defaults: defaults)
        store.engineMode = .perLanguage
        #expect(Language.allCases.allSatisfy { store.engine(for: $0) == .parakeet })
    }

    @Test func existingEnglishAndSwedishEnginesCarryOver() {
        defaults.set("perLanguage", forKey: "engineMode")
        defaults.set("parakeet", forKey: "englishEngine")
        defaults.set("apple", forKey: "swedishEngine")
        let store = SettingsStore(defaults: defaults)
        #expect(store.engine(for: .english) == .parakeet)
        #expect(store.engine(for: .swedish) == .apple)
    }

    @Test func engineForLanguageFollowsTheMode() {
        let store = SettingsStore(defaults: defaults)
        store.engine = .parakeet
        store.setEngine(.apple, for: .german)
        #expect(store.engine(for: .german) == .parakeet)   // same for all
        store.engineMode = .perLanguage
        #expect(store.engine(for: .german) == .apple)
    }

    @Test func engineSettingsPersist() {
        let store = SettingsStore(defaults: defaults)
        store.engineMode = .perLanguage
        store.setEngine(.parakeet, for: .dutch)
        #expect(SettingsStore(defaults: defaults).engine(for: .dutch) == .parakeet)
    }

    @Test func perLanguageEnginesAreSavedWhenThatModeIsChosen() {
        let store = SettingsStore(defaults: defaults)
        store.engine = .parakeet
        store.engineMode = .perLanguage
        store.engine = .apple
        #expect(SettingsStore(defaults: defaults).engine(for: .italian) == .parakeet)
    }
```

(`usesParakeetWhenAnyLanguageDoes` is rewritten in Task 4, where it gains the ticked set; for now: `store.engineMode = .perLanguage; store.setEngine(.parakeet, for: .swedish); #expect(store.usesParakeet)`.)

- [ ] **Step 2: Run** `cd WiskaKit && swift test --filter "LanguageTests|SettingsStoreTests"` → build errors.

- [ ] **Step 3: Implement**

`Language.swift`: add the cases in order; extend each switch:

```swift
    // locale
    case .german: Locale(identifier: "de_DE")
    case .french: Locale(identifier: "fr_FR")
    case .spanish: Locale(identifier: "es_ES")
    case .italian: Locale(identifier: "it_IT")
    case .portuguese: Locale(identifier: "pt_PT")
    case .danish: Locale(identifier: "da_DK")
    case .dutch: Locale(identifier: "nl_NL")
    // displayName: Deutsch, Français, Español, Italiano, Português, Dansk, Nederlands
    // flag: 🇩🇪 🇫🇷 🇪🇸 🇮🇹 🇵🇹 🇩🇰 🇳🇱 ; badge: DE FR ES IT PT DA NL

    /// The following ticked language in display order, wrapping; itself when alone.
    public func next(in languages: [Language]) -> Language {
        let all = Language.allCases
        let start = all.firstIndex(of: self)!
        for offset in 1...all.count {
            let candidate = all[(start + offset) % all.count]
            if languages.contains(candidate) { return candidate }
        }
        return self
    }

    /// Apple's SpeechTranscriber has no model for these; DictationTranscriber does.
    public var usesDictationTranscriber: Bool { [.swedish, .danish, .dutch].contains(self) }
```

Keep `other` for now (`self == .english ? .swedish : .english`); Task 4 removes it.

`AppleModule.make`: `if language.usesDictationTranscriber { DictationTranscriber … } else { SpeechTranscriber … }` (bodies unchanged).

`SettingsStore`: replace `englishEngine`/`swedishEngine` with

```swift
    /// Engines chosen per language (Per language mode). Missing entries use `engine`.
    public private(set) var languageEngines: [Language: SpeechEngine]

    private static func engineKey(_ language: Language) -> String { "\(language.rawValue)Engine" }

    public func setEngine(_ engine: SpeechEngine, for language: Language) {
        languageEngines[language] = engine
        defaults.set(engine.rawValue, forKey: Self.engineKey(language))
    }

    public func engine(for language: Language) -> SpeechEngine {
        guard engineMode == .perLanguage else { return engine }
        return languageEngines[language] ?? engine
    }
```

`init`: `languageEngines = Dictionary(uniqueKeysWithValues: Language.allCases.compactMap { l in defaults.string(forKey: Self.engineKey(l)).flatMap(SpeechEngine.init(rawValue:)).map { (l, $0) } })`. `engineMode` didSet: on `.perLanguage`, `for l in Language.allCases where languageEngines[l] == nil { setEngine(engine, for: l) }`.

`LanguageGuess.detect(_ text: String, among languages: [Language] = Language.allCases)`: constraints from `languages.map(\.nlLanguage)` where `nlLanguage` maps to `.english, .swedish, .german, .french, .spanish, .italian, .portuguese, .danish, .dutch`; map `dominantLanguage` back by the same table.

`SpeechTab.swift`: replace the two per-language pickers with

```swift
                    ForEach(Language.allCases, id: \.self) { language in
                        Picker("\(language.flag) \(language.displayName)",
                               selection: Binding(get: { settings.engine(for: language) },
                                                  set: { settings.setEngine($0, for: language); model.warmUpParakeetIfSelected() })) {
                            ForEach(SpeechEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                    }
```

and remove the `.onChange(of: settings.englishEngine/swedishEngine)` lines (Task 7 narrows the rows to ticked languages).

- [ ] **Step 4: Run** the filter → PASS; `cd WiskaKit && swift test` → all pass; app build → exit 0.
- [ ] **Step 5: Commit** `feat(languages): nine languages, engine per language, Apple module per language`.

---

### Task 2: Language rules

**Files:**
- Create: `WiskaKit/Sources/Core/LanguageRules.swift`
- Modify: `WiskaKit/Sources/Cleanup/RuleCleaner.swift`, `CleanupGuard.swift`, `VoiceCommands.swift`
- Test: `WiskaKit/Tests/CoreTests/LanguageRulesTests.swift` (create), `WiskaKit/Tests/CleanupTests/MultilingualCleanupTests.swift` (create)

**Interfaces:**
- Produces: `LanguageRules` (fields per spec §4), `Language.rules`, `LanguageRules.merged(_:)`, `LanguageRules.default` (= `merged([.english, .swedish])`); `RuleCleaner.clean(_:rules:)`, `CleanupGuard.check(original:cleaned:level:rules:)`, `CleanupGuard.requiredWords(_:rules:)`, `VoiceCommands.apply(_:rules:)` with `rules` defaulting to `.default`.

- [ ] **Step 1: Failing tests**

```swift
// WiskaKit/Tests/CoreTests/LanguageRulesTests.swift
import Testing
@testable import Core

struct LanguageRulesTests {
    @Test(arguments: Language.allCases)
    func everyLanguageHasFillersAndCommands(language: Language) {
        let rules = language.rules
        #expect(!rules.fillerSounds.isEmpty)
        #expect(!rules.newLine.isEmpty && !rules.newParagraph.isEmpty && !rules.scratchThat.isEmpty)
        #expect(!rules.questionWords.isEmpty && !rules.numberWords.isEmpty)
    }

    @Test func fillerSoundsAreNeverOrdinaryWordsElsewhere() {
        for language in Language.allCases {
            for other in Language.allCases where other != language {
                let words = other.rules.questionWords.union(other.rules.numberWords)
                    .union(other.rules.determiners).union(other.rules.softFillers)
                let clash = language.rules.fillerSounds.intersection(words)
                #expect(clash.isEmpty, "\(language) fillers \(clash) are words in \(other)")
            }
        }
    }

    @Test func englishAndSwedishAreTodaysLists() {
        let merged = LanguageRules.default
        #expect(merged.fillerSounds == ["um", "umm", "uh", "uhm", "erm", "ehm", "hmm", "öh", "eh", "äh", "ehh"])
        #expect(merged.newLine == ["new line", "ny rad"])
        #expect(merged.legitimateRepeats == ["had", "that"])
    }

    @Test func mergedIsTheUnion() {
        let rules = LanguageRules.merged([.german, .french])
        #expect(rules.fillerSounds.isSuperset(of: ["äh", "euh"]))
        #expect(rules.newLine.contains("neue zeile") && rules.newLine.contains("nouvelle ligne"))
    }
}
```

```swift
// WiskaKit/Tests/CleanupTests/MultilingualCleanupTests.swift
import Core
import Testing
@testable import Cleanup

struct MultilingualCleanupTests {
    @Test(arguments: [
        (Language.german, "äh ich glaube ähm das passt", "Ich glaube das passt."),
        (.french, "euh je pense que heu ça marche", "Je pense que ça marche."),
        (.spanish, "eh creo que mmm funciona", "Creo que funciona."),
        (.italian, "ehm penso che uhm funzioni", "Penso che funzioni."),
        (.portuguese, "hum acho que hã funciona", "Acho que funciona."),
        (.danish, "øh jeg tror æh det virker", "Jeg tror det virker."),
        (.dutch, "uh ik denk uhm dat het werkt", "Ik denk dat het werkt."),
    ])
    func fillerSoundsAreRemovedPerLanguage(language: Language, input: String, expected: String) {
        #expect(RuleCleaner.clean(input, rules: language.rules) == expected)
    }

    @Test(arguments: [
        (Language.german, "erste Zeile neue Zeile zweite Zeile", "erste Zeile\nzweite Zeile"),
        (.french, "bonjour nouvelle ligne merci", "bonjour\nmerci"),
        (.spanish, "hola nueva línea gracias", "hola\ngracias"),
        (.italian, "ciao nuova riga grazie", "ciao\ngrazie"),
        (.portuguese, "olá nova linha obrigado", "olá\nobrigado"),
        (.danish, "hej ny linje tak", "hej\ntak"),
        (.dutch, "hallo nieuwe regel bedankt", "hallo\nbedankt"),
    ])
    func newLineCommandPerLanguage(language: Language, input: String, expected: String) {
        #expect(VoiceCommands.apply(input, rules: language.rules) == expected)
    }

    @Test func scratchThatPerLanguage() {
        #expect(VoiceCommands.apply("falsch streich das richtig", rules: Language.german.rules) == "richtig")
        #expect(VoiceCommands.apply("faux efface ça vrai", rules: Language.french.rules) == "vrai")
    }

    @Test func determinerKeepsProse() {
        #expect(VoiceCommands.apply("eine neue Zeile im Text", rules: Language.german.rules) == "eine neue Zeile im Text")
    }

    @Test func spanishFillersNeverTouchPortuguese() {
        let text = "este carro está em casa"
        #expect(RuleCleaner.clean(text, rules: Language.portuguese.rules) == "Este carro está em casa.")
    }

    @Test func germanRelativeRepeatIsKept() {
        #expect(RuleCleaner.clean("die Frau die die Zeitung liest", rules: Language.german.rules)
                == "Die Frau die die Zeitung liest.")
    }

    @Test func questionStaysAQuestionInFrench() {
        #expect(CleanupGuard.check(original: "pourquoi tu pars si tôt", cleaned: "Tu pars si tôt.",
                                   level: .polished, rules: Language.french.rules) != .accept)
    }
}
```

- [ ] **Step 2: Run** `cd WiskaKit && swift test --filter "LanguageRulesTests|MultilingualCleanupTests"` → build errors.

- [ ] **Step 3: Implement**

`LanguageRules.swift`: the struct from spec §4 (all `public var`, memberwise `public init`), `extension Language { public var rules: LanguageRules { switch self { … } } }` with English/Swedish built from today's constants (move them here verbatim: `RuleCleaner.fillers` split into `fillerSounds` en = um, umm, uh, uhm, erm, ehm, hmm / sv = öh, eh, äh, ehh; `CleanupGuard.ambiguousFillers` en = like, basically, actually, well / sv = typ, liksom, alltså, asså; `fillerPhrases` en = [["you","know"]]; question and number words split by language from `CleanupGuard`; commands, determiners and infinitive markers split from `VoiceCommands`; `legitimateRepeats` en = had, that) and the seven new languages copied exactly from spec §4.

```swift
    public static func merged(_ languages: [Language]) -> LanguageRules {
        languages.map(\.rules).reduce(LanguageRules.empty) { a, b in
            LanguageRules(fillerSounds: a.fillerSounds.union(b.fillerSounds),
                          softFillers: a.softFillers.union(b.softFillers),
                          fillerPhrases: a.fillerPhrases + b.fillerPhrases,
                          questionWords: a.questionWords.union(b.questionWords),
                          numberWords: a.numberWords.union(b.numberWords),
                          newLine: a.newLine + b.newLine, newParagraph: a.newParagraph + b.newParagraph,
                          scratchThat: a.scratchThat + b.scratchThat,
                          determiners: a.determiners.union(b.determiners),
                          infinitiveMarkers: a.infinitiveMarkers.union(b.infinitiveMarkers),
                          legitimateRepeats: a.legitimateRepeats.union(b.legitimateRepeats))
        }
    }
    public static let `default` = merged([.english, .swedish])
```

Consumers: `RuleCleaner.clean(_ text: String, rules: LanguageRules = .default)` uses `rules.fillerSounds` / `rules.legitimateRepeats` (delete its constants). `CleanupGuard.check(…, rules: LanguageRules = .default)` and `requiredWords(_:rules:)` use `rules.softFillers`, `fillerPhrases`, `questionWords`, `numberWords`, and `rules.fillerSounds` where it used `RuleCleaner.fillers` (delete its constants). `VoiceCommands.apply(_ text: String, rules: LanguageRules = .default)` uses `rules.scratchThat/newParagraph/newLine/determiners/infinitiveMarkers` (delete its constants). Existing tests keep passing through the defaults.

- [ ] **Step 4: Run** the filter → PASS; full suite → PASS.
- [ ] **Step 5: Commit** `feat(cleanup): word lists per language`.

---

### Task 3: Cleanup follows the spoken language

**Files:**
- Modify: `WiskaKit/Sources/Core/DictationContext.swift`, `WiskaKit/Sources/Cleanup/CleanupPipeline.swift`, `WiskaKit/Sources/Cleanup/FoundationModelsRewriter.swift`, `WiskaKit/Sources/Core/Protocols.swift` (`TextRewriter`), `WiskaKit/Sources/Dictation/DictationController.swift`, `Wiska/AppModel.swift`
- Test: `WiskaKit/Tests/CleanupTests/CleanupPipelineTests.swift`, `WiskaKit/Tests/DictationTests/DictationControllerTests.swift`, `WiskaKit/Tests/CleanupTests/FoundationModelsRewriterTests.swift`

**Interfaces:**
- Consumes: `LanguageRules`, `Language.rules` (Task 2).
- Produces: `DictationContext(appBundleID:language:enabledLanguages:)` with `language: Language?` (default nil) and `enabledLanguages: [Language]` (default `[.english, .swedish]`); `TextRewriter.rewrite(_:level:language:)` (`language: Language?`); `FoundationModelsRewriter.instructions(for:language:)`.

- [ ] **Step 1: Failing tests**

`CleanupPipelineTests`:

```swift
    @Test func rulesFollowTheSpokenLanguage() async throws {
        rewriter.isAvailable = false   // rule cleanup only
        let pipeline = pipeline()
        let german = DictationContext(language: .german, enabledLanguages: [.german, .english])
        #expect(try await pipeline.clean("äh das passt neue Zeile gut", context: german) == "Das passt.\nGut.")
    }

    @Test func unknownLanguageUsesTheTickedLanguagesRules() async throws {
        rewriter.isAvailable = false
        let context = DictationContext(language: nil, enabledLanguages: [.dutch])
        #expect(try await pipeline().clean("uh dat klopt", context: context) == "Dat klopt.")
    }

    @Test func rewriterIsToldTheLanguage() async throws {
        _ = try await clean("bonjour je pense que ça marche bien", pipeline(),
                            context: DictationContext(language: .french, enabledLanguages: [.french]))
        #expect(rewriter.languages == [.french])
    }
```

(`FakeRewriter` records `languages: [Language?]`; the `clean` helper gains an optional `context:` parameter defaulting to `DictationContext()`.)

`DictationControllerTests`:

```swift
    @Test func cleanerReceivesTheTranscriptLanguage() async {
        transcriber.session.language = .danish
        let controller = makeController()
        controller.handle(en)
        controller.handle(.finish)
        await controller.currentTask?.value
        #expect(cleaner.contexts.first?.language == .danish)
    }
```

(and update `happyPathTranscribesCleansAndInjects`'s context expectation to `DictationContext(appBundleID: "com.apple.TextEdit", language: .english)`.)

`FoundationModelsRewriterTests`:

```swift
    @Test func instructionsNameTheLanguageAndItsFillers() {
        let text = FoundationModelsRewriter.instructions(for: .light, language: .german)
        #expect(text.contains("Deutsch"))
        #expect(text.contains("ähm"))
    }
```

- [ ] **Step 2: Run** `cd WiskaKit && swift test --filter "CleanupPipelineTests|DictationControllerTests|FoundationModelsRewriterTests"` → build errors.

- [ ] **Step 3: Implement**

- `DictationContext`: add the two fields and init parameters.
- `TextRewriter` protocol: `func rewrite(_ text: String, level: CleanupLevel, language: Language?) async throws -> String` (and `prewarm(level:)` unchanged). Update `FakeRewriter` accordingly.
- `CleanupPipeline.clean`: `let rules = context.language?.rules ?? LanguageRules.merged(context.enabledLanguages)`; pass `rules` to `VoiceCommands.apply`, `RuleCleaner.clean` and `CleanupGuard.check`, and `context.language` to the rewriter (thread `rules`/`language` through `cleanSegment` and `rewrite`).
- `FoundationModelsRewriter.instructions(for level: CleanupLevel, language: Language?)`: first sentence `"You clean up dictated text" + (language.map { " in \($0.displayName)" } ?? "") + "."`; filler examples `language.map { $0.rules.fillerSounds.sorted().joined(separator: ", ") } ?? "um, uh, ehm, öh, eh, äh"` (Polished also lists the soft fillers). Sessions are cached per `(level, language)`; `prewarm` warms `language: nil`.
- `DictationController.finishDictation`: before cleaning, `var context = self.context; context.language = transcript.language; finalText = try await cleaner.clean(transcript.text, context: context)`.
- `AppModel` `contextProvider`: `DictationContext(appBundleID: …, enabledLanguages: settings.enabledLanguages)` — `enabledLanguages` arrives in Task 4; use `[.english, .swedish]` until then.

- [ ] **Step 4: Run** the filter → PASS; full suite → PASS; app build → exit 0.
- [ ] **Step 5: Commit** `feat(cleanup): rules and model instructions follow the spoken language`.

---

### Task 4: Ticked languages in settings and routing

**Files:**
- Modify: `WiskaKit/Sources/Preferences/SettingsStore.swift`, `WiskaKit/Sources/Core/LanguageRouter.swift`, `WiskaKit/Sources/Core/EngineRouter.swift`, `WiskaKit/Sources/Dictation/CommandMapper.swift`, `WiskaKit/Sources/Core/Language.swift` (remove `other`), `Wiska/AppModel.swift`, `Wiska/MenuContent.swift`, `Wiska/Settings/LanguagesTab.swift`
- Test: `SettingsStoreTests`, `LanguageRouterTests`, `EngineRouterTests`, `CommandMapperTests`

**Interfaces:**
- Produces: `SettingsStore.enabledLanguages: [Language]`, `secondaryLanguage`, read fallbacks; `LanguageRouter.choice(mode:shifted:primary:secondary:toggle:)`; `HotkeyContext(mode:primary:secondary:toggle:enabled:canStart:)`; `EngineRouter.plan(choice:languages:engines:parakeetReady:)`, `languageChoiceMatters(languages:engines:parakeetReady:)`.

- [ ] **Step 1: Failing tests**

`SettingsStoreTests`:

```swift
    @Test func englishAndSwedishAreTickedByDefault() {
        #expect(SettingsStore(defaults: defaults).enabledLanguages == [.english, .swedish])
    }

    @Test func tickedLanguagesPersistInDisplayOrder() {
        let store = SettingsStore(defaults: defaults)
        store.enabledLanguages = [.dutch, .english, .german]
        #expect(SettingsStore(defaults: defaults).enabledLanguages == [.english, .german, .dutch])
    }

    @Test func theLastLanguageCannotBeUnticked() {
        let store = SettingsStore(defaults: defaults)
        store.enabledLanguages = []
        #expect(store.enabledLanguages == [.english, .swedish])
    }

    @Test func untickedLanguagesFallBackToTheFirstTicked() {
        let store = SettingsStore(defaults: defaults)
        store.toggleLanguage = .swedish
        store.primaryLanguage = .swedish
        store.enabledLanguages = [.german, .french]
        #expect(store.toggleLanguage == .german)
        #expect(store.primaryLanguage == .german)
        #expect(store.secondaryLanguage == .french)
    }

    @Test func usesParakeetOnlyCountsTickedLanguages() {
        let store = SettingsStore(defaults: defaults)
        store.engineMode = .perLanguage
        store.setEngine(.parakeet, for: .italian)
        #expect(!store.usesParakeet)
        store.enabledLanguages = [.english, .italian]
        #expect(store.usesParakeet)
    }
```

`LanguageRouterTests` (replace the per-language case):

```swift
    @Test func perLanguageHotkeysUseTheSecondaryLanguage() {
        #expect(LanguageRouter.choice(mode: .perLanguageHotkeys, shifted: true, primary: .english,
                                      secondary: .german, toggle: .english) == .fixed(.german))
        #expect(LanguageRouter.choice(mode: .perLanguageHotkeys, shifted: false, primary: .english,
                                      secondary: .german, toggle: .english) == .fixed(.english))
    }
```

`CommandMapperTests` (update `ctx` to pass `secondary: .swedish, enabled: [.english, .swedish]` and add):

```swift
    @Test func shiftTapCyclesThroughThreeTickedLanguages() {
        let context = HotkeyContext(mode: .toggle, primary: .english, secondary: .swedish, toggle: .swedish,
                                    enabled: [.english, .swedish, .german], canStart: true)
        #expect(CommandMapper.map(.tapped(shifted: true), context: context).newToggleLanguage == .german)
    }
```

`EngineRouterTests` (all existing calls gain `languages: [.english, .swedish]`; add):

```swift
    @Test func onlyTickedLanguagesCount() {
        let engines: (Language) -> SpeechEngine = { $0 == .german ? .parakeet : .apple }
        #expect(EngineRouter.plan(choice: .automatic, languages: [.english, .swedish], engines: engines,
                                  parakeetReady: true) == .single(.apple))
        #expect(EngineRouter.plan(choice: .automatic, languages: [.english, .german], engines: engines,
                                  parakeetReady: true) == .hybrid(apple: [.english]))
    }
```

- [ ] **Step 2: Run** `cd WiskaKit && swift test --filter "SettingsStoreTests|LanguageRouterTests|CommandMapperTests|EngineRouterTests"` → build errors.

- [ ] **Step 3: Implement**

- `SettingsStore`: key `languages`; stored `private var storedLanguages: [Language]`; public

```swift
    public var enabledLanguages: [Language] {
        get { storedLanguages }
        set {
            let ordered = Language.allCases.filter(newValue.contains)
            guard !ordered.isEmpty else { return }
            storedLanguages = ordered
            defaults.set(ordered.map(\.rawValue), forKey: Key.languages)
        }
    }
```

  `init` reads the array, drops unknown raw values, falls back to `[.english, .swedish]` if empty. `primaryLanguage`, `toggleLanguage`, `lastDetectedLanguage` become computed over stored backing values: getter returns the stored value if ticked, else `storedLanguages[0]`. `secondaryLanguage` (key `secondaryLanguage`): stored value if ticked and ≠ primary, else first ticked ≠ primary, else primary. `usesParakeet` iterates `enabledLanguages`.
- `Language.other` removed; `LanguageRouter` gains `secondary`.
- `HotkeyContext` gains `secondary` and `enabled`; `CommandMapper` flips to `context.toggle.next(in: context.enabled)` (nil when that equals `toggle`).
- `EngineRouter`: replace `Language.allCases` with `languages` in both functions.
- `AppModel`: pass `settings.enabledLanguages` / `settings.secondaryLanguage` into `HotkeyContext`, `EngineRouter`, `DictationContext`; `switchToggleLanguage()` uses `next(in:)`; `languageStatus` and `engineSummary` iterate ticked languages; per-language hotkeys status shows `secondaryLanguage`. `MenuContent`: "Switch to \(toggle.next(in: enabled).displayName)", hidden when only one is ticked.
- `LanguagesTab`: pickers list `settings.enabledLanguages`; fn+⇧ gets its own picker bound to `secondaryLanguage` (replacing the caption).

- [ ] **Step 4: Run** the filter → PASS; full suite → PASS; app build → exit 0.
- [ ] **Step 5: Commit** `feat(languages): ticked languages drive settings, hotkeys and engine routing`.

---

### Task 5: Transcribers use the ticked languages

**Files:**
- Modify: `WiskaKit/Sources/SpeechToText/AppleTranscriber.swift`, `WiskaKit/Sources/Parakeet/ParakeetTranscriber.swift`, `WiskaKit/Sources/Parakeet/ParakeetSession.swift`, `Wiska/AppModel.swift`
- Test: `WiskaKit/Tests/SpeechToTextTests/AppleTranscriberTests.swift`, `WiskaKit/Tests/ParakeetTests/ParakeetTests.swift`, `WiskaKit/Tests/SpeechToTextTests/NewLanguagesRealAudioTests.swift` (create), `WiskaKit/Tests/ParakeetTests/ParakeetLanguagesRealAudioTests.swift` (create)

**Interfaces:**
- Produces: `AppleTranscriber.init(languages: @escaping @MainActor () -> [Language] = { [.english, .swedish] }, fallbackLanguage:vocabulary:installer:)`; `ParakeetTranscriber.init(store:languages:)`; `ParakeetSession(backend:languages:)`.

- [ ] **Step 1: Failing tests**

`AppleTranscriberTests`:

```swift
    @Test func prepareInstallsOnlyTickedLanguages() async throws {
        let installed = Box([Language]())
        let transcriber = AppleTranscriber(languages: { [.english, .german] }, installer: { installed.value.append($0) })
        try await transcriber.prepare()
        #expect(installed.value == [.english, .german])
        #expect(transcriber.isReady)
    }

    @Test func automaticWithOneLanguageStartsOneSession() async throws {
        let transcriber = AppleTranscriber(languages: { [.english] })
        let session = try await transcriber.makeSession(language: .automatic)
        #expect(!(session is AutoDetectSession))
        session.cancel()
    }
```

(`Box` is a small `@MainActor final class Box<T> { var value: T }` added to the test file if not already available there.)

`ParakeetTests`:

```swift
    @Test func languageGuessIsLimitedToTickedLanguages() async throws {
        let backend = FakeBackend()
        backend.text = "Kan du skicka rapporten till mig innan lunch imorgon?"
        let session = ParakeetSession(backend: backend, languages: [.english, .danish])
        session.append(AudioChunk(samples: Array(repeating: 0.1, count: 16_000)))
        let language = try await session.finish().language
        #expect(language == .danish || language == .english)
    }
```

Real audio — Apple (fixed language; downloads assets on first run):

```swift
// WiskaKit/Tests/SpeechToTextTests/NewLanguagesRealAudioTests.swift
import AVFoundation
import Core
import Foundation
import Testing
@testable import SpeechToText

@MainActor
struct NewLanguagesRealAudioTests {
    static let samples: [(Language, String, String, String)] = [
        (.german, "Anna", "Kannst du mir den Bericht vor dem Mittagessen schicken", "bericht"),
        (.french, "Thomas", "Peux-tu m'envoyer le rapport avant le déjeuner", "rapport"),
        (.spanish, "Mónica", "Puedes enviarme el informe antes del almuerzo", "informe"),
        (.italian, "Alice", "Puoi mandarmi il rapporto prima di pranzo", "rapporto"),
        (.portuguese, "Joana", "Podes enviar-me o relatório antes do almoço", "relatório"),
        (.danish, "Sara", "Kan du sende mig rapporten før frokost", "rapporten"),
        (.dutch, "Xander", "Kun je mij het rapport voor de lunch sturen", "rapport"),
    ]

    @Test(.timeLimit(.minutes(10)), arguments: 0..<7)
    func appleTranscribesEachNewLanguage(index: Int) async throws {
        let (language, voice, sentence, keyword) = Self.samples[index]
        let audio = try SpeechSamples.spoken(sentence, voice: voice)
        let transcriber = AppleTranscriber(languages: { [language] })
        let session = try await transcriber.makeSession(language: .fixed(language))
        for start in stride(from: 0, to: audio.count, by: 1_600) {
            session.append(AudioChunk(samples: Array(audio[start..<min(start + 1_600, audio.count)])))
        }
        let transcript = try await session.finish()
        #expect(transcript.language == language)
        #expect(transcript.text.lowercased().contains(keyword), "\(language): \(transcript.text)")
    }
}
```

(`SpeechSamples.spoken(_:voice:)` is the existing `spokenSamples` helper from `AppleTranscriberTests`, moved into `WiskaKit/Tests/SpeechToTextTests/SpeechSamples.swift` as a static func so both test files share it.)

Real audio — Parakeet (`ParakeetLanguagesRealAudioTests`, enabled if `ParakeetTests.completedInstallPresent`): same seven samples through `ParakeetTranscriber(store: ParakeetModelStore(), languages: { Language.allCases })`, `.automatic`; expect `transcript.language == language` and the keyword (case-insensitive; for Parakeet's known weakness, a miss on the keyword is recorded but the language must match).

- [ ] **Step 2: Run** `cd WiskaKit && swift test --filter "AppleTranscriberTests|ParakeetTests"` → build errors.

- [ ] **Step 3: Implement**
- `AppleTranscriber`: stored `languages` closure; `isReady` = `Set(languages()).isSubset(of: installed)`; `prepare()` loops `languages()`; `.automatic` loops `languages()` (with one language the single session is returned, as today).
- `ParakeetTranscriber`: stored `languages` closure (default `{ Language.allCases }`), passed to `ParakeetSession`; `ParakeetSession.finish` uses `LanguageGuess.detect(text, among: languages)`.
- `AppModel`: `AppleTranscriber(languages: { settings.enabledLanguages }, …)`, `ParakeetTranscriber(store:, languages: { settings.enabledLanguages })`.

- [ ] **Step 4: Run** the filter → PASS; `swift test --filter "NewLanguagesRealAudioTests|ParakeetLanguagesRealAudioTests"` → PASS (first run downloads assets; allow time); full suite → PASS; app build → exit 0.
- [ ] **Step 5: Commit** `feat(speech): transcribers work over the ticked languages; real audio for seven new languages`.

---

### Task 6: Stats for any number of languages

**Files:**
- Modify: `WiskaKit/Sources/History/DictationStats.swift`, `Wiska/HistoryView.swift`
- Test: `WiskaKit/Tests/HistoryTests/DictationStatsTests.swift`

**Interfaces:**
- Produces: `DictationStats.shares: [Language: Double]` (replaces `swedishShare`/`englishShare`; init `DictationStats(words:timeSaved:shares:)`); `StatsFormatter.languagePercents(_:) -> [(language: Language, percent: Int)]`.

- [ ] **Step 1: Failing tests** (replace `languageShares`, `languagePercentsAlwaysAddUpTo100`, `noLanguagePercentsWhenNoLanguageIsKnown`):

```swift
    @Test func sharesPerLanguage() {
        let records = [record("ett två tre", language: .swedish), record("one", language: .english),
                       record("eins zwei", language: .german)]
        let stats = DictationStats.compute(records, now: now)
        #expect(stats.shares[.swedish] == 0.5)
        #expect(stats.shares[.german] == 2.0 / 6)
        #expect(stats.shares[.french] == nil)
    }

    @Test func percentsAddUpTo100LargestFirst() {
        let stats = DictationStats(words: 3, timeSaved: 0, shares: [.english: 1.0 / 3, .swedish: 1.0 / 3, .german: 1.0 / 3])
        let split = StatsFormatter.languagePercents(stats)
        #expect(split.map(\.percent).reduce(0, +) == 100)
        #expect(split.count == 3)
    }

    @Test func noPercentsWhenNoLanguageIsKnown() {
        #expect(StatsFormatter.languagePercents(DictationStats(words: 5, timeSaved: 0, shares: [:])).isEmpty)
    }
```

(The `record` helper in this test file gains a `language:` parameter if it lacks one.)

- [ ] **Step 2: Run** `cd WiskaKit && swift test --filter DictationStatsTests` → build errors.

- [ ] **Step 3: Implement**
- `compute`: count words per `record.language`; `shares[language] = words / known` for languages with words.
- `languagePercents`: floor each `share × 100`, hand the remaining points to the largest remainders, drop zero entries, sort by percent descending (ties in `allCases` order).
- `HistoryView.StatsHeader`: headline `split.map { "\($0.language.flag) \($0.percent)%" }.joined(separator: " · ")`; bar = one segment per entry, width proportional to its percent, colour interpolated along the highlight from `start` (first) to `end` (last) — reuse the channel interpolation from `WaveformView` by making a small `AuroraTheme.color(_ highlight: Highlight, at t: Double) -> Color` public helper in HUD (and use it in `WaveformView`).

- [ ] **Step 4: Run** the filter → PASS; full suite → PASS; app build → exit 0.
- [ ] **Step 5: Commit** `feat(history): language stats for any number of languages`.

---

### Task 7: Settings UI and auto-detect across nine languages

**Files:**
- Modify: `Wiska/Settings/LanguagesTab.swift`, `Wiska/Settings/SpeechTab.swift`, `Wiska/Settings/CleanupTab.swift`
- Test: `WiskaKit/Tests/SpeechToTextTests/AutoDetectNineLanguagesTests.swift` (create)

- [ ] **Step 1: My languages** — at the top of `LanguagesTab`:

```swift
            Section("My languages") {
                ForEach(Language.allCases, id: \.self) { language in
                    Toggle("\(language.flag) \(language.displayName)", isOn: Binding(
                        get: { settings.enabledLanguages.contains(language) },
                        set: { on in
                            settings.enabledLanguages = on ? settings.enabledLanguages + [language]
                                                           : settings.enabledLanguages.filter { $0 != language }
                            model.warmUpParakeetIfSelected()
                        }))
                    .disabled(settings.enabledLanguages == [language])
                }
                Text("Auto-detect, Toggle and the fn / fn+⇧ languages use only ticked languages.")
                    .font(.caption).foregroundStyle(.secondary)
            }
```

- [ ] **Step 2: Speech tab** — the Per language rows iterate `settings.enabledLanguages` instead of `Language.allCases`.
- [ ] **Step 3: Cleanup tab** — the command hint: `"Say " + settings.enabledLanguages.map { "“\($0.rules.newLine[0])”" }.joined(separator: ", ") + " for a new line; also new paragraph and scratch that in each language."`
- [ ] **Step 4: Auto-detect real-audio test**

```swift
// WiskaKit/Tests/SpeechToTextTests/AutoDetectNineLanguagesTests.swift
import Core
import Testing
@testable import SpeechToText

@MainActor
struct AutoDetectNineLanguagesTests {
    @Test(.timeLimit(.minutes(15)))
    func appleAutoDetectPicksTheSpokenLanguageAmongNine() async throws {
        let transcriber = AppleTranscriber(languages: { Language.allCases }, fallbackLanguage: { .english })
        var misses: [String] = []
        for (language, voice, sentence, _) in NewLanguagesRealAudioTests.samples {
            let audio = try SpeechSamples.spoken(sentence, voice: voice)
            let session = try await transcriber.makeSession(language: .automatic)
            for start in stride(from: 0, to: audio.count, by: 1_600) {
                session.append(AudioChunk(samples: Array(audio[start..<min(start + 1_600, audio.count)])))
            }
            let detected = try await session.finish().language
            if detected != language { misses.append("\(language) → \(String(describing: detected))") }
        }
        print("auto-detect misses: \(misses)")
        #expect(misses.count <= 1, "\(misses)")
    }
}
```

- [ ] **Step 5: Run** `cd WiskaKit && swift test --filter AutoDetectNineLanguagesTests` → PASS (≤ 1 miss); full suite → PASS; app build → exit 0.
- [ ] **Step 6: Commit** `feat(settings): My languages list; auto-detect across nine languages verified on real audio`.

---

### Task 8: Acceptance

- [ ] Full suite and app build; quit Wiska; `open build/Build/Products/Debug/Wiska.app`.
- [ ] User checklist:
  1. Settings → Languages: tick Deutsch (or another language you speak); Svenska and English stay ticked.
  2. Auto-detect: dictate in the new language — correct text, fillers removed, "neue Zeile" makes a line break; the badge/flash shows it; History lists it.
  3. Toggle mode: fn+⇧ taps cycle through the ticked languages.
  4. Per-language hotkeys: choose fn and fn+⇧ languages from the ticked ones.
  5. Speech tab, Per language: an engine row per ticked language; English → Parakeet and Svenska → Apple unchanged.
  6. History stats show a segment per language used.
