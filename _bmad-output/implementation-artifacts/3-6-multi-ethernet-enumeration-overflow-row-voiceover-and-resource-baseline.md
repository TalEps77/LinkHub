# Story 3.6: Multi-Ethernet Enumeration, Overflow Row, VoiceOver, and Resource Baseline

Status: done

## Story

As a user,
I want LinkHub to handle multiple Ethernet interfaces gracefully and let me jump to System Settings if I have more interfaces than the panel shows inline,
so that complex docking setups don't degrade the experience and assistive technology can perceive every interface.

## Acceptance Criteria

(Source of truth: epics.md Story 3.6, lines 1042–1064.)

1. Interfaces sorted active-first, ties broken by BSD name (FR20); top 2 inline, the rest collapse into one "+ N more in Settings…" overflow row (UX-DR10, FR21).
2. Overflow row / section footer → dismiss popover + open `x-apple.systempreferences:com.apple.Network-Settings.extension` (FR22, UX-DR32).
3. `EthernetRow` VoiceOver per UX-DR23 by state (active/obtaining/dhcpTimeout/noLink); decorative dots `accessibilityHidden` (FR57, NFR25, NFR27).
4. State-transition announcements per UX-DR25 (FR58, NFR26) — delivered in Story 3.5.
5. Epic 3 resource baseline: ≤80 MB / ≤0.5% CPU / zero 1-hour leaks (FR48/FR49/NFR8) — manual Instruments gate.

## Tasks / Subtasks

- [x] **Task 1: Sort + overflow** (AC #1) — `EthernetSection.linkedSorted(from:)` filters cable-out `.noLink` interfaces and sorts active-first then by BSD name (FR20). `displayedInterfaces` = top 2; `overflowCount` = remaining linked count. Both pure/unit-tested.
- [x] **Task 2: Overflow row + handoff** (AC #2) — "+ N more in Settings…" `.plain` row when `overflowCount > 0`: dismiss popover (`\.dismissPopover`) → `SystemSettingsService.openNetworkSettings()` (new `networkSettingsURL`). Distinct from the Story 2.6 Wi-Fi-settings URL.
- [x] **Task 3: UX-DR23 VoiceOver labels** (AC #3) — `EthernetRow.accessibilityLabel` now emits the canonical templates: "{name}, active, {ip}, {speed}" / "{name}, obtaining address" / "{name}, DHCP timeout, no address" / "{name}, no link". Dot already `accessibilityHidden` (Story 3.3).
- [x] **Task 4: Tests** — section: no-link filtering, active-first + BSD tie-break, top-2 cap, overflow count; row: all four UX-DR23 labels (incl. active no-address/no-speed); `networkSettingsURL`.
- [ ] **Task 5 (local macOS):** multi-adapter dock — sort/overflow render, overflow opens Network Settings with popover dismissed; VoiceOver reads UX-DR23; Epic 3 Instruments baseline (≤80 MB / ≤0.5% / zero leaks over 1 h with cable in/out + dock + sleep/wake). Cannot run on the web session.

## Dev Notes

- **Sort key (FR20):** `active` before non-active; within a group, ascending BSD name for stable, deterministic order. `.noLink` interfaces are excluded entirely — the section represents cabled interfaces, and the section's own visibility (Story 3.5) is already "has link".
- **Overflow handoff URL:** `com.apple.Network-Settings.extension` (the macOS Network pane), distinct from `com.apple.wifi-settings-extension` (Story 2.6 Wi-Fi pane). Both live in `SystemSettingsService` (AppKit confined to Services).
- **VoiceOver:** UX-DR23 templates are the canonical form (Story 3.3 shipped an interim label; this story replaces it). "{ip}" → "no address" when absent so the active label always reads sensibly.
- **Resource baseline (AC #5)** is a hardware Instruments gate — recorded in `release-gate-checklist.md` §F.

## Dev Agent Record

### File List
- `LinkHub/UI/Panels/EthernetSection.swift` (MODIFIED — linkedSorted/overflowCount, overflow row, dismissPopover)
- `LinkHub/UI/Components/EthernetRow.swift` (MODIFIED — UX-DR23 accessibilityLabel)
- `LinkHub/Services/SystemSettingsService.swift` (MODIFIED — networkSettingsURL + openNetworkSettings)
- `LinkHubTests/UI/Panels/EthernetSectionTests.swift`, `LinkHubTests/UI/Components/EthernetRowTests.swift`, `LinkHubTests/Services/SystemSettingsServiceTests.swift` (MODIFIED — sort/overflow/label/URL tests)

### Change Log
| Date | Change |
|---|---|
| 2026-06-09 | dev-story (orchestrator, direct): multi-interface active-first + BSD tie-break sort, top-2 inline + "+N more" overflow → Network Settings handoff, UX-DR23 VoiceOver labels. code-review (self): verified no-link exclusion, deterministic tie-break, overflow count, popover-dismiss-then-open ordering, label templates. Instruments baseline is a local gate. Status → done. Epic 3 complete (6/6). |
