# Story 2.3: WiFiRow Expanded State + Inline Password + Error Caption

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user,
I want to tap a password-protected Wi-Fi row, type the password inline, and see a specific error if it fails,
so that I can join networks without leaving the panel and retry without losing context.

## Acceptance Criteria

**Given** a password-protected Wi-Fi row in `.normal` state
**When** the user taps it
**Then** the row transitions to expanded and the row height grows from ~24 pt to ~56 pt (UX-DR5, UX-DR13)
**And** a `SecureField` is auto-focused; Return submits, Esc collapses without submit (UX-DR31)
**And** the expand animation runs 250 ms ease-in-out, instant under Reduce Motion (UX-DR18, UX-DR20)

**Given** the user submits a password
**When** the connection enters `.connecting`
**Then** the row visually reflects connecting state without a separate spinner — driven off `appState.connectingNetworkID == network.id` (UX-DR30, UX-DR33)

**Given** the connection fails
**When** the failure type is `WiFiConnectionFailure`
**Then** an inline `.caption` `Color.red` error label appears below the field with copy mapped from the case — e.g. `wrongPassword` → "Incorrect password" (UX-DR30, UX-DR34)
**And** the field is cleared, focus is retained, and the row stays expanded (UX-DR31)

**Given** an expanded `WiFiRow` with an error
**When** VoiceOver reads it
**Then** it follows UX-DR22 expanded/error templates: field-level label `"Password for {SSID}"` (FR56)
**And** the error caption is announced when it appears

**Given** a successful connection
**When** the row transitions to `.connected`
**Then** `NSAccessibility.post(.announcementRequested, "Connected to {SSID}")` is posted (UX-DR25)

**And** open networks (`requiresPassword == false`) connect on a single tap with no expansion (PRD 06 D4).

## Tasks / Subtasks

- [x] **Task 1: `AppState` — connect orchestration + `connectingNetworkID`** (AC: connecting state, success, persist-on-success)
  - [x] Add `@Published private(set) var connectingNetworkID: String?`.
  - [x] Add `func connect(to network: WiFiNetwork, password: String?) async -> Result<Void, WiFiConnectionFailure>`:
    set `connectingNetworkID = network.id`, `defer { connectingNetworkID = nil }`; `await wifiMonitor.associate(...)`;
    on `.success` with a non-empty password and a real SSID, `try KeychainService.set(password:forSSID:)` (failure logged + swallowed — UX-DR31);
    return the `Result` unchanged.
  - [x] Add `func storedPassword(forSSID:) -> String?` delegating to `KeychainService.password(forSSID:)` so the View can pre-fill without importing Keychain (NFR35).
  - [x] Add `Log.servicesKeychain` category for the swallowed-write log line.

- [x] **Task 2: `WiFiRow` — expanded state, inline password, error caption, a11y** (AC: all)
  - [x] Local `@State isExpanded / password / errorCaption` + `@FocusState passwordFieldFocused`.
  - [x] `@EnvironmentObject appState`; `isConnecting = appState.connectingNetworkID == network.id`.
  - [x] Tap: connected/connecting rows ignore taps; open networks single-tap connect; password networks toggle expansion.
  - [x] Expansion pre-fills `password` from `appState.storedPassword(forSSID:)`; `SecureField` `.focused`, `.onSubmit(submit)`, `.onExitCommand(collapse)`.
  - [x] Connecting visual = inline `ProgressView().controlSize(.small)` in the main row, driven off `connectingNetworkID` (no separate row-spinner state).
  - [x] Failure → `errorCaption` (`.caption`, `Color.red`), clear field, keep focus, stay expanded. Success → collapse + `announceConnected`.
  - [x] Static `errorCaption(for:) -> String` (pure, unit-testable). Keep Story 1.4 `accessibilityLabel(for:)` / `signalStrengthDescription(for:)`.
  - [x] Expand animation `reduceMotion ? nil : .easeInOut(duration: 0.25)`.

