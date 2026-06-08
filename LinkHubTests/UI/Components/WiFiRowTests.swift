import XCTest
@testable import LinkHub

final class WiFiRowTests: XCTestCase {
    private func network(
        ssid: String?,
        rssi: Int,
        isConnected: Bool,
        requiresPassword: Bool,
        isCaptive: Bool = false
    ) -> WiFiNetwork {
        WiFiNetwork(
            id: ssid ?? "hidden",
            ssid: ssid,
            bssid: ssid,
            rssi: rssi,
            isConnected: isConnected,
            requiresPassword: requiresPassword,
            security: requiresPassword ? .wpa2Personal : .none,
            isCaptive: isCaptive
        )
    }

    func testAccessibilityLabelConnectedWPA2() {
        let n = network(ssid: "HomeNetwork", rssi: -42, isConnected: true, requiresPassword: true)
        XCTAssertEqual(
            WiFiRow.accessibilityLabel(for: n),
            "HomeNetwork, connected, password required, signal excellent"
        )
    }

    func testAccessibilityLabelOpenNotConnected() {
        let n = network(ssid: "CoffeeWifi", rssi: -75, isConnected: false, requiresPassword: false)
        XCTAssertEqual(
            WiFiRow.accessibilityLabel(for: n),
            "CoffeeWifi, open network, signal fair"
        )
    }

    func testAccessibilityLabelHiddenNetwork() {
        let n = network(ssid: nil, rssi: -85, isConnected: false, requiresPassword: true)
        XCTAssertTrue(
            WiFiRow.accessibilityLabel(for: n).hasPrefix("Hidden Network, "),
            "hidden-network label must start with the FR24 literal"
        )
    }

    func testSignalStrengthDescriptionAcrossBuckets() {
        let cases: [(Int, String)] = [
            (-50, "excellent"), (-60, "excellent"),
            (-61, "good"), (-70, "good"),
            (-71, "fair"), (-80, "fair"),
            (-81, "weak"), (-100, "weak")
        ]
        for (rssi, expected) in cases {
            XCTAssertEqual(WiFiRow.signalStrengthDescription(for: rssi), expected, "rssi \(rssi)")
        }
    }
}
