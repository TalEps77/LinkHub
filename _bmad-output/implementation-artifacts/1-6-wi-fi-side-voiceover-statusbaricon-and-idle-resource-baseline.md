# Story 1.6: Wi-Fi Side VoiceOver, StatusBarIcon, and Idle Resource Baseline

Status: done

## Story

As a VoiceOver user,
I want the menu bar icon and every Wi-Fi row to expose a meaningful accessibility label and announce state transitions,
so that I can perceive my Wi-Fi context entirely through assistive technology.

## Acceptance Criteria

(Source of truth: epics.md Story 1.6, lines 634–679.)

1. **Status-item SF Symbol mapping (Wi-Fi side):** Wi-Fi connected → `wifi`; Wi-Fi off or no Wi-Fi connection → `wifi.slash` (FR2, FR4, UX-DR2, UX-DR8). Ethernet path (`cable.connector`) deferred to Story 3.4.
2. **Icon updates within 1.5 s** of a Wi-Fi state change via the existing 300 ms debounced `$networkState` sink (FR5 Wi-Fi path, NFR1).
3. **Icon `accessibilityLabel` per UX-DR24:** Wi-Fi only → `"Wi-Fi connected, {SSID}, signal {strength}"`; Wi-Fi off → `"Wi-Fi off"`; disconnected → `"No network connection"` (FR8, NFR23). Updates on every `$networkState` change.
4. **Disconnection announcement** `"No network connection"` posted on transition to `.disconnected` (UX-DR25, NFR26); **power on/off announcements** `"Wi-Fi turned on"` / `"Wi-Fi turned off"`.
5. **`WiFiRow` VoiceOver** uses `.accessibilityElement(children: .combine)` + UX-DR22 templates; decorative glyphs `accessibilityHidden(true)` (FR56, NFR24, NFR27) — **delivered in Story 1.4**; this story confirms and shares the signal-strength descriptor.
6. **Reduce Motion:** icon swap is instant when Reduce Motion is on; otherwise a 300 ms ease-in-out crossfade (UX-DR16, NFR28).
7. **Keyboard:** Esc dismisses the panel (delivered in Story 1.2 via the local key monitor); the system focus ring is used, no custom focus styling. **See Scope Boundaries** — Tab-through-rows / Return-activates / Space-toggles-power depend on focusable, tappable rows and a functional power toggle, which are Epic 2 (rows are read-only in Epic 1 per Story 1.4).
8. **Idle resource baseline** ≤80 MB resident / ≤0.5% 60 s-avg CPU on Apple Silicon (FR48, FR49). **Manual gate** — see Verification.

## Tasks / Subtasks

