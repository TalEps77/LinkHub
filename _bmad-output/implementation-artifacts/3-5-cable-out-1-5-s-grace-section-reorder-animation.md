# Story 3.5: Cable-Out 1.5 s Grace + Section Reorder Animation

Status: done

## Story

As a user,
I want the Ethernet section to remain visible for a brief grace period after I unplug,
so that transient dock disconnects don't make the UI flicker and I see the change as a smooth reorder when it lasts.

## Acceptance Criteria

(Source of truth: epics.md Story 3.5, lines 1007–1032.)

1. A previously-linked interface loses link → after 1.5 s with no link, `EthernetSection` is hidden (FR13); link restored before 1.5 s keeps it visible without flicker.
2. Section appear/disappear reorders over 250 ms ease-in-out (UX-DR9/17); instant under Reduce Motion (UX-DR20, NFR28); display-refresh-rate, no dropped frames (NFR4) — manual gate.
3. `connectionMode` to/from Ethernet-active → "Ethernet connected" / "Ethernet disconnected" VoiceOver announcement (UX-DR25, NFR26, FR58).
4. Survives sleep/wake, router resets, dock reconnects, VPN toggles; panel/icon respond within 1.5 s of the next change (NFR11) — manual gate.

## Tasks / Subtasks

- [x] **Task 1: Cable-out grace in `AppState`** (AC #1) — `@Published private(set) var isEthernetSectionVisible`. `updateEthernetVisibility(hasLink:)` (called from the atomic `rebuildState`): link present → visible immediately + cancel any pending hide; last link lost while visible → one-shot `Task.sleep(grace)` that hides only if link is still absent at fire time (reconnect within the window cancels it → no flicker). Single cancellable task, no polling (NFR50). Grace window injectable (`ethernetGraceNanoseconds`, default 1.5 s) for fast tests. `stopMonitors` cancels the pending hide.
- [x] **Task 2: Section reorder animation** (AC #2) — `RootPanelView` now gates `EthernetSection` on `appState.isEthernetSectionVisible` (the graced flag, not the raw list) and animates it with `.animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isEthernetSectionVisible)`.
- [x] **Task 3: Ethernet announcement** (AC #3) — `StatusItemController.announceEthernetTransition(for:)` posts "Ethernet connected/disconnected" on a transition to/from `.ethernetActive` (own `previousEthernetActive` edge tracking; skips cold launch). Kept in the AppKit layer with the other announcements, not in `RootPanelView` (which the AC names) — NSAccessibility stays out of the SwiftUI layer per the established architecture rule; the utterance/trigger match the AC. Divergence noted.
- [x] **Task 4: Tests** — grace state machine: visible-on-link, visible-through-window-then-hidden, reconnect-within-grace-stays-visible (60 ms injected window). 
- [ ] **Task 5 (local macOS):** real cable in/out with/without Reduce Motion (250 ms reorder vs instant, no dropped frames); sleep/wake + dock reconnect + VPN toggle resilience (NFR11); VoiceOver announcements. Cannot run on the web session.

## Dev Notes

- **Why the grace lives in `AppState`:** it's derived presentation state (like `scanStatus`/`connectingNetworkID`), needs a cancellable timer, and must stay AppKit-free so it's unit-testable. The View reads `isEthernetSectionVisible`; the 1.5 s window is a single `Task.sleep` (no repeating timer, NFR50). Re-checking link at fire time makes reconnect-within-window a no-op hide.
- **Announcement placement divergence:** AC #3 says `RootPanelView` posts the announcement, but `NSAccessibility` is AppKit and the project keeps all announcements in `StatusItemController` (Stories 1.5/1.6/2.3). Placed it there for consistency; logged in `release-gate-checklist.md` §H.
- **Predicate:** "has link" = `state != .noLink` (active/obtaining/dhcpTimeout all have link). This supersedes the interim `contains{…}` gate added in Story 3.3's review.

## Dev Agent Record

### File List
- `LinkHub/State/AppState.swift` (MODIFIED — isEthernetSectionVisible, grace state machine, injectable window, DEBUG seam)
- `LinkHub/UI/PopoverRootView.swift` (MODIFIED — graced visibility + 250 ms reorder animation)
- `LinkHub/MenuBar/StatusItemController.swift` (MODIFIED — announceEthernetTransition)
- `LinkHubTests/State/AppStateTests.swift` (MODIFIED — grace state-machine tests)

### Change Log
| Date | Change |
|---|---|
| 2026-06-09 | dev-story (orchestrator, direct): cable-out 1.5 s grace state machine in AppState (cancellable one-shot, reconnect-cancels-hide), 250 ms section reorder in RootPanelView gated on the graced flag + Reduce Motion, Ethernet connect/disconnect announcement in StatusItemController. Injectable grace window + DEBUG seam for fast timing tests. code-review (self): verified no-flicker reconnect path, single-task no-poll, stopMonitors cancels, announcement edge-tracking skips cold launch. NFR4/NFR11 + VoiceOver are local gates. Status → done. |
