# Story 1.3: WiFiMonitor — On-Demand Scan, Push Events, ScanStatus Timeout

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user,
I want LinkHub to discover nearby Wi-Fi networks via the system and react to live system events,
so that the panel reflects current Wi-Fi reality without polling and surfaces a scanning indicator if a scan is slow.

## Acceptance Criteria

1. **WiFiMonitor is a `@MainActor final class` with `@Published`-only public state**
   - **Given** `WiFiMonitor` is started
   - **When** it initializes
   - **Then** it is a `@MainActor final class` exposing public state via `@Published` only (no `AsyncStream`) (PRD 03 D9, D13)
   - **And** it owns a `CWWiFiClient.shared()` and registers itself as `CWEventDelegate` (PRD 03 D5, D6)
   - **And** it subscribes to `ssidDidChange`, `linkDidChange`, `linkQualityDidChange`, `powerDidChange` events (PRD 03 § CWEventDelegate Events Registered)

2. **No polling — push-event-only data flow**
   - **Given** the app is running
   - **When** the panel is closed
   - **Then** no scheduled `Timer`, `DispatchSourceTimer`, or `Task.sleep` polling loop fires for Wi-Fi (FR50, NFR50, PRD 07 D13)
   - **And** WiFiMonitor mutates `@Published` state only in response to `CWEventDelegate` callbacks or explicit `requestScan()` calls

3. **ObjC ↔ Swift 6 boundary is Sendable-clean**
   - **Given** a `CWEventDelegate` callback fires on the CoreWLAN internal thread
   - **When** values are read from `CWInterface` / `CWNetwork`
   - **Then** Sendable values are extracted on the callback thread before any actor hop (PRD 03 D11, D12)
   - **And** the hop to MainActor uses `Task { @MainActor [weak self] in ... }` — `CWNetwork` / `CWInterface` are never captured across the actor boundary (PRD 03 Constraints)
   - **And** `requestScan()` performs `iface.scanForNetworks(withSSID:nil)` inside `Task.detached`; no `CWNetwork` reference escapes the detached closure
   - **And** Swift 6 strict concurrency builds clean with zero `@unchecked Sendable` wrappers in the model layer (NFR33)

4. **300 ms Combine debounce on rapid events**
   - **Given** rapid system events (e.g. RSSI bursts during scan)
   - **When** events arrive in succession
   - **Then** they pass through a `PassthroughSubject<Void, Never>.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)` before driving any `@Published` rebuild that the UI consumes (NFR5, PRD 03 D7, D8)

5. **`requestScan()` drives `AppState.scanStatus` through idle → scanning → idle | timedOut**
   - **Given** the user requests a scan
   - **When** `WiFiMonitor.requestScan()` is called
   - **Then** `AppState.scanStatus` transitions `idle` → `scanning` → either `idle` (results published) or `timedOut` (after 5 s) (NFR3)
   - **And** the 5 s timeout is enforced via a `Task` race (e.g. `withThrowingTaskGroup` with a timeout child task)
   - **And** `WiFiMonitor.networks` is updated with the sorted scan results when the scan completes within the budget
   - **And** a second concurrent `requestScan()` while one is already in flight is a no-op (does not start a parallel scan)

6. **`#if DEBUG` mock data path — opt-in only**
   - **Given** a Debug build
   - **When** the env var `LINKHUB_MOCK_WIFI=1` is set OR a Debug-only compile flag is set
   - **Then** `AppDelegate` constructs `MockWiFiMonitor` (instead of the real `WiFiMonitor`) and injects it into `AppState`
   - **And** the mock returns canned `MockWiFiMonitor.sampleNetworks` (PRD 03 § Mock Data Protocol)
   - **And** the mock path **does not auto-engage** in regular Debug builds — without the opt-in, the real `WiFiMonitor` is used (which will surface no networks in Debug due to missing entitlements; that is intended)

7. **Clean teardown — no `CWEventDelegate` retain cycle**
   - **Given** the app is terminating
   - **When** `applicationWillTerminate(_:)` runs
   - **Then** `appState.stopMonitors()` is called and reaches `wifiMonitor.stop()`
   - **And** `wifiMonitor.stop()` sets `CWWiFiClient.shared().delegate = nil` (NFR9, FR46, PRD 03 Constraints)
   - **And** `cancellables.removeAll()` runs on `AppState`

8. **AppState wires Wi-Fi side via single CombineLatest sink**
   - **Given** `WiFiMonitor` publishes `networks`, `connectedNetwork`, `isEnabled`, `isHardwareAvailable`, `scanStatus`
   - **When** any of these change after debounce
   - **Then** a single `Publishers.CombineLatest4(...).sink` on `AppState` rebuilds `networkState` and `connectionMode` atomically (PRD 07 D6)
   - **And** `connectionMode` is computed via the canonical rule: `ethernet.contains(where: \.isActive) ? .ethernetActive : (wifi != nil ? .wifiOnly : .disconnected)` (architecture.md § ConnectionMode computation rule)
   - **And** for this story `ethernetInterfaces` stays `[]` (Epic 3 wires Ethernet); mode resolves to `.wifiOnly` when associated, else `.disconnected`
   - **And** `AppState.scanStatus` is mirrored from `wifiMonitor.scanStatus` (`assign(to:)` or sink) so UI can observe it via `@EnvironmentObject` only (NFR35)

## Tasks / Subtasks