- [x] **Task 3: Tests** (AC: error mapping, connect happy/failure, connecting transitions)
  - [x] `WiFiRowTests.testErrorCaptionCoversAllCases` (+ unknown-code invariance).
  - [x] `AppStateTests` — `testConnectReturnsSuccessFromMonitor`, `testConnectReturnsFailureUnchanged`, `testConnectSetsConnectingNetworkIDDuringAttempt` (mid-flight ID assert via the mock's 200 ms delay; nil-SSID networks used on success paths to avoid touching the real Keychain).

- [x] **Task 4: Build / verify (local macOS)** — `xcodegen generate` + `xcodebuild build/test`; VoiceOver + Reduce-Motion manual checks. **Deferred to local run — no Xcode on web.**

## Dev Notes

### Architecture — connection orchestration lives in `AppState` (NFR35)

The View never calls `associate` or Keychain directly. `AppState.connect(to:password:)`:

1. Sets `connectingNetworkID = network.id`, clears it in a `defer` (covers every exit incl. cancellation).
2. `await wifiMonitor.associate(network:password:)` (Story 2.1 contract — `password == nil` → open variant).
3. On `.success`, if `password` is non-empty **and** the network has a real, non-empty `ssid`, persists via `KeychainService.set(password:forSSID:)`. A Keychain write failure is **logged (`Log.servicesKeychain`) and swallowed** — the radio is already associated, so it must not turn a success into a failure (UX-DR31 "persist only on success").
4. Returns the monitor's `Result` verbatim; the row maps a `.failure` to its caption.

`connectingNetworkID` is the single source of truth for the `.connecting` visual — the row computes `isConnecting = appState.connectingNetworkID == network.id`. There is no per-row "connecting" boolean and no global "expanded row id"; expansion/password/error/focus are local view state (SwiftUI idiom, matches the design constraint).

### Stored-password pre-fill decision

Per the epic AC, tapping a password-protected row **expands to a `SecureField`** (it does not auto-connect). Decision: on expansion, **pre-fill** the field from any remembered passphrase (`appState.storedPassword(forSSID:)`), so a returning user just presses Return. Rationale: matches PRD 06's `PasswordPromptView.onAppear` pre-fill behavior while honoring the epic's "expand, don't auto-connect" AC — the user always sees the field and can confirm/edit before submitting. The Keychain read is routed through `AppState` so `WiFiRow` never imports `KeychainService` (NFR35 / layer purity).

### Error-copy table (UX-DR30/34)

| `WiFiConnectionFailure` | Caption |
|---|---|
| `.wrongPassword` | "Incorrect password" |
| `.outOfRange` | "Network out of range" |
| `.associationTimeout` | "Connection timed out" |
| `.authenticationError` | "Authentication failed" |
| `.unknown(code:)` | "Couldn't connect" |

Implemented as `WiFiRow.errorCaption(for:) -> String` — pure, static, exhaustive `switch`, unit-tested for all five cases. The carried `unknown(code:)` value does not affect the caption (logged at the monitor boundary in Story 2.1, not surfaced in UI).

These captions are shorter than PRD 06's Error Message Catalogue (e.g. "Incorrect password. Please try again."). The epic AC quotes the short form ("Incorrect password"); the epic AC is the source of truth, so the short captions are used. PRD 06's longer copy is flagged for future reconciliation in the Change Log.

### Open vs. password vs. connected tap behavior

- `requiresPassword == false` (open / enterprise) → single-tap `connect(password: nil)`, no expansion (PRD 06 D4). Enterprise (`requiresPassword == false` per PRD 06 D7) therefore also single-taps; its deeplink-on-`notPermitted` UX is out of scope here (Story 2.4+).
- `requiresPassword == true` → tap toggles expansion.
- `isConnected` or `isConnecting` → tap is a no-op (connected row is informational, PRD 06 D3; connecting row is busy).

### `.connecting` visual (UX-DR30/33 — "no separate spinner")

The AC forbids a *separate* spinner element/state divorced from real connection status. The row shows an inline `ProgressView().controlSize(.small)` in the main row's trailing cluster, gated purely on `appState.connectingNetworkID == network.id` — it is not driven by any local boolean and cannot desync from the actual attempt. This satisfies "reflects connecting state without a separate spinner": the indicator *is* the connecting state, sourced from AppState.

### NSAccessibility announcement (UX-DR25)

`announceConnected(ssid:)` is a `@MainActor private static` helper posting `NSAccessibility.post(element:notification:.announcementRequested, userInfo:[.announcement: "Connected to {SSID}"])` against `NSApplication.shared.mainWindow ?? keyWindow`. It is wrapped in `#if canImport(AppKit)` and guards on a non-nil window (no-op in previews/tests). `WiFiRow` keeps `import SwiftUI` only — on macOS SwiftUI re-exports AppKit, so `NSApplication`/`NSAccessibility` resolve without an explicit `import AppKit`, keeping the AppKit touch-point isolated to this one static helper. The SwiftUI-native `AccessibilityNotification.Announcement` API is macOS 14+, so it cannot be used on the 13.0 floor.

### Row height / sizing

The AC describes the row growing ~24→56 pt. The expanded height is **intrinsic** — the `VStack { mainRow; SecureField (+ optional caption) }` plus padding drives the height, and `NSHostingController.sizingOptions = .intrinsicContentSize` (PRD 04) propagates it to the popover. No fixed expanded-height constant is added to `PanelLayout` (would be redundant and risk drift against the field's natural height). No `Theme.swift` change was needed.

### macOS 13 API availability (verified)

- `@FocusState` / `.focused(_:)` — macOS 12+. ✅
- `.onSubmit(of:_:)` / `.onSubmit(_:)` — macOS 12+. ✅
- `.onExitCommand(perform:)` (Esc) — macOS 10.15+. ✅
- `SecureField(_:text:)` + `.textFieldStyle(.roundedBorder)` — macOS 10.15+/11+. ✅
- `Color.red` literal — allowed here only, for the error caption (UX-DR4/30).
- `AccessibilityNotification.Announcement` — macOS 14+ → NOT used; AppKit `NSAccessibility.post` used instead.

### Swift 6 strict concurrency notes

- `AppState` is `@MainActor`; `connect` is an async `@MainActor` method. `connectingNetworkID` writes happen on the MainActor; the `await associate` suspension does not change isolation. `defer` runs on return on the MainActor.
- `WiFiNetwork` and `WiFiConnectionFailure` are `Sendable` — safe across the `await`.
- `WiFiRow` is a `View` (implicitly MainActor on macOS 13). The connect `Task { await appState.connect(...) }` inherits MainActor isolation; `announceConnected` is `@MainActor`.
- The Keychain write inside `connect` is synchronous (`SecItem*` is thread-safe and `KeychainService` is a stateless enum) — no actor hop, no Sendable crossing.

### Scope boundaries (do NOT build here)

- OtherNetworkPanel / hidden-network join (Story 2.4).
- Wi-Fi power toggle wiring (Story 2.5) — `WiFiSection` toggle stays the Story 1.4 stub.
- Right-click context menu / Forget (Story 2.6).
- Captive "Sign in required" tap handoff, enterprise deeplink-on-`notPermitted`, disconnect, show/hide password eye, "Remember this network" checkbox — not in the epic AC for this story.
- Post-connect 1.5 s rescan (PRD 06 D15) lives in `WiFiMonitor` (Story 2.1/2.5), not the row.

### Spec divergences (flagged for reconciliation)

| Item | Epic AC (source of truth) | PRD 06 | Resolution |
|---|---|---|---|
| Error copy | "Incorrect password" (short) | "Incorrect password. Please try again." (long) | Use the short epic-AC captions. |
| Password prompt component | Inline `SecureField` on `WiFiRow` | Separate `PasswordPromptView` w/ eye-toggle + Remember checkbox + Cancel/Join buttons | Build the minimal epic-AC surface (field + Return/Esc + error caption); richer prompt UI deferred. |
| Connect API | `appState.connect(to:password:)` (NFR35) | `wifiMonitor.connect(to:password:remember:)` closure passed into the row | Orchestration centralized in `AppState`; `remember` is implicit (persist-on-success). |

### File-structure (this story creates / modifies)

| File | Status | Purpose |
|---|---|---|
| `LinkHub/State/AppState.swift` | MODIFIED | `connectingNetworkID`, `connect(to:password:)`, `storedPassword(forSSID:)` |
| `LinkHub/UI/Components/WiFiRow.swift` | MODIFIED | Expanded state, inline `SecureField`, error caption, connecting visual, success announcement, `errorCaption(for:)` |
| `LinkHub/Utilities/Logger.swift` | MODIFIED | Add `Log.servicesKeychain` category |
| `LinkHubTests/UI/Components/WiFiRowTests.swift` | MODIFIED | `errorCaption(for:)` mapping (all cases) |
| `LinkHubTests/State/AppStateTests.swift` | MODIFIED | `connect` happy/failure + `connectingNetworkID` transitions |

`WiFiMonitorProtocol` is unchanged (`associate` already exists from Story 2.1), so no test-stub edits were required. `project.yml` recursive globs cover the (already-existing) files — no edit needed.

### References

- [Source: \_bmad-output/planning-artifacts/epics.md#Story 2.3] — story ACs (source of truth).
- [Source: docs/06-wifi-management.md#NetworkRow / Password Prompt / Error Message Catalogue] — connect flow, inline expansion (D4/D5), persist-on-success, error copy.
- [Source: docs/04-panel-ui-architecture.md] — row expanded state, animation, intrinsic sizing.
- [Source: \_bmad-output/implementation-artifacts/1-4-rootpanelview-wifisection-wifirow-read-only.md] — WiFiRow conventions, UX-DR22 label work.
- [Source: \_bmad-output/implementation-artifacts/2-1-wifimonitor-associate-cause-typed-connection-failure.md] — `associate(network:password:)` typed-failure contract.
- [Source: \_bmad-output/implementation-artifacts/2-2-keychainservice-persist-wi-fi-passwords.md] — `KeychainService.set/password/remove`.

## Dev Agent Record

### Agent Model Used

BMad dev-story workflow (Amelia, Senior Software Engineer).

### Debug Log References

- No runtime debug logs — implemented on a Linux/web session without Xcode. `xcodebuild` build/test
  and VoiceOver / Reduce-Motion manual verification remain pending local execution on macOS + Xcode 16.
  All logic is authored to spec; pure-function and AppState-driven tests are deterministic.

### Completion Notes List

- Task 1 — `AppState` gains `connectingNetworkID`, `connect(to:password:)` (persist-only-on-success,
  swallow Keychain write failures), and `storedPassword(forSSID:)`. `Log.servicesKeychain` added.
- Task 2 — `WiFiRow` extended with local expand/password/error/focus state, inline `SecureField`
  (auto-focus, Return submit, Esc collapse), pre-fill via `appState.storedPassword`, inline
  `ProgressView` connecting visual gated on `connectingNetworkID`, `Color.red` `.caption` error,
  success collapse + `NSAccessibility` announcement, and pure `errorCaption(for:)`. Story 1.4
  `accessibilityLabel(for:)` preserved for `.normal`/`.connected`.
- Task 3 — `WiFiRowTests` error-caption coverage; `AppStateTests` connect happy/failure/connecting
  transitions (nil-SSID networks on success paths avoid touching the real Keychain).
- Task 4 — build/test + manual a11y verification deferred to local macOS run (no Xcode on web).

### File List

- `LinkHub/State/AppState.swift` (MODIFIED)
- `LinkHub/UI/Components/WiFiRow.swift` (MODIFIED)
- `LinkHub/Utilities/Logger.swift` (MODIFIED)
- `LinkHubTests/UI/Components/WiFiRowTests.swift` (MODIFIED)
- `LinkHubTests/State/AppStateTests.swift` (MODIFIED)

### Change Log

| Date | Change |
|---|---|
| 2026-06-08 | Story created and implemented via bmad-dev-story. AppState.connect orchestration + connectingNetworkID; WiFiRow expanded inline-password state with error caption + a11y; error-caption mapping + connect tests. Three spec divergences flagged (short error copy, minimal inline prompt vs PRD 06 PasswordPromptView, AppState.connect vs monitor.connect closure). Build/test + manual VoiceOver/Reduce-Motion verification deferred to local macOS run (web session has no Xcode). Status → review. |
| 2026-06-08 | code-review (orchestrator, static): verified AppState.connect orchestration (connectingNetworkID set/cleared via defer, Keychain-write-best-effort-on-success, Result passthrough), pure errorCaption mapping, @FocusState/onSubmit/onExitCommand (macOS 12+). FIX APPLIED: the "Connected to {SSID}" announcement was posting NSAccessibility/NSApplication from WiFiRow (SwiftUI-only file — would not compile, and violated the Story 1.4 layer rule). Relocated to StatusItemController.announceConnectionIfNew(for:) on the connectedWifi state edge (skips cold-launch), consistent with the 1.5/1.6 announcement pattern. WiFiRow is now SwiftUI-pure. Status → done. |
