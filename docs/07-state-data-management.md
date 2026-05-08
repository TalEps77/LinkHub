# PRD 07 — State & Data Management

**Status:** ✅ Done  
**Depends on:** 03, 05, 06  
**Blocks:** —

---

## Problem Statement

> How is app-wide network state modeled, how do the detection monitors publish into shared
> state, what is the concurrency model, and what (if anything) needs to be persisted?

This PRD decides:

- **AppState concurrency model** — `@Observable` (macOS 14+) vs. `@MainActor
  ObservableObject` with `@Published` (macOS 13 compatible)
- **AppState creation site and lifetime** — where the single instance is created and
  how long it lives
- **RootPanelView injection** — `@EnvironmentObject` vs. `@ObservedObject` prop-drilling
  (resolves PRD 04 Open Question 1)
- **Monitor ↔ AppState wiring** — how `EthernetMonitor` and `WiFiMonitor` feed into
  `AppState`; where `AnyCancellable` tokens are stored; when monitors are started
- **`NetworkState` computation** — stored `@Published` property (updated via Combine sink)
  vs. computed property (recomputed on every access)
- **`ConnectionMode` on `AppState`** — separate `@Published` property vs. derived from
  `networkState` inline in `StatusItemController`
- **Persistence** — what (if anything) survives process restart; what stays transient
- **Memory and CPU budget** — steady-state limits for a 24/7 menu bar process

---

## Decision Log

