#if DEBUG
import Foundation
import Combine

@MainActor
final class MockWiFiMonitor: WiFiMonitorProtocol {
    static let sampleNetworks: [WiFiNetwork] = [
        WiFiNetwork(
            id: "aa:bb:cc:dd:ee:01",
            ssid: "HomeNetwork",
            bssid: "aa:bb:cc:dd:ee:01",
            rssi: -42,
            isConnected: true,
            requiresPassword: true,
            security: .wpa2Personal,
            isCaptive: false
        ),
        WiFiNetwork(
            id: "aa:bb:cc:dd:ee:02",
            ssid: "GuestNetwork",
            bssid: "aa:bb:cc:dd:ee:02",
            rssi: -55,
            isConnected: false,
            requiresPassword: true,
            security: .wpa2Personal,
            isCaptive: false
        ),
        WiFiNetwork(
            id: "aa:bb:cc:dd:ee:03",
            ssid: "CoffeeWifi",
            bssid: "aa:bb:cc:dd:ee:03",
            rssi: -68,
            isConnected: false,
            requiresPassword: false,
            security: .none,
            isCaptive: true
        ),
        WiFiNetwork(
            id: "aa:bb:cc:dd:ee:04",
            ssid: "CorpNetwork",
            bssid: "aa:bb:cc:dd:ee:04",
            rssi: -72,
            isConnected: false,
            requiresPassword: false,
            security: .enterprise,
            isCaptive: false
        ),
        WiFiNetwork(
            id: "aa:bb:cc:dd:ee:05",
            ssid: nil,
            bssid: "aa:bb:cc:dd:ee:05",
            rssi: -80,
            isConnected: false,
            requiresPassword: true,
            security: .wpa3Personal,
            isCaptive: false
        )
    ]

    @Published var networks: [WiFiNetwork]
    @Published var connectedNetwork: WiFiNetwork?
    @Published var isEnabled: Bool = true
    @Published var isHardwareAvailable: Bool = true
    @Published var scanStatus: ScanStatus = .idle
    @Published var isLocationDenied: Bool = false

    var networksPublisher: Published<[WiFiNetwork]>.Publisher { $networks }
    var connectedNetworkPublisher: Published<WiFiNetwork?>.Publisher { $connectedNetwork }
    var isEnabledPublisher: Published<Bool>.Publisher { $isEnabled }
    var isHardwareAvailablePublisher: Published<Bool>.Publisher { $isHardwareAvailable }
    var scanStatusPublisher: Published<ScanStatus>.Publisher { $scanStatus }
    var isLocationDeniedPublisher: Published<Bool>.Publisher { $isLocationDenied }

    init() {
        self.networks = Self.sampleNetworks
        self.connectedNetwork = Self.sampleNetworks.first { $0.isConnected }
    }

    func start() {}
    func stop() {}

    func requestScan() async {
        scanStatus = .scanning
        do {
            try await Task.sleep(nanoseconds: 200_000_000)
            networks = Self.sampleNetworks
            scanStatus = .idle
        } catch {
            // Honor cancellation — leave networks untouched, return to idle.
            scanStatus = .idle
        }
    }
}
#endif
