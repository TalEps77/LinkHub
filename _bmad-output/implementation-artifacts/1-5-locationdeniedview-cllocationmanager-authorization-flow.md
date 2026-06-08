# Story 1.5: LocationDeniedView + CLLocationManager Authorization Flow

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user,
I want LinkHub to request Location authorization on first scan and recover gracefully if I deny it,
so that I can grant access from a one-tap path to Privacy settings and resume scanning without restarting the app.

## Acceptance Criteria

1. **Location authorization is requested on first scan (no modal onboarding)**
   - **Given** the user opens the panel for the first time and Wi-Fi scanning is requested
   - **When** `WiFiMonitor.requestScan()` runs
   - **Then** `CLLocationManager.requestWhenInUseAuthorization()` is invoked (FR39)
   - **And** no modal onboarding is shown; the panel is the introduction (FR42)

2. **Denial replaces the Wi-Fi list with `LocationDeniedView`**
   - **Given** Location authorization is `.denied` or `.restricted`
   - **When** `WiFiSection` would render
   - **Then** `LocationDeniedView` replaces the Wi-Fi list (UX-DR12, UX-DR14)
   - **And** the view shows a centered VStack with `lock` SF Symbol + headline "Location access required" + body explaining Apple's macOS 10.15+ requirement + a `.borderedProminent` "Open Privacy Settings" button (UX-DR14, UX-DR29, UX-DR34)

3. **"Open Privacy Settings" dismisses the popover and deep-links to Location Services**
   - **Given** the user taps "Open Privacy Settings"
   - **When** the action fires
   - **Then** the popover dismisses and `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)` opens the Privacy/Location pane (FR40)

4. **denied→granted while running auto-retries the scan and transitions to the list**
   - **Given** Location authorization flips from denied to `.authorized` (or `.authorizedWhenInUse`) while LinkHub is running
   - **When** the `CLLocationManagerDelegate.locationManagerDidChangeAuthorization` callback fires
   - **Then** `WiFiMonitor.requestScan()` is auto-retried (FR41)
   - **And** the panel transitions to the Wi-Fi list state without app restart

5. **Grant-after-denial posts a VoiceOver announcement on next scan completion**
   - **Given** the user grants Location after denial
   - **When** the next scan completes
   - **Then** `NSAccessibility.post(.announcementRequested, "Wi-Fi networks loading")` is posted (UX-DR25)

## Tasks / Subtasks

