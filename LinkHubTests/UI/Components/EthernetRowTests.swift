import XCTest
@testable import LinkHub

final class EthernetRowTests: XCTestCase {
    private func iface(
        _ id: String = "en3",
        name: String = "USB LAN",
        speed: Int? = nil,
        ipv4: String? = nil,
        state: EthernetInterfaceState
    ) -> EthernetInterface {
        EthernetInterface(id: id, bsdName: id, displayName: name, linkSpeedMbps: speed, ipv4: ipv4, state: state)
    }

    // MARK: - speedDescription

    func testSpeedDescriptionNilIsEmpty() {
        XCTAssertEqual(EthernetRow.speedDescription(nil), "")
    }

    func testSpeedDescriptionMbpsBelowOneGig() {
        XCTAssertEqual(EthernetRow.speedDescription(10), "10 Mbps")
        XCTAssertEqual(EthernetRow.speedDescription(100), "100 Mbps")
        XCTAssertEqual(EthernetRow.speedDescription(999), "999 Mbps")
    }

    func testSpeedDescriptionGbpsAtAndAboveOneGig() {
        XCTAssertEqual(EthernetRow.speedDescription(1000), "1.0 Gbps")
        XCTAssertEqual(EthernetRow.speedDescription(2500), "2.5 Gbps")
        XCTAssertEqual(EthernetRow.speedDescription(10_000), "10.0 Gbps")
    }

    // MARK: - statusLabel

    func testStatusLabelPerState() {
        XCTAssertEqual(EthernetRow.statusLabel(for: .active), "Active")
        XCTAssertEqual(EthernetRow.statusLabel(for: .obtaining), "Obtaining…")
        XCTAssertEqual(EthernetRow.statusLabel(for: .dhcpTimeout), "DHCP timeout")
        XCTAssertEqual(EthernetRow.statusLabel(for: .noLink), "No link")
    }

    // MARK: - dotColor

    func testDotColorPerState() {
        XCTAssertEqual(EthernetRow.dotColor(for: .active), .green)
        XCTAssertEqual(EthernetRow.dotColor(for: .obtaining), .yellow)
        XCTAssertEqual(EthernetRow.dotColor(for: .dhcpTimeout), .red)
        XCTAssertEqual(EthernetRow.dotColor(for: .noLink), .secondary)
    }

    // MARK: - detailString

    func testDetailStringActiveJoinsIpAndSpeed() {
        let i = iface(speed: 1000, ipv4: "192.168.1.5", state: .active)
        XCTAssertEqual(EthernetRow.detailString(for: i), "192.168.1.5 • 1.0 Gbps")
    }

    func testDetailStringActiveIpOnlyWhenSpeedMissing() {
        let i = iface(speed: nil, ipv4: "10.0.0.2", state: .active)
        XCTAssertEqual(EthernetRow.detailString(for: i), "10.0.0.2")
    }

    func testDetailStringActiveSpeedOnlyWhenIpMissing() {
        let i = iface(speed: 100, ipv4: nil, state: .active)
        XCTAssertEqual(EthernetRow.detailString(for: i), "100 Mbps")
    }

    func testDetailStringNonActiveUsesStatusLabel() {
        XCTAssertEqual(EthernetRow.detailString(for: iface(state: .obtaining)), "Obtaining…")
        XCTAssertEqual(EthernetRow.detailString(for: iface(state: .dhcpTimeout)), "DHCP timeout")
        XCTAssertEqual(EthernetRow.detailString(for: iface(state: .noLink)), "No link")
    }

    // MARK: - accessibilityLabel

    // UX-DR23 templates (Story 3.6).

    func testAccessibilityLabelActive() {
        let i = iface(name: "Thunderbolt Ethernet", speed: 1000, ipv4: "192.168.1.5", state: .active)
        XCTAssertEqual(
            EthernetRow.accessibilityLabel(for: i),
            "Thunderbolt Ethernet, active, 192.168.1.5, 1.0 Gbps"
        )
    }

    func testAccessibilityLabelActiveNoAddressNoSpeed() {
        let i = iface(name: "USB LAN", speed: nil, ipv4: nil, state: .active)
        XCTAssertEqual(EthernetRow.accessibilityLabel(for: i), "USB LAN, active, no address")
    }

    func testAccessibilityLabelObtaining() {
        XCTAssertEqual(EthernetRow.accessibilityLabel(for: iface(name: "USB-C LAN", state: .obtaining)),
                       "USB-C LAN, obtaining address")
    }

    func testAccessibilityLabelDhcpTimeout() {
        XCTAssertEqual(EthernetRow.accessibilityLabel(for: iface(name: "USB-C LAN", state: .dhcpTimeout)),
                       "USB-C LAN, DHCP timeout, no address")
    }

    func testAccessibilityLabelNoLink() {
        XCTAssertEqual(EthernetRow.accessibilityLabel(for: iface(name: "Dock Ethernet", state: .noLink)),
                       "Dock Ethernet, no link")
    }
}
