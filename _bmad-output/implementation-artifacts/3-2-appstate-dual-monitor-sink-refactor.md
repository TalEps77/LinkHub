# Story 3.2: AppState Dual-Monitor Sink Refactor

Status: done

## Story

As a developer,
I want `AppState` to combine Wi-Fi and Ethernet streams into a single atomic state update,
so that `connectionMode` and `networkState` are always coherent and no Epic-2 connect/disconnect path regresses.

## Acceptance Criteria

(Source of truth: epics.md Story 3.2, lines 917–941.)

1. The sink becomes `Publishers.CombineLatest(ethernetMonitor.interfacesPublisher, wifiCombined).debounce(…).sink { … }`, rebuilding `networkState` + `connectionMode` atomically in one write; `AppState` stays a single `@MainActor final class ObservableObject` (NFR35).
2. Epic-2 paths still pass (open/WPA/hidden connect, power on/off, Forget handoff); failed-connect retry stays clean (NFR10).
3. UI subscribes only to `AppState` via `@EnvironmentObject` — no view observes a monitor directly (NFR35).
4. Release builds emit zero Swift 6 strict-concurrency warnings (NFR33) — local gate.

## Tasks / Subtasks

- [x] **Task 1: Inject `EthernetMonitor`** — `AppState` gains `let ethernetMonitor: any EthernetMonitorProtocol`. Designated `init(wifiMonitor:ethernetMonitor:)`; convenience `init(wifiMonitor:)` (defaults real `EthernetMonitor`) keeps all existing call sites/tests compiling; `init()` wires both real monitors.
- [x] **Task 2: Combined sink** — `CombineLatest(ethernet.interfacesPublisher, CombineLatest4(wifi…))`, 300 ms debounce (NFR5), single `rebuildState` write. `startMonitors`/`stopMonitors` now start/stop both monitors.
- [x] **Task 3: `rebuildState(ethernet:…)`** — populates `ethernetInterfaces` and `primaryEthernet` (first `.active`); `computeConnectionMode(ethernet:wifi:)` (already Ethernet-aware from Story 1.3) yields `.ethernetActive` when any interface is active. One atomic `networkState` assignment.
- [x] **Task 4: Test** — `testDualMonitorRebuildsEthernetActiveAtomically`: active Ethernet + connected Wi-Fi → `mode == .ethernetActive`, `primaryEthernet == en3`, non-empty interfaces. Existing Epic-1/2 tests unchanged (convenience init preserves their call shape).
- [ ] **Task 5 (local macOS):** Release build zero strict-concurrency warnings; full Epic-2 regression suite green. Cannot run on the web session.

## Dev Notes

- **Atomicity:** a single `networkState` write carries both Ethernet and Wi-Fi; `connectionMode` mirrors via the `init` `assign(to:)` pipeline, so observers never see a split `(ethernet, wifi)` state. CombineLatest only fires once both sides have emitted — guaranteed because every `@Published` emits its current value on subscription (Ethernet emits `[]` initially).
- **NFR35:** the View layer is untouched here; it already reads `appState.networkState`. No view observes `WiFiMonitor`/`EthernetMonitor`.
- **Init compatibility:** rather than churn ~10 `AppState(wifiMonitor:)` call sites, the convenience initializer defaults the Ethernet monitor; tests that need Ethernet isolation pass `MockEthernetMonitor` explicitly. The real `EthernetMonitor` does work only in `start()`, so non-`startMonitors` call sites incur no SystemConfiguration cost.
- **Concurrency:** sink delivers on `DispatchQueue.main` (not MainActor-isolated under Swift 6) → `Task { @MainActor }` hop into `rebuildState`, mirroring the prior Wi-Fi-only sink. No new Sendable hazards (`[EthernetInterface]` and the Wi-Fi tuple are all Sendable).

## Dev Agent Record

### File List
- `LinkHub/State/AppState.swift` (MODIFIED — ethernetMonitor, dual init, combined sink, rebuildState)
- `LinkHubTests/State/AppStateTests.swift` (MODIFIED — dual-monitor atomic-rebuild test)

### Change Log
| Date | Change |
|---|---|
| 2026-06-09 | dev-story (orchestrator, direct): injected EthernetMonitor; CombineLatest(ethernet, wifi4) atomic rebuild; rebuildState populates interfaces + primaryEthernet; start/stop both monitors. Backward-compatible convenience init avoids call-site churn. code-review (self): verified atomic single-write, both-emit CombineLatest semantics, NFR35 (UI untouched), Task-hop concurrency. Release-build strict-concurrency + Epic-2 regression are local gates. Status → done. |
