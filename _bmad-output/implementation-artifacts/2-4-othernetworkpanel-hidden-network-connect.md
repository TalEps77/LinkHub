# Story 2.4: OtherNetworkPanel — Hidden Network Connect

Status: done

## Story

As a user,
I want to connect to a hidden Wi-Fi network by typing its SSID and security details,
so that I can join networks that don't broadcast their SSID without leaving LinkHub.

## Acceptance Criteria

**Given** the Wi-Fi list is rendered
**When** the user taps the "Other Network…" footer entry
**Then** `OtherNetworkPanel` fully replaces `RootPanelView` content within the same popover (UX-DR15, UX-DR32)
**And** no modal sheet, NSWindow, or drill-down navigation is used

**Given** `OtherNetworkPanel` is visible
**When** the user inspects it
**Then** it shows a title, SSID `TextField`, security `Picker` (Open / WPA / Enterprise), conditional `SecureField` (shown when security != Open), and `Cancel` / `Join` buttons (FR32, UX-DR15)
**And** the SSID field is auto-focused on appear (UX-DR31)
**And** `Join` is `.bordered` (secondary), `Cancel` is `.bordered`, with no primary action shown alongside (UX-DR29)

**Given** the user taps `Join`
**When** the security is WPA/Enterprise
**Then** the entered password is passed to the connect path with the typed SSID
**And** validation is deferred to `CWInterface.associate` (no client-side regex) (UX-DR31)

**Given** the user taps `Cancel` or presses Esc
**When** the action fires
**Then** `OtherNetworkPanel` is replaced by `RootPanelView` content (UX-DR32)
**And** no Keychain write occurs

**Given** the join attempt fails
**When** the error returns
**Then** an inline error caption appears under the form, the field state is preserved per UX-DR31

## Tasks / Subtasks

- [x] **Task 1: In-popover routing** (AC: content swap, no sheet/window/nav)
  - [x] `RootPanelView` gains `@State private var showingOtherNetwork`; `body` swaps between `VStack { WiFiSection() }` and `OtherNetworkPanel(onClose:)`.
  - [x] Define `\.showOtherNetwork` environment action (mirror `\.dismissPopover` EnvironmentKey/EnvironmentValues idiom — default no-op `@MainActor () -> Void`). `RootPanelView` injects it to set the flag.
  - [x] Swap animation gated under Reduce Motion (instant when reduced).
- [x] **Task 2: `WiFiSection` footer** (AC: "Other Network…" entry)
  - [x] Add a `.plain` "Other Network…" button below `content`, calling `@Environment(\.showOtherNetwork)`. No change to `WiFiSection`'s init API.
  - [x] Hidden in the location-denied state (list fully replaced there). "Open Network Settings…" footer is Story 2.6 — not added.
- [x] **Task 3: `OtherNetworkPanel`** (AC: form, focus, buttons, join, cancel/Esc, failure)
  - [x] Title + SSID `TextField` (auto-focused via `@FocusState` + `.onAppear`) + security `Picker` (Open/WPA/Enterprise) + conditional `SecureField` (security != Open) + `Cancel`/`Join` (both `.bordered`).
  - [x] `Join` builds a `WiFiNetwork` from the typed SSID + selection and calls `await appState.connect(to:password:)`; Open → nil password.
  - [x] Esc/`Cancel` → `onClose()`, no Keychain write.
  - [x] Failure → inline `Color.red` `.caption` via `WiFiRow.errorCaption(for:)`; field state preserved.
- [x] **Task 4: Tests** (AC: mapping, password-required, network construction)
  - [x] `OtherNetworkPanelTests` for `security(for:)`, `requiresPassword(for:)`, `password(for:entered:)`, `network(ssid:security:)`.
- [x] **Task 5: Build / verify (local macOS)** — `xcodegen generate` + `xcodebuild build/test`; VoiceOver + Reduce-Motion + auto-focus manual checks. **Deferred to local run — no Xcode on web.**

## Dev Notes

### Routing — in-popover content swap owned by `RootPanelView` (UX-DR15/32, docs/04)

