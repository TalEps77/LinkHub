# PRD 03 — Network Detection & Observation

**Status:** ✅ Done  
**Depends on:** 01  
**Blocks:** 05, 06, 07, 08

---

## Problem Statement

> Which frameworks and APIs will detect and observe Ethernet and Wi-Fi state changes, and
> how will those events be surfaced to the rest of the app?

This PRD must decide:

- **Ethernet detection framework** — `SystemConfiguration` (`SCDynamicStore` /
  `SCNetworkReachability`) vs. `Network.framework` (`NWPathMonitor`) vs.
  `IOKit`; which provides reliable link-state (up/down) detection for wired
  interfaces including USB-C Ethernet dongles
- **Wi-Fi detection framework** — `CoreWLAN` (`CWWiFiClient`) vs.
  `Network.framework` (`NWPathMonitor`) vs. a combination; which provides SSID,
  RSSI, security type, and association state without requiring undocumented APIs
- **Interface enumeration strategy** — how to discover all active Ethernet
  interfaces at launch and when new ones appear (e.g., dongles hotplugged);
  whether to enumerate once or maintain a live list
- **Push vs. polling** — whether each monitor registers for OS-pushed
  notifications (SCDynamicStore keys, CWEventDelegate) or polls on a timer;
  hybrid strategies; battery/CPU cost trade-offs for a persistent menu bar app
- **Event debounce** — minimum quiet period before publishing a state change
  upstream; where debounce lives (inside the monitor or in AppState); which
  debounce primitive to use (Combine `.debounce`, `Task.sleep`, serial queue)
- **Data model** — the exact types (`EthernetInterface`, `WiFiNetwork`,
  `NetworkState`, `ConnectionMode`) that monitors produce and `AppState`
  consumes; value-type shapes, field names, and `Sendable` conformances; where
  these types live in the PRD 01 folder layout
- **Threading and actor isolation** — which queue/actor each monitor's callback
  runs on; how results are safely handed off to `@MainActor AppState` under
  Swift 6 strict concurrency
- **Edge cases** — multiple simultaneous Ethernet adapters; USB-C dongles
  appearing/disappearing; VPN tunnel interfaces that masquerade as Ethernet;
  Wi-Fi disabled in System Settings; airplane-mode-like scenarios; interfaces
  that are "up" but have no IP address

---

## Decision Log

| # | Decision | Options Considered | Choice | Rationale |
|---|----------|--------------------|--------|-----------|
| 1 | Ethernet detection framework | `SCDynamicStore`, `NWPathMonitor`, `IOKit` | **`SCDynamicStore`** | Only option with Layer-2 link-state visibility before DHCP negotiation. Fires immediately on physical cable plug/unplug and USB-C dongle hotplug. Not deprecated on macOS 13+. `SCNetworkReachability` (same framework) is deprecated as of macOS 14.4 — not used. |
| 2 | Wi-Fi detection framework | `CWWiFiClient`, `NWPathMonitor`, combination | **`CWWiFiClient` (primary)** | Only public API supplying SSID, BSSID, RSSI, and security type via documented interfaces. `NWPathMonitor` cannot surface per-network details; added only as a future fallback safety net if needed. |
| 3 | Interface enumeration strategy | Once-at-launch, live polling, SCDynamicStore wildcard subscription | **SCDynamicStore wildcard subscription (live list)** | Subscribing to `State:/Network/Interface` pattern gives push notification when interfaces appear or disappear. Re-enumerate the full list on every callback — no extra bookkeeping required. |
| 4 | Push vs. polling | Pure push, pure polling, hybrid | **Pure push** | Menu bar app runs 24/7; even 1 Hz polling wastes CPU/battery for zero benefit. SCDynamicStore and `CWEventDelegate` deliver sub-second push notifications. RSSI is the sole exception: read on-demand when the panel opens rather than subscribing to the high-frequency `linkQualityDidChange` event. |
| 5 | Event debounce location | Inside monitor, inside AppState, shared utility | **Inside each monitor** | Monitors own their signal pipeline end-to-end. AppState remains a dumb consumer that only performs MainActor-safe writes. |
| 6 | Debounce primitive | Combine `.debounce`, `Task.sleep`, `DispatchWorkItem` cancellation | **Combine `.debounce(for: .milliseconds(300), scheduler: monitorQueue)`** | Compose naturally with the `PassthroughSubject` pipeline already used for push events. Chain `.removeDuplicates()` after debounce to discard no-op callbacks. |
| 7 | Debounce window | 100 ms, 300 ms, 500 ms | **300 ms** | Link state oscillates 10–20×/s during a plug/unplug transition. 300 ms eliminates ≥99% of noise while keeping UI update latency below perception threshold (~500 ms). |
| 8 | Data model value types | Various struct/enum shapes | **See Data Model section** | All model types are `struct` or `enum`, `Sendable`, `Equatable`. Fields designed for the display needs documented in PRDs 05 and 06. |
| 9 | Threading model | @MainActor monitors, actor-isolated monitors, serial-queue monitors | **Serial-queue monitors + MainActor AppState** | `CWWiFiClient` and `SCDynamicStore` are ObjC types with no Sendable guarantee; they must live on a stable thread. Each monitor owns one serial `DispatchQueue`; Combine's `.receive(on: DispatchQueue.main)` hops to the main thread before AppState writes. |
| 10 | VPN / tunnel exclusion | IOKit device class, name prefix, SCNetworkInterface type check | **Name-prefix filter** | Prefixes `lo`, `utun`, `awdl`, `bridge`, `llw`, `anpi`, `ipsec` reliably identify non-Ethernet interfaces. Cross-confirm with `SCNetworkInterfaceGetInterfaceType() == kSCNetworkInterfaceTypeEthernet` for any ambiguous name. |