| # | Decision | Options Considered | Choice | Rationale |
|---|----------|--------------------|--------|-----------|
| 1 | **AppState concurrency model** | `@Observable` macro (macOS 14+); `@MainActor ObservableObject` + `@Published` | **`@MainActor final class AppState: ObservableObject`** with `@Published` properties | PRD 01 locked the deployment target at macOS 13 (Ventura). `@Observable` is only available on macOS 14+; adopting it would require raising the minimum OS version and excluding a significant portion of the Ventura fleet. `ObservableObject` + `@Published` is fully supported on macOS 13, integrates directly with the Combine-based pattern already established in PRDs 02 and 03 (`AppState.$connectionMode`, `AnyCancellable`), and imposes no migration risk. |
| 2 | **AppState creation site** | `@main App` struct; `AppDelegate.applicationDidFinishLaunching` | **`AppDelegate.applicationDidFinishLaunching`** — `let appState = AppState()` stored as a property on `AppDelegate` | PRD 01 chose the `NSApplicationDelegate` pattern; there is no SwiftUI `@main App` struct. `AppDelegate` is the natural owner — it is the first point in the lifecycle where app-wide objects are created and it holds a strong reference for the process lifetime. Creating `AppState` here keeps the creation order explicit: `AppState` → `StatusItemController(appState:)` → `appState.startMonitors()`. |
| 3 | **RootPanelView injection (PRD 04 Q1)** | `@EnvironmentObject` injected at `NSHostingController` creation; `@ObservedObject` passed as constructor argument, prop-drilled to child views | **`@EnvironmentObject`** — `appState` injected via `.environmentObject(appState)` on the root view at `NSHostingController` creation | `EthernetSection` and `WiFiSection` are both direct consumers of `AppState` (network list, connection state, Wi-Fi toggle, location denial flag). Prop-drilling `appState` through `RootPanelView` to both child views adds constructor boilerplate with no benefit. `@EnvironmentObject` is the SwiftUI-idiomatic solution for shared mutable state that multiple levels of the view hierarchy read. The single injection point — `NSHostingController(rootView: RootPanelView().environmentObject(appState))` — is explicit and testable. |
| 4 | **`NetworkState` property type** | Computed property (recomputed on every SwiftUI access); stored `@Published` (updated via Combine sink when monitors publish) | **Stored `@Published var networkState: NetworkState`**, rebuilt atomically in one Combine sink each time either monitor publishes | A computed property would reconstruct the full `NetworkState` struct on every SwiftUI body evaluation — potentially dozens of times per second during a scan. A stored `@Published` property is rebuilt exactly once per monitor event (after debounce). SwiftUI diffing then decides whether to re-render based on `NetworkState.Equatable` conformance. The stored approach also allows `StatusItemController` and other non-SwiftUI consumers to subscribe via Combine without fighting SwiftUI's rendering cycle. |
| 5 | **`connectionMode` on `AppState`** | Separate `@Published var connectionMode: ConnectionMode`; derive inline in `StatusItemController` via `$networkState.map(\.mode)` | **Separate `@Published var connectionMode: ConnectionMode`** | PRD 02 Decision #14 overrides the naïve reading: `StatusItemController` actually subscribes to `AppState.$networkState` (not `$connectionMode`), because it needs `networkState.connectedWifi.ssid` and `networkState.primaryEthernet` to build accessibility labels and tooltips. `connectionMode` is still maintained as a separate `@Published var` (always equal to `networkState.mode`, updated atomically in the same sink) for any future subscriber that only needs the enum. The minor duplication is intentional: `networkState` is the primary data payload for UI consumers; `connectionMode` is a convenience publisher reserved for future use. |
| 6 | **Monitor wiring mechanism** | Combine `Publishers.CombineLatest`; separate `sink` per monitor; `AsyncStream`-based merge | **`Publishers.CombineLatest` on `EthernetMonitor.$interfaces` and a merged WiFiMonitor publisher**, single `sink` that rebuilds `networkState` and `connectionMode` atomically | A single combined sink ensures `networkState` is always rebuilt from a consistent, simultaneous snapshot of both monitors — there is no window where Ethernet has updated but Wi-Fi has not. `CombineLatest` fires immediately when either upstream publishes, which is correct: a cable event or Wi-Fi connection change should update the state promptly without waiting for the other monitor to also fire. |
| 7 | **`AnyCancellable` storage** | `Set<AnyCancellable>` on `AppState`; stored on `AppDelegate`; stored on each controller | **`Set<AnyCancellable>` on `AppState`** | The subscriptions encode the `AppState ← monitor` wiring relationship; they belong with the subscriber (`AppState`). Storing them on `AppDelegate` would scatter the ownership model. Cancellation happens in `stopMonitors()`, called from `AppDelegate.applicationWillTerminate(_:)` via `appState.stopMonitors()`. |
| 8 | **Monitor start timing** | Immediately in `AppState.init()`; `AppDelegate.applicationDidFinishLaunching`; lazily on first panel open | **`appState.startMonitors()`** called from `AppDelegate.applicationDidFinishLaunching(_:)` after `StatusItemController` is created | Starting in `init()` means monitors fire before `StatusItemController` has subscribed — the first state event is lost. Starting after `StatusItemController` construction guarantees the Combine chain is fully wired before the first monitor event arrives. Lazy start on panel open would leave the menu bar icon in the wrong state until the user first clicks. |
| 9 | **`primaryEthernet` derivation** | Stored on `NetworkState`; computed on demand in the UI | **Stored as `let primaryEthernet: EthernetInterface?` on `NetworkState`**, set to `interfaces.first(where: { $0.isActive })` on the list that is already sorted by BSD name ascending | BSD name sort (`en0 < en3 < en5`) is deterministic and stable across reboots for a given set of adapters. Sorting once at construction time (inside the `AppState` sink) is cheaper than sorting on every UI access. `primaryEthernet` being nil-able cleanly expresses "no active Ethernet" without requiring the UI to filter the array. |
| 10 | **Persistence scope** | Persist nothing (fully ephemeral); persist last SSID + preferences; persist full network state snapshot | **Persist `launchAtLogin: Bool` only**, via `UserDefaults`; all network state is transient | Network state (interfaces, SSID, RSSI, networks list) reflects physical reality — persisting it would only display stale data before the first monitor event, which arrives within milliseconds of app launch. Last SSID is already available from `WiFiMonitor.connectedNetwork` immediately after `start()` reads the current CoreWLAN association state; no cache is needed. `launchAtLogin` is the only preference that must survive restarts. |
| 11 | **`wifiLocationDenied` property** | On `AppState` as `@Published`; on `WiFiMonitor` only; passed as error to the UI | **`@Published var wifiLocationDenied: Bool = false` on `AppState`** | PRD 08 specifies this flag as an `AppState` property set by `WiFiMonitor` when `CLAuthorizationStatus == .denied`. Placing it on `AppState` makes it directly readable by `WiFiSection` via `@EnvironmentObject` — no additional plumbing needed. `WiFiMonitor` sets it via a direct assignment on the main actor after the authorization check. |
| 12 | **Memory budget** | 20 MB; 30 MB; 50 MB | **30 MB steady-state maximum** | A pure menu bar app with no windows, no video, and no large assets has a natural footprint well under 20 MB in steady state. The 30 MB ceiling is a conservative bound that accommodates CoreWLAN's internal scan cache, the `NSPopover` view hierarchy when the panel is open, and os.log's in-process ring buffer. Exceeding 30 MB with the panel closed indicates a leak and should trigger investigation. |
| 13 | **Background CPU** | Allow periodic polling; near-zero (event-driven only) | **Near-zero (~0%) with panel closed** — confirmed by architecture: no `Timer`, no `DispatchSourceTimer`, no `Task.sleep` loops anywhere in the monitor or state layer | SCDynamicStore and CoreWLAN both use push callbacks. The app sleeps until the OS delivers an event. This is critical for a process that runs 24/7 and must not drain laptop battery. Any future change that introduces a background timer must be explicitly justified in a PRD. |

