# Wiska — M7 Languages Design

Date: 2026-10-08
Status: Draft for review
Builds on: M1–M6, per-language engines (main @ 93f89f9)

## 1. Intent

Support nine languages instead of two, chosen by the user, with every language-specific
behaviour (fillers, voice commands, cleanup safety checks, engine) defined per language.

**Stated by user:** add "group A": English, Svenska, Deutsch, Français, Español,
Italiano, Português, Dansk, Nederlands. A "My languages" tick list decides which are
active; Auto-detect, Toggle and Per-language hotkeys use only ticked languages; each
ticked language has its own engine choice.

**Assumed:** English and Svenska stay ticked by default so nothing changes until the user
ticks more. Locales: en_US, sv_SE, de_DE, fr_FR, es_ES, it_IT, pt_PT, da_DK, nl_NL.

**Success:**
- Ticking a language and dictating in it gives correct text with that language's fillers
  removed and voice commands working, on Apple and on Parakeet.
- Auto-detect picks the right language among the ticked ones (real-audio test with all
  nine ticked).
- A filler or command word from one language never changes text in another language
  (e.g. Spanish "este" stays in Portuguese text).
- Only ticked languages download Apple speech assets.

## 2. Verified facts (probed 2026-10-08 on the dev Mac)

| Language | Apple SpeechTranscriber | Apple DictationTranscriber | Parakeet v3 | Apple Intelligence cleanup |
|---|---|---|---|---|
| English, Deutsch, Français, Español, Italiano, Português | ✅ | ✅ | ✅ | ✅ |
| Svenska, Dansk, Nederlands | ❌ | ✅ | ✅ | ✅ |

- Assets for de/fr/es/it/pt/da/nl are not installed yet; Apple downloads them on demand.
- **Apple allows an app at most 5 reserved speech locales** (`AssetInventory.maximumReservedLocales
  == 5`; a sixth fails with "Too many allocated locales, 5 maximum"). Found while implementing;
  user decision: **at most 5 ticked languages**. Unticking a language releases its reservation
  (`AssetInventory.release(reservedLocale:)`), so the user can swap languages.
- System voices for tests: Anna (de_DE), Thomas (fr_FR), Mónica (es_ES), Alice (it_IT),
  Joana (pt_PT), Sara (da_DK), Xander (nl_NL), plus Samantha (en) and Alva (sv).

## 3. Languages and settings

### 3.1 `Language`

`Language` gains `german, french, spanish, italian, portuguese, danish, dutch`, each
with `locale`, `displayName` (native: Deutsch, Français, Español, Italiano, Português,
Dansk, Nederlands), `flag` (🇩🇪 🇫🇷 🇪🇸 🇮🇹 🇵🇹 🇩🇰 🇳🇱) and `badge` (DE FR ES IT PT DA NL).
`allCases` order is the display and cycling order: English, Svenska, Deutsch,
Français, Español, Italiano, Português, Dansk, Nederlands.

`Language.other` is removed. Replacement: `func next(in languages: [Language]) -> Language`
(the following ticked language in `allCases` order, wrapping; itself if alone).

### 3.2 `SettingsStore`

| Key | Type | Default | Notes |
|---|---|---|---|
| `languages` (new) | array of raw values | `["english", "swedish"]` | the ticked set; stored in `allCases` order; 1–5 languages (unticking the last or ticking a sixth is refused) |
| `<raw>Engine` (generalised) | `SpeechEngine` | current `engine` | `englishEngine`/`swedishEngine` keep their keys, so existing choices carry over; first switch to Per language seeds and saves every language |
| `secondaryLanguage` (new) | `Language` | first ticked language ≠ primary | fn+⇧ language in Per-language hotkeys mode |
| `primaryLanguage`, `toggleLanguage`, `lastDetectedLanguage` | existing | — | if not ticked, they read as the first ticked language |

API:
- `enabledLanguages: [Language]` (get/set; set ignores an empty array);
- `engine(for:)` / `setEngine(_:for:)` replace `englishEngine` / `swedishEngine`;
- `usesParakeet` considers ticked languages only;
- `primary`, `secondary`, `toggle` accessors return ticked languages (§3.2 fallback).

### 3.3 Routing

- `LanguageRouter.choice(mode:shifted:primary:secondary:toggle:)` — Per-language hotkeys
  uses `secondary` for fn+⇧ instead of `primary.other`.
- `CommandMapper`: a shifted tap in Toggle mode flips to `toggle.next(in: enabled)`;
  `HotkeyContext` gains `enabled: [Language]` and `secondary`.
- `EngineRouter.plan(choice:languages:engines:parakeetReady:)` and
  `languageChoiceMatters(languages:...)` take the ticked languages instead of
  `Language.allCases`.

## 4. Rules per language (`Core/LanguageRules.swift`)

