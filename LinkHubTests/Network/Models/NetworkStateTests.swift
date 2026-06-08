import XCTest
@testable import LinkHub

final class NetworkStateTests: XCTestCase {
    func testEmptyShape() {
        let s = NetworkState.empty
        XCTAssertEqual(s.mode, .disconnected)
        XCTAssertEqual(s.ethernetInterfaces, [])
        XCTAssertNil(s.primaryEthernet)
        XCTAssertEqual(s.wifiNetworks, [])
        XCTAssertNil(s.connectedWifi)
        XCTAssertTrue(s.isWiFiEnabled)
        XCTAssertTrue(s.isWiFiHardwareAvailable)
    }

    func testEquatableSurfaceIncludesAllFields() {
        let a = NetworkState.empty
        var b = NetworkState(
            mode: .disconnected,
            ethernetInterfaces: [],
            primaryEthernet: nil,
            wifiNetworks: [],
            connectedWifi: nil,
            isWiFiEnabled: true,
            isWiFiHardwareAvailable: true
        )
        XCTAssertEqual(a, b)
        b = NetworkState(
            mode: .wifiOnly,
            ethernetInterfaces: [],
            primaryEthernet: nil,
            wifiNetworks: [],
            connectedWifi: nil,
            isWiFiEnabled: true,
            isWiFiHardwareAvailable: true
        )
        XCTAssertNotEqual(a, b)
    }
}
