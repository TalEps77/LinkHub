# PRD 03 — Network Detection & Observation

**Status:** ✅ Done  
**Depends on:** 01  
**Blocks:** 05, 06, 07, 08

---

## Problem Statement

> Which frameworks and APIs will detect and observe Ethernet and Wi-Fi state changes, and
> how will those events be surfaced to the rest of the app?

This PRD decides:

- **Ethernet detection framework** — `SystemConfiguration` (`SCDynamicStore`) vs.
  `Network.framework` (`NWPathMonitor`) vs. `IOKit`; which provides reliable link-state
  detection for wired interfaces including USB-C Ethernet dongles
- **Wi-Fi detection framework** — `CoreWLAN` (`CWWiFiClient`) vs. `NWPathMonitor` vs. a
  combination; which provides SSID, RSSI, security type, and association state
- **Interface enumeration strategy** — how to discover all active Ethernet interfaces at
  launch and when new ones hotplug; whether to enumerate once or maintain a live list
- **Push vs. polling** — event-driven OS callbacks vs. periodic timer; battery/CPU
  trade-offs for a persistent menu bar process
- **Event debounce** — minimum quiet period before publishing upstream; mechanism
  (Combine, Swift concurrency, DispatchWorkItem); where debounce lives
- **Data model** — exact Swift types produced by monitors and consumed by `AppState`;
  value shapes, field names, `Sendable` conformances, file locations
- **Threading and actor isolation** — which queue/actor each callback runs on; how
  results are safely handed off to `@MainActor AppState` under Swift 6 strict concurrency
- **Edge cases** — multiple simultaneous Ethernet adapters; hotplug dongles; VPN tunnel
  interfaces; Wi-Fi disabled; Wi-Fi hardware absent; interfaces "up" but without an IP address

---

## Decision Log