```swift
public struct LanguageRules: Sendable {
    public var fillerSounds: Set<String>      // never real words: always removed
    public var softFillers: Set<String>       // words Polished may drop as fillers
    public var fillerPhrases: [[String]]      // fillers only as a phrase ("you know")
    public var questionWords: Set<String>     // a dictation starting with one stays a question
    public var numberWords: Set<String>       // spoken numbers may become digits
    public var newLine: [String], newParagraph: [String], scratchThat: [String]
    public var determiners: Set<String>       // "a new line of…" is prose, not a command
    public var infinitiveMarkers: Set<String> // "to scratch that itch" is prose
    public var legitimateRepeats: Set<String> // doubled words that are correct ("had had")
}
extension Language { public var rules: LanguageRules }
extension LanguageRules { public static func merged(_ languages: [Language]) -> LanguageRules }
```

All words lower-case. Cleanup uses the transcript's language's rules; when the language
is unknown it uses `merged(enabledLanguages)`. English and Swedish rules are exactly
today's lists (moved, not changed). New languages:

| | Filler sounds | Soft fillers | Phrases | New line / paragraph / scratch that | Determiners | Infinitive | Legit repeats |
|---|---|---|---|---|---|---|---|
| de | äh, ähm, öhm, hm, hmm, ehm | also, halt, quasi, sozusagen | — | neue zeile / neuer absatz / streich das | ein, eine, einen, einem, einer, der, die, das, den, dem, des, dieser, diese, dieses, mein, meine, dein, deine, unser, unsere, ihr, ihre, sein, seine | zu | der, die, das |
| fr | euh, heu, hum, hm | genre, bah, ben, bref, quoi | — | nouvelle ligne / nouveau paragraphe / efface ça | un, une, le, la, les, ce, cette, ces, mon, ma, mes, ton, ta, tes, son, sa, ses, notre, votre, leur | de | nous, vous |
| es | eh, ehm, mmm, hmm | pues, bueno, tipo | o sea | nueva línea / nuevo párrafo / borra eso | un, una, el, la, los, las, este, esta, estos, estas, mi, mis, tu, tus, su, sus, nuestro, nuestra | — | — |
| it | ehm, eh, mmm, uhm | cioè, tipo, insomma, praticamente | — | nuova riga / nuovo paragrafo / cancella quello | un, una, uno, il, lo, la, i, gli, le, questo, questa, mio, mia, tuo, tua, suo, sua, nostro, nostra | di | — |
| pt | hum, hã, ahn, mmm | tipo, pronto, portanto | quer dizer | nova linha / novo parágrafo / apaga isso | um, uma, o, a, os, as, este, esta, meu, minha, teu, tua, seu, sua, nosso, nossa | de | — |
| da | øh, øhm, æh, hm | altså, ligesom | — | ny linje / nyt afsnit / slet det | en, et, den, det, denne, dette, min, mit, din, dit, vores, jeres, hans, hendes, deres, sin, sit | at | — |
| nl | uh, uhm, ehm, eh, hmm | dus, eigenlijk | zeg maar | nieuwe regel / nieuwe alinea / schrap dat | een, de, het, deze, dit, die, dat, mijn, jouw, je, zijn, haar, ons, onze, hun | te | — |

Question words:
- de: was, wer, wann, wo, warum, wie, welche, welcher, welches, kann, können, ist, sind, hast, hat
- fr: qui, quoi, quand, où, pourquoi, comment, quel, quelle, quels, quelles, est
- es: qué, quién, quiénes, cuándo, dónde, cómo, cuál, cuáles, puedes, puede, es
- it: che, chi, cosa, quando, dove, perché, come, quale, quali, puoi, è
- pt: que, quem, quando, onde, porque, porquê, como, qual, quais, pode, é
- da: hvad, hvem, hvornår, hvor, hvorfor, hvordan, hvilken, hvilket, hvilke, kan, er
- nl: wat, wie, wanneer, waar, waarom, hoe, welke, welk, kan, is, zijn

Number words:
- de: null, eins, zwei, drei, vier, fünf, sechs, sieben, acht, neun, zehn, elf, zwölf, fünfzehn, zwanzig, dreißig, vierzig, fünfzig, hundert, tausend, halb, viertel
- fr: zéro, un, une, deux, trois, quatre, cinq, six, sept, huit, neuf, dix, onze, douze, quinze, vingt, trente, quarante, cinquante, cent, mille, demi, quart
- es: cero, uno, una, dos, tres, cuatro, cinco, seis, siete, ocho, nueve, diez, once, doce, quince, veinte, treinta, cuarenta, cincuenta, cien, mil, media, cuarto
- it: zero, uno, una, due, tre, quattro, cinque, sei, sette, otto, nove, dieci, undici, dodici, quindici, venti, trenta, quaranta, cinquanta, cento, mille, mezza, quarto
- pt: zero, um, uma, dois, duas, três, quatro, cinco, seis, sete, oito, nove, dez, onze, doze, quinze, vinte, trinta, quarenta, cinquenta, cem, mil, meia, quarto
- da: nul, en, et, to, tre, fire, fem, seks, syv, otte, ni, ti, elleve, tolv, femten, tyve, tredive, fyrre, halvtreds, hundrede, tusind, halv, kvart
- nl: nul, een, één, twee, drie, vier, vijf, zes, zeven, acht, negen, tien, elf, twaalf, vijftien, twintig, dertig, veertig, vijftig, honderd, duizend, half, kwart

