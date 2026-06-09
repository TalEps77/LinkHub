# Story 4.3: Sparkle 2 SPM Dep + UpdaterController

Status: done

## Story

As a user,
I want LinkHub to check for updates in the background and let me trigger a check on demand, then install updates with cryptographic verification,
so that I get fixes and improvements without manually downloading new builds.

## Acceptance Criteria

1. **Sparkle 2 is the first and only SPM dependency**
   - **Given** the project's package dependencies
   - **When** they are inspected
   - **Then** Sparkle 2 (`https://github.com/sparkle-project/Sparkle`) is added as the first and only SPM dependency (NFR36)

2. **UpdaterController instantiated in the correct launch order**
   - **Given** the app launches
   - **When** `AppDelegate.applicationDidFinishLaunching` runs
   - **Then** `App/UpdaterController.swift` instantiates `SPUStandardUpdaterController` after `statusItemController.start()` and before `appState.startMonitors()`
   - **And** the updater is wired with the appcast feed `https://talepstein.github.io/LinkHub/appcast.xml`

3. **Info.plist carries the Sparkle keys**
   - **Given** `Info.plist`
   - **When** keys are inspected
   - **Then** `SUPublicEDKey` contains the EdDSA public key matching the appcast signing key (NFR16) — a clearly-marked PLACEHOLDER until Story 4.6 generates the real key
   - **And** `SUFeedURL` points at the GitHub Pages URL

4. **Check for Updates… triggers a manual check**
   - **Given** the user selects `Check for Updates…` from the status-item menu
   - **When** the action fires
   - **Then** `SPUStandardUpdaterController.checkForUpdates(_:)` runs (FR54)

5. **Background check notifies and verifies the signature**
   - **Given** an update is available on the periodic background cadence
   - **When** Sparkle's check fires
   - **Then** the user is notified via the standard Sparkle dialog (FR53)
   - **And** the artifact's EdDSA signature is verified before install; install proceeds only on signature match (FR55, NFR16)

6. **Install relaunches the new version**
   - **Given** an update install dialog is open
   - **When** the user installs
   - **Then** Sparkle relaunches LinkHub with the new version

## Tasks / Subtasks