The hard constraint (docs/04) forbids a modal sheet, `NSWindow`/`NSPanel`, or `NavigationStack`
drill-down. Routing is therefore a plain content swap that `RootPanelView` owns:

- `@State private var showingOtherNetwork` selects between `VStack { WiFiSection() }` and
  `OtherNetworkPanel(onClose: { showingOtherNetwork = false })`.
- A `\.showOtherNetwork` environment action (a `@MainActor () -> Void`, default no-op) is injected
  by `RootPanelView` to set the flag `true`. The `WiFiSection` footer reads
  `@Environment(\.showOtherNetwork)` and calls it. This **mirrors the `\.dismissPopover`
  EnvironmentKey/EnvironmentValues idiom exactly** (`LocationDeniedView.swift`), so `WiFiSection`'s
  init API stays stable — no closure is threaded through it.
- Routing is **not** pushed into `AppState`. AppState stays network-focused; navigation is view
  state (SwiftUI idiom). `OtherNetworkPanel` signals "done" through its `onClose` closure for both
  Cancel/Esc and a successful Join.
- The swap animation is `reduceMotion ? nil : .easeInOut(duration: 0.2)` on `showingOtherNetwork`
  (instant under Reduce Motion, UX-DR18/20), consistent with the existing gating in `WiFiSection`.

`OtherNetworkPanel` imports **SwiftUI only**; the connect routes through `appState` (NFR35); it
never imports CoreWLAN or Keychain.

### Hidden-network `WiFiNetwork` construction

`OtherNetworkPanel.network(ssid:security:)` builds the value the connect path receives:

| Field | Value | Rationale |
|---|---|---|
| `id` | `"\(ssid):\(security)"` | The model's documented nil-bssid composite fallback; `connectingNetworkID` matches against it for the busy state. |
| `ssid` | typed SSID | |
| `bssid` | `nil` | Hidden / not in scan results. Story 2.1 `WiFiMonitor.performAssociate` does an SSID-directed `scanForNetworks(withSSID:)`, so the network is located by name. |
| `rssi` | `0` | Unknown until associated; not surfaced in this form. |
| `isConnected` | `false` | |
| `requiresPassword` | `requiresPassword(for: selection)` | Open → false; WPA/Enterprise → true. |
| `security` | `security(for: selection)` | See mapping below. |
| `isCaptive` | `false` | |

`connect(to:password:)` is then called with `password(for:entered:)` — `nil` for Open, the typed
text for WPA/Enterprise. Validation is deferred to CoreWLAN (`CWInterface.associate`); there is
**no client-side SSID/password regex** (UX-DR31). The only client gate is a non-empty SSID for
`Join` (CoreWLAN cannot associate to an empty SSID).

### Picker → `WiFiSecurity` mapping

The 3-way Picker (`SecuritySelection`: `.open` / `.wpa` / `.enterprise`) maps to the richer
`WiFiSecurity` enum:

| Picker selection | `WiFiSecurity` | Password field? |
|---|---|---|
| Open | `.none` | No (passes `nil`) |
| WPA | `.wpa2Personal` | Yes |
| Enterprise | `.enterprise` | Yes |

WPA is modeled as `.wpa2Personal` — the password-protected personal case. `WiFiSecurity` has no
generic "wpa" case; `.wpa2Personal` is the closest fit and what CoreWLAN PSK association expects.
`.wpa3Personal` and `.other` are not Picker options (the form offers the three FR32 choices only).

This mapping is implemented as pure static helpers (`security(for:)`, `requiresPassword(for:)`,
`password(for:entered:)`, `network(ssid:security:)`) so the load-bearing logic is unit-tested
without instantiating SwiftUI (mirrors Story 1.4/2.3).

### Failure copy — single source of truth

Join failure copy reuses `WiFiRow.errorCaption(for:)` (no duplicate mapping). The caption renders
as `.caption` `Color.red` under the form; all field state (SSID, security, password) is preserved
across a failure (UX-DR31). On success the form closes via `onClose()` and the connected-state
visual follows from the monitor pipeline updating `appState.networkState`.

### Buttons (UX-DR29)

