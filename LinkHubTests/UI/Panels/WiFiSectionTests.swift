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
}