| # | Decision | Options Considered | Choice | Rationale |
|---|-----------|--------------------|--------|-----------|
| 1 | **Ethernet detection framework** | `SCDynamicStore` (SystemConfiguration); `NWPathMonitor` (Network.framework); `IOKit` | **`SCDynamicStore`** | `SCDynamicStore` is the only option that provides: push notifications per interface key, physical link state separate from IP assignment, MAC address via `SCNetworkInterfaceGetHardwareAddressString`, BSD interface name (needed to filter VPNs), and stable support for USB-C dongles (macOS assigns them standard `en*` names). `NWPathMonitor` aggregates all interfaces into a single path object — it cannot distinguish adapter A from adapter B, has no MAC address, and cannot separate link-up from IP-assigned. `IOKit` exposes lower-level hardware events but has no IP-stack integration and adds significant complexity for no benefit over `SCDynamicStore`. |
| 2 | **Ethernet notification model** | `SCDynamicStoreSetDispatchQueue` (push on queue); `SCDynamicStoreScheduleWithRunLoop` (push on run loop); periodic `Timer` poll | **`SCDynamicStoreSetDispatchQueue` with a private serial queue** | Dispatch-queue-based delivery is the modern (`macOS 10.6+`) alternative to run-loop scheduling. A private serial queue avoids run-loop ownership complexity and is straightforward to bridge to `@MainActor` with `Task { @MainActor in ... }`. Polling wastes CPU on a persistent process and introduces latency (a 2-second poll means up to 2-second detection lag). |
| 3 | **Ethernet interface enumeration** | `SCNetworkInterfaceCopyAll()` at launch + re-enumerate on notification; `SCDynamicStoreCopyKeyList` pattern matching | **`SCNetworkInterfaceCopyAll()` on start plus re-enumeration inside every SCDynamicStore callback** | `SCNetworkInterfaceCopyAll()` returns a static snapshot of all known interfaces. Re-enumerating inside the notification callback picks up hotplugged adapters automatically — there is no separate hotplug event to handle. Filtering to `kSCNetworkInterfaceTypeEthernet` excludes VPN tunnels (`utun*`), loopback (`lo0`), and Wi-Fi (`en0` when typed as AirPort). |
| 4 | **Link-state vs. IP-assignment detection** | Watch only IP keys (miss unplugged-but-configured interfaces); watch only Link keys (miss DHCP-assigned vs. static); watch both key patterns | **Watch two regex key patterns: `State:/Network/Interface/[^/]+/Link` and `State:/Network/Interface/[^/]+/IPv4`** | Link keys fire when the physical cable is inserted or removed — before DHCP. IPv4 keys fire when an address is assigned or revoked. Both events matter to LinkHub: `hasLink` (link key) triggers `EthernetSection` visibility in the panel (PRD 05 Decision #2); `isActive` (link + assigned IP) sets `ConnectionMode.ethernetActive` and switches the menu-bar icon. Link-only Ethernet does not change the menu-bar icon. A single key pattern would miss one of these two transitions. |
| 5 | **Wi-Fi framework** | `CoreWLAN` (`CWWiFiClient` + `CWEventDelegate`); `NWPathMonitor`; hybrid | **`CoreWLAN` (`CWWiFiClient`) exclusively** | LinkHub must show SSID, BSSID, RSSI, security type, and a list of nearby networks. `NWPathMonitor` provides none of these — it only reports path satisfiability (reachable / not reachable). `CoreWLAN` is the only public Apple API that exposes the full Wi-Fi control plane on macOS. Hybrid approaches add surface area for no benefit given that `CoreWLAN` already covers every required signal. |
| 6 | **Wi-Fi event delivery** | `CWEventDelegate` push callbacks; periodic scan-and-compare poll; `NWPathMonitor` for quick reachability + CoreWLAN for detail | **`CWEventDelegate` push for connection events; on-demand scan for network list** | `CWEventDelegate` provides push callbacks for: `ssidDidChangeForWiFiInterface(withName:)`, `linkDidChangeForWiFiInterface(withName:)`, `linkQualityDidChangeForWiFiInterface(withName:rssi:transmitRate:)`, `powerStateDidChangeForWiFiInterface(withName:)`. These cover all connection-state changes with zero polling overhead. Network list discovery (for the panel's "available networks" view) is triggered on-demand when the user opens the panel, not on a background timer, to avoid continuous location-permission usage and battery drain (scanning wakes the Wi-Fi radio). |
| 7 | **Debounce interval** | 100 ms; 200 ms; 300 ms; 500 ms | **300 ms** | Ethernet link negotiation and DHCP assignment can fire multiple `SCDynamicStore` keys within 50–200 ms of a cable event. Wi-Fi RSSI delegate callbacks can arrive multiple times per second during active scanning. A 300 ms quiet window absorbs this burst without introducing perceptible UI lag (human perception threshold for "instant" is ~100 ms; 300 ms is still well below the threshold for "slow"). |
| 8 | **Debounce mechanism** | `Combine .debounce(for:scheduler:)`; `DispatchWorkItem` cancel-and-reschedule; `Task.sleep` with structured cancellation | **`Combine .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)`** on a `PassthroughSubject<Void, Never>` inside each monitor | Combine is already the established data-flow layer (PRD 02 uses `@Published` and `AnyCancellable`). Placing debounce on a `PassthroughSubject` keeps the monitors consistent with that pattern. The debounce scheduler is `DispatchQueue.main`, which delivers on the main thread. Under Swift 6 strict concurrency, assigning to `@MainActor`-isolated `@Published` properties from a non-isolated `sink` closure still requires an explicit actor hop — the sink wraps the assignment in `Task { @MainActor [weak self] in ... }` (see Constraints). `DispatchWorkItem` is more verbose and not type-safe. `Task.sleep` requires restructuring the callback call sites. |
| 9 | **Monitor actor isolation** | `@MainActor final class`; `actor`; non-isolated class | **`@MainActor final class` for both `EthernetMonitor` and `WiFiMonitor`** | Both monitors publish into `AppState`, which is `@MainActor`. Making the monitors `@MainActor` themselves means all `@Published` mutations occur on the main actor without any explicit dispatch inside `AppState`. An `actor` would require `await` at every call site in `AppState` and forces `AsyncStream` instead of `@Published`, conflicting with the Combine-based pattern from PRD 02. Non-isolated class would require manual `DispatchQueue.main.async` at every mutation site and is error-prone under Swift 6 strict concurrency. |
| 10 | **SCDynamicStore → MainActor bridge** | `DispatchQueue.main.async { ... }`; `Task { @MainActor in ... }`; `@MainActor.run { ... }` | **`Task { @MainActor in ... }` inside the SCDynamicStore dispatch-queue callback** | The callback performs all `SCNetworkInterface`, `SCDynamicStoreCopyValue`, and `SCNetworkInterfaceCopyMediaOptions` reads on the private serial queue, then captures a fully extracted `[EthernetInterface]` snapshot — a `Sendable` value-type array — before creating the `Task`. No `SCNetworkInterface` or CF object crosses an actor boundary. `DispatchQueue.main.async` is not type-checked by the Swift 6 concurrency model and bypasses actor isolation checks. `MainActor.run` requires an async context; wrapping in `Task` provides that context cleanly. |
| 11 | **CWEventDelegate → MainActor bridge** | Same three options as #10 | **`Task { @MainActor in ... }` in every `CWEventDelegate` method; capture only `String` interface name** | `CWEventDelegate` callbacks arrive on CoreWLAN's private internal thread (not the main thread, not a known queue). Each delegate method must immediately extract the interface name (`String`) — the only `Sendable` value available in the callback signature — and schedule a `Task` that re-reads `CWInterface` properties on the main actor. `CWInterface` itself is not `Sendable` and must never be captured across actor boundaries. |
| 12 | **CWNetwork Sendable handling** | Pass `CWNetwork` objects across actor boundaries using `@unchecked Sendable` wrapper; extract all fields on callback thread before crossing; avoid `CWNetwork` in model types | **Extract all fields from `CWNetwork` on the CoreWLAN callback/scan thread into a `WiFiNetwork` value type before crossing any isolation boundary** | `CWNetwork` is an `NSObject` subclass with no `Sendable` conformance. Wrapping it as `@unchecked Sendable` would suppress safety checks without actually guaranteeing thread safety. Extracting `ssid`, `bssid`, `rssi`, `security`, `captiveNetwork`, etc. into a Swift value struct on the calling thread produces a fully `Sendable` result. The `WiFiNetwork` struct is the canonical model type; `CWNetwork` is an implementation detail confined to `WiFiMonitor`. |
| 13 | **Public API surface** | `@Published` properties (Combine); `AsyncStream`; direct method calls | **`@Published` properties on each `@MainActor` monitor, consumed by `AppState` via `sink`** | `@Published` on `@MainActor` is the pattern established in PRD 02 (`AppState.$connectionMode` drives `StatusItemController`). Consistency matters: PRD 07 defines `AppState` using the same Combine model. `AsyncStream` would require restructuring `AppState` as an `actor` and adds `async`/`await` call sites throughout, breaking PRD 02's synchronous Combine chain. Direct method calls would require `AppState` to poll. |
| 14 | **RSSI update source for connected network** | Use `rssi` value from `linkQualityDidChangeForWiFiInterface(withName:rssi:transmitRate:)` delegate parameter; always re-read from `CWInterface.rssiValue()` | **Use the delegate-supplied `rssi` parameter** | The delegate provides the RSSI value directly in the callback payload — using it avoids an extra `CWInterface` read on the main actor. Full interface state (SSID, BSSID, link, power) is re-read from `CWInterface` only for `ssidDidChange`, `linkDidChange`, and `powerStateDidChange` events. If the delegate value appears inconsistent, the next `requestScan()` or association refresh corrects it. |

---

## Data Model Definitions

All types live in `Network/Models/` per the PRD 01 folder layout. All types are `Sendable`
value types — they cross actor boundaries freely.

### `EthernetInterface.swift`

```swift
/// Snapshot of a single Ethernet adapter's state.
/// Produced by EthernetMonitor, consumed by AppState and UI.
struct EthernetInterface: Identifiable, Equatable, Sendable {

    /// BSD interface name, e.g. "en3". Stable identity for the duration of a session.
    let id: String

    /// Human-readable display name from IOKit / SCNetworkInterface,
    /// e.g. "USB 10/100/1000 LAN" or "Thunderbolt Ethernet Slot 1".
    /// Falls back to `id` if unavailable.
    let displayName: String

    /// True when the interface has a link (cable in) AND an assigned IP address.
    /// Used to compute ConnectionMode in AppState.
    let isActive: Bool

    /// True when the physical cable is inserted, even if DHCP has not yet assigned an IP.
    /// Used to show a "connected, obtaining address…" state in the Ethernet section.
    let hasLink: Bool

    /// Primary IPv4 address, nil until DHCP/manual assignment completes.
    let ipv4Address: String?

    /// Hardware MAC address, formatted as "xx:xx:xx:xx:xx:xx". Nil if unreadable.
    let macAddress: String?

    /// Negotiated link speed in megabits per second (e.g. 100, 1000, 2500, 10000).
    /// Nil when the interface has no link or the speed cannot be determined.
    /// Added in PRD 05 (Decision #1). Read via SCNetworkInterfaceCopyMediaOptions.
    let linkSpeed: Int?
}
```

### `WiFiNetwork.swift`

```swift
/// Snapshot of one visible Wi-Fi network (from scan results or current association).
/// Produced by WiFiMonitor, consumed by AppState and UI.
struct WiFiNetwork: Identifiable, Equatable, Sendable {

    /// Network identity for SwiftUI list diffing. Always non-empty.
    /// Set to BSSID when available; otherwise a composite of ssid and security type
    /// (e.g. "MySSID:wpa2Personal"). The fallback is stable within a single scan result
    /// but may collide across scans. Empty string is never a valid id.
    let id: String

    /// Network SSID. Nil for hidden networks (empty SSID broadcast).
    let ssid: String?

    /// BSSID formatted as "xx:xx:xx:xx:xx:xx". Nil on networks that do not advertise
    /// a BSSID (rare in practice, possible on some hidden networks).
    let bssid: String?

    /// Received signal strength in dBm, e.g. -65.
    /// Typical range: -30 (excellent) to -90 (unusable).
    let rssi: Int

    /// True when this is the currently associated network on the primary Wi-Fi interface.
    let isConnected: Bool

    /// True when the network requires a user passphrase (PSK security).
    /// False for .none (open) and .enterprise (802.1X — no user passphrase;
    /// EAP credentials are configured in System Settings). See PRD 06 Decision #7.
    let requiresPassword: Bool

    /// CoreWLAN security classification, preserved for display and connection logic.
    let security: WiFiSecurity

    /// True when the network is a captive portal requiring sign-in.
    /// Read from CWNetwork.captiveNetwork during scan extraction (PRD 06 Decision #17).
    let isCaptive: Bool
}

/// Simplified security classification derived from CWSecurity.
enum WiFiSecurity: Equatable, Sendable {
    case none          // Open network — requiresPassword = false
    case wpa2Personal  // WPA2-PSK (most common) — requiresPassword = true
    case wpa3Personal  // WPA3-SAE — requiresPassword = true
    case enterprise    // 802.1X (EAP) — requiresPassword = false; connect via
                       // associate(..., password:nil); deeplink to Network Settings
                       // if credentials not configured (PRD 06 Decision #8)
    case other         // WEP, WPA, or unknown — treat as password-required
}
```

> **Extraction note:** `id = bssid ?? "\(ssid ?? "hidden"):\(security)"`. BSSID is
> preferred for cross-scan identity. The composite fallback is stable within a single scan
> result and never empty. All fields must be extracted from `CWNetwork` on the scan thread
> before crossing actor boundaries (Decision #12).

### `NetworkState.swift`

```swift
/// Full snapshot of combined Wi-Fi + Ethernet state.
/// Computed by AppState from EthernetMonitor and WiFiMonitor outputs.
/// Replaces the entire prior state on every update (value semantics).
struct NetworkState: Equatable, Sendable {

    /// Drives the menu bar icon (see PRD 02 icon table).
    let mode: ConnectionMode

    /// All detected Ethernet interfaces.
    /// Sorted: active (isActive) first → link-only (hasLink, no IP) second →
    /// no-link third; BSD name tiebreak within each tier.
    /// Sort contract defined normatively in PRD 05 Decision #8.
    let ethernetInterfaces: [EthernetInterface]

    /// The first interface where isActive == true, nil if none.
    /// Used by EthernetSection in the panel UI.
    let primaryEthernet: EthernetInterface?

    /// Nearby Wi-Fi networks from the most recent scan, sorted by rssi descending.
    let wifiNetworks: [WiFiNetwork]

    /// The currently associated Wi-Fi network, nil if not connected.
    let connectedWifi: WiFiNetwork?

    /// False when the user has turned Wi-Fi off in System Settings (radio disabled).
    /// Used to show an "Enable Wi-Fi" prompt instead of a network list.
    let isWiFiEnabled: Bool

    /// False when no Wi-Fi hardware is present in the system.
    /// Distinct from isWiFiEnabled — UI must not show "Turn on Wi-Fi" in this state.
    /// PRD 07 wireSubscriptions() must include wifiMonitor.$isHardwareAvailable.
    let isWiFiHardwareAvailable: Bool
}

/// Drives the menu bar icon. Defined here (normative); referenced in PRD 02.
enum ConnectionMode: Equatable, Sendable {
    /// ≥1 Ethernet interface is active (has link + IP). Wi-Fi state is irrelevant.
    /// Requires isActive == true on at least one EthernetInterface.
    /// Link-only Ethernet (hasLink, no IP) does NOT set this mode.
    case ethernetActive
    /// Wi-Fi is associated; no active Ethernet interfaces.
    case wifiOnly
    /// Neither Ethernet nor Wi-Fi is active.
    case disconnected
}
```

### `ConnectionMode` computation rule (in `AppState`)

```swift
// AppState.computeConnectionMode() — pseudocode, implemented in PRD 07
private func computeConnectionMode(
    ethernet: [EthernetInterface],
    wifi: WiFiNetwork?
) -> ConnectionMode {
    if ethernet.contains(where: { $0.isActive }) { return .ethernetActive }
    if wifi != nil { return .wifiOnly }
    return .disconnected
}
```

---

## Monitor Class Contracts

These are normative interface definitions. Implementation bodies are written in the first
coding session.

### `EthernetMonitor.swift` (`Network/EthernetMonitor.swift`)

```swift
/// Observes all Ethernet interfaces via SCDynamicStore.
/// Must be created and used on the main actor.
@MainActor
final class EthernetMonitor {

    /// Current snapshot of all detected Ethernet interfaces.
    /// Updated within 300 ms of any link or IP change.
    @Published private(set) var interfaces: [EthernetInterface] = []

    /// Starts SCDynamicStore observation and performs initial enumeration.
    /// Safe to call multiple times; subsequent calls are no-ops.
    func start()

    /// Stops SCDynamicStore observation and clears the interface list.
    func stop()
}
```

**Internal flow:**
```
start() — initial enumeration on MainActor
          │  SCNetworkInterfaceCopyAll() + SCDynamicStoreCopyValue
          ▼
SCDynamicStore registers notification keys (regex patterns) on private serial queue

── per-notification flow ─────────────────────────────────────────────────────────

SCDynamicStore callback fires on private serial queue
          │
          │  SCNetworkInterfaceCopyAll()       ← re-enumerate all Ethernet interfaces
          │  SCDynamicStoreCopyValue(link key) ← read hasLink per interface
          │  SCDynamicStoreCopyValue(IPv4 key) ← read ipv4Address per interface
          │  SCNetworkInterfaceCopyMediaOptions ← read linkSpeed per interface
          │  extract → [EthernetInterface]     ← fully Sendable value snapshot
          │
          │  Task { @MainActor in ... }        ← crosses actor boundary here
          ▼                                        only [EthernetInterface] captured
PassthroughSubject<Void, Never>.send()
          │  (with snapshot captured in Task closure)
          │  .debounce(300ms, scheduler: DispatchQueue.main)
          ▼
sink { [weak self] snapshot in
    Task { @MainActor [weak self] in          ← explicit MainActor hop required
        self?.interfaces = snapshot           ← @Published mutation on MainActor
    }
}
```

### SCDynamicStore C-Callback Context (normative)

```swift
// Inside EthernetMonitor (not shown in class contract above — implementation detail)
// SCDynamicStore requires a C-compatible callback context with retain/release.

private static let scCallback: SCDynamicStoreCallBack = { store, changedKeys, context in
    guard let context else { return }
    let monitor = Unmanaged<EthernetMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.handleSCNotification()
}

func start() {
    var context = SCDynamicStoreContext(
        version: 0,
        info: Unmanaged.passUnretained(self).toOpaque(),
        retain: { ptr in
            guard let ptr else { return nil }
            _ = Unmanaged<EthernetMonitor>.fromOpaque(ptr).retain()
            return ptr
        },
        release: { ptr in
            guard let ptr else { return }
            Unmanaged<EthernetMonitor>.fromOpaque(ptr).release()
        },
        copyDescription: nil
    )
    guard let store = SCDynamicStoreCreate(
        nil,
        "com.linkhub.app" as CFString,
        EthernetMonitor.scCallback,
        &context
    ) else {
        os_log(.error, "Failed to create SCDynamicStore")
        return
    }
    self.store = store  // stored as: private var store: SCDynamicStore?

    let linkPattern  = "State:/Network/Interface/[^/]+/Link"  as CFString
    let ipv4Pattern  = "State:/Network/Interface/[^/]+/IPv4" as CFString
    SCDynamicStoreSetNotificationKeys(store, nil, [linkPattern, ipv4Pattern] as CFArray)
    SCDynamicStoreSetDispatchQueue(store, scQueue)  // private serial queue: DispatchQueue(label: "com.linkhub.sc", qos: .utility)
    
    // Initial enumeration on MainActor (we're already on MainActor since start() is @MainActor)
    handleSCNotification()
}

@MainActor
private func handleSCNotification() {
    // Called from start() on MainActor, and from scCallback via Task { @MainActor in ... }
    let snapshot = buildInterfaceSnapshot()  // reads all SCDynamicStore keys on calling context
    Task { @MainActor [weak self] in
        self?.interfaces = snapshot
    }
}
```

### `WiFiMonitor.swift` (`Network/WiFiMonitor.swift`)

```swift
/// Observes Wi-Fi state via CWWiFiClient and CWEventDelegate.
/// Must be created and used on the main actor.
@MainActor
final class WiFiMonitor: NSObject, CWEventDelegate {

    /// Networks visible in the most recent scan, sorted by RSSI descending.
    @Published private(set) var networks: [WiFiNetwork] = []

    /// Currently associated network, nil if disconnected.
    @Published private(set) var connectedNetwork: WiFiNetwork?

    /// Whether the Wi-Fi radio is powered on. False when the user has disabled Wi-Fi
    /// in System Settings. Also false when isHardwareAvailable == false.
    @Published private(set) var isEnabled: Bool = true

    /// True when a Wi-Fi interface is detected in the system.
    /// False when no Wi-Fi hardware exists. Distinct from isEnabled (radio on/off).
    /// UI must not show "Turn on Wi-Fi" when isHardwareAvailable == false.
    @Published private(set) var isHardwareAvailable: Bool = true

    /// Registers CWEventDelegate events and reads initial association state.
    /// CWWiFiClient.shared() delegate registration must occur on the main actor —
    /// guaranteed by @MainActor. Sets isHardwareAvailable = false and returns early
    /// if CWWiFiClient.shared().interface() returns nil.
    func start()

    /// Unregisters from CWEventDelegate and clears all published state.
    func stop()

    /// Triggers a CoreWLAN scan. Called by the UI layer when the panel opens.
    /// Throws CWError if the scan cannot be performed (e.g., Wi-Fi disabled,
    /// permission denied).
    func requestScan() async throws
}
```

**Internal flow (event callback):**
```
CWEventDelegate method fires on CoreWLAN internal thread
          │  capture: interfaceName: String (Sendable only)
          │  Task { @MainActor in ... }
          ▼
read CWInterface state on MainActor (WiFiMonitor is @MainActor;
CWWiFiClient.shared() was set up on main actor in start())
          │  extract Sendable values: ssid, bssid, rssiValue, security
          ▼
PassthroughSubject<Void, Never>.send()
          │  .debounce(300ms, scheduler: DispatchQueue.main)
          ▼
sink { Task { @MainActor [weak self] in        ← explicit MainActor hop required
    self?.connectedNetwork = <new WiFiNetwork>  ← @Published mutation on MainActor
}}
```

**`requestScan()` flow:**
```swift
// CWInterface.scanForNetworks(withSSID:nil) is synchronous and can take 1–3 s.
// It must NOT be called on the main thread (Apple documentation).
// CWWiFiClient.shared() for delegate registration requires main actor (start());
// for scan access, a fresh CWWiFiClient.shared().interface() call is obtained
// inside Task.detached on the cooperative thread pool.
func requestScan() async throws {
    let rawNetworks: [WiFiNetwork] = try await Task.detached(priority: .userInitiated) {
        // Obtain a fresh interface reference inside the detached task.
        // All CWNetwork property reads (ssid, bssid, rssiValue, security(),
        // captiveNetwork) must occur here — CWNetwork is not Sendable.
        guard let iface = CWWiFiClient.shared().interface() else { return [] }
        let connectedBSSID = iface.bssid()
        return try iface.scanForNetworks(withSSID: nil).map { cwNet in
            WiFiNetwork(
                id:               cwNet.bssid ?? "\(cwNet.ssid ?? "hidden"):\(WiFiSecurity(from: cwNet.security()))",
                ssid:             cwNet.ssid,
                bssid:            cwNet.bssid,
                rssi:             cwNet.rssiValue,
                isConnected:      cwNet.bssid == connectedBSSID,
                requiresPassword: cwNet.security() != .none && cwNet.security() != .enterprise,
                security:         WiFiSecurity(from: cwNet.security()),
                isCaptive:        cwNet.captiveNetwork
            )
        }
        // No CWNetwork or CWInterface reference escapes this closure.
    }.value
    // .value awaits on the caller's actor (MainActor) — assignment is safe.
    self.networks = rawNetworks.sorted { $0.rssi > $1.rssi }
}
```

**`WiFiMonitor.start()` / `stop()` flow:**
```swift
// WiFiMonitor.start() — normative implementation
func start() {
    guard let client = CWWiFiClient.shared(),
          let iface = client.interface() else {
        isHardwareAvailable = false
        isEnabled = false
        return
    }
    isHardwareAvailable = true

    // Read initial power state
    isEnabled = iface.powerOn()

    // Register for push events
    client.delegate = self
    client.startMonitoringEvent(with: .ssidDidChange)
    client.startMonitoringEvent(with: .linkDidChange)
    client.startMonitoringEvent(with: .linkQualityDidChange)
    client.startMonitoringEvent(with: .powerDidChange)

    // Read initial association state (synchronous — runs on MainActor in start())
    if isEnabled, let bssid = iface.bssid() {
        connectedNetwork = WiFiNetwork(
            id: bssid,
            ssid: iface.ssid(),
            bssid: bssid,
            rssi: iface.rssiValue(),
            isConnected: true,
            requiresPassword: false,
            security: WiFiSecurity(from: iface.security()),
            isCaptive: false   // unknown at start; set by next scan
        )
    } else {
        connectedNetwork = nil
    }
}

// WiFiMonitor.stop() — normative
func stop() {
    CWWiFiClient.shared().delegate = nil  // breaks retain cycle (PRD 03 constraint)
    networks = []
    connectedNetwork = nil
}
```

---

## SCDynamicStore Key Patterns

The following are **regex(3) pattern strings** passed to the `patterns:` parameter of
`SCDynamicStoreSetNotificationKeys`. They are not literal keys — the `[^/]+` component
matches any single path segment (interface name such as `en0`, `en3`, `en5`).

```
// Physical link state (cable in / cable out)
State:/Network/Interface/[^/]+/Link

// IPv4 address assignment / revocation
State:/Network/Interface/[^/]+/IPv4
```

Both patterns are registered in a single `SCDynamicStoreSetNotificationKeys` call via the
`patterns:` array argument. The callback fires once per changed key — the debounce absorbs
rapid multi-key bursts from a single physical cable event.

**VPN and loopback filtering:**

```swift
// Inside re-enumeration: keep only hardware Ethernet
let ethernetType = kSCNetworkInterfaceTypeEthernet as String
let interfaces = (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [])
    .filter {
        SCNetworkInterfaceGetInterfaceType($0) as String? == ethernetType
    }
// This excludes: lo0 (loopback), utun* (VPN), bridge*, llw*, awdl*, stf*
```

---

## CWEventDelegate Events Registered

| Event | `CWEventType` constant | Trigger |
|-------|------------------------|---------|
| SSID change | `.ssidDidChange` | Associated to a different network |
| Link change | `.linkDidChange` | Association dropped or established |
| RSSI change | `.linkQualityDidChange` | Signal strength changed significantly |
| Power state | `.powerDidChange` | Wi-Fi turned on or off in System Settings |

`scanCacheUpdated` is intentionally **not** registered — scan results are populated only
by explicit `requestScan()` calls to avoid continuous background radio activity.

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| USB-C Ethernet dongle hotplugged | SCDynamicStore fires on the `Link` key for the new `en*` interface. The re-enumeration in the callback picks it up automatically. |
| USB-C dongle unplugged | Link key fires (link down), IPv4 key fires (address revoked). Both debounce to one update. Interface is removed from the `interfaces` array. |
| Multiple active Ethernet adapters | All are represented in `ethernetInterfaces`. `primaryEthernet` is the first `isActive` one (after three-tier sort). The panel displays all of them (PRD 05 decides the multi-adapter UI). |
| VPN tunnel active | `SCNetworkInterfaceGetInterfaceType` returns a non-Ethernet type. Excluded by the type filter. |
| Ethernet link up, no DHCP yet | `hasLink = true`, `isActive = false`, `ipv4Address = nil`. `ConnectionMode` is **not** `.ethernetActive` — the icon stays at its current state. The panel shows the `EthernetSection` (triggered by `hasLink`) with "Obtaining address…" state. `ConnectionMode.ethernetActive` requires `isActive == true`. |
| Wi-Fi disabled in System Settings | `powerStateDidChangeForWiFiInterface` fires; `CWInterface.powerOn()` returns `false`; `isEnabled = false`, `isHardwareAvailable = true` published. Panel shows "Enable Wi-Fi" control. |
| Wi-Fi scanning while associated | `requestScan()` proceeds normally — CoreWLAN permits scanning while associated. The currently associated network remains in `connectedNetwork` regardless of scan results. |
| Location permission denied | `CWInterface.scanForNetworks(withSSID:nil)` throws `CWError.operationNotPermitted`. `requestScan()` propagates the error to the caller (PRD 06 handles the UI). `connectedNetwork` is still readable without location permission. |
| No Wi-Fi hardware | `CWWiFiClient.shared().interface()` returns `nil` in `start()`. `WiFiMonitor` sets `isHardwareAvailable = false`, `isEnabled = false`, and returns without registering any events. UI must not show "Turn on Wi-Fi" in this state — distinguish via `isHardwareAvailable`. |

---

## Threading Summary

| Component | Runs on | Hops to MainActor via |
|-----------|---------|----------------------|
| `SCDynamicStore` callback | Private serial `DispatchQueue` | `Task { @MainActor in ... }` |
| `CWEventDelegate` methods | CoreWLAN internal thread | `Task { @MainActor in ... }` |
| `requestScan()` heavy work | `Task.detached` (cooperative pool) | `await Task.detached { }.value` returns to caller's actor (MainActor) |
| `@Published` mutations | MainActor (guaranteed) | — |
| Combine `sink` after debounce | DispatchQueue.main (main thread) | `Task { @MainActor [weak self] in ... }` inside the sink |

---

## Constraints

- **`CWWiFiClient.shared()` delegate registration must occur on the main actor:** Calling it
  for event delegate setup off the main actor raises an internal CoreWLAN assertion. The
  `@MainActor` annotation on `WiFiMonitor` guarantees this — `start()` is always called on
  the main actor. For scan access, `CWWiFiClient.shared().interface()` is obtained inside
  `Task.detached` (see `requestScan()` flow above); this is distinct from delegate
  registration.
- **`CWNetwork` is not `Sendable`:** All `CWNetwork` property reads (`ssid`, `bssid`,
  `rssiValue`, `security()`, `captiveNetwork`) must occur before crossing an actor boundary.
  The conversion to `WiFiNetwork` must happen on the thread that received the scan results.
- **`SCNetworkInterface` is not `Sendable`:** Same constraint. All re-enumeration and
  `SCDynamicStoreCopyValue` / `SCNetworkInterfaceCopyMediaOptions` reads happen on the
  private SCDynamicStore serial queue, inside the callback, before the `Task` hop. The
  extracted `[EthernetInterface]` snapshot (Sendable value type) is the only value captured
  by the `Task` closure.
- **CoreWLAN scanning requires location permission (macOS 10.15+):** The app must hold
  "When In Use" location authorization before calling `scanForNetworks`. Denial must be
  handled gracefully (error propagated, not crash). See PRD 08 for the permission flow.
- **`DispatchQueue.main` is not the same as `MainActor`:** The debounce scheduler
  `DispatchQueue.main` delivers events on the main thread/queue, but Swift 6 strict
  concurrency does not automatically consider this equivalent to `MainActor` isolation.
  Assignments to `@MainActor`-isolated `@Published` properties inside a non-isolated `sink`
  closure must be wrapped in `Task { @MainActor [weak self] in ... }` or an explicitly
  `@MainActor`-annotated method. Do not claim `receive(on: DispatchQueue.main)` or
  `.debounce(scheduler: DispatchQueue.main)` alone satisfies Swift 6 actor isolation for
  `@Published` mutation.
- **Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`):** Any type that
  crosses an actor boundary must be `Sendable`. `EthernetInterface`, `WiFiNetwork`,
  `NetworkState`, and `ConnectionMode` are all value types with only `Sendable` stored
  properties — conformance is automatic. No `@unchecked Sendable` wrappers are needed in
  the model layer.
- **`CWEventDelegate` retain cycle risk:** `CWWiFiClient.shared()` holds a strong reference
  to its delegate. `WiFiMonitor` must call `CWWiFiClient.shared().delegate = nil` in
  `stop()` to break the cycle before the monitor is deallocated.
- **SCDynamicStore callback registration uses a C-compatible context:** The
  `SCDynamicStoreCreate` context pointer and `retain`/`release` callbacks must be set
  correctly when using a Swift `self` pointer. Use the established pattern of a
  `SCDynamicStoreContext` with `Unmanaged<EthernetMonitor>` to avoid memory errors.

---

## Out of Scope

- **Wi-Fi scanning cadence / background timer** — LinkHub does not scan on a background
  timer. Scan is triggered by the panel opening (PRD 06). This PRD only decides the
  on-demand API (`requestScan()`).
- **Wi-Fi connect / disconnect / forget operations** — read-only observation is this PRD's
  concern. The write path (association, password prompt, Keychain) is PRD 06.
- **Ethernet toggle (enable/disable interface)** — the control path for toggling an
  Ethernet interface is PRD 05.
- **Link duplex information** (half/full duplex) — not included in `EthernetInterface`.
  `SCNetworkInterfaceCopyMediaOptions` exposes duplex but it is not useful at the panel
  size. Link speed (`linkSpeed: Int?`) is in scope (added by PRD 05 Decision #1).
- **IPv6 addresses** — `EthernetInterface.ipv4Address` stores IPv4 only. IPv6 display is
  deferred; the detection mechanism (additional regex pattern
  `State:/Network/Interface/[^/]+/IPv6`) is identical and can be added in PRD 05 if needed.
- **Captive portal URL extraction** — `WiFiNetwork.isCaptive` is populated from
  `CWNetwork.captiveNetwork`. Extracting the actual portal URL from the network response or
  `NEHotspotHelper` is deferred (PRD 06 handles the portal sign-in UI).
- **VPN-aware routing** — LinkHub shows physical interface state only. Which interface
  carries actual traffic when a VPN is active is not tracked.
- **Bluetooth PAN / hotspot interfaces** — not Ethernet type; excluded by the type filter
  automatically.
- **NWPathMonitor as secondary reachability check** — decided against. `SCDynamicStore` is
  sufficient and authoritative. Adding `NWPathMonitor` would create redundant state.

---

## Open Questions

None for PRD 03. Empirical hardware/API behavior checks are listed under Implementation
Verification below.

---

## Implementation Verification / Acceptance Criteria

- [ ] SCDynamicStore notification patterns use regex(3) syntax (`[^/]+` component) and match
      Link and IPv4 interface keys; no `+` wildcard.
- [ ] Ethernet hotplug publishes `hasLink = true` within the debounce window (≤ 300 ms + OS
      notification latency).
- [ ] DHCP assignment changes `isActive = true` and populates `ipv4Address` in the next
      debounce window.
- [ ] Link-only Ethernet (`hasLink = true`, `isActive = false`) shows the `EthernetSection`
      in the panel but does **not** set `ConnectionMode.ethernetActive`.
- [ ] Active Ethernet (`hasLink = true`, `isActive = true`) sets `ConnectionMode.ethernetActive`
      and switches the menu bar icon.
- [ ] USB Ethernet dongle hotplug and unplug each produce one `EthernetMonitor.$interfaces`
      update (debounce absorbs multi-key burst).
- [ ] VPN / tunnel interfaces (`utun*`, `bridge*`, etc.) are absent from
      `EthernetMonitor.$interfaces`.
- [ ] `WiFiMonitor.isHardwareAvailable == false` is distinguishable from
      `WiFiMonitor.isEnabled == false` (radio off); UI does not show "Turn on Wi-Fi" when
      no hardware exists.
- [ ] Wi-Fi radio disabled (`setPower(false)`) publishes `isEnabled = false`,
      `isHardwareAvailable = true`.
- [ ] Wi-Fi association changes update `connectedNetwork` via `CWEventDelegate` without
      triggering a full scan.
- [ ] `requestScan()` returns only `[WiFiNetwork]` (Sendable) across actor boundaries; no
      `CWNetwork` or `CWInterface` reference escapes `Task.detached`.
- [ ] No `CWNetwork`, `CWInterface`, or `SCNetworkInterface` crosses actor boundaries at any
      point in EthernetMonitor or WiFiMonitor.
- [ ] Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`) compiles clean with
      no `@unchecked Sendable` wrappers in the model layer.

---

## Mock Data Protocol (`#if DEBUG`)

PRD 01 requires that Wi-Fi scanning support a mock data path in Debug builds, since Debug builds have no entitlements and CoreWLAN scanning returns empty results.

### Protocol Definitions

```swift
// Network/WiFiMonitorProtocol.swift
protocol WiFiMonitorProtocol: AnyObject {
    var networks: [WiFiNetwork] { get }
    var networkPublisher: Published<[WiFiNetwork]>.Publisher { get }
    var connectedNetwork: WiFiNetwork? { get }
    var connectedNetworkPublisher: Published<WiFiNetwork?>.Publisher { get }
    var isEnabled: Bool { get }
    var isEnabledPublisher: Published<Bool>.Publisher { get }
    var isHardwareAvailable: Bool { get }
    var isHardwareAvailablePublisher: Published<Bool>.Publisher { get }

    func start()
    func stop()
    func requestScan() async throws
    func connect(to network: WiFiNetwork, password: String?, remember: Bool) async throws
    func connect(ssid: String, security: WiFiSecurity, password: String?, remember: Bool) async throws
    func disconnect() async
}

// WiFiMonitor conforms (retroactively — already has all these methods/properties):
extension WiFiMonitor: WiFiMonitorProtocol {
    var networkPublisher: Published<[WiFiNetwork]>.Publisher { $networks }
    var connectedNetworkPublisher: Published<WiFiNetwork?>.Publisher { $connectedNetwork }
    var isEnabledPublisher: Published<Bool>.Publisher { $isEnabled }
    var isHardwareAvailablePublisher: Published<Bool>.Publisher { $isHardwareAvailable }
}
```

```swift
// Network/MockWiFiMonitor.swift — compiled only in DEBUG builds
#if DEBUG
@MainActor
final class MockWiFiMonitor: WiFiMonitorProtocol {
    @Published var networks: [WiFiNetwork] = MockWiFiMonitor.sampleNetworks
    @Published var connectedNetwork: WiFiNetwork? = MockWiFiMonitor.sampleNetworks.first
    @Published var isEnabled: Bool = true
    @Published var isHardwareAvailable: Bool = true

    var networkPublisher: Published<[WiFiNetwork]>.Publisher { $networks }
    var connectedNetworkPublisher: Published<WiFiNetwork?>.Publisher { $connectedNetwork }
    var isEnabledPublisher: Published<Bool>.Publisher { $isEnabled }
    var isHardwareAvailablePublisher: Published<Bool>.Publisher { $isHardwareAvailable }

    func start() {}
    func stop() {}
    func requestScan() async throws {}
    func connect(to network: WiFiNetwork, password: String?, remember: Bool) async throws {}
    func connect(ssid: String, security: WiFiSecurity, password: String?, remember: Bool) async throws {}
    func disconnect() async {}

    static let sampleNetworks: [WiFiNetwork] = [
        WiFiNetwork(id: "aa:bb:cc:dd:ee:ff", ssid: "HomeNetwork",   bssid: "aa:bb:cc:dd:ee:ff", rssi: -45, isConnected: true,  requiresPassword: true,  security: .wpa2Personal, isCaptive: false),
        WiFiNetwork(id: "11:22:33:44:55:66", ssid: "GuestNetwork",  bssid: "11:22:33:44:55:66", rssi: -65, isConnected: false, requiresPassword: true,  security: .wpa2Personal, isCaptive: false),
        WiFiNetwork(id: "aa:11:bb:22:cc:33", ssid: "CoffeeWifi",    bssid: "aa:11:bb:22:cc:33", rssi: -72, isConnected: false, requiresPassword: false, security: .none,         isCaptive: true),
        WiFiNetwork(id: "de:ad:be:ef:00:01", ssid: "CorpNetwork",   bssid: "de:ad:be:ef:00:01", rssi: -58, isConnected: false, requiresPassword: false, security: .enterprise,   isCaptive: false),
        WiFiNetwork(id: "fe:ed:fa:ce:00:01", ssid: nil,             bssid: "fe:ed:fa:ce:00:01", rssi: -80, isConnected: false, requiresPassword: true,  security: .wpa3Personal, isCaptive: false),
    ]
}
#endif
```

### Injection

`AppState` gains conditional init parameter:

```swift
// State/AppState.swift
init(
    ethernetMonitor: EthernetMonitor = EthernetMonitor(),
    wifiMonitor: any WiFiMonitorProtocol = WiFiMonitor()
) {
    self.ethernetMonitor = ethernetMonitor
    self.wifiMonitor = wifiMonitor
    ...
}
```

For Xcode Previews:
```swift
#if DEBUG
extension AppState {
    static let preview: AppState = AppState(wifiMonitor: MockWiFiMonitor())
}
#endif
```

### File Ownership

| File | Target |
|------|--------|
| `Network/WiFiMonitorProtocol.swift` | App target |
| `Network/MockWiFiMonitor.swift` | App target (`#if DEBUG` wrapped) |

---

## References

- [Apple Developer: SCDynamicStore](https://developer.apple.com/documentation/systemconfiguration/scdynamicstore-gb2) — Push-notification API for network configuration changes.
- [Apple Developer: SCDynamicStoreSetNotificationKeys](https://developer.apple.com/documentation/systemconfiguration/1517052-scdynamicstoresetnotificationkey) — `keys:` for literal keys; `patterns:` for regex(3) pattern strings.
- [Apple Developer: SCDynamicStoreSetDispatchQueue](https://developer.apple.com/documentation/systemconfiguration/1517088-scdynamicstoresetdispatchqueue) — Modern dispatch-queue-based delivery; avoids CFRunLoop integration.
- [Apple Developer: SCNetworkInterface](https://developer.apple.com/documentation/systemconfiguration/scnetworkinterface) — `SCNetworkInterfaceCopyAll()`, `SCNetworkInterfaceGetInterfaceType()`, `SCNetworkInterfaceGetHardwareAddressString()`.
- [Apple Developer: CoreWLAN framework](https://developer.apple.com/documentation/corewlan) — `CWWiFiClient`, `CWInterface`, `CWNetwork`, `CWEventDelegate`.
- [Apple Developer: CWEventDelegate](https://developer.apple.com/documentation/corewlan/cweventdelegate) — Push-notification delegate for Wi-Fi state changes; callback thread is unspecified.
- [Apple Developer: CWInterface — scanForNetworks(withSSID:)](https://developer.apple.com/documentation/corewlan/cwinterface/1413273-scanfornetworks) — Synchronous scan; must not be called on the main thread.
- [Apple Developer: NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor) — Excluded from LinkHub; documented here to record the decision against it.
- [WWDC 2022: Meet Swift Async Algorithms (session 110355)](https://developer.apple.com/videos/play/wwdc2022/110355/) — Debounce patterns in Swift Concurrency; informed the Combine `.debounce` vs. `AsyncStream` decision.
- [WWDC 2023: Beyond the basics of structured concurrency (session 10170)](https://developer.apple.com/videos/play/wwdc2023/10170/) — `Task { @MainActor in ... }` pattern for bridging non-actor callbacks.
- [WWDC 2024: Migrate your app to Swift 6 (session 10169)](https://developer.apple.com/videos/play/wwdc2024/10169/) — `Sendable` conformance for value types; `@unchecked Sendable` guidance; C-callback bridging; `DispatchQueue.main` vs. `MainActor` isolation.
- [Swift.org: Swift 6 Concurrency Migration Guide](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/) — Handling `SCDynamicStore` C-callback context with `Unmanaged<T>`; actor isolation for `@Published` mutations.