Filler sounds avoid common words of the other group-A languages (Spanish "em" = Portuguese
"in" and Portuguese "é" = "is" are excluded). `merged` is only used when the transcript's
language is unknown, so a rare clash (English "hum" vs French/Portuguese "hum") can only
affect that case.

### 4.1 Consumers

- `RuleCleaner.clean(_:rules:)`, `CleanupGuard.check(original:cleaned:level:rules:)`,
  `VoiceCommands.apply(_:rules:)` take rules; their defaults are
  `LanguageRules.merged([.english, .swedish])` (today's behaviour).
- `CleanupPipeline.clean(_:context:)` picks rules from `context.language`
  (`DictationContext` gains `language: Language?` and `enabledLanguages: [Language]`),
  falling back to `merged(context.enabledLanguages)`.
- `DictationController` sets `context.language` from the transcript before cleanup.
- `FoundationModelsRewriter` instructions name the language when known ("The text is in
  Deutsch.") and list that language's filler sounds and soft fillers as examples; the
  self-correction example stays English/Swedish.

## 5. Speech

- `AppleModule.make`: SpeechTranscriber for en/de/fr/es/it/pt, DictationTranscriber for
  sv/da/nl.
- `AppleTranscriber` takes `languages: () -> [Language]`: `prepare()` installs assets for
  ticked languages only, `isReady` means all ticked are installed, and `.automatic`
  starts one session per ticked language.
- `ParakeetTranscriber`/`ParakeetSession` take `languages: () -> [Language]` and constrain
  `LanguageGuess` to them (NLLanguage codes en, sv, de, fr, es, it, pt, da, nl).
- `HybridTranscriber` is unchanged (the router passes the Apple languages).

## 6. Settings UI and app

- **Languages tab:** "My languages" — a checkbox per language (flag + native name); the
  last ticked one is disabled, and unticked ones are disabled while five are ticked. Then the existing mode picker; Toggle's "Current language"
  and Per-language hotkeys' "fn" / "fn+⇧" pickers list ticked languages only.
- **Speech tab:** in Per language mode, one engine picker per ticked language.
- **Menu:** "Switch to <next>" uses `next(in:)`; hidden when one language is ticked or
  switching changes nothing (`languageChoiceMatters`).
- **Cleanup tab:** the voice-command hint lists the commands of the ticked languages.
- **HUD:** badge per language; language flash unchanged.

## 7. Stats

- `DictationStats` replaces `swedishShare`/`englishShare` with `shares: [Language: Double]`.
- `StatsFormatter.languagePercents` returns `[(Language, Int)]`, largest first, summing to
  100 (largest-remainder rounding), or `[]` when no language is known.
- History's bar has one segment per language, coloured along the highlight gradient.

## 8. Error handling

- Unticking the last language or ticking a sixth is impossible (checkboxes disabled with a note
  "Up to 5 languages — Apple's limit"; the setter ignores empty or > 5).
- Unticked languages' Apple reservations are released when the ticked set changes.
- A stored primary/secondary/toggle language that isn't ticked reads as the first ticked.
- Unknown stored language raw values are dropped when reading `languages`.
- Asset download failure for one language never blocks others (existing per-language
  `prepare`).

## 9. Testing

- `LanguageRules`: every language has at least one filler sound and all three commands;
  no filler sound of one language is a question/number/determiner word or soft filler of
  another; English/Swedish rules equal today's lists.
- `RuleCleaner`/`VoiceCommands`/`CleanupGuard` per language (one case each for de, fr,
  es, it, pt, da, nl), and the cross-language case: Spanish rules don't remove "este"
  from Portuguese text; Portuguese text keeps "em".
- Settings: default ticked set, persistence, empty set refused, engine keys carry over,
  fallbacks for unticked primary/secondary/toggle.
- `next(in:)` cycling; `LanguageRouter` with secondary; `CommandMapper` toggle with three
  ticked; `EngineRouter` with a ticked subset.
- `DictationStats` shares and percents summing to 100 for three languages.
- Real audio (Apple): one sentence per new language with its voice, fixed language.
- Real audio (Parakeet): one sentence per new language; `LanguageGuess` returns it.
- Real audio auto-detect (Apple, five ticked at a time): {en, sv, de, fr, es}, {en, sv, it, pt,
  da} and {en, sv, nl} — each new language's sentence detected correctly (at most one miss in
  total). Real-audio tests run serialized and release the locales they reserved.
- Manual (user): tick Deutsch (or another), dictate, check text, History language, badge.

## 10. Out of scope

- Group B/C languages; per-language Dictionary; translating between languages.
