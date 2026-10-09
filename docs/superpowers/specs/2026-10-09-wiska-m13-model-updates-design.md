# Wiska M13 — Parakeet model update checks

## Goal

Know when a newer Parakeet model is published, without Wiska ever downloading on its own: check automatically every few days (or on demand), and offer a Download button when an update exists.

Decided with the user: automatic checks every X days (configurable) plus "Check now"; when an update is found, enable a download. Approach **A**: compare the Hugging Face repo revision (sha).

## 1. What counts as an update

- FluidAudio downloads Parakeet v3 from the `main` branch of `FluidInference/parakeet-tdt-0.6b-v3-coreml`.
- `GET https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml` returns `sha` and `lastModified` (ISO 8601 with fractional seconds).
- After a successful download, the store writes the revision sha into the completion marker (`.securewispr-complete`, today empty). `installedRevision` reads it (nil when empty).
- Rule `ModelUpdateChecker.isUpdate(installed: String?, installedAt: Date?, latest: ModelRevision) -> Bool`:
  - installed sha known → update when it differs from `latest.sha`;
  - unknown (installs from before M13) → update only when `latest.lastModified` is after `installedAt` (the marker file's modification date); when not an update, the latest sha is written into the marker so later checks compare shas.
- A newer model generation (v4) needs a newer FluidAudio and therefore a Wiska release — out of scope.

## 2. Behaviour

- **Settings → Speech → Parakeet card** (only when the model is installed): a status line — "Up to date · checked <relative date>", "Checking…", "Update available", or "Couldn't check: <message>"; a **Check now** button; and **Download update** when an update is available.
- **"Check for model updates"** picker on the same card: Never / Every day / Every 7 days (default) / Every 30 days (`modelUpdateInterval`, days; 0 = never).
- **Automatic checks:** at launch and every hour while Wiska runs, `checkIfDue(now:)` checks when Parakeet is installed, the interval isn't Never, and `lastModelUpdateCheck` is nil or older than the interval. A failed automatic check does not update `lastModelUpdateCheck` (so it's retried next hour) and stays silent.
- **Update found by an automatic check:** the menu bar menu shows "Speech model update available…" (opens Settings), and the notch shows "Speech model update available" once per newly found revision.
- **Download update:** removes the old model and downloads the new one in the same folder (FluidAudio writes to a fixed folder). Meanwhile Parakeet is unavailable and dictation uses Apple, as today when Parakeet isn't ready; afterwards Parakeet is reloaded (`parakeetModelBecameReady`). A failed download leaves the card in today's "Download" state.
- Wiska never downloads automatically.

## 3. Components

- `ModelRevision { sha: String; lastModified: Date }` and protocol `ModelRevisionSource { func latestRevision() async throws -> ModelRevision }` (Parakeet module).
- `HuggingFaceRevisionSource(repo: String = Repo.parakeetV3.rawValue, session: URLSession = .shared)`: 15 s timeout; non-2xx → error; decodes `sha` and `lastModified`. Static `decode(_ data: Data) throws -> ModelRevision` for tests.
- `ParakeetModelStore`: `download(revision: String? = nil)` writes the revision into the marker; `installedRevision: String?`; `installedAt: Date?` (marker modification date); `recordRevision(_:)` writes a sha into the marker of an installed model.
- `ModelUpdateChecker` (`@MainActor @Observable`): init(store, source, interval: () -> Int, lastCheck: () -> Date?, setLastCheck: (Date) -> Void); `state: idle | checking | upToDate(Date) | updateAvailable(ModelRevision) | failed(String)`; `checkNow() async`; `checkIfDue(now: Date) async -> Bool` (true when it found a new update); `downloadUpdate()`.
- `SettingsStore`: `modelUpdateInterval: Int` (key `"modelUpdateInterval"`, default 7), `lastModelUpdateCheck: Date?` (key `"lastModelUpdateCheck"`); `modelUpdateIntervals = [0, 1, 7, 30]`.
- README: the privacy line mentions the optional update check.

## 4. Testing

- `isUpdate`: same sha; different sha; unknown sha with repo older / newer than the install.
- `HuggingFaceRevisionSource.decode`: real response shape (fractional seconds); missing field → error.
- `checkIfDue`: Never; not installed; checked recently; due → checks; failure doesn't move the last-check date; returns true only for a newly found update.
- `checkNow` states: upToDate on same sha, updateAvailable on new sha, failed on error; legacy install records the sha when up to date.
- `ParakeetModelStore` writes and reads the revision (fake downloader).
- Settings round-trip and defaults.
- No test touches the network.

## Out of scope

Automatic downloads; model generations beyond v3; Apple speech assets (macOS manages those).
