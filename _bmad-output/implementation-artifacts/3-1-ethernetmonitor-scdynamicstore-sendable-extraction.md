# Story 3.1: EthernetMonitor — SCDynamicStore + Sendable Extraction

Status: done

## Story

As a user,
I want LinkHub to detect Ethernet interfaces (USB-C, Thunderbolt, dock) and react to link / IP changes immediately,
so that the panel and icon track cable plug/unplug without polling.

## Acceptance Criteria

1. **SCDynamicStore bound to a private serial queue with the two regex patterns**
   - **Given** the app launches
   - **When** `EthernetMonitor.start()` runs
   - **Then** an `SCDynamicStore` is created with `SCDynamicStoreSetDispatchQueue` bound to a private serial `DispatchQueue` (not the main queue)
   - **And** watch keys are the regex(3) patterns `State:/Network/Interface/[^/]+/Link` AND `State:/Network/Interface/[^/]+/IPv4`
   - **And** every callback re-enumerates interfaces via `SCNetworkInterfaceCopyAll()` to handle hotplug (FR15)

2. **Sendable extraction before the MainActor hop (NFR8)**
   - **Given** an SCDynamicStore C callback fires
   - **When** values are read from `SCNetworkInterface` / `CFType`
   - **Then** Sendable values populate a `[EthernetInterface]` snapshot on the private queue
   - **And** the hop to MainActor uses `Task { @MainActor in ... }` — `SCNetworkInterface` and `CFType` are never captured across the actor boundary

3. **300 ms Combine debounce on rapid Link/IPv4 events (NFR5)**
   - **Given** rapid Link/IPv4 events (dock-wake or cable-flutter)
   - **When** events arrive in succession
   - **Then** they pass through a `PassthroughSubject<Void, Never>.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)` before re-enumeration

4. **Snapshot exposes display name, BSD name, IPv4, link speed, and one of four states (FR16–FR19)**
   - **Given** an Ethernet interface
   - **When** the snapshot is built
   - **Then** each `EthernetInterface` exposes display name, BSD name (e.g. en3), IPv4 address, negotiated link speed (Mbps), and state (`active`, `obtaining`, `dhcpTimeout`, `noLink`)
   - **And** all model types in `Network/Models/` are Foundation-only value types and `Sendable`

5. **Clean teardown (NFR9, FR46)**
   - **Given** `EthernetMonitor.stop()` is called on termination
   - **When** teardown runs
   - **Then** `SCDynamicStoreSetDispatchQueue(store, nil)` is invoked (detaching the queue and balancing the context retain), and the interface list is cleared

## Tasks / Subtasks

- [x] Expand `EthernetInterface` (Models, Foundation-only `Sendable` value type): add `ipv4: String?` and `state: EthernetInterfaceState`; keep `id`/`bsdName`/`displayName`/`linkSpeedMbps`; make `isActive` a computed `{ state == .active }`. (AC4)
- [x] Define `enum EthernetInterfaceState: Equatable, Sendable { active; obtaining; dhcpTimeout; noLink }`. (AC4)
- [x] Add `Log.networkEthernet` category in `Logger.swift`. (already present, consistent with the existing `network.wifi` pattern)
- [x] New `EthernetMonitor.swift` (`@MainActor final class`): `@Published private(set) var interfaces` + `interfacesPublisher`. (AC1, AC2)
- [x] `start()`: build `SCDynamicStoreContext` with `Unmanaged` retain/release, `SCDynamicStoreCreate`, register the two regex patterns via `SCDynamicStoreSetNotificationKeys`, bind a private serial queue via `SCDynamicStoreSetDispatchQueue`, wire the 300 ms debounced sink, perform initial enumeration. (AC1, AC3)
- [x] `@convention(c)` `scCallback`: recover `self` via `Unmanaged.fromOpaque(info)`, ping `eventSubject` through a MainActor hop. (AC2)
- [x] `refresh()`: dispatch the SC/CF reads to the private queue (continuation), build the Sendable `[EthernetInterface]`, hop back to MainActor and `ingest()`. (AC2)
- [x] Pure helpers: `static interfaceState(hasLink:ipv4:dhcpTimedOut:)`, `static megabitsFromSubtype(_:)`; live reads `readHasLink` / `readIPv4` / `readLinkSpeedMbps` confined to the private queue. (AC4)
- [x] `stop()`: `SCDynamicStoreSetDispatchQueue(store, nil)`, clear cancellables + interfaces. (AC5)
- [x] New `EthernetMonitorProtocol` mirroring `WiFiMonitorProtocol` (interfaces getter + publisher, `start()`, `stop()`). (AC1)
- [x] New `MockEthernetMonitor` (`#if DEBUG`) with settable `@Published var interfaces` + sample interfaces (active en3 with IP + 1000 Mbps, obtaining en5). (AC4)
- [x] Tests: pure `interfaceState(...)` across all four states, `megabitsFromSubtype` known/unknown, `EthernetInterface.isActive` computed, `MockEthernetMonitor` publishing. Live SCDynamicStore path NOT unit-tested (needs hardware/network config).