---

## Data Model

All types live in `LinkHub/Network/Models/` as specified in PRD 01.

### `EthernetInterface.swift`

```swift
/// A snapshot of one physical Ethernet interface at a point in time.
struct EthernetInterface: Identifiable, Equatable, Hashable, Sendable {
    /// BSD interface name; stable for the lifetime of the interface (e.g. "en0", "en2").
    let id: String
    /// Human-readable name from SCNetworkInterfaceGetLocalizedDisplayName,
    /// e.g. "USB 10/100/1000 LAN", "Thunderbolt Ethernet". Falls back to `id`.
    let displayName: String
    /// True when the physical link layer reports a connected peer (cable plugged in,
    /// dongle connected). Independent of whether an IP address has been assigned.
    var isLinkUp: Bool
    /// Primary IPv4 address, if DHCP has completed or a static address is configured.
    var ipv4Address: String?
    /// Primary IPv6 address, if configured.
    var ipv6Address: String?
    /// MAC address string in colon-separated hex (aa:bb:cc:dd:ee:ff), if readable.
    var macAddress: String?
}
```

### `WiFiNetwork.swift`

```swift
/// Association state of the Wi-Fi subsystem at a point in time.
enum WiFiStatus: Equatable, Sendable {
    /// Wi-Fi hardware is disabled in System Settings (power state off).
    case disabled
    /// Wi-Fi is powered on but not associated with any network.
    case notAssociated
    /// Wi-Fi is associated; carries per-network details.
    case associated(network: WiFiNetwork)
}

/// A snapshot of the currently associated Wi-Fi network.
struct WiFiNetwork: Equatable, Hashable, Sendable {
    /// Network name. Nil when location permission has not been granted (macOS 14+).
    let ssid: String?
    /// BSSID of the access point (MAC address of the AP radio).
    let bssid: String?
    /// Received signal strength in dBm (e.g. -65). Populated on-demand when
    /// the panel is open; stale value is –∞ (Int.min) before first read.
    var rssi: Int
    /// Security protocol in use.
    let security: WiFiSecurity
    /// BSD interface name, typically "en0".
    let interfaceName: String
}

/// Security classification exposed in the UI.
enum WiFiSecurity: String, Equatable, Sendable {
    case open
    case wep
    case wpaPersonal
    case wpa2Personal
    case wpa3Personal
    case enterprise
    case unknown
}
```

### `NetworkState.swift`

```swift
/// Complete snapshot of network state consumed by AppState.
/// ConnectionMode is defined here (established in PRD 02).
struct NetworkState: Equatable, Sendable {
    var ethernet: [EthernetInterface]
    var wifi: WiFiStatus

    /// Derived from ethernet and wifi; not stored separately.
    var connectionMode: ConnectionMode {
        if ethernet.contains(where: { $0.isLinkUp }) { return .ethernetActive }
        if case .associated = wifi { return .wifiOnly }
        return .disconnected
    }
}

/// Icon and accessibility state for the menu bar status item. Defined in PRD 02.
enum ConnectionMode: Equatable, Sendable {
    case ethernetActive   // ≥1 Ethernet interface has link
    case wifiOnly         // Wi-Fi associated, no active Ethernet
    case disconnected     // Neither active
}
```

---

## Monitor Architecture

### `EthernetMonitor.swift` (`LinkHub/Network/`)

```
Responsibilities
  ├── Create SCDynamicStoreRef with CFRunLoop source on `ethernetQueue`
  ├── Subscribe to pattern: State:/Network/Interface/.*/Link
  ├── On callback: re-enumerate Ethernet interfaces (name-prefix filter + type check)
  ├── Read link state, IP, MAC for each interface via SCDynamicStoreCopyValue
  ├── Publish [EthernetInterface] via PassthroughSubject
  └── Apply .debounce(300ms) + .removeDuplicates() before exposing publisher

Public interface
  var ethernetPublisher: AnyPublisher<[EthernetInterface], Never>
  func start()   // registers SCDynamicStore keys, starts CFRunLoop source
  func stop()    // invalidates CFRunLoop source, cancels subscriptions
```