---

## `AppState` Class Definition (normative)

File: `State/AppState.swift`

```swift
import Combine
import Foundation

/// Central observable state for the app.
/// All properties are published on the main actor.
/// Created once by AppDelegate; lifetime equals the process lifetime.
@MainActor
final class AppState: ObservableObject {

    // MARK: — Published network state

    /// Full snapshot of combined Ethernet + Wi-Fi state.
    /// Rebuilt atomically each time either monitor publishes (after 300 ms debounce).
    @Published private(set) var networkState: NetworkState = .empty

    /// The current connection mode — drives the StatusItemController icon.
    /// Always equals networkState.mode; kept as a separate @Published to honour
    /// the normative PRD 02 contract (AppState.$connectionMode).
    @Published private(set) var connectionMode: ConnectionMode = .disconnected

    /// True when CoreLocation authorization is denied and Wi-Fi scanning is unavailable.
    /// Set by WiFiMonitor; consumed by WiFiSection via @EnvironmentObject.
    @Published var wifiLocationDenied: Bool = false

    // MARK: — Persistence

    /// Whether the app is registered as a login item. Persisted to UserDefaults.
    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    // MARK: — Monitors (internal)

    let ethernetMonitor: EthernetMonitor
    let wifiMonitor: WiFiMonitor

    // MARK: — Combine subscriptions

    private var cancellables: Set<AnyCancellable> = []

    // MARK: — Init

    init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.ethernetMonitor = EthernetMonitor()
        self.wifiMonitor = WiFiMonitor()
    }

    // MARK: — Lifecycle

    /// Starts both monitors and wires Combine subscriptions.
    /// Called from AppDelegate.applicationDidFinishLaunching, after StatusItemController
    /// has been created (ensuring the full Combine chain is wired before the first event).
    func startMonitors() {
        wireSubscriptions()
        ethernetMonitor.start()
        wifiMonitor.start()
    }

    /// Stops both monitors and cancels all Combine subscriptions.
    /// Called from AppDelegate.applicationWillTerminate.
    func stopMonitors() {
        cancellables.removeAll()   // cancels the CombineLatest sink
        ethernetMonitor.stop()
        wifiMonitor.stop()
    }

    // MARK: — Private

    private func wireSubscriptions() {
        // Combine the four WiFiMonitor publishers into a single tuple publisher.
        let wifiPublisher = Publishers.CombineLatest4(
            wifiMonitor.$networks,
            wifiMonitor.$connectedNetwork,
            wifiMonitor.$isEnabled,
            wifiMonitor.$isHardwareAvailable
        )

        // One sink rebuilds networkState and connectionMode atomically whenever
        // either monitor publishes. Both monitors debounce internally (300 ms),
        // so this sink does not need an additional debounce.
        Publishers.CombineLatest(ethernetMonitor.$interfaces, wifiPublisher)
            .sink { [weak self] interfaces, wifiTuple in
                guard let self else { return }
                let (networks, connectedWifi, isWiFiEnabled, isWiFiHardwareAvailable) = wifiTuple
                self.rebuildState(
                    interfaces: interfaces,
                    networks: networks,
                    connectedWifi: connectedWifi,
                    isWiFiEnabled: isWiFiEnabled,
                    isWiFiHardwareAvailable: isWiFiHardwareAvailable
                )
            }
            .store(in: &cancellables)
    }

    private func rebuildState(
        interfaces: [EthernetInterface],
        networks: [WiFiNetwork],
        connectedWifi: WiFiNetwork?,
        isWiFiEnabled: Bool,
        isWiFiHardwareAvailable: Bool
    ) {
        // Sort interfaces: active first, then by BSD name for determinism.
        let sorted = interfaces.sorted {
            if $0.isActive != $1.isActive { return $0.isActive }
            return $0.id < $1.id   // BSD name (id) ascending: en0 < en3 < en5
        }
        let primary = sorted.first(where: { $0.isActive })
        let mode = computeConnectionMode(ethernet: sorted, wifi: connectedWifi)

        networkState = NetworkState(
            mode: mode,
            ethernetInterfaces: sorted,
            primaryEthernet: primary,
            wifiNetworks: networks,
            connectedWifi: connectedWifi,
            isWiFiEnabled: isWiFiEnabled,
            isWiFiHardwareAvailable: isWiFiHardwareAvailable
        )
        connectionMode = mode
    }

    private func computeConnectionMode(
        ethernet: [EthernetInterface],
        wifi: WiFiNetwork?
    ) -> ConnectionMode {
        if ethernet.contains(where: { $0.isActive }) { return .ethernetActive }
        if wifi != nil { return .wifiOnly }
        return .disconnected
    }
}

// Convenience empty state used as @Published initial value before monitors start.
extension NetworkState {
    static let empty = NetworkState(
        mode: .disconnected,
        ethernetInterfaces: [],
        primaryEthernet: nil,
        wifiNetworks: [],
        connectedWifi: nil,
        isWiFiEnabled: true,
        isWiFiHardwareAvailable: true
    )
}
```