## Dev Notes

### Scope boundary
Story 3.1 delivers the monitor + protocol + mock + model only. `AppState` is **untouched** — the dual-monitor sink that consumes `interfacesPublisher` is Story 3.2. UI (`EthernetSection`/`EthernetRow`) is Story 3.3. `StatusItemController` is untouched.

### SCDynamicStoreContext / Unmanaged pattern (architecture.md, PRD 03 normative § "SCDynamicStore C-Callback Context")
`SCDynamicStoreCreate` takes a `SCDynamicStoreContext` whose `info` is an opaque pointer to caller state. We pass `Unmanaged.passUnretained(self).toOpaque()` and supply `retain` / `release` C callbacks that bump and balance the Swift refcount, so the store keeps `self` alive for queue callbacks and releases it when the queue is detached (`SCDynamicStoreSetDispatchQueue(store, nil)` in `stop()`). The `@convention(c)` callback is necessarily `nonisolated`; it recovers `self` via `Unmanaged<EthernetMonitor>.fromOpaque(info).takeUnretainedValue()`.

### Concurrency model — divergence from the doc's normative snippet (deliberate, NFR8-correct)
The PRD 03 normative `handleSCNotification` reads the snapshot on the *calling context* but then mutates `interfaces` inside a `Task { @MainActor }` — and when invoked from `start()` (on MainActor) the SC reads would run on MainActor. To keep **all** SC/CF reads off the MainActor and on the private serial queue (NFR8, architecture.md "never cross with `SCNetworkInterface`"), this implementation splits the flow:

1. `scCallback` (private queue, nonisolated) → `Task { @MainActor } eventSubject.send(())` — pings only; reads nothing from `self`.
2. Debounced sink (300 ms) → `refresh()` on MainActor.
3. `refresh()` dispatches the SC/CF reads onto the **private serial queue** via `withCheckedContinuation { queue.async { cont.resume(returning: enumerate(store:)) } }`, then hops the resulting `[EthernetInterface]` (Sendable) back and calls `ingest()`.

Because the store's callbacks and `refresh()`'s reads both run on the same **serial** queue, an enumeration read cannot race a notification. Only the Sendable value type crosses the actor boundary. The initial `start()` enumeration goes through the same `refresh()` path, so MainActor never touches CF/SC.

### Four-state derivation table (FR16) — pure `interfaceState(hasLink:ipv4:dhcpTimedOut:)`

| hasLink | ipv4    | dhcpTimedOut | state          |
|---------|---------|--------------|----------------|
| false   | (any)   | (any)        | `.noLink`      |
| true    | non-nil | (any)        | `.active`      |
| true    | nil     | false        | `.obtaining`   |
| true    | nil     | true         | `.dhcpTimeout` |

