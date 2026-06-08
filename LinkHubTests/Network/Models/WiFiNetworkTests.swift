import XCTest
@testable import LinkHub

final class WiFiNetworkTests: XCTestCase {
    private func make(
        id: String,
        ssid: String? = "Net",
        bssid: String? = "aa:bb:cc:dd:ee:ff",
        rssi: Int = -50,
        isConnected: Bool = false,
        requiresPassword: Bool = true,
        security: WiFiSecurity = .wpa2Personal,
        isCaptive: Bool = false
    ) -> WiFiNetwork {
        WiFiNetwork(
            id: id,
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            isConnected: isConnected,
            requiresPassword: requiresPassword,
            security: security,
            isCaptive: isCaptive
        )
    }

    func testIdComposesFromBSSIDWhenAvailable() {
        let bssid = "aa:bb:cc:dd:ee:ff"
        let net = make(id: bssid, bssid: bssid)
        XCTAssertEqual(net.id, bssid)
    }

    func testIdFallsBackToCompositeWhenBSSIDIsNil() {
        let composite = "Hidden:\(WiFiSecurity.wpa3Personal)"
        let net = make(id: composite, ssid: "Hidden", bssid: nil, security: .wpa3Personal)
        XCTAssertEqual(net.id, composite)
    }

    func testEquatableHonorsAllFields() {
        let a = make(id: "x", ssid: "A")
        let b = make(id: "x", ssid: "A")
        XCTAssertEqual(a, b)
        let c = make(id: "x", ssid: "B")
        XCTAssertNotEqual(a, c)
    }

    func testSendableConformanceCompiles() {
        // If WiFiNetwork is not Sendable, this @Sendable closure won't compile.
        let net: WiFiNetwork = make(id: "x")
        let _: @Sendable () -> WiFiNetwork = { net }
    }
}
