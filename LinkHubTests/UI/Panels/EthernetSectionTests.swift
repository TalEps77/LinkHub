import XCTest
@testable import LinkHub

final class EthernetSectionTests: XCTestCase {
    private func iface(
        _ id: String,
        state: EthernetInterfaceState
    ) -> EthernetInterface {
        EthernetInterface(id: id, bsdName: id, displayName: id, linkSpeedMbps: nil, ipv4: nil, state: state)
    }

    private func networkState(_ interfaces: [EthernetInterface]) -> NetworkState {
        NetworkState(
            mode: interfaces.contains(where: \.isActive) ? .ethernetActive : .disconnected,
            ethernetInterfaces: interfaces,
            primaryEthernet: interfaces.first { $0.isActive },
            wifiNetworks: [],
            connectedWifi: nil,
            isWiFiEnabled: true,
            isWiFiHardwareAvailable: true
        )
    }

    func testEmptyReturnsEmpty() {
        XCTAssertTrue(EthernetSection.displayedInterfaces(from: networkState([])).isEmpty)
    }

    func testSingleInterfaceRendered() {
        let result = EthernetSection.displayedInterfaces(from: networkState([iface("en3", state: .active)]))
        XCTAssertEqual(result.map(\.id), ["en3"])
    }

    func testCapsAtTwoRows() {
        let result = EthernetSection.displayedInterfaces(from: networkState([
            iface("en3", state: .active),
            iface("en5", state: .active),
            iface("en6", state: .obtaining)
        ]))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.id), ["en3", "en5"])
    }

    func testActiveInterfacesSortFirst() {
        // Inactive interface listed first by the monitor; the active one must float to the top.
        let result = EthernetSection.displayedInterfaces(from: networkState([
            iface("en6", state: .obtaining),
            iface("en3", state: .active)
        ]))
        XCTAssertEqual(result.map(\.id), ["en3", "en6"])
    }

    func testPreservesMonitorOrderWithinActiveAndInactiveGroups() {
        let result = EthernetSection.displayedInterfaces(from: networkState([
            iface("en6", state: .noLink),
            iface("en3", state: .active),
            iface("en7", state: .dhcpTimeout)
        ]))
        // Active first (en3), then inactive in monitor order capped at 2 → drops en7.
        XCTAssertEqual(result.map(\.id), ["en3", "en6"])
    }
}
