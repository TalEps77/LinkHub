# Story 2.6: Forget Network + Open Wi-Fi Settings Handoffs

Status: done

## Story

As a user,
I want to forget a known network and open the system Wi-Fi settings pane from inside LinkHub,
so that I can complete management actions LinkHub intentionally hands off to Apple's UI without leaving my flow.

## Acceptance Criteria

(Source of truth: epics.md Story 2.6, lines 844–875.)

1. Right-click on a known-SSID `WiFiRow` → `.contextMenu` with `Forget` + `Open in Settings` (UX-DR36); unknown SSIDs show no menu.
2. `Forget` → popover dismisses + `SystemSettingsService.openWiFiSettings()` (`x-apple.systempreferences:com.apple.wifi-settings-extension`) (FR36, UX-DR32); no in-app removal of the *system* known-network entry.
3. `WiFiSection` footer has an `Open Network Settings…` `.plain` link (UX-DR34) opening the same URL (FR38); popover auto-dismisses first (UX-DR32).
4. All handoffs use `NSWorkspace.shared.open(_:)` with the architecture-specified scheme; no other URLs.
5. Epic 2 resource baseline (10 connect/disconnect/forget cycles) — manual Instruments gate (FR48/FR49).

## Tasks / Subtasks

- [x] **Task 1: `SystemSettingsService`** (AC #2, #3, #4) — NEW `LinkHub/Services/SystemSettingsService.swift`: stateless enum, `wifiSettingsURL` constant + `@MainActor openWiFiSettings()` via `NSWorkspace`. AppKit confined to the Services layer.
- [x] **Task 2: AppState `isRemembered` / `forget`** (AC #1, #2) — `isRemembered(_:)` returns `true` iff a Keychain passphrase exists for the SSID (LinkHub's computable "known" set; hidden/nil-SSID never known). `forget(ssid:)` removes LinkHub's stored passphrase via `KeychainService.remove` (logs failures); does NOT touch the system entry.
- [x] **Task 3: `WiFiRow` context menu** (AC #1, #2) — `body` conditionally attaches `.contextMenu` only when `appState.isRemembered(network)` (unknown rows get no menu). `Forget` clears the Keychain entry, dismisses the popover (`\.dismissPopover`), and opens Wi-Fi settings; `Open in Settings` dismisses + opens.
- [x] **Task 4: `WiFiSection` footer link** (AC #3) — `Open Network Settings…` `.plain` button below `Other Network…`, dismiss-then-open, gated to the visible-list states (hidden when off/denied).
- [x] **Task 5: Tests** — `SystemSettingsService.wifiSettingsURL`; `isRemembered` false for hidden network; `forget` of an unstored SSID is a non-throwing no-op.
- [ ] **Task 6 (local macOS):** `xcodegen generate` + `xcodebuild build/test`; manual: right-click menu visibility for known vs unknown, Forget/Settings handoffs open the pane with the popover dismissed; Epic 2 Instruments baseline. Cannot run on the web session.

## Dev Notes

### Architecture / boundaries
- `NSWorkspace` lives in `SystemSettingsService` (Services). `WiFiSection` stays SwiftUI-only and calls the service; `WiFiRow` already imports AppKit (Story 2.5 captive handoff). Popover dismissal uses the `\.dismissPopover` environment action (Story 1.5) — no view↔popover coupling. Keychain access stays inside `AppState`/`KeychainService` (NFR35).

### Spec decisions / divergences
- **"Known" definition:** macOS exposes no public API for the system known-network list, so LinkHub defines "known" as *LinkHub-remembered* (a stored Keychain passphrase). This gates the context menu per AC #1 without private API. Documented for reconciliation; revisit if a public enumeration API becomes available.
- **Forget semantics:** per AC #2 LinkHub does not mutate the system known-network entry; it clears its own stored passphrase and hands off to Settings, where the user removes the system entry. `KeychainService.remove` (built in Story 2.2 for this) is used.
- The `Open Network Settings…` footer uses the Wi-Fi-settings URL (FR38). The broader macOS Network-Settings pane (`com.apple.Network-Settings.extension`) for the Ethernet overflow handoff is Story 3.6.

## Dev Agent Record

### File List
- `LinkHub/Services/SystemSettingsService.swift` (NEW)
- `LinkHub/State/AppState.swift` (MODIFIED — `isRemembered`, `forget`)
- `LinkHub/UI/Components/WiFiRow.swift` (MODIFIED — conditional context menu, Forget/Open handoffs)
- `LinkHub/UI/Panels/WiFiSection.swift` (MODIFIED — `Open Network Settings…` footer)
- `LinkHubTests/Services/SystemSettingsServiceTests.swift` (NEW), `LinkHubTests/State/AppStateTests.swift` (MODIFIED)

### Change Log
| Date | Change |
|---|---|
| 2026-06-08 | dev-story implementation (orchestrator, direct): SystemSettingsService handoff, known-network context menu (Forget / Open in Settings), section footer settings link, AppState isRemembered/forget. code-review (self): verified boundary (NSWorkspace in Services), conditional context-menu attach (no empty menu on unknown rows), dismiss-then-open ordering, Keychain-only "known" definition documented. Build/test + manual gates deferred to local macOS. Status → done. Epic 2 complete (6/6). |