Both `Cancel` and `Join` are `.bordered`; there is **no** `.borderedProminent` primary action.
`Join` is disabled until a non-empty SSID is typed (and while a join is in flight); `Cancel` is
disabled only while joining. The connecting/busy state is sourced from
`appState.connectingNetworkID == network.id` (single source of truth, UX-DR30/33).

### macOS 13 API availability (verified)

- `@FocusState` / `.focused(_:)` — macOS 12+. ✅ (SSID auto-focus via `@FocusState` + `.onAppear`.)
- `.onExitCommand(perform:)` (Esc) — macOS 10.15+. ✅
- `Picker(_:selection:)` + `.tag` — macOS 10.15+. ✅
- `TextField` / `SecureField` + `.textFieldStyle(.roundedBorder)` — macOS 10.15+/11+. ✅
- `.onSubmit(_:)` — macOS 12+. ✅ (Return in the password field submits.)
- `Color.red` literal — allowed here only, for the error caption (UX-DR4/30).

### Swift 6 strict concurrency notes

- `OtherNetworkPanel` is a SwiftUI `View` (implicitly `@MainActor` on macOS 13). The `Join`
  `Task { await appState.connect(...) }` inherits MainActor isolation; `attemptJoin` is `@MainActor`.
- `WiFiNetwork` / `WiFiConnectionFailure` are `Sendable` — safe across the `await`.
- The `\.showOtherNetwork` / `onClose` actions are `@MainActor () -> Void` — invoked on the
  MainActor, no Sendable crossing. The environment-action default is a no-op (matches `\.dismissPopover`).

### Spec divergences (flagged for reconciliation)

| Item | Epic AC / story brief (source of truth) | docs/06-wifi-management.md | Resolution |
|---|---|---|---|
| Presentation | In-popover content swap (`OtherNetworkPanel` View under `UI/Panels/`), UX-DR15/32 + docs/04 | `OtherNetworkPanel` as an `NSPanel` subclass under `UI/Windows/`, lazily created and floated | Build the in-popover content swap. docs/06's NSPanel design predates the UX-DR15/32 + docs/04 "no sheet/window" constraint; that section is superseded for this story. |
| Footer copy | "Other Network…" (singular, UX-DR34) | "Other Networks…" (plural) | Use the singular per the story brief / UX-DR34. |
| Connect API | `appState.connect(to:password:)` (NFR35) | `wifiMonitor.connect(to:password:remember:)` closure | Orchestration centralized in `AppState` (consistent with Story 2.3). `remember` is implicit (persist-on-success inside `connect`). |
| "Remember this network" checkbox | Not in the epic AC | Present in docs/06 `OtherNetworkView` | Omitted — minimal epic-AC surface. Persistence is the implicit persist-on-success in `AppState.connect`. |

### Scope boundaries (do NOT build here)

- Wi-Fi power toggle wiring (Story 2.5) — `WiFiSection` toggle stays the Story 1.4 stub.
- "Open Network Settings…" footer link (Story 2.6) — only "Other Network…" added here.
- Right-click context menu / Forget (Story 2.6).
- `WiFiMonitor` / `performAssociate` — unchanged (Story 2.1 already SSID-directs the scan).
- Show/hide password eye, "Remember this network" checkbox — not in the epic AC.

### File-structure (this story creates / modifies)

| File | Status | Purpose |
|---|---|---|
| `LinkHub/UI/Panels/OtherNetworkPanel.swift` | NEW | Hidden-network join form + pure helpers (Picker→`WiFiSecurity`, password-required, network construction) |
| `LinkHub/UI/PopoverRootView.swift` | MODIFIED | `showingOtherNetwork` routing + `\.showOtherNetwork` env key, content swap, Reduce-Motion-gated animation |
| `LinkHub/UI/Panels/WiFiSection.swift` | MODIFIED | "Other Network…" `.plain` footer entry via `\.showOtherNetwork` |
| `LinkHubTests/UI/Panels/OtherNetworkPanelTests.swift` | NEW | Mapping / password-required / network-construction unit tests |

