import XCTest
@testable import LinkHub

final class WiFiSectionTests: XCTestCase {
    private func net(_ id: String, rssi: Int, connected: Bool = false) -> WiFiNetwork {
        WiFiNetwork(
            id: id,
            ssid: id,
            bssid: id,
            rssi: rssi,
            isConnected: connected,
            requiresPassword: true,
            security: .wpa2Personal,
            isCaptive: false
        )
    }

    private func state(networks: [WiFiNetwork], connected: WiFiNetwork?) -> NetworkState {
        NetworkState(
            mode: connected != nil ? .wifiOnly : .disconnected,
            ethernetInterfaces: [],
            primaryEthernet: nil,
            wifiNetworks: networks,
            connectedWifi: connected,
            isWiFiEnabled: true,
            isWiFiHardwareAvailable: true
        )
    }

    func testDedupeRemovesConnectedFromOthers() {
        let x = net("X", rssi: -40, connected: true)
        let y = net("Y", rssi: -60)
        let result = WiFiSection.displayedNetworks(from: state(networks: [x, y], connected: x))
        XCTAssertEqual(result.connected?.id, "X")
        XCTAssertEqual(result.others.map(\.id), ["Y"])
    }

    func testNoConnectedShowsAllAsOthers() {
        let nets = [net("A", rssi: -40), net("B", rssi: -60)]
        let result = WiFiSection.displayedNetworks(from: state(networks: nets, connected: nil))
        XCTAssertNil(result.connected)
        XCTAssertEqual(result.others.count, nets.count)
    }

    func testEmptyStateInputs() {
        let result = WiFiSection.displayedNetworks(from: state(networks: [], connected: nil))
        XCTAssertNil(result.connected)
        XCTAssertTrue(result.others.isEmpty)
    }

    func testOrderingPreservesMonitorRSSISort() {
        let nets = [net("A", rssi: -40), net("B", rssi: -60), net("C", rssi: -80)]
        let result = WiFiSection.displayedNetworks(from: state(networks: nets, connected: nil))
        XCTAssertEqual(result.others.map(\.id), ["A", "B", "C"])
    }

    // MARK: - contentMode branch selection (Story 1.5)

    func testContentModeLocationDeniedWinsOverEverything() {
        // Even if a scan is in flight and the list is non-empty, denial replaces the list.
        let mode = WiFiSection.contentMode(
            locationDenied: true,
            isEmpty: false,
            isScanning: true,
            isWiFiEnabled: true,
            isWiFiHardwareAvailable: true
        )
        XCTAssertEqual(mode, .locationDenied)
    }

    func testContentModeScanningWhenEmptyAndScanning() {
        let mode = WiFiSection.contentMode(
            locationDenied: false,
            isEmpty: true,
            isScanning: true,
            isWiFiEnabled: true,
            isWiFiHardwareAvailable: true
        )
        XCTAssertEqual(mode, .scanning)
    }

    func testContentModeEmptyWhenIdleEnabledAndNoNetworks() {
        let mode = WiFiSection.contentMode(
            locationDenied: false,
            isEmpty: true,
            isScanning: false,
            isWiFiEnabled: true,
            isWiFiHardwareAvailable: true
        )
        XCTAssertEqual(mode, .empty)
    }

    func testContentModeListWhenNetworksPresent() {
        let mode = WiFiSection.contentMode(
            locationDenied: false,
            isEmpty: false,
            isScanning: false,
            isWiFiEnabled: true,
            isWiFiHardwareAvailable: true
        )
        XCTAssertEqual(mode, .list)
    }

    func testContentModeWiFiOffWhenDisabled() {
        // Story 2.5: Wi-Fi off shows the "Wi-Fi: Off" state, not the list or empty copy.
        let mode = WiFiSection.contentMode(
            locationDenied: false,
            isEmpty: true,
            isScanning: false,
            isWiFiEnabled: false,
            isWiFiHardwareAvailable: true
        )
        XCTAssertEqual(mode, .wifiOff)
    }

    func testContentModeWiFiOffWinsOverLocationDeniedAndScanning() {
        // Power-off is the highest-priority content state (FR34): nothing to scan or deny when off.
        let mode = WiFiSection.contentMode(
            locationDenied: true,
            isEmpty: false,
            isScanning: true,
            isWiFiEnabled: false,
            isWiFiHardwareAvailable: true
        )
        XCTAssertEqual(mode, .wifiOff)
    }

    // MARK: - LocationDeniedView Settings deep-link (FR40)

    func testLocationDeniedViewSettingsURL() {
        XCTAssertEqual(
            LocationDeniedView.settingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        )
    }
}