---

## `AppDelegate` Wiring (normative)

```swift
// App/AppDelegate.swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // AppState and StatusItemController live for the process lifetime.
    private let appState = AppState()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Create StatusItemController first — it subscribes to AppState.$networkState.
        //    The subscription must exist before startMonitors() fires the first event.
        statusItemController = StatusItemController(appState: appState)

        // 2. Start monitors. Events begin flowing; the Combine chain is fully wired.
        appState.startMonitors()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.tearDown()
        appState.stopMonitors()
    }
}
```

---

## `RootPanelView` Injection (normative)

```swift
// MenuBar/PopoverController.swift — inside PopoverController.init(appState:)
let hostingController = NSHostingController(
    rootView: RootPanelView()
        .environmentObject(appState)   // AppState available in entire view hierarchy
)
hostingController.sizingOptions = [.intrinsicContentSize]
popover.contentViewController = hostingController

// UI/ContentView.swift (RootPanelView)
struct RootPanelView: View {
    @EnvironmentObject var appState: AppState
    // ...
}

// UI/Panels/EthernetSection.swift
struct EthernetSection: View {
    @EnvironmentObject var appState: AppState
    // Reads appState.networkState.ethernetInterfaces directly — no prop-drilling.
}

// UI/Panels/WiFiSection.swift
struct WiFiSection: View {
    @EnvironmentObject var appState: AppState
    // Reads appState.networkState.wifiNetworks, appState.wifiLocationDenied, etc.
}
```