- [x] **Task 1: Extend `WiFiMonitorProtocol` with a CoreLocation-free denial surface** (AC: #2, #4)
  - [x] Add `var isLocationDenied: Bool { get }` + `var isLocationDeniedPublisher: Published<Bool>.Publisher { get }` mirroring the existing publisher pattern. No CoreLocation type crosses the boundary — a plain `Bool` only.
  - [x] `import Foundation` + `import Combine` only (unchanged).
- [x] **Task 2: `WiFiMonitor` — own a `CLLocationManager`, drive `isLocationDenied`, request auth on first scan, auto-retry on grant** (AC: #1, #4)
  - [x] `import CoreLocation`; conform to `CLLocationManagerDelegate`; add `@Published private(set) var isLocationDenied` + publisher accessor.
  - [x] Own one `CLLocationManager` created and accessed on MainActor; set `delegate = self` in `init`; seed `isLocationDenied` from the live `authorizationStatus` at init.
  - [x] `requestScan()` calls `requestWhenInUseAuthorization()` exactly once (guarded by `didRequestAuthorization`), preserving the in-flight guard, timeout race, and sort from Story 1.3.
  - [x] `nonisolated func locationManagerDidChangeAuthorization(_:)` hops to MainActor via `Task { @MainActor [weak self] in … }`, reads the status there, equality-guards `isLocationDenied`, and on denied→granted (while started) auto-retries `requestScan()` (FR41).
  - [x] Add pure `static func isDenied(_ status: CLAuthorizationStatus) -> Bool` for unit-testable mapping (`.denied`/`.restricted` → true; everything else → false).
- [x] **Task 3: `MockWiFiMonitor` + `PopoverStubWiFiMonitor` + `StubWiFiMonitor` conform to the extended protocol** (AC: #2)
  - [x] `MockWiFiMonitor`: `@Published var isLocationDenied = false` + publisher accessor (simple, settable for tests).
  - [x] `PopoverStubWiFiMonitor` (PopoverControllerTests) and `StubWiFiMonitor` (AppStateTests): add the same two members so the test bundle compiles against the new protocol surface.
- [x] **Task 4: `AppState` sinks the denial flag into its existing `wifiLocationDenied`** (AC: #2)
  - [x] In `startMonitors()`, sink `wifiMonitor.isLocationDeniedPublisher` into `@Published var wifiLocationDenied` via `.sink { Task { @MainActor … } }`, equality-guarded, stored in `cancellables` so `stopMonitors()` severs it. No `import CoreLocation` added.
- [x] **Task 5: `LocationDeniedView` (NEW) + `WiFiSection` branch** (AC: #2, #3)
  - [x] Create `LinkHub/UI/Panels/LocationDeniedView.swift` — SwiftUI + AppKit only (no CoreLocation). Centered VStack: `lock` symbol + "Location access required" headline + body + `.borderedProminent` "Open Privacy Settings". Static `settingsURL` constant for testability. Button action: `dismissPopover()` then `NSWorkspace.shared.open(Self.settingsURL)`.
  - [x] Add `\.dismissPopover` environment action (`DismissPopoverKey`) with a no-op default; `PopoverController` injects `close()`.
  - [x] `WiFiSection`: add `enum ContentMode` + pure `static func contentMode(locationDenied:isEmpty:isScanning:isWiFiEnabled:isWiFiHardwareAvailable:)` decider; `content` switches on it. Location denial wins over all other states.
- [x] **Task 6: `PopoverController` wires `\.dismissPopover`** (AC: #3)
  - [x] Inject `.environment(\.dismissPopover)` on the hosted root view, routed to `close()` via a late-bound `DismissBox` (closure captures `self` weakly — no retain cycle).
- [x] **Task 7: `StatusItemController` posts the grant-after-denial announcement** (AC: #5)
  - [x] Observe `appState.$wifiLocationDenied`; on a true→false edge arm a pending flag; consume it on the next `networkState` emission to post `NSAccessibility.post(element: button, .announcementRequested, "Wi-Fi networks loading")`. AppKit announcement lives here, not in State/Network layers.
- [x] **Task 8: Info.plist privacy keys** (AC: #1)
  - [x] Add `NSLocationUsageDescription` (kept the pre-existing `NSLocationWhenInUseUsageDescription`). Info.plist is the tracked source of truth (`GENERATE_INFOPLIST_FILE: NO`, `INFOPLIST_FILE: LinkHub/Info.plist`) — edited directly; no `project.yml` `info:` block exists.
  - [x] Entitlement `com.apple.security.personal-information.location` already present (docs/08 D2) — no change.
- [x] **Task 9: Tests** (AC: all)
  - [x] `WiFiMonitorTests`: `isDenied` mapping (denied/restricted → true; notDetermined/authorized variants → false); initial `isLocationDenied` reflects live status; first scan requests authorization exactly once (via `#if DEBUG` `_didRequestAuthorizationForTesting` seam).
  - [x] `AppStateTests`: denial propagates `monitor.isLocationDenied → appState.wifiLocationDenied`; sink severed after `stopMonitors()`; updated `StubWiFiMonitor` for the new protocol surface.
  - [x] `WiFiSectionTests`: `contentMode` branch selection (denial wins, scanning, empty, list, disabled→list); `LocationDeniedView.settingsURL` equals the exact FR40 string.
  - [x] `PopoverControllerTests`: dismiss action no-op when not shown.

## Dev Notes

### Story foundation

This story is the **graceful-degradation** layer for Wi-Fi scanning. macOS 10.15+ gates `CWWiFiClient.scanForNetworks` behind granted Location access (docs/08 Constraints), so without it the list can never populate. Story 1.5 makes `WiFiMonitor` request `requestWhenInUseAuthorization()` lazily on first scan (no launch-time prompt, no modal onboarding — the panel is the introduction, FR42), surfaces denial through a plain `Bool` to the UI, renders `LocationDeniedView` in place of the list, and recovers without restart when the user grants access in System Settings.

**Pre-existing working-tree state:** the Network layer for this story (the `WiFiMonitorProtocol` extension, the `WiFiMonitor` CoreLocation implementation, `MockWiFiMonitor.isLocationDenied`, and the `PopoverStubWiFiMonitor` member) was already present in the working tree from an earlier partial pass. This pass completed the remaining wiring: the `AppState` denial sink, `LocationDeniedView` (NEW), the `WiFiSection` branch + decider, the `PopoverController` dismiss action, the `StatusItemController` grant-after-denial announcement, the `NSLocationUsageDescription` Info.plist key, the `StubWiFiMonitor` protocol-conformance fix, and all tests.

### Architecture-boundary rules (followed exactly)

- **CoreLocation is confined to `Network/WiFiMonitor.swift`.** It is the only file that `import CoreLocation`s in product code. `Network/Models/` stays Foundation-only; `State/AppState.swift` imports `Foundation`/`Combine` only; UI files import SwiftUI (+ AppKit where the layer already does).
- **No CoreLocation type crosses the protocol boundary.** `WiFiMonitorProtocol` exposes `isLocationDenied: Bool` + `isLocationDeniedPublisher: Published<Bool>.Publisher` only. `CLAuthorizationStatus` never leaves `WiFiMonitor`.
- **`CLLocationManager` is MainActor-owned.** Created/owned/`delegate`-set on the `@MainActor` `WiFiMonitor`. The `nonisolated locationManagerDidChangeAuthorization(_:)` callback hops to MainActor via `Task { @MainActor [weak self] in … }` (identical to the `CWEventDelegate` pattern), reads `authorizationStatus` on MainActor, equality-guards the write, and auto-retries `requestScan()` on the denied→granted edge.
- **`LocationDeniedView` imports SwiftUI + AppKit, never CoreLocation.** It reads `appState.wifiLocationDenied` (Bool) and hands off to System Settings via `NSWorkspace`. Popover dismissal goes through the injected `\.dismissPopover` environment action so the view stays decoupled from the popover machinery. AppKit in the UI layer is consistent with existing UI files (`PopoverBackground`, `PopoverController`).
- **The "Wi-Fi networks loading" announcement is posted from AppKit (`StatusItemController`).** `WiFiMonitor` stays CoreWLAN/CoreLocation/Combine only; `AppState` stays Foundation/Combine only; neither imports AppKit. `StatusItemController` already owns the status button and `NSAccessibility` plumbing and already observes `appState.$networkState`, so it observes `appState.$wifiLocationDenied` for the true→false edge and posts on the next `networkState` emission (the auto-retried scan's first result). This is the boundary-clean resolution prescribed by the story brief.

### Spec divergences

- **`lock` symbol + "Location access required" copy (epic AC) vs. `wifi.slash` + "Wi-Fi scanning requires Location access." (docs/06 Location Denial View Spec).** Followed the **epic AC** (the brief's source of truth): `lock` SF Symbol, headline "Location access required", body referencing the macOS 10.15+ requirement. docs/06's `LocationDenialView` snippet is the older sketch; recorded here as a known, intentional divergence.
- **File placement / name.** docs/06 sketches `LocationDenialView` *embedded in* `WiFiSection.swift`; the brief mandates a **separate `LocationDeniedView.swift`** file. Created the standalone file; `WiFiSection` references it via the `ContentMode` decider.
- **docs/06 calls `SystemSettingsService.openLocationPrivacySettings()`.** No such service exists in the codebase and creating one is out of scope (and would gold-plate). The URL is inlined as `LocationDeniedView.settingsURL` (static constant, unit-testable) and opened directly — exactly the FR40 string from the epic AC.
- **`NSLocationUsageDescription` added alongside `NSLocationWhenInUseUsageDescription`.** docs/08 mandates only `NSLocationWhenInUseUsageDescription` on macOS; the brief asked for both. Added both — `NSLocationUsageDescription` is harmless on macOS and satisfies the brief.

### Concurrency notes

- `DismissBox` (PopoverController) is a `@MainActor` late-binding holder so the SwiftUI environment closure can be constructed *before* `super.init()` (where `self` is unavailable) and have its target wired *after*. The stored closure is typed `@MainActor () -> Void` to match `close()`'s isolation and the `\.dismissPopover` key's value type; it captures `self` weakly, so no retain cycle is introduced.
- The `\.dismissPopover` `EnvironmentKey.defaultValue` is a `@MainActor () -> Void` no-op so previews and tests render without an `NSPopover`.
- All `@Published` writes in the new sinks are equality-guarded inside a `Task { @MainActor }` hop (Swift 6: a Combine sink delivering on `DispatchQueue.main` is not MainActor isolation).

### Build-config / `#if DEBUG` discipline

- `WiFiMonitor._didRequestAuthorizationForTesting` is `#if DEBUG`-gated (test seam for AC #1), alongside the existing `_scanOverride`.
- `MockWiFiMonitor` remains entirely `#if DEBUG`-wrapped.
- No `#if DEBUG` changes user-visible behavior.

### File-structure requirements (this story creates / modifies these files)

| File | Status | Purpose |
|---|---|---|
| `LinkHub/UI/Panels/LocationDeniedView.swift` | NEW | Denial-state view (SwiftUI+AppKit, no CoreLocation) + `\.dismissPopover` environment key |
| `LinkHub/Network/WiFiMonitorProtocol.swift` | MODIFIED | Add `isLocationDenied` + `isLocationDeniedPublisher` |
| `LinkHub/Network/WiFiMonitor.swift` | MODIFIED | `CLLocationManager` ownership, auth request on first scan, `isLocationDenied`, `isDenied(_:)`, auto-retry on grant |
| `LinkHub/Network/MockWiFiMonitor.swift` | MODIFIED | `isLocationDenied` + publisher |
| `LinkHub/State/AppState.swift` | MODIFIED | Sink `isLocationDeniedPublisher → wifiLocationDenied` in `startMonitors()` |
| `LinkHub/UI/Panels/WiFiSection.swift` | MODIFIED | `ContentMode` enum + pure `contentMode(...)` decider; branch to `LocationDeniedView` |
| `LinkHub/MenuBar/PopoverController.swift` | MODIFIED | Inject `\.dismissPopover` via `DismissBox` |
| `LinkHub/MenuBar/StatusItemController.swift` | MODIFIED | Observe `wifiLocationDenied` edge; post "Wi-Fi networks loading" on next networkState |
| `LinkHub/Info.plist` | MODIFIED | Add `NSLocationUsageDescription` |
| `LinkHubTests/Network/WiFiMonitorTests.swift` | MODIFIED | `isDenied` mapping, initial status, first-scan-requests-auth |
| `LinkHubTests/State/AppStateTests.swift` | MODIFIED | Denial propagation + sink-severed-after-stop; `StubWiFiMonitor` conformance fix |
| `LinkHubTests/UI/Panels/WiFiSectionTests.swift` | MODIFIED | `contentMode` branches + `settingsURL` |
| `LinkHubTests/MenuBar/PopoverControllerTests.swift` | MODIFIED | Dismiss action no-op |

### Testing standards

- XCTest, `@testable import LinkHub`. New assertions mirror Story 1.3/1.4 style (pure static functions tested directly; Combine sinks driven via `Task.sleep` drain or `XCTestExpectation`).
- CoreLocation status mapping (`isDenied`) is a pure `static` — tested with no live manager. The initial-status test asserts agreement with the pure mapping for whatever status the host reports (no hard-coded expectation, so it is host-independent).
- `requestScan`-requests-auth and reentrancy/timeout tests are gated with `XCTSkipIf(CWWiFiClient.shared().interface() == nil, …)` because `requestScan()` early-returns on a never-started monitor.
- The `NSAccessibility.post` announcement cannot be intercepted in unit tests (consistent with the existing `announceIfDisconnected` test, which only asserts no-crash); the grant-after-denial edge logic is straightforward state tracking verified by inspection.

### References

- [Source: \_bmad-output/planning-artifacts/epics.md#Story 1.5] — BDD acceptance criteria (source of truth)
- [Source: docs/08-permissions-entitlements.md#Location Permission UX Flow] — request timing (first scan), denial handling, deep-link URL, `requestWhenInUseAuthorization()` choice (D4), entitlement (D2)
- [Source: docs/06-wifi-management.md#Location Denial View Spec] — older `LocationDenialView` sketch (superseded by epic AC for copy/symbol/filename)
- [Source: \_bmad-output/implementation-artifacts/1-3-…md] — `WiFiMonitor` shape, nonisolated-delegate→MainActor hop pattern, `wifiLocationDenied`-is-Story-1.5 note
- [Source: \_bmad-output/implementation-artifacts/1-4-…md] — `WiFiSection` `displayedNetworks` pure-function test pattern (mirrored by `contentMode`)

## Dev Agent Record

### Debug Log References

- Cannot build/test on Linux (no Xcode/swiftc). Implementation written to compile under Swift 6 strict concurrency by reasoning; requires local `xcodegen generate` + `xcodebuild … test` verification on macOS + Xcode 16.

### Completion Notes List

- All 5 ACs implemented. CoreLocation confined to `WiFiMonitor.swift`; the protocol boundary carries only a `Bool`.
- `LocationDeniedView` (NEW) uses the epic AC's `lock` symbol + "Location access required" copy + `.borderedProminent` button; dismisses the popover via the injected `\.dismissPopover` action then opens the exact FR40 Settings URL.
- `WiFiSection` branches via a pure, unit-tested `contentMode(...)` decider; denial wins over scanning/empty/list.
- `AppState` sinks the denial flag into its existing `wifiLocationDenied` (equality-guarded, severed by `stopMonitors()`), no CoreLocation import.
- `StatusItemController` posts the UX-DR25 "Wi-Fi networks loading" announcement on the denied→granted edge's next `networkState` emission — the boundary-clean AppKit location.
- `Info.plist` gains `NSLocationUsageDescription`; the location entitlement and `PrivacyInfo.xcprivacy` were already present from earlier stories.
- `StubWiFiMonitor` in `AppStateTests` was missing the new protocol members (would not have compiled) — fixed.

### File List

**New (LinkHub/):**
- LinkHub/UI/Panels/LocationDeniedView.swift

**Modified (LinkHub/):**
- LinkHub/Network/WiFiMonitorProtocol.swift
- LinkHub/Network/WiFiMonitor.swift
- LinkHub/Network/MockWiFiMonitor.swift
- LinkHub/State/AppState.swift
- LinkHub/UI/Panels/WiFiSection.swift
- LinkHub/MenuBar/PopoverController.swift
- LinkHub/MenuBar/StatusItemController.swift
- LinkHub/Info.plist

**Modified (LinkHubTests/):**
- LinkHubTests/Network/WiFiMonitorTests.swift
- LinkHubTests/State/AppStateTests.swift
- LinkHubTests/UI/Panels/WiFiSectionTests.swift
- LinkHubTests/MenuBar/PopoverControllerTests.swift

### Change Log

| Date | Change |
|---|---|
| 2026-06-08 | Story created and implemented: LocationDeniedView (NEW), WiFiMonitor CLLocationManager auth flow + auto-retry, protocol `isLocationDenied` surface, AppState denial sink, WiFiSection `contentMode` branch, PopoverController `\.dismissPopover`, StatusItemController grant-after-denial announcement, Info.plist `NSLocationUsageDescription`, tests. Status: review. |
| 2026-06-08 | code-review (orchestrator, static Swift-6 concurrency + boundary audit): verified CLLocationManager is MainActor-owned and confined to Network/; `nonisolated locationManagerDidChangeAuthorization` hops to MainActor before reading `authorizationStatus`; `DismissBox`/`\.dismissPopover` injection is retain-cycle-free (weak self); `Info.plist` is the source of truth (GENERATE_INFOPLIST_FILE: NO, project.yml:88) so the edit holds; all 4 `WiFiMonitorProtocol` conformers updated. No blockers. Flagged for local verification: env-closure `@MainActor () -> Void` typing under strict concurrency, and the un-unit-testable NSAccessibility announcement (VoiceOver QA). Status → done. |