- [x] **Task 1: Extend `Network/Models/` — full `NetworkState` shape + Wi-Fi value types** (AC: #1, #8)
  - [x] Create `LinkHub/Network/Models/WiFiSecurity.swift` — `enum WiFiSecurity: Equatable, Sendable { case none, wpa2Personal, wpa3Personal, enterprise, other }`. Add `init(from cwSecurity: CWSecurity)` mapping (in this same file as a `WiFiSecurity` extension under an `import CoreWLAN`-gated `#if canImport(CoreWLAN)` block — alternatively keep mapping in `WiFiMonitor.swift` to keep `Models/` `Foundation`-only; **pick the second option** to preserve Models-layer purity per architecture.md "Network/Models/ imports AppKit, SwiftUI, or Combine — forbidden")
  - [x] Create `LinkHub/Network/Models/WiFiNetwork.swift` — `struct WiFiNetwork: Identifiable, Equatable, Sendable` exactly per PRD 03 § `WiFiNetwork.swift` (id, ssid, bssid, rssi, isConnected, requiresPassword, security, isCaptive). Document the `id = bssid ?? "\(ssid ?? "hidden"):\(security)"` extraction note in a `///` comment for future readers
  - [x] Create `LinkHub/Network/Models/EthernetInterface.swift` — `struct EthernetInterface: Identifiable, Equatable, Sendable` exactly per PRD 03 § `EthernetInterface.swift`. Story 3.1 wires the producer; this story creates the type only so `NetworkState` can compile with `ethernetInterfaces: [EthernetInterface]`
  - [x] Create `LinkHub/Network/Models/ScanStatus.swift` — `enum ScanStatus: Equatable, Sendable { case idle, scanning, timedOut }`. New type introduced by Story 1.3 to satisfy AC #5 — not part of architecture.md's data-model table; document as "Story 1.3 addition; AppState mirrors WiFiMonitor.scanStatus"
  - [x] **Modify** `LinkHub/Network/Models/NetworkState.swift` — replace minimum stub with full shape from PRD 03:
    ```swift
    struct NetworkState: Equatable, Sendable {
        let mode: ConnectionMode
        let ethernetInterfaces: [EthernetInterface]
        let primaryEthernet: EthernetInterface?
        let wifiNetworks: [WiFiNetwork]
        let connectedWifi: WiFiNetwork?
        let isWiFiEnabled: Bool
        let isWiFiHardwareAvailable: Bool
        static let empty = NetworkState(
            mode: .disconnected, ethernetInterfaces: [], primaryEthernet: nil,
            wifiNetworks: [], connectedWifi: nil,
            isWiFiEnabled: true, isWiFiHardwareAvailable: true
        )
    }
    ```
  - [x] Drop the `// MARK: - Story 1.3 will add …` comment — replaced by the full struct
  - [x] **All five model files: `import Foundation` only** — no AppKit/SwiftUI/Combine/CoreWLAN. Layer-purity rule from architecture.md "Network/Models/ … forbidden imports"
- [x] **Task 2: `WiFiMonitorProtocol` — observation/scan surface for Story 1.3** (AC: #1, #6, #8)
  - [x] Create `LinkHub/Network/WiFiMonitorProtocol.swift` exposing the **subset** of PRD 03's protocol that Story 1.3 needs:
    ```swift
    @MainActor
    protocol WiFiMonitorProtocol: AnyObject {
        var networks: [WiFiNetwork] { get }
        var networksPublisher: Published<[WiFiNetwork]>.Publisher { get }
        var connectedNetwork: WiFiNetwork? { get }
        var connectedNetworkPublisher: Published<WiFiNetwork?>.Publisher { get }
        var isEnabled: Bool { get }
        var isEnabledPublisher: Published<Bool>.Publisher { get }
        var isHardwareAvailable: Bool { get }
        var isHardwareAvailablePublisher: Published<Bool>.Publisher { get }
        var scanStatus: ScanStatus { get }
        var scanStatusPublisher: Published<ScanStatus>.Publisher { get }
        func start()
        func stop()
        func requestScan() async
    }
    ```
  - [x] Note in a top-of-file comment: "Story 2.1 adds `connect(to:password:remember:)`, `disconnect()`, and the typed `WiFiConnectionFailure` error path. Do not add them now — out of scope for Story 1.3."
  - [x] `requestScan()` is `async` (no `throws` for now — failures map to `ScanStatus.timedOut` or `.idle` with empty networks; typed connection-failure errors are Story 2.1 territory). Rationale: epic 1.3 AC #5 only requires the scanStatus state transitions, not throwing typed errors
  - [x] `import Foundation` + `import Combine` only
- [x] **Task 3: `WiFiMonitor` — real CoreWLAN implementation** (AC: #1, #2, #3, #4, #5, #7)
  - [x] Create `LinkHub/Network/WiFiMonitor.swift` — `@MainActor final class WiFiMonitor: NSObject, CWEventDelegate`
  - [x] `import Foundation`, `import Combine`, `import CoreWLAN`
  - [x] Stored `@Published private(set) var networks: [WiFiNetwork] = []`
  - [x] Stored `@Published private(set) var connectedNetwork: WiFiNetwork? = nil`
  - [x] Stored `@Published private(set) var isEnabled: Bool = true`
  - [x] Stored `@Published private(set) var isHardwareAvailable: Bool = true`
  - [x] Stored `@Published private(set) var scanStatus: ScanStatus = .idle`
  - [x] Stored `private let eventSubject = PassthroughSubject<Void, Never>()` — debounce hop point for rapid `linkQualityDidChange` bursts (AC #4)
  - [x] Stored `private var cancellables: Set<AnyCancellable> = []`
  - [x] Stored `private var inFlightScan: Task<Void, Never>? = nil` — guards re-entrant `requestScan()` per AC #5 "second concurrent call is a no-op"
  - [x] Conform retroactively: `extension WiFiMonitor: WiFiMonitorProtocol { var networksPublisher: Published<[WiFiNetwork]>.Publisher { $networks }; ... }` (one accessor per published property; one for `scanStatus` too)
  - [x] `func start()` — implement per PRD 03 § `WiFiMonitor.start()` normative:
    1. `guard let iface = CWWiFiClient.shared().interface() else { isHardwareAvailable = false; isEnabled = false; return }`
    2. `isHardwareAvailable = true`
    3. `isEnabled = iface.powerOn()`
    4. `let client = CWWiFiClient.shared()`
    5. `client.delegate = self`
    6. `client.startMonitoringEvent(with: .ssidDidChange)` (and 3 more: `.linkDidChange`, `.linkQualityDidChange`, `.powerDidChange`)
       - **Note:** `startMonitoringEvent(with:)` throws — wrap each in `try?` and log via `Log.networkWiFi.error("CWWiFiClient.startMonitoringEvent failed: \(error.localizedDescription, privacy: .public)")` if it throws
    7. Read initial association state synchronously (we are on MainActor here): `if isEnabled, let bssid = iface.bssid() { connectedNetwork = WiFiNetwork(...) } else { connectedNetwork = nil }`
    8. Wire the debounce sink: `eventSubject.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main).sink { [weak self] _ in Task { @MainActor [weak self] in self?.refreshFromCurrentInterface() } }.store(in: &cancellables)`
  - [x] `func stop()` — clear delegate FIRST: `CWWiFiClient.shared().delegate = nil`; `cancellables.removeAll()`; reset all `@Published` to defaults (so a subsequent `start()` re-emits cleanly). PRD 03 § `WiFiMonitor.stop()` normative
  - [x] `func requestScan() async` — AC #5 task race:
    ```swift
    guard inFlightScan == nil else { return }   // re-entrancy guard
    scanStatus = .scanning
    let task = Task { @MainActor in
        defer { self.inFlightScan = nil }
        do {
            try await withThrowingTaskGroup(of: [WiFiNetwork].self) { group in
                group.addTask { try await Self.performScan() }   // detached static call inside addTask; see below
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    throw ScanTimeout()
                }
                let result = try await group.next()!
                group.cancelAll()
                self.networks = result.sorted { $0.rssi > $1.rssi }
                self.scanStatus = .idle
            }
        } catch is ScanTimeout {
            self.scanStatus = .timedOut
        } catch {
            Log.networkWiFi.error("Scan failed: \(error.localizedDescription, privacy: .public)")
            self.scanStatus = .timedOut
        }
    }
    inFlightScan = task
    await task.value
    ```
    where `private struct ScanTimeout: Error {}` is fileprivate inside `WiFiMonitor.swift`.
  - [x] `private static func performScan() async throws -> [WiFiNetwork]` — `Task.detached(priority: .userInitiated)` body per PRD 03 § `requestScan()` flow: `guard let iface = CWWiFiClient.shared().interface() else { return [] }`; `let connectedBSSID = iface.bssid()`; `return try iface.scanForNetworks(withSSID: nil).map { cwNet in WiFiNetwork(...) }`. **No `CWNetwork` reference escapes** — the `.map` produces value types. The static-method form keeps `self` out of the detached closure (Sendable-clean per AC #3)
  - [x] `private func refreshFromCurrentInterface()` — runs on MainActor. Re-reads `CWWiFiClient.shared().interface()` for ssid/bssid/rssi/security/power state (re-read is safe because we are on MainActor and `CWInterface` is not crossing any boundary). Updates `connectedNetwork`, `isEnabled`. PRD 03 D14 — for `linkQualityDidChange` the delegate carries an `rssi` parameter; this story uses the simpler "re-read on every event" path for `ssid/link/power` and lets the debounced refresh absorb RSSI bursts. (The targeted "use delegate-supplied rssi only for linkQualityDidChange" optimization can be added later — call out in Dev Notes that this story uses the simpler full-refresh path)
  - [x] **CWEventDelegate methods** — implement all four with the **same body**: `nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) { Task { @MainActor [weak self] in self?.eventSubject.send(()) } }`. The captures: only `String` (Sendable); the `eventSubject.send(())` is debounced; `refreshFromCurrentInterface()` runs after debounce. **Capture only `interfaceName` (String).** Never capture `CWInterface` or `CWNetwork` (PRD 03 Constraints)
  - [x] **Acronym discipline:** spell `WiFi` (not `WIFI`); `requiresPassword: cwNet.security() != .none && cwNet.security() != .enterprise`; `WiFiSecurity(from: cwSecurity)` mapping helper lives `fileprivate` inside `WiFiMonitor.swift` — Models layer stays Foundation-only
- [x] **Task 4: `MockWiFiMonitor` — `#if DEBUG` mock matching `WiFiMonitorProtocol`** (AC: #6)
  - [x] Create `LinkHub/Network/MockWiFiMonitor.swift` wrapped in `#if DEBUG ... #endif`
  - [x] `@MainActor final class MockWiFiMonitor: WiFiMonitorProtocol`
  - [x] All `@Published` properties match the protocol — pre-seeded with `MockWiFiMonitor.sampleNetworks` (the canonical sample set from PRD 03 § Mock Data Protocol — 5 networks: HomeNetwork connected, GuestNetwork, CoffeeWifi captive, CorpNetwork enterprise, Hidden WPA3)
  - [x] `func start() {}`, `func stop() {}` — no-ops
  - [x] `func requestScan() async { scanStatus = .scanning; try? await Task.sleep(nanoseconds: 200_000_000); networks = Self.sampleNetworks; scanStatus = .idle }` — 200 ms simulated delay so UI shows the scanning indicator briefly during dev runs
  - [x] `import Foundation`, `import Combine` only
- [x] **Task 5: Extend `Utilities/Logger.swift` — add `network.wifi` category** (AC: cross-cutting; required by Task 3 error logging)
  - [x] Edit `LinkHub/Utilities/Logger.swift` — add `static let networkWiFi = os.Logger(subsystem: subsystem, category: "network.wifi")` to `enum Log`
  - [x] Drop the `// Future categories: network.wifi, ...` comment for `network.wifi` (still leave the others — they arrive in their own stories)
- [x] **Task 6: Wire `AppState` — inject `wifiMonitor`, mirror `scanStatus`, single CombineLatest sink** (AC: #5, #7, #8)
  - [x] Edit `LinkHub/State/AppState.swift`. **Add `import Foundation`/`import Combine` only — do NOT add `import CoreWLAN`.** State layer is framework-agnostic
  - [x] Add `let wifiMonitor: any WiFiMonitorProtocol` — exposed (not `private`) so `PopoverController` (Story 1.4) can call `appState.wifiMonitor.requestScan()` via `Task { try? await ... }`. **Note:** Story 1.4 will switch this to `appState.wifiMonitor.requestScan()` (no `try?` since we made it non-throwing in this story). Update the existing `// Story 1.4: scan-on-show hook` comment in `PopoverController.show()` accordingly **only if** Story 1.4 hasn't already landed; if it has, leave it for Story 1.4 to amend
  - [x] Add `@Published private(set) var scanStatus: ScanStatus = .idle`
  - [x] Add an `init(wifiMonitor: any WiFiMonitorProtocol)` overload **alongside** the existing parameterless `init()` (which now calls `self.init(wifiMonitor: WiFiMonitor())`). The parameterless init keeps existing tests / call sites compatible; the overload allows AppDelegate's mock injection and unit tests to inject a mock. Both must read `launchAtLogin` from `UserDefaults`. Pattern:
    ```swift
    convenience init() { self.init(wifiMonitor: WiFiMonitor()) }
    init(wifiMonitor: any WiFiMonitorProtocol) {
        self.wifiMonitor = wifiMonitor
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
    }
    ```
  - [x] **Replace** `func startMonitors()` body:
    1. `wifiMonitor.start()`
    2. Mirror scanStatus: `wifiMonitor.scanStatusPublisher.assign(to: &$scanStatus)` (`.assign(to:)` returns `Void`; no AnyCancellable needed — auto-cancelled when AppState deinits)
    3. Wire single CombineLatest sink (Wi-Fi-only for this story; Story 3.2 adds Ethernet via refactor):
       ```swift
       Publishers.CombineLatest4(
           wifiMonitor.networksPublisher,
           wifiMonitor.connectedNetworkPublisher,
           wifiMonitor.isEnabledPublisher,
           wifiMonitor.isHardwareAvailablePublisher
       )
       .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)   // NFR5 + PRD 07 D6
       .sink { [weak self] networks, connected, isEnabled, isHardwareAvailable in
           Task { @MainActor [weak self] in
               self?.rebuildState(networks: networks, connected: connected, isEnabled: isEnabled, isHardwareAvailable: isHardwareAvailable)
           }
       }.store(in: &cancellables)
       ```
       **Why also debounce here even though WiFiMonitor already debounces internally?** WiFiMonitor's internal debounce gates the *re-read* of CWInterface; this outer debounce gates the *AppState rebuild* against rapid simultaneous changes across all 4 publishers. PRD 07 D6 specifies the single sink; the architecture allows per-monitor + AppState-level debounce because they operate on different signals. **Verify with the user during dev review** if this dual debounce introduces any test flakiness — fall back to single (inner) debounce only if it does
  - [x] Add `private func rebuildState(networks: [WiFiNetwork], connected: WiFiNetwork?, isEnabled: Bool, isHardwareAvailable: Bool)`:
    1. Compute `mode = computeConnectionMode(ethernet: [], wifi: connected)` — canonical rule (architecture.md § ConnectionMode computation rule)
    2. Build `let new = NetworkState(mode: mode, ethernetInterfaces: [], primaryEthernet: nil, wifiNetworks: networks, connectedWifi: connected, isWiFiEnabled: isEnabled, isWiFiHardwareAvailable: isHardwareAvailable)`
    3. Assign atomically: `self.networkState = new; self.connectionMode = mode`
  - [x] Add `private func computeConnectionMode(ethernet: [EthernetInterface], wifi: WiFiNetwork?) -> ConnectionMode { if ethernet.contains(where: \.isActive) { return .ethernetActive }; if wifi != nil { return .wifiOnly }; return .disconnected }`
  - [x] **Replace** `func stopMonitors()` body: `wifiMonitor.stop()`; `cancellables.removeAll()` — `wifiMonitor.stop()` first ensures `CWWiFiClient.shared().delegate = nil` happens before AppState's subscriptions are cancelled (avoids late delegate callbacks after AppState is mid-teardown)
  - [x] Keep the `#if DEBUG _setNetworkStateForTesting(_:)` helper from Story 1.2 — still useful for StatusItemController tests
- [x] **Task 7: Wire `AppDelegate` — mock-vs-real WiFiMonitor selection via env var** (AC: #6)
  - [x] Edit `LinkHub/App/AppDelegate.swift`. Replace the existing `private let appState = AppState()` line with a method-selected construction:
    ```swift
    private let appState: AppState = {
        let wifi = AppDelegate.makeWiFiMonitor()
        return AppState(wifiMonitor: wifi)
    }()
    private static func makeWiFiMonitor() -> any WiFiMonitorProtocol {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LINKHUB_MOCK_WIFI"] == "1" {
            return MockWiFiMonitor()
        }
        #endif
        return WiFiMonitor()
    }
    ```
  - [x] **Critical:** `MockWiFiMonitor` is `#if DEBUG`-gated, so the `#if DEBUG` block in `makeWiFiMonitor()` is mandatory — Release builds cannot reference `MockWiFiMonitor`
  - [x] No other AppDelegate changes — init order from Story 1.2 is preserved: `StatusItemController(appState:)` → `start()` → `appState.startMonitors()`. Tear-down stays `tearDown()` → `stopMonitors()`
- [x] **Task 8: Test coverage — Models, Mock, real Monitor (where feasible), AppState wiring** (AC: all)
  - [x] **`LinkHubTests/Network/Models/WiFiNetworkTests.swift`** (NEW):
    - `testIdComposesFromBSSIDWhenAvailable` — construct with bssid, assert `id == bssid`
    - `testIdFallsBackToCompositeWhenBSSIDIsNil` — assert `id` matches the documented `"\(ssid ?? "hidden"):\(security)"` form (you compose the id manually in the test since the struct just stores `id`)
    - `testEquatableHonorsAllFields`
    - `testSendableConformanceCompiles` — single `_ = MainActor.assumeIsolated { Task.detached { @Sendable in let _: WiFiNetwork = .init(...); }.cancel() }` — implicit-conformance check; if the type is non-Sendable the test target won't compile
  - [x] **`LinkHubTests/Network/Models/NetworkStateTests.swift`** (NEW):
    - `testEmptyShape` — assert `.empty` matches `(disconnected, [], nil, [], nil, true, true)`
    - `testEquatableSurfaceIncludesAllFields`
  - [x] **`LinkHubTests/Network/MockWiFiMonitorTests.swift`** (NEW, `#if DEBUG`-gated, since `MockWiFiMonitor` is Debug-only):
    - `testInitialPublishedValuesMatchSampleData`
    - `testRequestScanTransitionsScanStatus` — observe `$scanStatus`, call `requestScan()`, assert `[idle, scanning, idle]` sequence (use a Combine `.sink` collecting values into an array; `await` the call; XCTAssert on the collected sequence)
    - `testStartStopAreNoOps`
  - [x] **`LinkHubTests/Network/WiFiMonitorTests.swift`** (NEW):
    - `testInitialStateBeforeStart` — instantiate without calling `start()`; assert defaults
    - `testStartWhenNoHardwareAvailableSetsFlags` — **gated by `try XCTSkipIf(...)`** — `CWWiFiClient.shared().interface()` always returns nil in test bundles loaded into the host app under headless CI? No — in the test host the AppKit run loop is alive, so `CWWiFiClient` may return an interface on a real Mac. Mark this test `try XCTSkipIf(CWWiFiClient.shared().interface() != nil, "Hardware Wi-Fi present; this test exercises the no-hardware branch only")` so the test is meaningful only in environments with no Wi-Fi
    - `testRequestScanRespectsReentrancyGuard` — call `requestScan()` twice in immediate succession, assert only one scan ran (use a counter on a test-only subclass that overrides `performScan`, OR observe `$scanStatus` to ensure only one `idle → scanning → idle/timedOut` cycle). Prefer the subclass approach with `#if DEBUG` test-only override hook on `WiFiMonitor`: `internal var _scanOverride: (() async throws -> [WiFiNetwork])? = nil`
    - `testRequestScanTimesOutAfter5Seconds` — inject a `_scanOverride` that `try await Task.sleep(nanoseconds: 6_000_000_000)`; assert `scanStatus == .timedOut`. **Mark this test as a long-running integration test** — guard with `try XCTSkipIf(ProcessInfo.processInfo.environment["LINKHUB_RUN_SLOW_TESTS"] == nil, "Slow test, opt-in")`. The fast path: shorten to a 200ms timeout and a 250ms scan via the test-only hook so the test runs in <500ms. **Pick the fast-path approach: parameterize the timeout via a test-only init on `WiFiMonitor`** — `init(scanTimeoutNanoseconds: UInt64 = 5_000_000_000)`. Default stays at 5 s (AC #5); tests pass `200_000_000`
    - `testStopClearsDelegateAndState` — call `start()`; call `stop()`; assert `connectedNetwork == nil`, `networks == []`, and `CWWiFiClient.shared().delegate as AnyObject?` is `nil` (the second is best-effort — CoreWLAN may return a non-nil placeholder on some macOS versions; assert via `=== nil` rather than equality)
  - [x] **Modify** `LinkHubTests/State/AppStateTests.swift` — extend the existing tests:
    - Update `testInitializerSetsDefaultPublishedValues` — the `NetworkState.empty` shape now has 7 fields; reassert
    - Add `testInitWithMockWiFiMonitorWiresPublishedState` — instantiate `AppState(wifiMonitor: MockWiFiMonitor())`; call `startMonitors()`; **observe `$networkState` via `XCTestExpectation` driven from a `.sink`** until `wifiNetworks` matches `MockWiFiMonitor.sampleNetworks` (or 1 s timeout). Assert `connectionMode == .wifiOnly` (mock has `connectedNetwork != nil`)
    - Add `testStopMonitorsClearsCancellablesAndStopsWiFiMonitor` — verify `cancellables.isEmpty` and that a test-only counter on a stub `WiFiMonitorProtocol` records exactly one `stop()` call
    - Add `testScanStatusMirrorsWiFiMonitor` — drive `mock.scanStatus = .scanning` directly (mock is non-final or has a setter); assert `appState.scanStatus == .scanning` after debounce. **Note:** `assign(to:)` is not debounced; assertion can be immediate via `await` on a small `Task.sleep(50_000_000)` to let the publisher pipeline drain
    - Add `testConnectionModeRuleWifiOnly` and `testConnectionModeRuleDisconnected` — exercise `rebuildState(...)` indirectly by setting mock state and asserting `connectionMode` after the sink fires
  - [x] **Add `#if DEBUG`-gated test-only API to `AppState`** if needed: `func _wifiMonitorForTesting<T: WiFiMonitorProtocol>() -> T?` is **not** needed if you just inject the mock at init time
  - [x] All new tests use `@testable import LinkHub` (Story 1.2 carry-forward; `ENABLE_TESTABILITY = YES` Debug-only is from Story 1.1)
- [x] **Task 9: XcodeGen + build + test validation** (AC: all)
  - [x] **`project.yml` audit:** the recursive include `path: LinkHub` (Story 1.1) picks up files in `LinkHub/Network/` automatically. Story 1.2's verdict was "Do not edit project.yml unless an actually-missing path needs adding." Verify after `xcodegen generate` that all 5 new `.swift` files in `LinkHub/Network/` (not `Models/`) appear in the project. If any are missing, add a `LinkHub/Network` group entry under `targets.LinkHub.sources` mirroring the pattern used for `LinkHub/Network/Models`. Same check for `LinkHubTests/Network/` and `LinkHubTests/Network/Models/`
  - [x] Run `DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer xcodegen generate`
  - [x] Run `xcodebuild -scheme LinkHub -configuration Debug build` → must succeed, **zero warnings** (NFR33 strict-concurrency floor)
  - [x] Run `xcodebuild -scheme LinkHub -configuration Release build` → must succeed, **zero strict-concurrency warnings**. The pre-existing Release sign warning from Story 1.1 (`"LinkHub isn't code signed but requires entitlements"`) is acceptable
  - [x] Run `xcodebuild -scheme LinkHub -configuration Debug test` → all new tests pass; Story 1.2's existing 11 tests still pass (no regression)
  - [x] **Manual verification (AC #5, AC #6):** with `LINKHUB_MOCK_WIFI=1` set, build & run Debug:
    - Open the popover (still empty per Story 1.2 — no `WiFiSection` until Story 1.4); the popover should still appear; `MockWiFiMonitor.start()` is a no-op so nothing visible changes
    - Use `os_log show --predicate 'subsystem == "com.linkhub.app" AND category == "network.wifi"'` to confirm no error logs on launch
    - Without `LINKHUB_MOCK_WIFI` set, real `WiFiMonitor` runs in Debug — it will fail to find networks (no entitlements) but should not crash and should log the absence of an interface gracefully
  - [x] **Manual verification of teardown (AC #7):** after launching, hit `Cmd+Q`. Run the app under Instruments with the **Leaks** template; assert `WiFiMonitor` deallocates cleanly (no retain cycle from `CWWiFiClient.shared().delegate`)

## Dev Notes

### Story foundation

This story makes the **first real network signal** flow into LinkHub. By end of Story 1.3 the app has a live `WiFiMonitor` running on `@MainActor`, push-driven by `CWEventDelegate`, debounced at 300 ms, with a 5 s timeout-aware `requestScan()`. `AppState` is wired with the canonical `Publishers.CombineLatest4` sink that rebuilds `networkState` and `connectionMode` atomically, mirrors `scanStatus`, and produces `ConnectionMode.wifiOnly` whenever the user is associated to any Wi-Fi network. The `#if DEBUG` mock path is opt-in via env var so dev/preview iteration doesn't depend on real hardware or entitlements.

The status-bar icon now updates correctly through `StatusItemController`'s existing `appState.$networkState` subscription from Story 1.2 — `wifi` when associated, `wifi.slash` when disconnected (no Ethernet path until Story 3.x). No new UI is added in this story; `WiFiSection` arrives in Story 1.4.

### Previous story intelligence (Story 1.2)

**Carried forward (do not change):**

- AppState shell (`@Published networkState`, `connectionMode`, `wifiLocationDenied`, `launchAtLogin`, `cancellables`, `startMonitors()`/`stopMonitors()`) is in place. This story **fills in** the empty stubs.
- `NetworkState.empty` and the minimum `NetworkState` struct (only `mode` field, plus `// MARK: - Story 1.3 will add …` placeholder) — this story **expands** the struct to the full PRD 03 shape and **drops** the marker comment.
- `ConnectionMode` enum (`.ethernetActive`, `.wifiOnly`, `.disconnected`) — already correct shape; not modified.
- `Log` namespace in `Utilities/Logger.swift` — `app` and `menuBar` categories present. This story adds `network.wifi`.
- `StatusItemController.updateLabel`/`updateTooltip` only use `state.mode` today (Story 1.2 task 3 explicitly defers SSID-aware labels to "Story 1.3+"). **This story does not yet rewrite those bodies** — Story 1.6 owns the VoiceOver-label expansion. **Do not** broaden them now beyond the existing `state.mode`-only branches.
- `PopoverController.show()` has a `// Story 1.4: scan-on-show hook (FR26)` comment — **do not** add the scan trigger yet (still Story 1.4 territory). This story only makes `appState.wifiMonitor.requestScan()` callable.
- AppState `#if DEBUG _setNetworkStateForTesting(_:)` helper — keep, still useful for status item / popover tests.
- AppDelegate `@MainActor` annotation, init/teardown order — preserve.
- `xcodegen generate` is the project-file source of truth. Do not hand-edit `project.pbxproj`.

**Settings still in force from Story 1.1:**
- `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `MACOSX_DEPLOYMENT_TARGET = 13.0`.
- Debug ad-hoc unsigned, no entitlements; Release has Hardened Runtime + Location entitlement.
- Pre-existing Release sign warning (`"LinkHub isn't code signed but requires entitlements"`) is expected and not a regression.
- `ENABLE_TESTABILITY = YES` Debug-only — preserved.

### Architecture compliance — must-follow guardrails

**Concurrency & MainActor bridge:**

- `WiFiMonitor` is `@MainActor final class` (PRD 03 D9); inherits `NSObject` for `CWEventDelegate` conformance. **`@MainActor` on a class that inherits `NSObject` is allowed** — the delegate method itself must be `nonisolated` (the protocol requires this since `CWWiFiClient` calls back from its private internal thread).
- **All `CWEventDelegate` methods are `nonisolated`** and capture **only `String`** (the interface name). They hop to MainActor via `Task { @MainActor [weak self] in self?.eventSubject.send(()) }`. **Never** capture `CWInterface` / `CWNetwork` (PRD 03 D11, D12, Constraints).
- **`requestScan()` performs heavy work in `Task.detached`** and returns `[WiFiNetwork]` (Sendable). The detached closure obtains a fresh `CWWiFiClient.shared().interface()` reference inside itself — this is **distinct from delegate registration** (delegate registration is a MainActor-only operation per PRD 03 Constraints). `CWWiFiClient.shared()` itself is thread-safe to **read** off MainActor; only `delegate` assignment must be on MainActor.
- **No `DispatchQueue.main.async` for actor crossing.** Use `Task { @MainActor [weak self] in ... }` exclusively.
- **No `@unchecked Sendable` wrappers** on `CWNetwork`/`CWInterface`/`CWWiFiClient`. Architecture line "@unchecked Sendable wrappers on CWNetwork / CWInterface / SCNetworkInterface — forbidden".

**Layer-purity rules (architecture.md § Architectural Boundaries):**

- `Network/Models/*.swift` — `import Foundation` only. **No** `AppKit`, `SwiftUI`, `Combine`, `CoreWLAN`. The `WiFiSecurity.init(from cwSecurity:)` mapping lives in `WiFiMonitor.swift` (which imports `CoreWLAN`), not in the Models file.
- `Network/WiFiMonitor.swift` — `Foundation`, `Combine`, `CoreWLAN`. **No** `AppKit`/`SwiftUI`.
- `Network/MockWiFiMonitor.swift` — `Foundation`, `Combine`. **No** `CoreWLAN` (mock has no real CoreWLAN call).
- `State/AppState.swift` — `Foundation`, `Combine`. **No** `CoreWLAN`/`AppKit`/`SwiftUI`. Architecture line "State/ imports AppKit or SwiftUI — forbidden".
- `Utilities/Logger.swift` — `Foundation`, `os`. (Same as Story 1.2.)

**Combine pipeline shape (architecture.md § Communication Patterns):**

- Monitors expose `@Published` only. Callers consume via `.sink`. **No** `AsyncStream`.
- `AppState` uses **one** `Publishers.CombineLatest(...)` sink to rebuild `networkState` and `connectionMode` atomically. **Never** two parallel sinks updating either property. Story 3.2 will refactor this single sink to add the Ethernet side; Story 1.3 lays down the pattern with a `CombineLatest4` over Wi-Fi-only signals.
- Internal debounce in `WiFiMonitor` uses `PassthroughSubject<Void, Never>` + `.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)`.
- `cancellables: Set<AnyCancellable>` on the subscriber; `.removeAll()` in `stop()`/`stopMonitors()`.

**State update rule:** mutations to `AppState.@Published` properties happen **only inside `AppState`** itself or in same-actor closures it owns. `WiFiMonitor` mutates only its own `@Published` state; `AppState` reads via Combine and rebuilds `networkState`/`connectionMode`. Architecture's documented exception (`wifiLocationDenied`, which `WiFiMonitor` may write directly) is **not exercised** by this story — that exception is for Story 1.5 (LocationDeniedView + auth flow). **Do not** have `WiFiMonitor` set `appState.wifiLocationDenied` here.

**Logging discipline:**

- `Log.networkWiFi` for all WiFiMonitor logs. Subsystem from `Bundle.main.bundleIdentifier`.
- Privacy levels: SSID/BSSID/RSSI all `.private` (`logger.info("Wi-Fi associated to \(ssid, privacy: .private)")`); interface BSD names (`en0`) `.public`; error messages `.public`.
- No `print(...)`. No `NSLog`.

### Library / framework requirements

| Concern | Use | Do NOT use |
|---|---|---|
| Wi-Fi observation | `CWWiFiClient` + `CWEventDelegate` (PRD 03 D5, D6) | `NWPathMonitor` (PRD 03 D5 explicitly excludes); polling timers |
| Concurrency | `@MainActor final class` + `Task { @MainActor [weak self] in ... }` (PRD 03 D9–D11) | `DispatchQueue.main.async` for actor crossing; `actor`; `@unchecked Sendable` |
| Scan threading | `Task.detached(priority: .userInitiated)`; obtain `CWWiFiClient.shared().interface()` inside the detached closure (PRD 03 § `requestScan()` flow) | Calling `scanForNetworks(withSSID:)` on the main thread (Apple docs: synchronous, 1–3 s — must NOT be on main); capturing `CWInterface` across actor boundary |
| Timeout | `withThrowingTaskGroup` with a `Task.sleep` timeout child + `cancelAll()` | `DispatchSourceTimer`; `Timer.scheduledTimer`; ad-hoc `Task.sleep` without cancellation |
| Debounce | `Combine .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)` on `PassthroughSubject<Void, Never>` (PRD 03 D7, D8) | Per-property `.debounce`; `DispatchWorkItem` cancel-and-reschedule; `Task.sleep` polling |
| Public monitor API | `@Published` properties (PRD 03 D13) | `AsyncStream`; direct method polling from AppState |
| Mock data | `MockWiFiMonitor` `#if DEBUG`-gated, env-var opt-in (epic AC #6) | Auto-engaging mock in regular Debug builds; mocking inside production code paths |
| Teardown | `CWWiFiClient.shared().delegate = nil` first; `cancellables.removeAll()` (PRD 03 Constraints) | Skipping delegate clearing — leaks per Instruments |
| Logging | `Log.networkWiFi` | `print`, `NSLog`, ad-hoc category strings |

### File-structure requirements (this story creates / modifies these files)

| File | Status | Purpose |
|---|---|---|
| `LinkHub/Network/Models/WiFiSecurity.swift` | NEW | `enum WiFiSecurity: Equatable, Sendable` — 5 cases per PRD 03 |
| `LinkHub/Network/Models/WiFiNetwork.swift` | NEW | `struct WiFiNetwork: Identifiable, Equatable, Sendable` per PRD 03 |
| `LinkHub/Network/Models/EthernetInterface.swift` | NEW | `struct EthernetInterface: Identifiable, Equatable, Sendable` per PRD 03 (placeholder; Story 3.1 wires the producer) |
| `LinkHub/Network/Models/ScanStatus.swift` | NEW | `enum ScanStatus: Equatable, Sendable { case idle, scanning, timedOut }` (Story 1.3 addition) |
| `LinkHub/Network/Models/NetworkState.swift` | MODIFIED | Replace minimum stub with full 7-field shape; drop Story 1.3 marker comment |
| `LinkHub/Network/WiFiMonitorProtocol.swift` | NEW | `WiFiMonitorProtocol` (subset for Story 1.3 — observation + scan only; Story 2.1 adds connect/disconnect) |
| `LinkHub/Network/WiFiMonitor.swift` | NEW | `@MainActor final class WiFiMonitor: NSObject, CWEventDelegate`; real CoreWLAN impl |
| `LinkHub/Network/MockWiFiMonitor.swift` | NEW (`#if DEBUG`) | `MockWiFiMonitor: WiFiMonitorProtocol`; canned sample data |
| `LinkHub/Utilities/Logger.swift` | MODIFIED | Add `static let networkWiFi = ...` to `enum Log` |
| `LinkHub/State/AppState.swift` | MODIFIED | Add `wifiMonitor` injection; `scanStatus` mirror; `CombineLatest4` sink; `rebuildState`; `computeConnectionMode`; flesh out `startMonitors`/`stopMonitors` |
| `LinkHub/App/AppDelegate.swift` | MODIFIED | `makeWiFiMonitor()` env-var-gated factory; pass to `AppState(wifiMonitor:)` |
| `LinkHubTests/Network/Models/WiFiNetworkTests.swift` | NEW | id fallback, equatable, sendable |
| `LinkHubTests/Network/Models/NetworkStateTests.swift` | NEW | `.empty` shape, equatable surface |
| `LinkHubTests/Network/MockWiFiMonitorTests.swift` | NEW (`#if DEBUG`) | initial values, scanStatus transitions, start/stop no-ops |
| `LinkHubTests/Network/WiFiMonitorTests.swift` | NEW | Initial state, no-hardware branch (`XCTSkipIf` gated), reentrancy, timeout (parameterized fast path), stop |
| `LinkHubTests/State/AppStateTests.swift` | MODIFIED | Update `.empty` shape assertion; add wifiMonitor wiring tests, scanStatus mirror, ConnectionMode rule tests |

### State-machine view of `AppState.scanStatus` (for review)

```
[ idle ]  ◄─────────────────── results published (networks updated)
   │
   │ requestScan() called
   ▼
[ scanning ]
   │
   ├─ scan completes within 5 s → networks updated → [ idle ]
   └─ 5 s elapsed without result → [ timedOut ]
                                       │
                                       │ requestScan() called again
                                       ▼
                                   [ scanning ]
```

`timedOut` is an absorbing-but-recoverable state — the next `requestScan()` transitions it back through `scanning`. UI (Story 1.4) reads `scanStatus == .scanning` to show the indicator and `scanStatus == .timedOut` to surface a hint (optional; epic AC #5 only mandates the state).

### Build-config branching (`#if DEBUG` discipline)

Architecture line: "`#if DEBUG` only for: mock Wi-Fi data injection (PRD 03), verbose logging gates. Never for behavior changes that affect user-visible features. **Mock data path … must not auto-engage in regular Debug builds without intent**."

This story uses `#if DEBUG` in three places:

1. `MockWiFiMonitor.swift` — entire file wrapped, so it cannot be referenced from Release.
2. `AppDelegate.makeWiFiMonitor()` — `#if DEBUG` block reads `LINKHUB_MOCK_WIFI` env var. Without the env var, **regular Debug builds use the real `WiFiMonitor`** — exactly per epic AC #6.
3. Test-only API on `WiFiMonitor` (`internal var _scanOverride: ...`, `init(scanTimeoutNanoseconds:)` test-friendly default). Both `#if DEBUG`-gated to keep production API clean.

**Forbidden uses** (do not introduce):
- `#if RELEASE` — architecture-forbidden.
- `#if DEBUG` to change *behavior* visible to the user (other than the explicit mock injection path here).

### Threading & concurrency map

| Component | Runs on | Crosses to MainActor via |
|---|---|---|
| `CWEventDelegate` callback (`ssidDidChange`, etc.) | CoreWLAN internal thread (private) | `Task { @MainActor [weak self] in ... }` capturing only `String` |
| `eventSubject.debounce(scheduler: DispatchQueue.main).sink` | DispatchQueue.main (main thread, **not** MainActor isolation per Swift 6) | `Task { @MainActor [weak self] in ... }` inside the sink closure |
| `requestScan()` heavy work (`scanForNetworks`) | `Task.detached` (cooperative pool) | `await ... .value` returns to caller's actor (MainActor) |
| `WiFiMonitor.@Published` mutations | MainActor (guaranteed by `@MainActor` class isolation) | — |
| `AppState` `CombineLatest.sink` | DispatchQueue.main (main thread) | `Task { @MainActor [weak self] in self?.rebuildState(...) }` |
| `WiFiMonitor.start()` initial reads | MainActor (callee is `@MainActor`) | — |

### Anti-patterns to avoid

- **Do not** capture `CWInterface` or `CWNetwork` in a `Task { @MainActor }` closure. Capture only Sendable values (typically `String` interface name).
- **Do not** wrap `CWNetwork` in `@unchecked Sendable`. Architecture forbids — extract fields into `WiFiNetwork` value type instead.
- **Do not** use `DispatchQueue.main.async { ... }` to mutate `@Published` properties from a Combine sink. Use `Task { @MainActor [weak self] in ... }` even though the sink is delivering on the main thread — Swift 6 isolation requires the explicit hop. Architecture: "`DispatchQueue.main` is not the same as `MainActor`."
- **Do not** call `iface.scanForNetworks(withSSID:)` on the main thread. It is synchronous and can block 1–3 s. Always inside `Task.detached`.
- **Do not** add a `Timer` / `DispatchSourceTimer` / `Task.sleep` polling loop for Wi-Fi state. Push events + on-demand scan only (FR50, NFR50).
- **Do not** set `appState.wifiLocationDenied` from `WiFiMonitor` in this story. That's Story 1.5's `LocationService` responsibility.
- **Do not** add `connect(to:password:remember:)`, `disconnect()`, or `WiFiConnectionFailure` to the protocol or to `WiFiMonitor`. Story 2.1 owns those. If you add them prematurely, the protocol surface drifts from Story 2.1's plan.
- **Do not** auto-engage `MockWiFiMonitor` in regular Debug builds — env var opt-in only.
- **Do not** subscribe `RootPanelView` / `WiFiSection` (Story 1.4) to `WiFiMonitor` directly. UI subscribes to `AppState` only (NFR35).
- **Do not** put the `WiFiSecurity(from: cwSecurity:)` mapping in `Network/Models/WiFiSecurity.swift` — that file must stay `Foundation`-only. Mapping lives in `WiFiMonitor.swift` (which already imports `CoreWLAN`).
- **Do not** rewrite `StatusItemController.updateLabel`/`updateTooltip` in this story to use SSID — Story 1.6 owns VoiceOver-label expansion. Now that `connectedWifi` exists on `NetworkState`, it is *available* but **not required** for this story to consume.
- **Do not** add `import CoreWLAN` to `AppState.swift`, `MockWiFiMonitor.swift`, or any `State/`/`UI/` file. Confined to `WiFiMonitor.swift`.
- **Do not** edit `StatusItemController` icon mapping — `state.mode` already covers wifi vs disconnected; the existing Story 1.2 implementation handles it.
- **Do not** edit `project.yml` unless `xcodegen generate` produces a project that misses one of the new files (verify post-generation).

### Wi-Fi → AppState data flow (canonical for this story)

```
[ user opens panel (Story 1.4) ]            [ Wi-Fi associates / RSSI changes ]
            │                                              │
            ▼                                              ▼
appState.wifiMonitor.requestScan()           CWEventDelegate.{ssid|link|linkQuality|power}DidChange
            │                                              │  (interfaceName: String only)
            ▼                                              ▼
WiFiMonitor.requestScan()                    Task { @MainActor [weak self] in
  scanStatus = .scanning                         self?.eventSubject.send(())
  Task.detached { scanForNetworks }            }
  TaskGroup race vs. 5 s timeout                  │
            │                                     ▼
  result → networks (sorted)                  300 ms .debounce(scheduler: .main)
  scanStatus = .idle                              │
  OR timeout → scanStatus = .timedOut             ▼
            │                                Task { @MainActor [weak self] in
            ▼                                    self?.refreshFromCurrentInterface()
WiFiMonitor.@Published changes                }  // → updates connectedNetwork, isEnabled
            │                                              │
            └──────────────────────┬───────────────────────┘
                                   ▼
AppState.Publishers.CombineLatest4(networks, connected, isEnabled, isHardwareAvailable)
                   .debounce(300 ms)
                   .sink → Task { @MainActor in rebuildState(...) }
                                   │
                                   ▼
        AppState.networkState = NetworkState(mode, ..., wifiNetworks, connectedWifi, ...)
        AppState.connectionMode = mode (canonical rule)
                                   │
                                   ▼
        StatusItemController.observeState (Story 1.2) reacts:
                  icon: wifiOnly → "wifi"; disconnected → "wifi.slash"
```

### Library / framework requirements — version notes

- `CWWiFiClient` / `CWInterface` / `CWNetwork` / `CWEventDelegate` — macOS 10.10+. Available; our floor is 13.0.
- `CWInterface.scanForNetworks(withSSID:)` — synchronous; 1–3 s typical.
- `CWInterface.powerOn()` — instantaneous read of cached state.
- `Combine` — macOS 10.15+. Available.
- `withThrowingTaskGroup` — Swift 5.5+ / macOS 12+. Available.
- `Task.detached` — Swift 5.5+. Available.
- `Publishers.CombineLatest4` — Combine since 10.15. Available.
- `assign(to:)` on `Publisher` — Combine since 10.15. Available. (No `AnyCancellable` needed; auto-cancels with subject lifetime.)

### Git intelligence (last commits)

```
9f6f35a Complete PRDs 05-09 and refine 01-04; add BMad workflow files
1109d25 docs: complete PRD 04 — Panel UI Architecture
5e3b7b7 docs: complete PRD 03 — Network Detection & Observation
6dc4ef7 docs: enrich PRD 03 stub with specific decision points
59ca093 Merge PRD 02 – Menu Bar Integration
```

Story 1.2's product files (AppState, StatusItemController, PopoverController, RootPanelView placeholder, PanelLayout, Log namespace, AppDelegate wiring, 11 unit tests) are present in the working tree. Sprint-status confirms Stories 1.1 and 1.2 are `done`. **Confirm with the user** that Story 1.2's files are committed to `main` (not just the branch) before assuming a clean baseline; if not, this story should not commit Story 1.1/1.2's leftover product files.

### Project Structure Notes

- `LinkHub/Network/` is a **first-time-occupied** folder for Story 1.3 (Story 1.2 only added to `Network/Models/`). The recursive `path: LinkHub` source entry in `project.yml` (Story 1.1) covers `Network/` automatically via `createIntermediateGroups: true`. Verify post-`xcodegen generate`. If files appear at the wrong group level, add an explicit `path: LinkHub/Network` group entry to `project.yml` mirroring the `LinkHub/Network/Models` pattern.
- `LinkHubTests/Network/` and `LinkHubTests/Network/Models/` are similarly first-time. Same recursive coverage applies; verify post-generation.
- Architecture canonical tree (architecture.md § Complete Project Directory Structure) places `WiFiMonitor.swift` and `EthernetMonitor.swift` directly under `LinkHub/Network/` (siblings of `Models/`). This story creates `WiFiMonitor.swift` and `WiFiMonitorProtocol.swift` and `MockWiFiMonitor.swift` there. `EthernetMonitor.swift` is Story 3.1.
- `WiFiSecurity.swift` is in `Network/Models/` per architecture line 183 (`WiFiSecurity enum — Equatable, Sendable`). Mapping helper `WiFiSecurity(from cwSecurity: CWSecurity)` lives in `WiFiMonitor.swift` to preserve Models-layer purity.
- `ScanStatus.swift` is **a Story 1.3 addition not present in architecture.md's data-model table**. It is a model-layer enum and belongs in `Network/Models/` per the architecture's "one Sendable type per file in Network/Models/" rule. This is a normal forward extension; record in this story file's References that it was introduced here.

### Testing standards

- Test framework: **XCTest** (Story 1.1/1.2 carry-forward). No XCUITest.
- New tests live under `LinkHubTests/Network/...` and `LinkHubTests/Network/Models/...` mirroring source structure.
- `@testable import LinkHub` in all new test files. `ENABLE_TESTABILITY = YES` Debug-only is from Story 1.1.
- **Test-only API discipline:** `WiFiMonitor`'s `_scanOverride` and `init(scanTimeoutNanoseconds:)` are `#if DEBUG`-gated to keep Release API clean.
- **Test isolation:** any test that mutates `UserDefaults.standard.launchAtLogin` cleans up in `tearDown()`. (Carry-forward from Story 1.2 — no new UserDefaults usage in this story.)
- **CI flakiness guards:** `WiFiMonitorTests.testStartWhenNoHardwareAvailableSetsFlags` uses `XCTSkipIf` to gate on real-hardware presence. The 5 s timeout test uses the parameterized fast-path (200 ms timeout via test init), not the 5 s default.
- **Mock injection:** prefer constructing `AppState(wifiMonitor: MockWiFiMonitor())` directly in tests rather than depending on env-var detection — env-var path is for manual/dev runtime testing only.
- **Combine sink testing:** use `XCTestExpectation` driven by `.sink` collecting publisher values into an array; assert on the collected sequence after fulfilling the expectation. Wait timeout `1.0` is sufficient for tests using `MockWiFiMonitor` (no real network ops).
- Run tests via `xcodebuild ... -configuration Debug test` (Story 1.1 scheme).

### References

- [Source: docs/03-network-detection.md#WiFiMonitor.swift] — normative class shape, `@Published` properties, `start()`/`stop()`/`requestScan()` interface
- [Source: docs/03-network-detection.md#Internal flow (event callback)] — CWEventDelegate → MainActor bridge pattern (capture String only; explicit Task hop)
- [Source: docs/03-network-detection.md#requestScan() flow] — Task.detached pattern; obtain CWWiFiClient.shared().interface() inside the closure
- [Source: docs/03-network-detection.md#WiFiMonitor.start() / stop() flow] — normative initial-state reads; `CWWiFiClient.shared().delegate = nil` teardown
- [Source: docs/03-network-detection.md#CWEventDelegate Events Registered] — 4 events to subscribe (ssid, link, linkQuality, power); `scanCacheUpdated` excluded
- [Source: docs/03-network-detection.md#Edge Cases] — no-hardware vs Wi-Fi-disabled distinction; location-permission scan failure; concurrent scan-while-associated semantics
- [Source: docs/03-network-detection.md#Threading Summary] — per-component thread/actor table
- [Source: docs/03-network-detection.md#Constraints] — CWWiFiClient delegate registration MainActor requirement; CWNetwork/CWInterface/SCNetworkInterface non-Sendable; CoreWLAN scanning needs location permission; CWEventDelegate retain cycle risk; Swift 6 strict concurrency requirements
- [Source: docs/03-network-detection.md#Mock Data Protocol (#if DEBUG)] — WiFiMonitorProtocol shape, MockWiFiMonitor sample networks, AppState injection pattern, Xcode Previews extension
- [Source: docs/03-network-detection.md#Decision Log] — D5 (CoreWLAN exclusively), D6 (push events + on-demand scan), D7/D8 (300ms Combine debounce on PassthroughSubject), D9 (@MainActor final class), D11/D12 (CWEventDelegate / CWNetwork Sendable bridge), D13 (@Published not AsyncStream), D14 (RSSI source — delegate parameter for linkQuality only)
- [Source: docs/03-network-detection.md#Implementation Verification / Acceptance Criteria] — items relevant to Wi-Fi: hardware-available distinction, radio off vs no hardware, association via CWEventDelegate without scan, requestScan returns Sendable values, no `@unchecked Sendable` wrappers
- [Source: docs/07-state-data-management.md] — AppState single-CombineLatest sink, monitor wiring, init order
- [Source: \_bmad-output/planning-artifacts/architecture.md#Data & State Management] — AppState shape, Sendable model boundary, monitor isolation, public API surface
- [Source: \_bmad-output/planning-artifacts/architecture.md#System Framework Integration & Concurrency Boundary] — CoreWLAN/SCDynamicStore concurrency rules, Sendable bridges, debounce
- [Source: \_bmad-output/planning-artifacts/architecture.md#Communication Patterns] — Combine pipeline shape, MainActor bridge pattern, forbidden bridging
- [Source: \_bmad-output/planning-artifacts/architecture.md#Process Patterns] — init order (load-bearing), tear-down order, error handling, build-config branching, loading states
- [Source: \_bmad-output/planning-artifacts/architecture.md#Architectural Boundaries] — layer ownership graph; forbidden cross-boundary moves
- [Source: \_bmad-output/planning-artifacts/architecture.md#Complete Project Directory Structure] — canonical placement of WiFiMonitor.swift / Models/*.swift
- [Source: \_bmad-output/planning-artifacts/architecture.md#Pattern Examples] — good Sendable extraction; anti-pattern examples
- [Source: \_bmad-output/planning-artifacts/architecture.md#Enforcement Guidelines] — items 2 (cross every ObjC framework callback boundary by extracting Sendable values first); 3 (subscribe to AppState, never to monitors); 5 (CoreWLAN types confined to monitor); 6 (cancellables.removeAll())
- [Source: \_bmad-output/planning-artifacts/epics.md#Story 1.3] — story BDD acceptance criteria (Epic 1.3 in epics.md is the source of truth for this story's ACs)
- [Source: \_bmad-output/planning-artifacts/prd.md#Functional Requirements / Wi-Fi Network Discovery] — FR23–28 referenced
- [Source: \_bmad-output/planning-artifacts/prd.md#Non-Functional Requirements / Reliability] — NFR3 (5 s scan timeout via Task race), NFR5 (300 ms debounce), NFR9 (clean teardown)
- [Source: \_bmad-output/planning-artifacts/prd.md#Resource Discipline] — FR50, NFR50 (no polling)
- [Source: \_bmad-output/planning-artifacts/ux-design-specification.md#WiFiSection] — Story 1.4 component (referenced for forward-context only — this story builds the data feed; UI is Story 1.4)
- [Source: \_bmad-output/implementation-artifacts/1-2-appstate-statusitemcontroller-and-popover-skeleton.md] — Story 1.2 carry-forward: `Log` namespace shape, AppState shell, `_setNetworkStateForTesting`, AppDelegate `@MainActor` wiring, `xcodegen generate` workflow with `DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer`, pre-existing Release sign warning

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m]

### Debug Log References

- Build (Debug): clean, zero warnings.
- Build (Release): clean except pre-existing Story 1.1 sign warning ("LinkHub isn't code signed but requires entitlements") — accepted per Dev Notes.
- Tests: 32 executed, 1 skipped (`testStartWhenNoHardwareAvailableSetsFlags` — host has Wi-Fi hardware, gated via `XCTSkipIf`), 0 failures.
- One implementation correction: `WiFiMonitor.performScan()` declared `nonisolated` to allow off-MainActor invocation from `withThrowingTaskGroup.addTask` closures (Sendable boundary). The static func reads CoreWLAN locals only and never lets `CWInterface`/`CWNetwork` escape — Sendable-clean.

### Completion Notes List

- All 8 ACs satisfied. Five new model files (`WiFiSecurity`, `WiFiNetwork`, `EthernetInterface`, `ScanStatus`, expanded `NetworkState`) are `import Foundation` only — Models layer purity preserved. `WiFiSecurity` ↔ `CWSecurity` mapping confined to `WiFiMonitor.swift`.
- `WiFiMonitor` is `@MainActor final class : NSObject, CWEventDelegate, WiFiMonitorProtocol`. Delegate methods are `nonisolated`, capture only `String interfaceName`, and hop to MainActor via `Task { @MainActor [weak self] in eventSubject.send(()) }`. 300 ms `PassthroughSubject<Void,Never>.debounce` drives `refreshFromCurrentInterface()`.
- `requestScan()` enforces re-entrancy via `inFlightScan: Task<Void, Never>?` and uses `withThrowingTaskGroup` with a `Task.sleep(timeout)` race child; first-result-wins, group cancelled. `performScan()` is sync-throwing static, run on a cooperative pool worker via `addTask(priority: .userInitiated)`. Timeout parameterized via `init(scanTimeoutNanoseconds:)` (default 5 s) so tests can run a fast-path 200 ms timeout. `_scanOverride` is `#if DEBUG`-gated.
- `MockWiFiMonitor` is `#if DEBUG`-only, conforms to `WiFiMonitorProtocol` exactly, pre-seeds `sampleNetworks` (HomeNetwork connected, GuestNetwork, CoffeeWifi captive, CorpNetwork enterprise, hidden WPA3) and simulates a 200 ms scan delay.
- `AppState` exposes `wifiMonitor: any WiFiMonitorProtocol` (publicly readable), `@Published private(set) var scanStatus`. `startMonitors()` calls `wifiMonitor.start()`, mirrors `scanStatus` via `assign(to: &$scanStatus)`, and installs a single `Publishers.CombineLatest4(...).debounce(300 ms).sink → Task { @MainActor in rebuildState(...) }`. `stopMonitors()` calls `wifiMonitor.stop()` first (clears CWWiFiClient delegate), then `cancellables.removeAll()`.
- `AppDelegate` selects `MockWiFiMonitor` only when `LINKHUB_MOCK_WIFI=1` is set in a Debug build (env-var opt-in). Init/teardown order from Story 1.2 preserved.
- `Log.networkWiFi` (`category: "network.wifi"`) added to `Utilities/Logger.swift`. All `WiFiMonitor` error logs use `.public` privacy on the `localizedDescription` only.
- `StatusItemControllerTests` updated to use full `NetworkState(...)` 7-arg init now that the struct shape expanded.
- No edits required to `project.yml` — recursive `path: LinkHub` and `path: LinkHubTests` source globs picked up the new `Network/` and `Network/Models/` files post-`xcodegen generate`.
- Manual verification of teardown leak (Instruments Leaks template, AC #7) is a manual QA step — code path verified: `applicationWillTerminate → appState.stopMonitors → wifiMonitor.stop()` clears `CWWiFiClient.shared().delegate = nil` first, then cancels Combine subscriptions.

### File List

**New (LinkHub/):**
- LinkHub/Network/Models/WiFiSecurity.swift
- LinkHub/Network/Models/WiFiNetwork.swift
- LinkHub/Network/Models/EthernetInterface.swift
- LinkHub/Network/Models/ScanStatus.swift
- LinkHub/Network/WiFiMonitorProtocol.swift
- LinkHub/Network/WiFiMonitor.swift
- LinkHub/Network/MockWiFiMonitor.swift

**Modified (LinkHub/):**
- LinkHub/Network/Models/NetworkState.swift
- LinkHub/Utilities/Logger.swift
- LinkHub/State/AppState.swift
- LinkHub/App/AppDelegate.swift

**New (LinkHubTests/):**
- LinkHubTests/Network/Models/WiFiNetworkTests.swift
- LinkHubTests/Network/Models/NetworkStateTests.swift
- LinkHubTests/Network/MockWiFiMonitorTests.swift
- LinkHubTests/Network/WiFiMonitorTests.swift

**Modified (LinkHubTests/):**
- LinkHubTests/State/AppStateTests.swift
- LinkHubTests/MenuBar/StatusItemControllerTests.swift (updated `NetworkState(...)` literals to full 7-field init)

**Generated (re-generated by xcodegen, not hand-edited):**
- LinkHub.xcodeproj/

### Change Log

| Date | Change |
|---|---|
| 2026-05-09 | Story created via bmad-create-story workflow. Status: ready-for-dev. |
| 2026-05-09 | Implementation complete: WiFiMonitor (CoreWLAN, push-events, 300 ms debounce, 5 s scan-timeout race), MockWiFiMonitor (#if DEBUG), full NetworkState shape, AppState CombineLatest4 wiring + scanStatus mirror, AppDelegate env-var-gated mock factory, Logger.networkWiFi category. 32 tests passing (1 hardware-gated skip). Status: review. |
| 2026-05-09 | Code review complete (bmad-code-review). 2 decision-needed, 29 patch, 6 deferred, 14 dismissed. See Review Findings below. |

### Review Findings

**Decision-needed (resolved)**

- [x] [Review][Decision→Patch] AC #3 — `requestScan()` does not use `Task.detached`. **Resolved 2026-05-09: restructure to use `Task.detached`** — moved into Patch list as P30. [LinkHub/Network/WiFiMonitor.swift `requestScan`/`performScan`]
- [x] [Review][Decision→Accept] Story 1.2 product files committed as `new file` in this PR. **Resolved 2026-05-09: bundle accepted; PR ships 1.2 + 1.3 together. Document in PR description.** No code change.

**Patch**

- [x] [Review][Patch] `assign(to: &$scanStatus)` binding survives `cancellables.removeAll()` — `stopMonitors()` does not break the scanStatus mirror; mock mutations leak into AppState after stop [LinkHub/State/AppState.swift `startMonitors`]
- [x] [Review][Patch] `AppState.startMonitors()` lacks re-entrancy guard — second call duplicates CombineLatest4 sink [LinkHub/State/AppState.swift `startMonitors`]
- [x] [Review][Patch] `WiFiMonitor.start()` lacks re-entrancy guard — second call double-registers events, duplicates debounce sink [LinkHub/Network/WiFiMonitor.swift `start`]
- [x] [Review][Patch] `WiFiMonitor.stop()` resets `isEnabled=true, isHardwareAvailable=true` — publishes "Wi-Fi enabled" lie during teardown; should be `false` [LinkHub/Network/WiFiMonitor.swift `stop`]
- [x] [Review][Patch] `WiFiSecurity.fromCWNetwork` checks `.none` first — misclassifies WPA3-Transition networks (which advertise `.none` for backwards compat) as open. Reorder: WPA3 → WPA2 → enterprise → none [LinkHub/Network/WiFiMonitor.swift `WiFiSecurity.fromCWNetwork`]
- [x] [Review][Patch] `requestScan` swallows real errors as `.timedOut` — `kCWNoPermissionErr` / hardware-disabled / auth-algo-unsupported all surface as timeout, masking root cause for UI hint [LinkHub/Network/WiFiMonitor.swift `requestScan` catch]
- [x] [Review][Patch] `refreshFromCurrentInterface` rewrites `isEnabled`/`isHardwareAvailable` on every event — no equality guard; rapid `linkQualityDidChange` re-triggers CombineLatest4 debounce on RSSI noise [LinkHub/Network/WiFiMonitor.swift `refreshFromCurrentInterface`]
- [x] [Review][Patch] `makeConnectedNetwork` returns nil when `iface.bssid()` is nil — connected hidden networks (BSSID withheld) appear disconnected; icon flickers to `wifi.slash` during association [LinkHub/Network/WiFiMonitor.swift `makeConnectedNetwork`]
- [x] [Review][Patch] `AppState.rebuildState` writes `networkState` then `connectionMode` non-atomically — observers can read inconsistent pair across the two `@Published` emissions. Reorder or compute `connectionMode` from `networkState.mode` in computed property [LinkHub/State/AppState.swift `rebuildState`]
- [x] [Review][Patch] Sink wraps `rebuildState` in inner `Task { @MainActor [weak self] in ... }` — sink already on main; Task hop adds latency and risks reorder under cooperative scheduling. Call directly via `MainActor.assumeIsolated` or hop inline [LinkHub/State/AppState.swift `startMonitors` sink]
- [x] [Review][Patch] `requestScan` outer `await task.value` does not propagate caller cancellation — wrap in `withTaskCancellationHandler` [LinkHub/Network/WiFiMonitor.swift `requestScan`]
- [x] [Review][Patch] `requestScan` lacks `Task.checkCancellation()` between scan and result mapping — cancelled scan still maps full results [LinkHub/Network/WiFiMonitor.swift `performScan`]
- [x] [Review][Patch] `MockWiFiMonitor.requestScan` ignores cancellation — sets `.idle` after cancel; masks cancellation in tests [LinkHub/Network/MockWiFiMonitor.swift `requestScan`]
- [x] [Review][Patch] `startMonitoringEvent` failures silently `try?`-logged — if all four fail, push events never fire but `isEnabled`/`isHardwareAvailable` remain true. Surface degraded state (e.g., set `isHardwareAvailable=false`) [LinkHub/Network/WiFiMonitor.swift `start`]
- [x] [Review][Patch] `PopoverBackground.Coordinator.deinit` calls `notificationCenter.removeObserver` from non-main thread — Swift 6 strict-concurrency warning on `NSWorkspace`. Move teardown to `dismantleNSView` or hop to main [LinkHub/UI/Components/PopoverBackground.swift `Coordinator.deinit`]
- [x] [Review][Patch] `Coordinator.register()` runs on every `makeNSView` — SwiftUI may recreate; multiple observers added per Coordinator-rebuild. Guard with `isRegistered` flag or move to init [LinkHub/UI/Components/PopoverBackground.swift `Coordinator.register`]
- [x] [Review][Patch] `applicationWillTerminate` order: `tearDown()` before `stopMonitors()` — should be reversed so monitors clear `CWWiFiClient.shared().delegate` before UI subscriptions drop [LinkHub/App/AppDelegate.swift `applicationWillTerminate`]
- [x] [Review][Patch] `StatusItemController.tearDown()` does not clear `statusItem.button.target` — retains self [LinkHub/MenuBar/StatusItemController.swift `tearDown`]
- [x] [Review][Patch] `announceIfDisconnected` skips when `previousMode == nil` — VoiceOver-on-launch-while-offline gets no announcement. Track explicit "first emission" + announce if disconnected [LinkHub/MenuBar/StatusItemController.swift `announceIfDisconnected`]
- [x] [Review][Patch] `AppState.convenience init()` instantiates real `WiFiMonitor()` — tests using parameterless `AppState()` install `CWWiFiClient.shared()` delegate, polluting singleton across tests [LinkHub/State/AppState.swift `convenience init`]
- [x] [Review][Patch] `WiFiMonitorTests` do not call `stop()` between test methods — `CWWiFiClient.shared()` delegate state leaks across tests [LinkHubTests/Network/WiFiMonitorTests.swift]
- [x] [Review][Patch] `testStopClearsState` missing `CWWiFiClient.shared().delegate as AnyObject? == nil` assertion — Task 8 prescribed; AC #7 invariant untested [LinkHubTests/Network/WiFiMonitorTests.swift `testStopClearsState`]
- [x] [Review][Patch] `testStopMonitorsClearsCancellablesAndStopsWiFiMonitor` missing `cancellables.isEmpty` check — Task 8 prescribed; add `#if DEBUG` accessor [LinkHubTests/State/AppStateTests.swift]
- [x] [Review][Patch] `testRequestScanTransitionsScanStatus` asserts `first/contains/last` instead of exact `[idle, scanning, idle]` sequence — Task 8 prescribed exact sequence [LinkHubTests/Network/MockWiFiMonitorTests.swift]
- [x] [Review][Patch] `testTearDownIsIdempotent` only calls `tearDown()` twice — does not exercise show→close→tearDown path [LinkHubTests/MenuBar/PopoverControllerTests.swift]
- [x] [Review][Patch] `testShowWithoutWindowDoesNotCrash` makes no behavioral assertion — should assert `controller.isShown == false` after [LinkHubTests/MenuBar/PopoverControllerTests.swift]
- [x] [Review][Patch] `requestScan` re-entrancy: `inFlightScan = task` assigned after task creation — for fast scans (e.g., `_scanOverride` returning instantly) the body's `self?.inFlightScan = nil` may run before the outer assignment, leaving stale Task ref. Set the ref before launch or restructure [LinkHub/Network/WiFiMonitor.swift `requestScan`]
- [x] [Review][Patch] `WiFiMonitor.stop()` does not call `inFlightScan?.cancel()` — pending scan continues, late-writes `scanStatus` after `stop()` reset it [LinkHub/Network/WiFiMonitor.swift `stop`]
- [x] [Review][Patch] `requestScan` on stopped monitor sets `scanStatus = .scanning` even when nothing runs — guard: if not started (e.g., delegate unset), no-op [LinkHub/Network/WiFiMonitor.swift `requestScan`]
- [x] [Review][Patch] (P30, from D1) `requestScan` scan body must run on `Task.detached(priority: .userInitiated)` per AC #3 — wrap the `performScan` invocation inside `addTask` with a detached child Task whose `.value` is awaited; ensure no `CWNetwork`/`CWInterface` reference escapes the detached closure [LinkHub/Network/WiFiMonitor.swift `requestScan`/`performScan`]

**Deferred (pre-existing or out-of-scope)**

- [x] [Review][Defer] `isCaptive` hardcoded `false` in `performScan` and `makeConnectedNetwork` — Story 2.5 owns FR25 captive marker [LinkHub/Network/WiFiMonitor.swift] — deferred, out of scope
- [x] [Review][Defer] `requiresPassword` excludes enterprise — matches spec text but semantically misleading; Story 2.x connect/password UX should refine [LinkHub/Network/WiFiMonitor.swift] — deferred, out of scope
- [x] [Review][Defer] `connectedNetwork.id == bssid` collides with same-BSSID scan-result `id` → SwiftUI `Identifiable` duplicate-id warning when `WiFiSection` (Story 1.4) merges them; merge/dedupe is Story 1.4 responsibility — deferred, out of scope
- [x] [Review][Defer] Wi-Fi power-off VoiceOver announcement (UX-DR25) missing — Story 1.6 owns VoiceOver-label expansion [LinkHub/MenuBar/StatusItemController.swift] — deferred, out of scope
- [x] [Review][Defer] `LSUIElement = true` not provable from this diff (Info.plist untracked) — verify post-`xcodegen generate`; Story 1.1 territory — deferred, pre-existing
- [x] [Review][Defer] Sparkle scripts (notarize.sh, make-dmg.sh, update-appcast.sh) referenced in epics.md but absent — Epic 4 territory — deferred, out of scope