---

## Data Flow Diagram

```
AppDelegate.applicationDidFinishLaunching
  │
  ├─► AppState.init()          ← creates EthernetMonitor, WiFiMonitor
  ├─► StatusItemController.init(appState:)
  │     └─► subscribes to AppState.$networkState  (Combine sink → icon + labels update)
  │           (also calls updateIcon(for: .disconnected) synchronously — see Startup note)
  └─► AppState.startMonitors()
        ├─► wireSubscriptions()  ← Publishers.CombineLatest sink → rebuildState()
        ├─► EthernetMonitor.start()
        └─► WiFiMonitor.start()

── steady state ──────────────────────────────────────────────────────────────────

EthernetMonitor.$interfaces  ──┐
WiFiMonitor.$networks          │
WiFiMonitor.$connectedNetwork  ├─► CombineLatest sink → AppState.rebuildState()
WiFiMonitor.$isEnabled         │         │
                               ┘         ├─► AppState.@Published networkState  ──►  StatusItemController.observeState()
                                         │         │  (subscribes to $networkState, not $connectionMode)
                                         │         │       ├─► icon swap (networkState.mode)
                                         │         │       ├─► accessibility label (networkState.connectedWifi.ssid)
                                         │         │       └─► tooltip (networkState.primaryEthernet)
                                         │         └─► SwiftUI views re-render
                                         │               (via @EnvironmentObject)
                                         └─► AppState.@Published connectionMode
                                                   (maintained for potential future subscribers;
                                                    always equals networkState.mode)

── panel open (user clicks menu bar icon) ───────────────────────────────────────

PopoverController.show()
  └─► WiFiMonitor.requestScan() async throws
        └─► Task.detached → CWInterface.scanForNetworks(withSSID:nil)
              └─► WiFiMonitor.$networks updated → CombineLatest fires
```

**Startup Sequencing Note**

The launch sequence creates a brief, intentional `.disconnected` icon state before monitors correct it:

1. `StatusItemController.init()` calls `updateIcon(for: .disconnected)` synchronously (pre-monitor state). This ensures no blank icon at launch — a blank icon is unacceptable; a `.disconnected` icon for one run-loop cycle is acceptable.
2. `AppState.startMonitors()` is called immediately after. Both `EthernetMonitor.start()` and `WiFiMonitor.start()` publish their initial state **synchronously** in `start()` (Constraint: "Both monitors publish their initial state synchronously in `start()`").
3. The `CombineLatest` sink fires for the first time after both monitors have emitted. It calls `rebuildState()`, which updates `AppState.networkState` to the actual current state and emits via `$networkState`.
4. `StatusItemController`'s `$networkState` subscription fires, correcting the icon from `.disconnected` to the real current state — within the first run-loop cycle after `startMonitors()`.

This sequencing is intentional and correct. The alternative (deferring `StatusItemController.init()` until after monitors start) is rejected by Decision #8, which requires the subscription to exist before the first monitor event.

---

## Persistence Contract

| Key | Type | Storage | Persisted | Notes |
|-----|------|---------|-----------|-------|
| `launchAtLogin` | `Bool` | `UserDefaults` | ✅ | Read/written by AppState; toggled by a UI control (future PRD) |
| Network interfaces | `[EthernetInterface]` | In-memory only | ❌ | Always reflects live OS state |
| Wi-Fi networks | `[WiFiNetwork]` | In-memory only | ❌ | Populated by on-demand scan |
| Connected SSID | `WiFiNetwork?` | In-memory only | ❌ | Read from CoreWLAN at `start()` |
| Connection mode | `ConnectionMode` | In-memory only | ❌ | Derived; valid within ~300 ms of launch |
| `wifiLocationDenied` | `Bool` | In-memory only | ❌ | Re-evaluated on every scan attempt |