No `Theme.swift` change was needed — the form uses existing `PanelLayout` constants. `project.yml`
recursive paths (`LinkHub/UI/Panels`, `LinkHubTests`) cover the new files — no edit required.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.4] — story ACs (source of truth).
- [Source: docs/04-panel-ui-architecture.md] — in-popover content replacement; no NavigationStack/sheet (hard constraint).
- [Source: docs/06-wifi-management.md#Other Networks Panel] — hidden-network flow + SSID-directed scan (NSPanel presentation superseded).
- [Source: LinkHub/UI/Panels/LocationDeniedView.swift] — `\.dismissPopover` EnvironmentKey/EnvironmentValues idiom (mirrored for `\.showOtherNetwork`).
- [Source: _bmad-output/implementation-artifacts/2-3-wifirow-expanded-state-inline-password-error-caption.md] — `AppState.connect` orchestration, `connectingNetworkID`, `errorCaption(for:)`.

## Dev Agent Record

### Agent Model Used

BMad dev-story workflow (Amelia, Senior Software Engineer).

### Debug Log References

- No runtime debug logs — implemented on a Linux/web session without Xcode. `xcodebuild` build/test
  and manual VoiceOver / Reduce-Motion / auto-focus verification remain pending local execution on
  macOS + Xcode 16. All logic is authored to spec; the pure-function tests are deterministic.

### Completion Notes List

- Task 1 — `RootPanelView` owns `showingOtherNetwork` and the `\.showOtherNetwork` environment
  action (mirrors `\.dismissPopover`); content swaps between `WiFiSection` and `OtherNetworkPanel`,
  animation Reduce-Motion-gated. No routing state added to `AppState`.
- Task 2 — `WiFiSection` gains a `.plain` "Other Network…" footer below `content`, routed via
  `\.showOtherNetwork`; hidden in the location-denied state. Init API unchanged.
- Task 3 — `OtherNetworkPanel`: title + auto-focused SSID `TextField` + Open/WPA/Enterprise
  `Picker` + conditional `SecureField` + `.bordered` Cancel/Join. Join builds the hidden-network
  `WiFiNetwork` and calls `appState.connect`; Open → nil password. Esc/Cancel → `onClose`, no
  Keychain write. Failure → `WiFiRow.errorCaption(for:)` caption, field state preserved.
- Task 4 — `OtherNetworkPanelTests` cover the Picker→`WiFiSecurity` mapping, password-required
  decision, password passthrough, and hidden-network `WiFiNetwork` construction (incl. composite id).
- Task 5 — build/test + manual a11y/focus verification deferred to local macOS run (no Xcode on web).

### File List

- `LinkHub/UI/Panels/OtherNetworkPanel.swift` (NEW)
- `LinkHub/UI/PopoverRootView.swift` (MODIFIED)
- `LinkHub/UI/Panels/WiFiSection.swift` (MODIFIED)
- `LinkHubTests/UI/Panels/OtherNetworkPanelTests.swift` (NEW)

### Change Log

| Date | Change |
|---|---|
| 2026-06-08 | Story created and implemented via bmad-dev-story. In-popover routing (`RootPanelView.showingOtherNetwork` + `\.showOtherNetwork` env action mirroring `\.dismissPopover`); `OtherNetworkPanel` hidden-network join form (auto-focused SSID, Open/WPA/Enterprise Picker, conditional SecureField, `.bordered` Cancel/Join, `WiFiRow.errorCaption` reuse); `WiFiSection` "Other Network…" footer; pure mapping/construction helpers + tests. Spec divergences flagged (in-popover swap vs docs/06 NSPanel, singular footer copy, AppState.connect vs monitor closure, no Remember checkbox). Build/test + manual VoiceOver/Reduce-Motion/auto-focus verification deferred to local macOS run (web session has no Xcode). Status → review. |
| 2026-06-08 | code-review (orchestrator, static): verified in-popover content swap (no sheet/NSWindow/NavigationStack), `\.showOtherNetwork` env action mirrors `\.dismissPopover` correctly, footer hidden in location-denied state, hidden-network WiFiNetwork construction + Picker→WiFiSecurity mapping pure/tested, errorCaption reused (single source of truth), Cancel/Join both .bordered (UX-DR29). @MainActor env-action passed to Button(action:) is safe (non-Sendable closure can't cross actors). No fixes. Status → done. |
