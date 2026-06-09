# Story 4.7: Final Instruments Validation Pass

Status: done (authoring) — execution is a maintainer hardware gate

## Story

As the maintainer,
I want a final 1-hour Instruments session validating memory, CPU, and leaks against representative state-change traffic,
so that NFR48, NFR49, and NFR8 are confirmed before tagging a release.

## Acceptance Criteria

(Source of truth: epics.md Story 4.7, lines 1248–1273.)

1. 1-hour Allocations + Leaks + Time Profiler with induced traffic (Wi-Fi scan loop, connect/disconnect, cable in/out, sleep/wake) → **zero leaks** attributable to LinkHub (NFR8).
2. End-of-session memory (panel closed 60 s) ≤80 MB resident (FR48); 60 s avg CPU ≤0.5% on Apple Silicon (FR49).
3. No regression beyond ±5% vs. the Epic 1/2/3 baselines; any regression flagged before tagging.
4. Crash-free session rate ≥99.5% over the first 30 days via Apple-collected crash reports (no in-app telemetry, NFR19/NFR7); verification method documented in release notes.

## Nature of this story

Story 4.7 is **verification-only** — it produces no shippable code. It is the terminal quality gate of the BMad implementation: a structured Instruments + post-release measurement pass that must run on **Apple Silicon hardware with Xcode 16 Instruments** and, for AC #4, against real-world install telemetry over 30 days. **None of it can execute in the Linux/web authoring environment.**

Accordingly, the deliverable authored here is the **executable procedure**, captured in the project's release-gate checklist so it is run as part of every release:

- `release-gate-checklist.md` / `.html` **§F (Performance / reliability — Instruments)** enumerates the popover-paint, idle memory/CPU, per-epic regression, and the Story-4.7 1-hour Allocations/Leaks/Time-Profiler pass with the exact budgets above.
- §A (build) gates a zero-warning Release build first; the Instruments session runs against that Release build.

## Procedure (run on Apple Silicon + Xcode 16 Instruments)

1. Build Release (`xcodebuild -scheme LinkHub -configuration Release build`), confirm zero strict-concurrency warnings.
2. Launch under Instruments with the **Allocations + Leaks + Time Profiler** template; run 1 hour while inducing: repeated Wi-Fi scans (reopen panel), connect/disconnect cycles, Ethernet cable in/out + dock reconnect, and a sleep/wake cycle.
3. Assert: zero leaks attributable to LinkHub (AC #1).
4. Idle 60 s with the panel closed → resident memory ≤80 MB, 60 s avg CPU ≤0.5% (AC #2).
5. Compare against the Epic 1 (Story 1.6), Epic 2 (Story 2.6), and Epic 3 (Story 3.6) baselines; flag any regression > ±5% before tagging (AC #3).
6. Post-release: monitor Apple crash reports (Console / Xcode Organizer) for ≥99.5% crash-free sessions over 30 days; document the method in the release notes (AC #4, NFR7/NFR19).

## Dev Agent Record

### File List
- (No source code.) Procedure recorded in `_bmad-output/implementation-artifacts/release-gate-checklist.md` / `.html` §F.

### Change Log
| Date | Change |
|---|---|
| 2026-06-09 | Story authored as the terminal verification gate: procedure + budgets recorded in the release-gate checklist §F; no code to write. Execution requires Apple Silicon + Instruments and 30-day post-release crash telemetry — a maintainer hardware/release gate, not runnable in the web session. Status → done (authoring complete; execution pending hardware). Epic 4 complete (7/7). |
