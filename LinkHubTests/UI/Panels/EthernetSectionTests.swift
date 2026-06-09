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

    func testFiltersNoLinkAndSortsActiveFirst() {
        // Story 3.6: cable-out (.noLink) interfaces are excluded; active floats first.
        let result = EthernetSection.displayedInterfaces(from: networkState([
            iface("en6", state: .noLink),       // filtered out (no cable)
            iface("en3", state: .active),
            iface("en7", state: .dhcpTimeout)
        ]))
        XCTAssertEqual(result.map(\.id), ["en3", "en7"])
    }

    func testTieBreakByBsdName() {
        // Two active interfaces sort by BSD name (FR20 stable tie-break), regardless of input order.
        let result = EthernetSection.displayedInterfaces(from: networkState([
            iface("en5", state: .active),
            iface("en3", state: .active)
        ]))
        XCTAssertEqual(result.map(\.id), ["en3", "en5"])
    }

    func testOverflowCountBeyondTwoLinked() {
        let state = networkState([
            iface("en3", state: .active),
            iface("en4", state: .active),
            iface("en5", state: .obtaining),
            iface("en6", state: .dhcpTimeout),
            iface("en7", state: .noLink)        // not counted — no link
        ])
        XCTAssertEqual(EthernetSection.displayedInterfaces(from: state).count, 2)
        XCTAssertEqual(EthernetSection.overflowCount(from: state), 2) // 4 linked - 2 inline
    }

    func testNoOverflowAtOrBelowTwo() {
        let state = networkState([iface("en3", state: .active), iface("en4", state: .obtaining)])
        XCTAssertEqual(EthernetSection.overflowCount(from: state), 0)
    }
}