The live path always passes `dhcpTimedOut: false` — the 30 s DHCP-timeout clock lives in the UI layer (PRD 05 Decision #11), so the monitor only ever emits `.active` / `.obtaining` / `.noLink`; the UI re-derives `.dhcpTimeout`. The pure helper takes the flag so the same derivation is reusable and unit-tested for all four states.

### Sendable-extraction rationale
`SCNetworkInterface`, `SCDynamicStore`, and the `CFDictionary`/`CFArray` results of `SCDynamicStoreCopyValue` / `SCNetworkInterfaceCopyMediaOptions` are non-Sendable CF types. They are read exclusively inside `enumerate(store:)` and its `readHasLink`/`readIPv4`/`readLinkSpeedMbps` helpers, all `nonisolated static`, all executed on the private serial queue. The only thing that leaves the queue is `[EthernetInterface]` — a Foundation-only `Sendable` value type. `Network/Models/` imports Foundation only; `SystemConfiguration` is imported solely in `EthernetMonitor.swift` (architecture.md framework-confinement rule).

### Live SC reads
- Interface type filter: `SCNetworkInterfaceGetInterfaceType(iface) == kSCNetworkInterfaceTypeEthernet` excludes lo0, utun* (VPN), bridge*, awdl*, and Wi-Fi.
- `hasLink`: `State:/Network/Interface/<bsd>/Link` → `Active` (Bool).
- `ipv4`: `State:/Network/Interface/<bsd>/IPv4` → `Addresses[0]`.
- `linkSpeedMbps`: `SCNetworkInterfaceCopyMediaOptions(iface, &current, nil, nil, false)` → `kSCPropNetEthernetMediaSubType` string → `megabitsFromSubtype`. Read only when `hasLink` (nil otherwise, per PRD 05 — speed is undefined with no link).

### Equality-guarded `@Published` writes
`ingest()` writes `interfaces` only when the snapshot differs (`if interfaces != snapshot`), mirroring `WiFiMonitor`'s guarded writes, so a no-op SCDynamicStore burst that debounces to an identical snapshot does not retrigger Story 3.2's downstream CombineLatest.

### Spec divergences
1. **Field name `linkSpeedMbps` / `ipv4`** vs. the doc sketch's `linkSpeed` / `ipv4Address`. The model already shipped with `linkSpeedMbps`/`ipv4` (Foundation-only, the `isActive` computed preserves `AppState.computeConnectionMode`); kept as-is to avoid a gratuitous rename across the (existing) model. The `linkSpeedDisplayString` formatter from PRD 05 is a UI concern (Story 3.3), not added here.
2. **Callback splits ping vs. read** (see Concurrency model above) — chosen over the doc's inline-read sketch to guarantee MainActor never performs CF/SC reads. Functionally equivalent re: AC1–AC3; stricter on NFR8.

### Risks needing local build verification (no Xcode on Linux)
- `SCDynamicStoreContext.retain` return type: signature is `(@convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?)?`. The impl returns `UnsafeRawPointer(ptr)`; confirm the Swift importer accepts this (the doc sketch returns `ptr` directly — both should bridge, but verify).
- `SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]` bridging from `CFArray?` — confirm the optional-cast compiles under Swift 6 strict concurrency without an `@unchecked` wrapper.
- `SCDynamicStoreCallBack` typealias shape and `SCDynamicStoreSetNotificationKeys(_, nil, patterns)` (keys nil, patterns array) — verify against the SDK signature.
- `withCheckedContinuation` capturing `store` (a non-Sendable `SCDynamicStore`) into `queue.async`: `store` is a local `let` captured for the duration of one synchronous read; confirm Swift 6 does not flag the capture (it is not stored, not crossed back). If flagged, route via the stored `self.store` read on the queue instead.
- Strict-concurrency clean build of the whole monitor (the C-callback `@convention(c)` static, the `Unmanaged` round-trips).

## File List

- `LinkHub/Network/Models/EthernetInterface.swift` — expanded (ipv4, state, EthernetInterfaceState, computed isActive)
- `LinkHub/Network/EthernetMonitor.swift` — new
- `LinkHub/Network/EthernetMonitorProtocol.swift` — new
- `LinkHub/Network/MockEthernetMonitor.swift` — new
- `LinkHub/Utilities/Logger.swift` — `Log.networkEthernet` category (consistent with existing pattern)
- `LinkHubTests/Network/EthernetMonitorTests.swift` — new (pure derivation + isActive)
- `LinkHubTests/Network/MockEthernetMonitorTests.swift` — new (mock publishing)

## Change Log

| Date       | Change                                                                 |
|------------|------------------------------------------------------------------------|
| 2026-06-09 | Story 3.1 implemented: EthernetInterface expansion, EthernetMonitor (SCDynamicStore + private serial queue + Sendable extraction + 300 ms debounce), protocol, mock, pure-derivation helpers, tests. Status → review. |
| 2026-06-09 | code-review (orchestrator, static Swift-6 audit): verified C-callback recovers self via Unmanaged + Task-hop only; CF/SC reads stay on the private queue; only Sendable [EthernetInterface] crosses to MainActor; stop() detaches the queue (NFR9). Applied fix: refresh() no longer captures the non-Sendable SCDynamicStore into a @Sendable continuation closure — rewritten to queue.async + nonisolated(unsafe) store hand-off. Residual local-build risks (retain-callback pointer optionality, SDK callback signatures, SCNetworkInterfaceCopyAll bridging) logged in release-gate-checklist. Status → done. |
