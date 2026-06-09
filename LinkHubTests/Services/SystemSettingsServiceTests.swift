import XCTest
@testable import LinkHub

final class SystemSettingsServiceTests: XCTestCase {
    func testWiFiSettingsURLMatchesSpec() {
        // FR36 / FR38: the only deep-link LinkHub opens for Wi-Fi handoffs.
        XCTAssertEqual(
            SystemSettingsService.wifiSettingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.wifi-settings-extension"
        )
    }
}
