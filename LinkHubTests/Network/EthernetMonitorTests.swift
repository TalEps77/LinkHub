import XCTest
@testable import LinkHub

/// Coverage for `EthernetMonitor`'s pure, SystemConfiguration-free derivation helpers and the
/// `EthernetInterface.isActive` computed property. A live `SCDynamicStore` path is NOT tested
/// here — it requires real hardware / network configuration and a running dispatch source; the
/// derivation helpers carry the unit coverage (per Story 3.1 test plan).
final class EthernetMonitorTests: XCTestCase {

    // MARK: - interfaceState(...) — the four-state derivation (FR16)

    func testInterfaceStateNoLinkWhenLinkDown() {
        // No physical link → .noLink regardless of ipv4 / timeout.
        XCTAssertEqual(EthernetMonitor.interfaceState(hasLink: false, ipv4: nil, dhcpTimedOut: false), .noLink)
        XCTAssertEqual(EthernetMonitor.interfaceState(hasLink: false, ipv4: "10.0.0.2", dhcpTimedOut: false), .noLink)
        XCTAssertEqual(EthernetMonitor.interfaceState(hasLink: false, ipv4: nil, dhcpTimedOut: true), .noLink)
    }

    func testInterfaceStateActiveWhenLinkAndIPv4() {
        // Link + assigned IPv4 → .active, even if a timeout flag is (erroneously) set.
        XCTAssertEqual(EthernetMonitor.interfaceState(hasLink: true, ipv4: "192.168.1.5", dhcpTimedOut: false), .active)
        XCTAssertEqual(EthernetMonitor.interfaceState(hasLink: true, ipv4: "192.168.1.5", dhcpTimedOut: true), .active)
    }

    func testInterfaceStateObtainingWhenLinkNoIPWithinWindow() {
        // Link, no IPv4, timeout not yet elapsed → .obtaining.
        XCTAssertEqual(EthernetMonitor.interfaceState(hasLink: true, ipv4: nil, dhcpTimedOut: false), .obtaining)
    }

    func testInterfaceStateDhcpTimeoutWhenLinkNoIPAfterWindow() {
        // Link, no IPv4, timeout elapsed → .dhcpTimeout (UI-supplied flag).
        XCTAssertEqual(EthernetMonitor.interfaceState(hasLink: true, ipv4: nil, dhcpTimedOut: true), .dhcpTimeout)
    }

    // MARK: - megabitsFromSubtype(...) — link-speed mapping (PRD 05 Decision #1)

    func testMegabitsFromKnownSubtypes() {
        XCTAssertEqual(EthernetMonitor.megabitsFromSubtype("100baseTX"), 100)
        XCTAssertEqual(EthernetMonitor.megabitsFromSubtype("1000baseT"), 1000)
        XCTAssertEqual(EthernetMonitor.megabitsFromSubtype("2500baseT"), 2500)
        XCTAssertEqual(EthernetMonitor.megabitsFromSubtype("10GbaseT"), 10_000)
    }

    func testMegabitsFromUnknownSubtypeIsNil() {
        XCTAssertNil(EthernetMonitor.megabitsFromSubtype("none"))
        XCTAssertNil(EthernetMonitor.megabitsFromSubtype("autoselect"))
        XCTAssertNil(EthernetMonitor.megabitsFromSubtype(""))
    }

    // MARK: - EthernetInterface.isActive computed (preserves AppState.computeConnectionMode API)

    func testIsActiveTrueOnlyForActiveState() {
        XCTAssertTrue(makeInterface(state: .active).isActive)
        XCTAssertFalse(makeInterface(state: .obtaining).isActive)
        XCTAssertFalse(makeInterface(state: .dhcpTimeout).isActive)
        XCTAssertFalse(makeInterface(state: .noLink).isActive)
    }

    private func makeInterface(state: EthernetInterfaceState) -> EthernetInterface {
        EthernetInterface(
            id: "en3",
            bsdName: "en3",
            displayName: "Test Ethernet",
            linkSpeedMbps: state == .active ? 1000 : nil,
            ipv4: state == .active ? "192.168.1.5" : nil,
            state: state
        )
    }
}
