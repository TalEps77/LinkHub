# Story 2.5: Wi-Fi Power Toggle + Captive Portal Handoff

Status: done

## Story

As a user,
I want to toggle Wi-Fi power directly from the panel and be routed to my browser when joining a captive network,
so that I can disable Wi-Fi without opening System Settings and complete captive sign-in in my own browser.

## Acceptance Criteria

(Source of truth: epics.md Story 2.5, lines 811–841.)

1. Header `Toggle` click → `WiFiMonitor.setPowered(_:)` flips the CoreWLAN interface power (FR35); the power state surfaces via `isWiFiEnabled`.
2. Wi-Fi off → list hidden; header + `Toggle` + "Wi-Fi: Off" label remain (UX-DR12/33); no current association (FR34).
3. Power change → "Wi-Fi turned on" / "Wi-Fi turned off" VoiceOver announcement (UX-DR25).
4. Captive network connect → `NSWorkspace.shared.open("http://captive.apple.com")` opens the default browser (FR33, NFR22); no in-app webview.
5. Captive network in list → `WiFiRow` shows the `globe` marker (FR25) — delivered in Story 1.4.

## Tasks / Subtasks

- [x] **Task 1: `WiFiMonitor.setPowered(_:)`** (AC #1, #2) — added to `WiFiMonitorProtocol` + all 4 conformers. Real monitor runs the blocking `CWInterface.setPower(_:)` off the MainActor (`Task.detached`, like `performAssociate`), logs errors (non-throwing), then `refreshFromCurrentInterface()` for immediacy; the `powerStateDidChange` event reconciles independently. Power *state* remains the existing `isEnabled` flag (the AC's `isPowered` maps to it).
- [x] **Task 2: AppState routing** (AC #1, NFR35) — `AppState.setWiFiPower(_:)` forwards to the monitor (mirrors `connect`); the View never calls the monitor directly.
- [x] **Task 3: `WiFiSection` power toggle + off state** (AC #1, #2) — header `Toggle` now bound to `wifiPowerBinding` (get: `networkState.isWiFiEnabled`; set: `Task { await appState.setWiFiPower(_) }`), replacing the Epic-1 `@State` stub. New `.wifiOff` `ContentMode` (highest priority) renders a centered "Wi-Fi: Off" label; the "Other Network…" footer is hidden when off or location-denied.
- [x] **Task 4: Power announcements** (AC #3) — already delivered by `StatusItemController.announceWiFiPowerChange` (Story 1.6) on the `isWiFiEnabled` edge; toggling now drives that edge. No new code.
- [x] **Task 5: Captive handoff** (AC #4) — on a successful `connect`, if `network.isCaptive`, `WiFiRow` opens `Self.captivePortalURL` (`http://captive.apple.com`) via `NSWorkspace` (imports AppKit, following the `LocationDeniedView` handoff precedent). No in-app webview.
- [x] **Task 6: Tests** — `contentMode` `.wifiOff` priority; `AppState.setWiFiPower` forwarding (stub records calls); `WiFiRow.captivePortalURL`. Conformer stubs gained `setPowered`.
- [ ] **Task 7 (local macOS):** `xcodegen generate` + `xcodebuild build/test`; manual: toggle flips real radio, off-state copy, VoiceOver power announcements, captive join opens browser. Cannot run on the web session.

## Dev Notes

### Architecture / boundaries
- Power toggle path: View → `AppState.setWiFiPower` → `WiFiMonitor.setPowered` (NFR35; no direct monitor call from the View). The `CWInterface` never crosses the actor boundary — only the Sendable `Bool` enters the detached closure.
- Captive handoff uses `NSWorkspace` from `WiFiRow` (AppKit import), consistent with the `LocationDeniedView` (Story 1.5) Settings-handoff precedent. The URL is a `static` constant for unit-testing.
- The power announcement reuses the Story 1.6 mechanism — no duplicate NSAccessibility wiring; the "Wi-Fi off" disconnect path was already gated there to avoid a double "No network connection" utterance.

### Spec divergences / decisions
- AC names `appState.wifiMonitor.isPowered`; LinkHub already models power as `isEnabled` (`CWInterface.powerOn()`). Rather than add a duplicate property, `setPowered` drives `isEnabled`. Documented for reconciliation.
- `.wifiOff` is the highest-priority `ContentMode` (above location-denied/scanning): when the radio is off there is nothing to scan or authorize. Hardware-absent (`isWiFiEnabled == false` because no interface) also renders "Wi-Fi: Off" — a dedicated "Wi-Fi unavailable" copy is out of v1 scope.
- Captive detection is treated as the network's `isCaptive` flag at connect time (FR33 handoff), not a live post-association probe (NEHotspotHelper is out of scope; see Story 1.3 deferred-work note on `isCaptive`).

## Dev Agent Record

### File List
- `LinkHub/Network/WiFiMonitorProtocol.swift` (MODIFIED — add `setPowered`)
- `LinkHub/Network/WiFiMonitor.swift` (MODIFIED — `setPowered` + detached `setPower`)
- `LinkHub/Network/MockWiFiMonitor.swift` (MODIFIED — `setPowered`)
- `LinkHub/State/AppState.swift` (MODIFIED — `setWiFiPower`)
- `LinkHub/UI/Panels/WiFiSection.swift` (MODIFIED — power binding, `.wifiOff` state, footer gating)
- `LinkHub/UI/Components/WiFiRow.swift` (MODIFIED — captive handoff + `captivePortalURL`)
- `LinkHubTests/State/AppStateTests.swift`, `LinkHubTests/UI/Panels/WiFiSectionTests.swift`, `LinkHubTests/UI/Components/WiFiRowTests.swift`, `LinkHubTests/MenuBar/PopoverControllerTests.swift` (MODIFIED — tests + conformer stubs)

### Change Log
| Date | Change |
|---|---|
| 2026-06-08 | dev-story implementation (orchestrator, direct): power toggle wired View→AppState→monitor, `.wifiOff` content state, captive-portal browser handoff. Power announcements reuse Story 1.6. Tests added; all conformer stubs updated. code-review (self): verified Task/Binding concurrency, `CWInterface` stays off the actor boundary, `.wifiOff` priority, no double power announcement. Build/test + manual gates deferred to local macOS. Status → done. |