**Why last SSID is not cached:** `WiFiMonitor.start()` reads `CWInterface.ssid()` synchronously on the main actor before registering event callbacks. The connected SSID is available in `AppState.networkState.connectedWifi` within the first Combine tick — before the user can open the panel. A UserDefaults cache would display stale data (e.g., a network the device left yesterday) and complicate the state model for no observable benefit.

---

## Memory and CPU Budget

| Metric | Limit | Rationale |
|--------|-------|-----------|
| Steady-state RSS (panel closed) | **≤ 30 MB** | Natural footprint for a text-only menu bar process. Includes CoreWLAN internal cache, os.log ring buffer, and Swift runtime. |
| Peak RSS (panel open, scan in progress) | **≤ 50 MB** | `NSPopover` + `NSHostingController` SwiftUI render tree is allocated transiently; the popover view hierarchy is deallocated when the popover closes. |
| CPU (panel closed, no network events) | **~0%** | No timers, no polling, no background tasks. Process sleeps until SCDynamicStore or CoreWLAN delivers a push event. |
| CPU during a Wi-Fi scan | **Brief spike ≤ 30%** on one core | `Task.detached` in `requestScan()` runs `CWInterface.scanForNetworks` (1–3 s). Normal for active scanning; not a background concern since scans are only triggered by panel open. |

**Error-state cleanup:** If either monitor enters an unrecoverable error state (e.g., CoreWLAN internal assertion, SCDynamicStore invalidation), `AppState.stopMonitors()` is the canonical cleanup path. It cancels all Combine subscriptions via `cancellables.removeAll()` and calls `monitor.stop()` on both monitors. The UI falls back to the `.empty` NetworkState, showing the disconnected icon. Recovery (re-calling `startMonitors()`) is not attempted automatically — the user can relaunch the app. All error events are logged via `os.log` at the `.error` level using the subsystem defined in `Utilities/Logger.swift`.

---

## Constraints

