import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var networkState: NetworkState = .empty
    @Published private(set) var connectionMode: ConnectionMode = .disconnected
    @Published private(set) var scanStatus: ScanStatus = .idle
    @Published var wifiLocationDenied: Bool = false
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
        }
    }

    let wifiMonitor: any WiFiMonitorProtocol

    private var cancellables: Set<AnyCancellable> = []
    private var isStarted: Bool = false

    convenience init() {
        self.init(wifiMonitor: WiFiMonitor())
    }

    init(wifiMonitor: any WiFiMonitorProtocol) {
        self.wifiMonitor = wifiMonitor
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        // Derive connectionMode from networkState.mode so the two cannot diverge across
        // separate emissions. Bound to AppState lifetime via assign(to:).
        $networkState.map(\.mode).assign(to: &$connectionMode)
    }

    func startMonitors() {
        guard !isStarted else { return }
        isStarted = true
        wifiMonitor.start()

        // Use sink (not assign(to: &$scanStatus)) so stopMonitors can sever the mirror via
        // cancellables.removeAll(). assign(to:) binds to the @Published lifetime instead.
        wifiMonitor.scanStatusPublisher
            .sink { [weak self] status in
                Task { @MainActor [weak self] in self?.scanStatus = status }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            wifiMonitor.networksPublisher,
            wifiMonitor.connectedNetworkPublisher,
            wifiMonitor.isEnabledPublisher,
            wifiMonitor.isHardwareAvailablePublisher
        )
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] networks, connected, isEnabled, isHardwareAvailable in
            // Sink delivers on DispatchQueue.main, which under Swift 6 is not MainActor
            // isolation; hop via Task { @MainActor }. Cooperative-scheduling FIFO ordering is
            // not strictly guaranteed here, but subsequent emissions go through the same
            // 300 ms debounce — out-of-order rebuilds across two debounced ticks are
            // bounded to the rebuilt-state shape and converge on the latest snapshot.
            Task { @MainActor [weak self] in
                self?.rebuildState(
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
        cancellables.removeAll()
        isStarted = false
    }

    private func rebuildState(
        networks: [WiFiNetwork],
        connected: WiFiNetwork?,
        isEnabled: Bool,
        isHardwareAvailable: Bool
    ) {
        let mode = computeConnectionMode(ethernet: [], wifi: connected)
        // Single write — connectionMode mirrors via the init pipeline, so observers cannot
        // see a transient (mode, networkState) mismatch across two @Published emissions.
        self.networkState = NetworkState(
            mode: mode,
            ethernetInterfaces: [],
            primaryEthernet: nil,
            wifiNetworks: networks,
            connectedWifi: connected,
            isWiFiEnabled: isEnabled,
            isWiFiHardwareAvailable: isHardwareAvailable
        )
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