### `WiFiMonitor.swift` (`LinkHub/Network/`)

```
Responsibilities
  ├── Obtain CWWiFiClient.shared() on `wifiQueue`
  ├── Register self as CWEventDelegate for:
  │     ssidDidChange, bssidDidChange, powerStateDidChange
  ├── On each delegate event: read CWInterface properties on `wifiQueue`
  ├── Map to WiFiStatus enum value
  ├── Publish WiFiStatus via PassthroughSubject
  ├── Apply .debounce(300ms) + .removeDuplicates() before exposing publisher
  └── Expose readRSSI() → Int for on-demand panel refresh

Public interface
  var wifiPublisher: AnyPublisher<WiFiStatus, Never>
  func readRSSI() -> Int   // synchronous; call only from wifiQueue or with explicit hop
  func start()
  func stop()
```

### Threading diagram

```
SCDynamicStore CFRunLoop source
  │  (fires on ethernetQueue serial thread)
  ▼
EthernetMonitor.callback()
  → PassthroughSubject<[EthernetInterface]>.send(...)
  → .debounce(300ms, scheduler: ethernetQueue)
  → .removeDuplicates()
  → .receive(on: DispatchQueue.main)          ← hop to main thread
  → AppState.updateEthernet(_:)               ← @MainActor write

CWEventDelegate callback
  │  (fires on undefined background thread)
  ▼
WiFiMonitor.ssidDidChange(...)
  → DispatchQueue("com.linkhub.wifi").async { read CWInterface }
  → PassthroughSubject<WiFiStatus>.send(...)
  → .debounce(300ms, scheduler: wifiQueue)
  → .removeDuplicates()
  → .receive(on: DispatchQueue.main)          ← hop to main thread
  → AppState.updateWifi(_:)                   ← @MainActor write
```

---

## Swift 6 Concurrency Notes

- `EthernetMonitor` and `WiFiMonitor` are `final class` with no actor annotation. Internal
  mutable state is protected by their respective serial `DispatchQueue`s.
- `CWWiFiClient` and `CWInterface` are ObjC types without `Sendable` conformance. They are
  stored as `nonisolated(unsafe) let` within `WiFiMonitor` and never passed across actor
  boundaries. Only Swift value types (`WiFiStatus`, `WiFiNetwork`) cross the queue boundary.
- `SCDynamicStoreRef` is a CFTypeRef (opaque pointer) and is also captured as
  `nonisolated(unsafe)` within `EthernetMonitor` for the same reason.
- `AppState` is `@MainActor final class ObservableObject`. Both monitors reach it via
  the Combine `.receive(on: DispatchQueue.main)` hop — no `Task { await MainActor.run { } }`
  nesting required.
- All published model types (`EthernetInterface`, `WiFiStatus`, `WiFiNetwork`, `NetworkState`,
  `WiFiSecurity`, `ConnectionMode`) are `Sendable` struct/enum values — safe to cross any
  isolation boundary.

---

## Edge Case Handling

| Scenario | Handling |
|----------|----------|
| Multiple Ethernet adapters simultaneously | `EthernetMonitor` emits `[EthernetInterface]` (array). `connectionMode` = `.ethernetActive` if `ethernet.contains { $0.isLinkUp }`. PRD 05 decides display order. |
| USB-C dongle hotplug | SCDynamicStore wildcard fires when kernel creates `State:/Network/Interface/enN/Link`. Re-enumerate full list; new `EthernetInterface` added to array. |
| USB-C dongle unplug | Key disappears from SCDynamicStore key list; interface removed from array. |
| VPN tunnel (utun*) | Excluded by name-prefix filter at enumeration time. Never appears in `[EthernetInterface]`. |
| Wi-Fi disabled in System Settings | `powerStateDidChangeForWiFiInterfaceWithName` fires → `WiFiStatus.disabled` → `connectionMode` re-evaluated. |
| Interface link-up, no IP address yet | `EthernetInterface.isLinkUp = true`, `ipv4Address = nil`. Counts as `ethernetActive`. PRD 05 decides UI treatment ("Obtaining IP…"). |
| SSID unavailable (no location permission) | `WiFiNetwork.ssid = nil`. UI (PRD 06) shows "Connected" without name. Full entitlement/permission flow owned by PRD 08. |
| Both Ethernet and Wi-Fi active | `connectionMode = .ethernetActive` (Ethernet priority established in PRD 02 icon contract). |
| AWDL / peer-to-peer interfaces (awdl0, llw0) | Excluded by name-prefix filter. |

---

## Constraints

