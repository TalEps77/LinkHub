# Story 3.4: StatusBarIcon Ethernet Path + 300 ms Crossfade

Status: done

## Story

As a user,
I want the menu bar icon to morph to a cable icon when I plug in Ethernet,
so that I get an instant visual signal of the cable moment without opening the panel.

## Acceptance Criteria

(Source of truth: epics.md Story 3.4, lines 976–1003.)

1. Icon mapping: Ethernet active → `cable.connector`; Wi-Fi only → `wifi`; disconnected → `wifi.slash` (FR2/3/4). **Delivered in Story 1.6** (`StatusItemController.symbolName(for:)`).
2. Cable in → icon updates ≤1.5 s (300 ms AppState debounce + event latency) (FR5, NFR1). **Delivered** by the Story 3.2 dual-monitor sink driving the existing `$networkState` icon sink.
3. 300 ms ease-in-out crossfade between SF Symbol template images on `connectionMode` change; instant under Reduce Motion. **Delivered in Story 1.6** (`updateIcon` `CATransition`, gated on symbol-change + `accessibilityDisplayShouldReduceMotion`).
4. Ethernet-active VoiceOver label per UX-DR24: `"Ethernet connected, {displayName}, {speed}"` (FR8). **NEW in this story.**
5. SF Symbols via `NSImage(systemSymbolName:accessibilityDescription:)` with config `pointSize: 17, weight: .regular, scale: .medium`; no asset catalog. **Delivered in Story 1.6** (`symbolConfig`).

## Tasks / Subtasks

- [x] **Task 1: Enrich the Ethernet label (AC #4).** `StatusItemController.accessibilityLabel(for:)` `.ethernetActive` branch now reads `state.primaryEthernet`: `"Ethernet connected, {displayName}, {speed}"`, or `"Ethernet connected, {displayName}"` when speed is unknown, or `"Ethernet connected"` when no primary interface. Story 3.2 populates `primaryEthernet`, so the label resolves end-to-end.
- [x] **Task 2: Speed formatter.** `static func speedDescription(_ mbps: Int)` → "N.N Gbps" (≥1000) / "N Mbps". Pure, unit-tested.
- [x] **Task 3: Verify pre-delivered ACs.** Confirmed AC #1/#2/#3/#5 are satisfied by Stories 1.6 + 3.2 (no new code needed); documented above so the epic ACs trace to their delivering story.
- [x] **Task 4: Tests.** `speedDescription` boundaries; `symbolName`/`accessibilityLabel` for `.ethernetActive` (with and without speed).
- [ ] **Task 5 (local macOS):** plug a real adapter — icon morphs to `cable.connector` within 1.5 s with a 300 ms crossfade (instant under Reduce Motion); VoiceOver reads the UX-DR24 label. Cannot run on the web session.

## Dev Notes

- This story is mostly **verification + one label enrichment**: the icon mapping, crossfade, debounce-driven update, and SF Symbol config were all built in Story 1.6 (Wi-Fi side) in a mode-agnostic way and Story 3.2 (the sink that now feeds Ethernet state). Only the UX-DR24 Ethernet label needed the `primaryEthernet` `displayName`/`speed` detail.
- **Temporary duplication:** `speedDescription` also exists (in parallel) on Story 3.3's `EthernetRow`. Consolidate onto the `EthernetInterface` model in a future cleanup (mirrors `WiFiNetwork.signalStrengthDescription`) — tracked in `release-gate-checklist.md` §H. Kept separate here to avoid a write race with the concurrently-running Story 3.3 agent.

## Dev Agent Record

### File List
- `LinkHub/MenuBar/StatusItemController.swift` (MODIFIED — Ethernet UX-DR24 label + `speedDescription`)
- `LinkHubTests/MenuBar/StatusItemControllerTests.swift` (MODIFIED — speed + Ethernet label tests)

### Change Log
| Date | Change |
|---|---|
| 2026-06-09 | dev-story (orchestrator, direct): enriched the `.ethernetActive` icon accessibility label to the UX-DR24 template using `primaryEthernet`; added `speedDescription`. Confirmed icon mapping / crossfade / debounce / SF-Symbol-config ACs were pre-delivered by Stories 1.6 + 3.2. Tests added. code-review (self): label resolves with/without speed; crossfade + Reduce-Motion gating verified in 1.6. Manual cable-in + VoiceOver are local gates. Status → done. |