- **`@MainActor` required throughout AppState:** `ObservableObject` + `@Published` mutations must occur on the main actor. Both monitors are already `@MainActor`, so all `@Published` writes from the Combine sink arrive on the main actor — no explicit `receive(on:)` is needed. Adding any non-`@MainActor` mutation path would introduce a Swift 6 strict-concurrency violation.
- **No `@Observable`:** The `@Observable` macro (Observation framework) requires macOS 14. LinkHub targets macOS 13. Using `@Observable` is prohibited unless the deployment target is explicitly raised in a future PRD.
- **`Publishers.CombineLatest` initial fire:** `CombineLatest` only fires after all upstream publishers have emitted at least one value. Both monitors publish their initial state synchronously in `start()` (Ethernet via `SCNetworkInterfaceCopyAll()`, Wi-Fi via `CWInterface.ssid()`), ensuring the first combined event fires before the first runloop cycle completes after `startMonitors()`.
- **`StatusItemController` must subscribe before `startMonitors()`:** The creation order in `AppDelegate.applicationDidFinishLaunching` is normative (Decision #8). Reversing it means `StatusItemController` misses the first `connectionMode` event and displays the wrong icon until the next monitor event.
- **`wifiLocationDenied` is set directly by `WiFiMonitor`, not via the Combine sink:** This flag is not part of `NetworkState` (which is a snapshot of physical connectivity, not of permission state). `WiFiMonitor` sets `appState.wifiLocationDenied = true` directly — a simple `@MainActor` assignment. This is safe because both `WiFiMonitor` and `AppState` are `@MainActor`.
- **`NetworkState.empty` is the only valid initial value:** The default `@Published` values must represent "no data yet" — not a best guess. `.empty` has `mode: .disconnected`, empty arrays, and `isWiFiEnabled: true`. The `isWiFiEnabled: true` default avoids briefly showing the "Turn on Wi-Fi" empty state before the first monitor event; the connected/disconnected icon will be `.disconnected` (correct) until monitors fire.
- **`UserDefaults` key stability:** The `"launchAtLogin"` key is the persisted identifier for the launch-at-login preference. Do not rename it without a migration. No other UserDefaults keys are introduced by this PRD.

---

## Out of Scope

- **Wi-Fi connect / disconnect / forget operations** — write operations on `WiFiMonitor` are PRD 06.
- **Ethernet toggle (enable/disable interface)** — `EthernetMonitor` write path is PRD 05.
- **Login-item registration UI** — the toggle control that calls `SMAppService.mainApp` is a UI feature deferred to a future coding session; this PRD only defines `launchAtLogin` storage.
- **`NetworkState` fields for link speed, IPv6, captive portal** — these are per-PRD 05/06 additions to the data model; AppState wiring follows the same Combine pattern once those fields exist.
- **`@Observable` migration** — if the deployment target is ever raised to macOS 14 in a future PRD, the migration path is: replace `ObservableObject` + `@Published` with `@Observable`; remove `@EnvironmentObject` in views (use plain `@Environment`); the Combine subscription wiring in `wireSubscriptions()` remains unchanged.
- **Multiple `AppState` instances** — LinkHub is a single-window-equivalent app; there is exactly one `AppState`. No factory, dependency injection container, or service locator is needed.
- **iCloud or CloudKit sync** — preferences are local only; no cross-device sync is planned.

---

## Open Questions

| # | Question | Impact | To resolve before |
|---|----------|--------|-------------------|
| 1 | Should `EthernetInterface` gain a `linkSpeed` field (PRD 03 Open Question 1)? If so, PRD 05 adds it to the model and the `rebuildState()` sink automatically includes it in the next `NetworkState` reconstruction — no AppState changes needed. | Panel display only. | PRD 05 coding session |
| 2 | PRD 06 will define whether `WiFiMonitor.requestScan()` errors (location denied, Wi-Fi off) are propagated to `AppState` or handled locally in `WiFiSection`. The `wifiLocationDenied` flag (Decision #11) covers the location case; a `scanError: Error?` property on `AppState` may be needed for other errors. | WiFiSection error UI. | PRD 06 coding session |

---

## References

- [Apple Developer: ObservableObject](https://developer.apple.com/documentation/combine/observableobject) — `@Published` property wrapper and `objectWillChange` publisher.
- [Apple Developer: Combine — CombineLatest](https://developer.apple.com/documentation/combine/publishers/combinelatest) — Emits a tuple when any upstream publishes; requires all upstreams to have emitted at least once.
- [Apple Developer: Combine — AnyCancellable](https://developer.apple.com/documentation/combine/anycancellable) — Type-erased cancellable; `store(in:)` convenience for `Set<AnyCancellable>`.
- [Apple Developer: EnvironmentObject](https://developer.apple.com/documentation/swiftui/environmentobject) — `@EnvironmentObject` property wrapper; `.environmentObject(_:)` view modifier injection.
- [Apple Developer: NSHostingController](https://developer.apple.com/documentation/swiftui/nshostingcontroller) — `environmentObject` propagation through the hosting controller boundary.
- [Apple Developer: UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults) — `bool(forKey:)` / `set(_:forKey:)` for persisting the `launchAtLogin` flag.
- [Apple Developer: Observation (macOS 14+)](https://developer.apple.com/documentation/observation) — `@Observable` macro; documented here to record the decision against it for macOS 13.
- [WWDC 2019: Data Flow Through SwiftUI (session 226)](https://developer.apple.com/videos/play/wwdc2019/226/) — `ObservableObject`, `@Published`, `@EnvironmentObject` patterns; foundational reference for the AppState design.
- [WWDC 2023: Discover Observation in SwiftUI (session 10149)](https://developer.apple.com/videos/play/wwdc2023/10149/) — `@Observable` macro introduction; explains why it cannot be used on macOS 13.
- [WWDC 2024: Migrate your app to Swift 6 (session 10169)](https://developer.apple.com/videos/play/wwdc2024/10169/) — `@MainActor`-isolated `ObservableObject`; Combine sink isolation guarantees under Swift 6 strict concurrency.
- [Swift.org: Swift 6 Concurrency Migration Guide](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/) — `@MainActor` and `@Published` interaction; implications for `ObservableObject` subclasses.