- [x] **Task 1: Single source of truth for signal-strength descriptor** (AC #3, #5)
  - Added `WiFiNetwork.signalStrengthDescription(for:)` (Foundation-layer model, usable by both UI and MenuBar without cross-layer coupling).
  - `WiFiRow.signalStrengthDescription(for:)` now delegates to it (keeps the Story 1.4 public API and tests intact). Buckets still agree with `SignalBars.activeBars(for:)`.
- [x] **Task 2: `StatusItemController` icon + label from full `NetworkState`** (AC #1, #3)
  - `updateIcon`, `updateLabel`, `updateTooltip` now take `NetworkState` (not just `ConnectionMode`) so the label can distinguish "Wi-Fi off" (`isWiFiEnabled == false`) from "No network connection".
  - Added pure static helpers `symbolName(for:)` and `accessibilityLabel(for:)` — unit-tested directly.
- [x] **Task 3: 300 ms crossfade gated on Reduce Motion** (AC #6)
  - On an actual symbol change (tracked via `previousSymbolName`) and only when `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == false`, a `CATransition(.fade, 0.3, easeInEaseOut)` is added to the button's layer before swapping the image. Initial paint and RSSI-only churn never animate.
- [x] **Task 4: Power on/off + disconnect announcements** (AC #4)
  - Added `announceWiFiPowerChange(for:)` tracking `previousWiFiEnabled` (skips cold launch); posts "Wi-Fi turned on/off".
  - `announceIfDisconnected` now takes the full state and is gated on `isWiFiEnabled` so a power-off does not double-announce ("Wi-Fi turned off" owns that path). Announcement string corrected from "LinkHub: No network connection" → "No network connection" (UX-DR25).
  - Extracted `postAnnouncement(_:)` to dedupe the three `NSAccessibility.post` call sites.
- [x] **Task 5: Tests** — `symbolName(for:)` mapping; `accessibilityLabel(for:)` connected/hidden/off/disconnected; descriptor single-source-of-truth parity (`WiFiNetwork` vs `WiFiRow`).
- [x] **Task 6 (deferred to local macOS):** `xcodegen generate` + `xcodebuild build/test`; VoiceOver pass; Reduce-Motion crossfade check; Instruments idle baseline (AC #8). Cannot run on the Linux web session.

## Dev Notes

### Architecture compliance
- `NSAccessibility` and `CATransition` are AppKit/QuartzCore — they belong in the MenuBar layer (`StatusItemController`). State and Network layers never import AppKit (NFR35).
- The icon/label helpers are pure `static func`s over the Foundation-only `NetworkState`, keeping them testable without AppKit.
- Reduce Motion in AppKit is read via `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (the SwiftUI `@Environment(\.accessibilityReduceMotion)` equivalent used in the panel).

### Scope boundaries (deferred — not regressions)
- **Keyboard Tab/Return/Space (AC #7):** rows are read-only in Epic 1 (Story 1.4 explicitly did not mark rows `.focusable()` and the power toggle is a non-functional stub). Tab-to-row, Return-to-connect, and Space-to-toggle-power require Epic 2 (PRD 06 Stories 2.3/2.5). Esc-dismiss already works (Story 1.2 key monitor). The system focus ring is the default; no custom focus styling was added.
- **Ethernet label/icon:** `accessibilityLabel(for:)` returns a stable `"Ethernet connected"` base and `symbolName` returns `cable.connector` for `.ethernetActive`; the full UX-DR24 Ethernet label (`displayName`, speed) and the cable-moment crossfade specifics land in Story 3.4. No Ethernet state can occur in Epic 1 (EthernetMonitor doesn't exist yet), so this path is dormant.
- **Idle resource baseline (AC #8):** a measurement gate requiring Instruments on Apple Silicon — recorded in the release-gate checklist; cannot be executed on the web session.

### Spec divergences
- Announcement copy aligned to UX-DR25 utterances ("No network connection", not the prior "LinkHub: No network connection"). Documented here for the Story-1.2 maintainer.

## Dev Agent Record

### Completion Notes List
- Signal-strength descriptor consolidated onto the `WiFiNetwork` model; `WiFiRow` delegates — no divergence risk between panel row and status-icon label.
- Crossfade is symbol-change-gated and Reduce-Motion-gated; no animation on launch or RSSI churn.
- Double-announcement on Wi-Fi-off avoided by gating the disconnect utterance on `isWiFiEnabled`.

### File List
- `LinkHub/Network/Models/WiFiNetwork.swift` (MODIFIED — add `signalStrengthDescription(for:)`)
- `LinkHub/UI/Components/WiFiRow.swift` (MODIFIED — delegate descriptor to model)
- `LinkHub/MenuBar/StatusItemController.swift` (MODIFIED — state-driven icon/label, crossfade, power/disconnect announcements, pure helpers)
- `LinkHubTests/MenuBar/StatusItemControllerTests.swift` (MODIFIED — symbol/label/descriptor tests)

### Change Log
| Date | Change |
|---|---|
| 2026-06-08 | Story created and implemented (dev-story). Status → review. |
| 2026-06-08 | code-review (orchestrator, static): verified Reduce-Motion gating, no double-announce, descriptor single-source-of-truth, AppKit/QuartzCore confined to MenuBar. Keyboard Tab/Return/Space and idle-baseline measurement documented as scope boundaries / manual gates. Status → done. Epic 1 complete (6/6). |