- **macOS 13.0 minimum** (Ventura): all APIs used (`SCDynamicStore`, `CWWiFiClient`,
  `NWPathMonitor`) are fully supported and stable on this target.
- **SCNetworkReachability is NOT used**: deprecated as of macOS 14.4 / iOS 17.4.
- **CoreWLAN SSID privacy (macOS 14+)**: `CWInterface.ssid()` returns `nil` if the app
  lacks location permission. This is a privacy enforcement change in Sonoma; not a bug.
  Apps distributed via the Mac App Store require `com.apple.developer.networking.wifi-info`
  entitlement; distribution channel and entitlement strategy are deferred to PRD 08.
- **CWWiFiClient thread safety**: Apple's documentation makes no thread-safety guarantee.
  All `CWWiFiClient` and `CWInterface` access is confined to `wifiQueue` (serial).
- **SCDynamicStore CFRunLoop requirement**: the store's run-loop source must be scheduled on
  an active CFRunLoop. `EthernetMonitor` creates its own serial `DispatchQueue` and uses
  `SCDynamicStoreSetDispatchQueue` (available macOS 10.6+) to avoid raw CFRunLoop management.
- **Swift 6 strict concurrency**: no `@preconcurrency` suppressions in new code; ObjC types
  confined to their owning queue via `nonisolated(unsafe)`.
- **Sandboxing**: `SCDynamicStore` and `CoreWLAN` work under the hardened runtime but are
  restricted in the full App Sandbox. Distribution channel decision (PRD 09) will determine
  whether sandbox entitlements are needed.

---

## Out of Scope

- **Wi-Fi scanning** (listing nearby networks) — owned by PRD 06.
- **Connect / disconnect / forget network** flows — owned by PRD 06.
- **Keychain credential storage** — owned by PRD 06 / Services layer.
- **IP configuration changes** (static IP, DNS) — out of LinkHub scope entirely.
- **Bluetooth PAN and cellular** interfaces — not relevant to the product.
- **NWPathMonitor** as active path: retained in the design space for PRD 07 if a simple
  "is any network reachable?" signal is needed, but not used by the monitors in this PRD.
- **RSSI continuous subscription** — `linkQualityDidChange` events are not subscribed;
  RSSI is read on-demand. Continuous RSSI tracking (e.g., animated signal bars) is a PRD 06
  decision.
- **Login-item auto-start** — PRD 09.
- **Entitlement request to Apple** (`com.apple.developer.networking.wifi-info`) — PRD 08.

---

## Open Questions

| # | Question | Owner PRD |
|---|----------|-----------|
| 1 | Should `AppState` store the full `NetworkState` struct or keep `ethernet` and `wifi` as separate `@Published` properties? Struct is cleaner; separate properties let SwiftUI views observe only what they need. | PRD 07 |
| 2 | If `CWWiFiClient.shared()` returns nil (theoretically possible on hardware with no Wi-Fi), how should `WiFiMonitor` signal permanent failure vs. transient disabled state? | PRD 07 |
| 3 | Does the `com.apple.developer.networking.wifi-info` entitlement require a Mac App Store build, or is it also available for Developer ID distribution? | PRD 08 |
| 4 | Should RSSI reads use `CWInterface.rssiValue()` (integer dBm) or `CWInterface.noiseMeasurement()` to calculate SNR for a richer signal quality indicator? | PRD 06 |

---

## References

- [SCDynamicStore — Apple Developer Documentation](https://developer.apple.com/documentation/systemconfiguration/scdynamicstore-gb2)
- [SCDynamicStoreSetDispatchQueue — Apple Developer Documentation](https://developer.apple.com/documentation/systemconfiguration/1437625-scdynamicstoresetdispatchqueue)
- [CWWiFiClient — Apple Developer Documentation](https://developer.apple.com/documentation/corewlan/cwwificlient)
- [CWEventDelegate — Apple Developer Documentation](https://developer.apple.com/documentation/corewlan/cweventdelegate)
- [CWInterface — Apple Developer Documentation](https://developer.apple.com/documentation/corewlan/cwinterface)
- [NWPathMonitor — Apple Developer Documentation](https://developer.apple.com/documentation/network/nwpathmonitor)
- [SCNetworkReachability deprecation — macOS 14.4 release notes](https://developer.apple.com/tutorials/data/documentation/macos-release-notes/macos-14_4-release-notes.json)
- [Adopting Swift 6 — Apple Developer Documentation](https://developer.apple.com/documentation/swift/adoptingswift6)
- [WWDC 2019 — Advances in Networking, Part 1 (NWPathMonitor)](https://developer.apple.com/videos/play/wwdc2019/712/)
- [WWDC 2018 — Introducing Network.framework](https://developer.apple.com/videos/play/wwdc2018/715/)
- [Technical Note TN3179 — Understanding Local Network Privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
