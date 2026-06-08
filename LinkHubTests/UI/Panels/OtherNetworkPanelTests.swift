import XCTest
@testable import LinkHub

/// Pure-logic tests for the hidden-network join form. The SwiftUI body isn't unit-tested; the
/// load-bearing logic lives in `OtherNetworkPanel`'s static helpers (Picker → `WiFiSecurity`
/// mapping, password-required decision, and the `WiFiNetwork` built for the typed network).
final class OtherNetworkPanelTests: XCTestCase {
    typealias Selection = OtherNetworkPanel.SecuritySelection

    // MARK: - Picker → WiFiSecurity mapping

    func testSecurityMappingOpen() {
        XCTAssertEqual(OtherNetworkPanel.security(for: .open), .none)
    }

    func testSecurityMappingWPA() {
        XCTAssertEqual(OtherNetworkPanel.security(for: .wpa), .wpa2Personal)
    }

    func testSecurityMappingEnterprise() {
        XCTAssertEqual(OtherNetworkPanel.security(for: .enterprise), .enterprise)
    }

    // MARK: - requiresPassword decision

    func testOpenDoesNotRequirePassword() {
        XCTAssertFalse(OtherNetworkPanel.requiresPassword(for: .open))
    }

    func testWPARequiresPassword() {
        XCTAssertTrue(OtherNetworkPanel.requiresPassword(for: .wpa))
    }

    func testEnterpriseRequiresPassword() {
        XCTAssertTrue(OtherNetworkPanel.requiresPassword(for: .enterprise))
    }

    // MARK: - password handed to connect

    func testOpenPassesNilPassword() {
        XCTAssertNil(OtherNetworkPanel.password(for: .open, entered: "ignored"))
    }

    func testWPAPassesEnteredPassword() {
        XCTAssertEqual(OtherNetworkPanel.password(for: .wpa, entered: "hunter2"), "hunter2")
    }

    func testEnterprisePassesEnteredPassword() {
        XCTAssertEqual(OtherNetworkPanel.password(for: .enterprise, entered: "secret"), "secret")
    }

    // MARK: - WiFiNetwork construction for the hidden network

    func testNetworkOpenHasNoPasswordAndNilBSSID() {
        let net = OtherNetworkPanel.network(ssid: "Hidden", security: .open)
        XCTAssertEqual(net.ssid, "Hidden")
        XCTAssertNil(net.bssid)
        XCTAssertFalse(net.requiresPassword)
        XCTAssertFalse(net.isConnected)
        XCTAssertFalse(net.isCaptive)
        XCTAssertEqual(net.security, .none)
    }

    func testNetworkWPARequiresPassword() {
        let net = OtherNetworkPanel.network(ssid: "Hidden", security: .wpa)
        XCTAssertTrue(net.requiresPassword)
        XCTAssertEqual(net.security, .wpa2Personal)
    }

    func testNetworkEnterpriseRequiresPassword() {
        let net = OtherNetworkPanel.network(ssid: "Corp", security: .enterprise)
        XCTAssertTrue(net.requiresPassword)
        XCTAssertEqual(net.security, .enterprise)
    }

    func testNetworkIDIsCompositeOfSSIDAndSecurity() {
        // The composite id (nil-bssid fallback) is what connectingNetworkID matches against.
        let net = OtherNetworkPanel.network(ssid: "MyNet", security: .wpa)
        XCTAssertEqual(net.id, "MyNet:\(WiFiSecurity.wpa2Personal)")
    }

    func testNetworkIDIsStableForSameInputs() {
        let a = OtherNetworkPanel.network(ssid: "MyNet", security: .wpa)
        let b = OtherNetworkPanel.network(ssid: "MyNet", security: .wpa)
        XCTAssertEqual(a.id, b.id)
    }
}