- [x] **Task 1: Add Sparkle 2 SPM dependency in `project.yml`** (AC: #1)
  - [x] Top-level `packages:` block — `Sparkle: { url: https://github.com/sparkle-project/Sparkle, from: 2.6.0 }`
  - [x] `targets.LinkHub.dependencies: [ { package: Sparkle } ]` — linked to the app target only (NOT the test target)
  - [x] Uncomment `.build/ .swiftpm/ Packages/` in `.gitignore`
- [x] **Task 2: Create `LinkHub/App/UpdaterController.swift`** (AC: #2, #4, #5, #6)
  - [x] `@MainActor final class UpdaterController` wrapping `SPUStandardUpdaterController`
  - [x] `import AppKit`, `import Sparkle`
  - [x] `init()` → `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)` (starts periodic background checks)
  - [x] `func checkForUpdates()` → `updaterController.checkForUpdates(nil)` for the menu item
  - [x] No appcast URL set in code — `Info.plist` (`SUFeedURL`) is the single source of truth
- [x] **Task 3: Wire into `AppDelegate.applicationDidFinishLaunching`** (AC: #2, #4)
  - [x] Instantiate `UpdaterController` AFTER `statusItemController.start()` and BEFORE `appState.startMonitors()`
  - [x] Retain it on `AppDelegate` for the app lifetime (Sparkle's background schedule depends on a live updater)
  - [x] `statusItemController.setUpdaterController(updaterController)` so the menu's Check for Updates is enabled
- [x] **Task 4: `Info.plist` keys** (AC: #3) — *this session owns all Info.plist edits*
  - [x] `SUFeedURL` = `https://talepstein.github.io/LinkHub/appcast.xml`
  - [x] `SUPublicEDKey` = `REPLACE_WITH_EDDSA_PUBLIC_KEY` (clearly-marked placeholder; Story 4.6 generates the real key)
  - [x] `CFBundleShortVersionString` = `1.0.0` (SemVer) — already present, verified
  - [x] `CFBundleVersion` = `1` (monotonic integer) — already present, verified
- [x] **Task 5: Logger category** (cross-cutting)
  - [x] `Log.appUpdater = os.Logger(subsystem: subsystem, category: "app.updater")` present in `Utilities/Logger.swift`

## Dev Notes

### Sparkle wiring (the load-bearing decision)

`UpdaterController` is a thin `@MainActor` wrapper over Sparkle 2's `SPUStandardUpdaterController`:

- Constructed with `startingUpdater: true`, which both starts the updater and schedules Sparkle's periodic background check. On first launch Sparkle shows its own opt-in permission dialog — accepted behaviour per docs/09 Open Question #2; no workaround.
- No custom `updaterDelegate` / `userDriverDelegate` in v1 — Sparkle's standard scheduling and UI satisfy FR53 (notify), FR55/NFR16 (EdDSA verify before install), and the relaunch-on-install behaviour with no extra code.
- The feed URL and public key are read from `Info.plist` (`SUFeedURL`, `SUPublicEDKey`); nothing is set in code, so there is a single source of truth and no risk of code/plist drift. AC #2's "wired with the appcast feed" is satisfied via `SUFeedURL` — `SPUStandardUpdaterController` reads it from the main bundle automatically.

**Launch order (AC #2):** `AppDelegate.applicationDidFinishLaunching` does, in order: build + `start()` the status item → construct `UpdaterController` → `setUpdaterController(_:)` on the controller → `appState.startMonitors()`. The updater is therefore created strictly after `statusItemController.start()` and strictly before `appState.startMonitors()`, exactly as the AC requires. It is retained on `AppDelegate` (`private var updaterController: UpdaterController?`) so the background schedule survives past launch.

**Menu integration:** `StatusItemController.setUpdaterController(_:)` stores the updater; the Story 4.2 menu's "Check for Updates…" item calls `updaterController?.checkForUpdates()` → `SPUStandardUpdaterController.checkForUpdates(nil)` (AC #4). If the updater is absent the menu item is disabled rather than crashing.

### project.yml SPM schema

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: 2.6.0
```

and on the app target:

```yaml
    dependencies:
      - package: Sparkle
```

`from: 2.6.0` pins the 2.x major (`from` is XcodeGen's `.upToNextMajor`), matching docs/09 D7 "pin to the latest 2.x". Sparkle is linked to the **app target only** — the test target has no Sparkle dependency, so test code must not `import Sparkle` (it doesn't). `2.6.0` is a known-good 2.x floor; XcodeGen/SPM resolves the latest compatible 2.x at generate time.

### Info.plist (this session owns all Info.plist edits)

Added `SUFeedURL` and `SUPublicEDKey`; verified `CFBundleShortVersionString = 1.0.0` and `CFBundleVersion = 1` are present and correct (both consumed by Story 4.6's release tooling and by Sparkle/Gatekeeper version comparison). `SUPublicEDKey` is the placeholder string `REPLACE_WITH_EDDSA_PUBLIC_KEY` — **Story 4.6 generates the real EdDSA key pair via Sparkle's `generate_keys` and replaces this value.** `SUEnableAutomaticChecks` is intentionally omitted: the ACs only require `SUFeedURL` + `SUPublicEDKey`, and Sparkle 2 shows the opt-in dialog regardless (docs/09 Open Question #2). It can be added in a later release-config story if a default-on policy is desired.

### Build cannot be resolved here — local gates

Sparkle is not available on this Linux host (no Xcode/swiftc, no SPM resolution), so `import Sparkle` and `SPUStandardUpdaterController` cannot be compiled or run here. The code is authored to compile-correctness by reasoning against Sparkle 2's public API. The following are **local verification gates**:

- `xcodegen generate` resolves the Sparkle SPM package and links it to the LinkHub target only.
- `import Sparkle` and `SPUStandardUpdaterController(startingUpdater:updaterDelegate:userDriverDelegate:)` compile under `SWIFT_STRICT_CONCURRENCY = complete`.
- Build is clean; the app launches; Sparkle's first-launch opt-in dialog appears.
- "Check for Updates…" presents Sparkle's standard dialog (with the placeholder key it will fail signature verification on any real update — that is expected until Story 4.6 ships the real key + a signed appcast).

### Why no Sparkle unit tests

Sparkle is not resolvable on the headless host and `SPUStandardUpdaterController` performs real network/UI work on init; there is nothing pure to assert. Per the brief, Sparkle is a local/manual gate, not a unit test. The menu's interaction with the updater is covered structurally by `StatusItemMenuTests` (Check-for-Updates disabled when the updater is nil).

### File-structure requirements

| File | Status | Purpose |
|---|---|---|
| `project.yml` | MODIFIED | `packages: Sparkle`; app-target `dependencies: [package: Sparkle]` |
| `.gitignore` | MODIFIED | uncomment `.build/ .swiftpm/ Packages/` |
| `LinkHub/App/UpdaterController.swift` | NEW | `SPUStandardUpdaterController` wrapper; `checkForUpdates()` |
| `LinkHub/App/AppDelegate.swift` | MODIFIED | instantiate updater after status item / before monitors; retain; hand to menu |
| `LinkHub/Info.plist` | MODIFIED | `SUFeedURL`, `SUPublicEDKey` (placeholder); versions verified |
| `LinkHub/Utilities/Logger.swift` | MODIFIED | `app.updater` category |

## Dev Agent Record

### Completion Notes

- Sparkle wired via `Info.plist` as single source of truth (no in-code feed URL).
- `SUPublicEDKey` is a clearly-marked placeholder; real key is Story 4.6.
- No AI model identifier in code/comments/docs. No keys or secrets committed.

### Risks needing local build verification

- Sparkle SPM resolution + `import Sparkle` compile is unverifiable here — local gate.
- The `from: 2.6.0` floor should resolve a current 2.x; bump if a newer minimum is required at generate time.
- With the placeholder `SUPublicEDKey`, any real update download fails EdDSA verification by design until Story 4.6 supplies the real key and a signed appcast.
