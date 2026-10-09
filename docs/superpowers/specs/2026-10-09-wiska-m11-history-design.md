# Wiska M11 — Richer History: filters, stats over time, raw vs cleaned

## Goal

Find a past dictation quickly, see what cleanup changed, and see how much you dictate over time — all from data History already keeps.

Decided with the user: **filters**, **stats over time**, **raw vs cleaned** (no export); layout **A**: two tabs in the History window.

## 1. Window layout

The History window gets a segmented control at the top: **Dictations** | **Stats**. The old stats header above the list is removed (the Stats tab replaces it). The menu bar's "This week: …" line is unchanged. Minimum window size stays 520 × 420.

## 2. Dictations tab

**Filters** — four toolbar menus next to the search field, combined with each other and with the search text:

- **App:** "All apps", then each app present in history (icon + name; bundle ID when the app is no longer installed), most entries first.
- **Language:** "All languages", then each language present in history (flag + name). Entries without a language match only "All".
- **Period:** Today / 7 days / 30 days / All (default All). "Today" = since the start of the current calendar day; "7 days"/"30 days" = since the start of the day 6 / 29 days ago.
- **Pasted:** All / Not pasted only.

A "Clear filters" button shows while any filter differs from its default. With everything filtered out, the list shows "No matches".

`HistoryFilter` (History module): `query: String`, `app: String?`, `language: Language?`, `period: HistoryPeriod`, `notPastedOnly: Bool`; `isDefault`; `matches(_ record: DictationRecord, now: Date, calendar: Calendar) -> Bool`. The query matches final or raw text, case-insensitively (as today). `HistoryPeriod`: `today`, `week`, `month`, `all` with `start(now:calendar:) -> Date?`.

**Raw vs cleaned** — clicking a row expands it (one row at a time) and shows:

- **Heard:** the raw transcript; words cleanup removed are red with strikethrough.
- **Pasted:** the final text; words cleanup added or changed are tinted with the highlight colour.
- Identical texts → "No changes by cleanup".

`WordDiff` (History module): `static func diff(raw: String, final: String) -> (heard: [DiffToken], pasted: [DiffToken])` where `DiffToken { text: String; changed: Bool }`. Words are split on whitespace; matching ignores case and surrounding punctuation ("um," = "um", "Tuesday." = "tuesday"); the longest common subsequence decides what is unchanged. Tokens keep their original text.

Copy and Delete stay on each row; **Clear All** still deletes everything regardless of filters.

## 3. Stats tab

- **Period picker:** 7 days / 30 days / All (default 7 days). If the History retention keeps fewer days than the period, a caption says "History keeps \<N\> days — change this in Settings → History" (N from the retention setting: 1, 7, 30).
- **Tiles:** Words · Time saved · Dictations · Average words per dictation.
- **Words over time:** Swift Charts bar chart, one bar per day (days without dictation are 0); for "All" spanning more than 60 days, one bar per week (weeks start on the calendar's first weekday). Bars use the highlight gradient.
- **Top apps:** horizontal bars for the 5 apps with the most words (icon, name, word count); the rest summed as "Other"; entries without an app count as "Unknown app".
- **Languages:** the existing split bar with percentages (`StatsFormatter.languagePercents`).
- Empty period → "No dictations in this period".

`HistoryReport` (History module): `static func compute(_ records: [DictationRecord], period: HistoryPeriod, now: Date, calendar: Calendar) -> HistoryReport` with `words`, `timeSaved`, `dictations`, `averageWords`, `buckets: [(start: Date, words: Int)]`, `bucketIsWeek: Bool`, `topApps: [(app: String?, words: Int)]` (≤ 5, then an "Other" entry with `app == nil` and a flag), `shares: [Language: Double]`. Only **pasted** dictations count (as the weekly stats do). Time saved uses the existing formula (`DictationStats.typingWordsPerMinute`). For `.all`, the buckets start at the first record's day.

`HistoryPeriod.today` is not offered in the Stats picker.

## 4. Data and performance

No new storage. `HistoryStore.records() -> [HistoryItem]` returns everything newest first; the view filters with `HistoryFilter` and computes the report from the same fetch, re-run when `revision` changes. Linear passes; the diff runs only for the expanded row.

## 5. Testing

Unit (Swift Testing):

- `HistoryFilter`: each criterion alone; combinations; query on raw text; period boundaries at midnight (23:59 yesterday excluded from Today, 00:00 today included); "not pasted"; `isDefault`.
- `WordDiff`: identical; filler removed (`um` changed in heard); punctuation/capitalisation-only change counts as unchanged; reworded sentence; empty raw or final.
- `HistoryReport`: totals and average; empty days as 0; weekly buckets beyond 60 days; top 5 + Other; Unknown app; not-pasted excluded; period cut-off; empty input.
- `HistoryStore.records()`: returns stored records newest first (in-memory store).

## Out of scope

Export; editing entries; charts per language over time; syncing.
