import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var networkState: NetworkState = .empty
    @Published private(set) var connectionMode: ConnectionMode = .disconnected
    @Published private(set) var scanStatus: ScanStatus = .idle
    /// `id` of the network whose `connect(to:password:)` attempt is currently in flight, or `nil`.
    /// `WiFiRow` reads this to render its `.connecting` visual (Story 2.3 — no separate spinner).
    /// Single source of truth so concurrent taps cannot light up two rows at once.
    @Published private(set) var connectingNetworkID: String?
    @Published var wifiLocationDenied: Bool = false
    /// Whether the Ethernet section should be visible (Story 3.5). Driven by the cable-out grace:
    /// `true` while any interface has link, and held `true` for a 1.5 s grace window after the last
    /// link is lost so transient dock/cable flutter doesn't flicker the UI (FR13). The View reads
    /// this (not the raw interface list) to decide whether to render `EthernetSection`.
    @Published private(set) var isEthernetSectionVisible: Bool = false
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
        }
    }

    let wifiMonitor: any WiFiMonitorProtocol
    let ethernetMonitor: any EthernetMonitorProtocol

    private var cancellables: Set<AnyCancellable> = []
    private var isStarted: Bool = false
    /// In-flight 1.5 s grace timer that hides the Ethernet section after link loss. Cancelled if
    /// link is restored within the window (no flicker). `nil` when no hide is pending.
    private var ethernetHideTask: Task<Void, Never>?
    /// Cable-out grace window (FR13). Injectable so tests can shrink it; defaults to 1.5 s.
    private let ethernetGraceNanoseconds: UInt64

    convenience init() {
        self.init(wifiMonitor: WiFiMonitor(), ethernetMonitor: EthernetMonitor())
    }

    /// Backward-compatible convenience for call sites (and tests/previews) that only inject a
    /// Wi-Fi monitor; the Ethernet monitor defaults to the real `EthernetMonitor` (Story 3.2).
    convenience init(wifiMonitor: any WiFiMonitorProtocol) {
        self.init(wifiMonitor: wifiMonitor, ethernetMonitor: EthernetMonitor())
    }

    init(
        wifiMonitor: any WiFiMonitorProtocol,
        ethernetMonitor: any EthernetMonitorProtocol,
        ethernetGraceNanoseconds: UInt64 = 1_500_000_000
    ) {
        self.wifiMonitor = wifiMonitor
        self.ethernetMonitor = ethernetMonitor
        self.ethernetGraceNanoseconds = ethernetGraceNanoseconds
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        // Derive connectionMode from networkState.mode so the two cannot diverge across
        // separate emissions. Bound to AppState lifetime via assign(to:).
        $networkState.map(\.mode).assign(to: &$connectionMode)
    }

    func startMonitors() {
        guard !isStarted else { return }
        isStarted = true
        wifiMonitor.start()
        ethernetMonitor.start()

        // Use sink (not assign(to: &$scanStatus)) so stopMonitors can sever the mirror via
        // cancellables.removeAll(). assign(to:) binds to the @Published lifetime instead.
        wifiMonitor.scanStatusPublisher
            .sink { [weak self] status in
                Task { @MainActor [weak self] in self?.scanStatus = status }
            }
            .store(in: &cancellables)

        // Mirror the monitor's Location-denial flag (Story 1.5). A plain Bool crosses the
        // protocol boundary — no CoreLocation type reaches the State layer. Stored in
        // cancellables so stopMonitors() severs it. Equality-guarded write avoids redundant
        // @Published emissions on repeated same-value pushes.
        wifiMonitor.isLocationDeniedPublisher
            .sink { [weak self] denied in
                Task { @MainActor [weak self] in
                    guard let self, self.wifiLocationDenied != denied else { return }
                    self.wifiLocationDenied = denied
                }
            }
            .store(in: &cancellables)

        // Story 3.2: combine the Ethernet + Wi-Fi streams so `networkState` and `connectionMode`
        // are always rebuilt atomically in one write — no Epic-2 connect/disconnect path can see a
        // transient (ethernet, wifi) mismatch. CombineLatest takes 2 publishers (the Wi-Fi 4-tuple
        // is itself a nested CombineLatest4); both must emit once before the first combined tick,
        // which they do (every `@Published` emits its current value on subscription).
        let wifiCombined = Publishers.CombineLatest4(
            wifiMonitor.networksPublisher,
            wifiMonitor.connectedNetworkPublisher,
            wifiMonitor.isEnabledPublisher,
            wifiMonitor.isHardwareAvailablePublisher
        )
        Publishers.CombineLatest(ethernetMonitor.interfacesPublisher, wifiCombined)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] ethernet, wifi in
                let (networks, connected, isEnabled, isHardwareAvailable) = wifi
                // Sink delivers on DispatchQueue.main, which under Swift 6 is not MainActor
                // isolation; hop via Task { @MainActor }. Subsequent emissions go through the same
                // 300 ms debounce and converge on the latest snapshot.
                Task { @MainActor [weak self] in
                    self?.rebuildState(
                        ethernet: ethernet,
                        networks: networks,
                        connected: connected,
                        isEnabled: isEnabled,
                        isHardwareAvailable: isHardwareAvailable
                    )
                }
            }
            .store(in: &cancellables)
    }

    func stopMonitors() {
        wifiMonitor.stop()
        ethernetMonitor.stop()
        cancellables.removeAll()
        ethernetHideTask?.cancel()
        ethernetHideTask = nil
        isStarted = false
    }

    /// Applies the Story 3.5 cable-out grace to `isEthernetSectionVisible`. Called on every state
    /// rebuild. When link is present, the section is visible immediately and any pending hide is
    /// cancelled. When the last link is lost while the section is visible, a 1.5 s one-shot timer
    /// hides it — re-checking link at fire time so a reconnect within the window leaves it visible
    /// (FR13). No polling: a single cancellable `Task.sleep`, not a repeating timer (NFR50).
    private func updateEthernetVisibility(hasLink: Bool) {
        if hasLink {
            ethernetHideTask?.cancel()
            ethernetHideTask = nil
            if !isEthernetSectionVisible { isEthernetSectionVisible = true }
        } else if isEthernetSectionVisible, ethernetHideTask == nil {
            let grace = ethernetGraceNanoseconds
            ethernetHideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: grace)
                guard let self, !Task.isCancelled else { return }
                // Only hide if link is still absent after the grace window.
                if !self.networkState.ethernetInterfaces.contains(where: { $0.state != .noLink }) {
                    self.isEthernetSectionVisible = false
                }
                self.ethernetHideTask = nil
            }
        }
    }

    #if DEBUG
    /// Test seam: drives the cable-out grace state machine directly without the Combine pipeline.
    func _updateEthernetVisibilityForTesting(hasLink: Bool) {
        updateEthernetVisibility(hasLink: hasLink)
    }
    #endif

    /// Connection orchestration (NFR35 — the View never calls `associate`/Keychain directly).
    ///
    /// 1. Associates with `network` via the monitor (`password == nil` → open variant).
    /// 2. On `.success`, persists the passphrase keyed by SSID — but only when there *is* a
    ///    non-empty password and a real SSID (hidden / nil-SSID networks have no stable Keychain
    ///    account here; their persistence is Story 2.4's concern). Persist-only-on-success is the
    ///    UX-DR31 rule. A Keychain write failure must NOT fail the connection: it is logged and
    ///    swallowed, and the original `.success` is returned unchanged.
    /// 3. Returns the monitor's `Result` verbatim so the row can map a failure to its caption.
    ///
    /// `connectingNetworkID` is set to `network.id` for the duration of the attempt and cleared in
    /// a `defer` (covering every exit, including a cancelled task), driving the row's `.connecting`
    /// visual without a separate spinner.
    func connect(to network: WiFiNetwork, password: String?) async -> Result<Void, WiFiConnectionFailure> {
        connectingNetworkID = network.id
        defer { connectingNetworkID = nil }

        let result = await wifiMonitor.associate(network: network, password: password)

        if case .success = result,
           let password, !password.isEmpty,
           let ssid = network.ssid, !ssid.isEmpty {
            do {
                try KeychainService.set(password: password, forSSID: ssid)
            } catch {
                // UX-DR31: persistence is best-effort — a failed write must not surface as a
                // connection failure. The radio is already associated.
                Log.servicesKeychain.error("Keychain write failed for SSID after successful connect: \(String(describing: error), privacy: .public)")
            }
        }

        return result
    }

    /// Stored passphrase for `ssid`, or `nil` if none is remembered. Lets `WiFiRow` pre-fill its
    /// `SecureField` on expansion (so a returning user just presses Return) without the View ever
    /// importing `KeychainService` — the Keychain boundary stays inside the State layer (NFR35).
    func storedPassword(forSSID ssid: String) -> String? {
        KeychainService.password(forSSID: ssid)
    }

    /// Flips Wi-Fi power via the monitor (FR35). Routed through `AppState` so the View never calls
    /// the monitor directly (NFR35), mirroring `connect`. The new power state surfaces through the
    /// normal `networkState.isWiFiEnabled` pipeline; the "Wi-Fi turned on/off" announcement is
    /// posted by `StatusItemController` on that flag's edge (Story 1.6), keeping NSAccessibility in
    /// the AppKit layer.
    func setWiFiPower(_ on: Bool) async {
        await wifiMonitor.setPowered(on)
    }

    /// LinkHub's notion of a "known" network (Story 2.6): one whose passphrase LinkHub has stored
    /// in the Keychain. This is the only known-set computable without private API; it gates the
    /// row context menu so unknown networks show no menu. Hidden / nil-SSID networks are never
    /// "known" here.
    func isRemembered(_ network: WiFiNetwork) -> Bool {
        guard let ssid = network.ssid, !ssid.isEmpty else { return false }
        return KeychainService.password(forSSID: ssid) != nil
    }

    /// Forgets LinkHub's stored passphrase for `ssid` (Story 2.6 "Forget"). The *system*
    /// known-network entry is managed by the user in System Settings (UX-DR32) — LinkHub does not
    /// remove it. A Keychain removal failure is logged, not surfaced (the handoff still proceeds).
    func forget(ssid: String) {
        do {
            try KeychainService.remove(forSSID: ssid)
        } catch {
            Log.servicesKeychain.error("Keychain remove failed on Forget: \(String(describing: error), privacy: .public)")
        }
    }

    private func rebuildState(
        ethernet: [EthernetInterface],
        networks: [WiFiNetwork],
        connected: WiFiNetwork?,
        isEnabled: Bool,
        isHardwareAvailable: Bool
    ) {
        let mode = computeConnectionMode(ethernet: ethernet, wifi: connected)
        // Primary = the first active interface (Story 3.3/3.6 refine sort/overflow). Single write —
        // connectionMode mirrors via the init pipeline, so observers cannot see a transient
        // (mode, networkState) mismatch across two @Published emissions.
        self.networkState = NetworkState(
            mode: mode,
            ethernetInterfaces: ethernet,
            primaryEthernet: ethernet.first(where: \.isActive),
            wifiNetworks: networks,
            connectedWifi: connected,
            isWiFiEnabled: isEnabled,
            isWiFiHardwareAvailable: isHardwareAvailable
        )
        // Story 3.5: drive the graced Ethernet-section visibility off the same atomic rebuild.
        updateEthernetVisibility(hasLink: ethernet.contains { $0.state != .noLink })
    }

    private func computeConnectionMode(ethernet: [EthernetInterface], wifi: WiFiNetwork?) -> ConnectionMode {
        if ethernet.contains(where: \.isActive) { return .ethernetActive }
        if wifi != nil { return .wifiOnly }
        return .disconnected
    }

    #if DEBUG
    func _setNetworkStateForTesting(_ state: NetworkState) {
        self.networkState = state
    }

    var _hasActiveSubscriptionsForTesting: Bool { !cancellables.isEmpty }
    #endif
}
