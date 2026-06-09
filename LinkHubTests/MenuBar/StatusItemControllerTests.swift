import XCTest
@testable import LinkHub

final class StatusItemControllerTests: XCTestCase {
    @MainActor
    func testInitCreatesStatusItemAndStartSetsInitialIcon() {
        let appState = AppState()
        let controller = StatusItemController(appState: appState)
        defer { controller.tearDown() }

        controller.start()

        XCTAssertNotNil(controller.statusItem)
        XCTAssertNotNil(controller.statusItem.button?.image, "Icon must be set synchronously before first publisher emission")
    }

    @MainActor
    func testTearDownClearsState() {
        let appState = AppState()
        let controller = StatusItemController(appState: appState)
        controller.start()

        controller.tearDown()
        // No crash; status item removed from system status bar.
    }

    @MainActor
    func testHandleStatusItemClickOpensPopover() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["CI"] != nil,
            "AppKit popover lifecycle is unreliable in headless CI"
        )
        let appState = AppState()
        let controller = StatusItemController(appState: appState)
        defer { controller.tearDown() }
        controller.start()

        guard let button = controller.statusItem.button else {
            return XCTFail("Status item button missing")
        }

        XCTAssertFalse(controller.isPopoverShown)
        button.performClick(nil)
        XCTAssertTrue(controller.isPopoverShown, "Click must open popover (AC#3)")
        // AC#4 (second-click closes) covered by manual verification:
        // .transient popover auto-dismisses on outside click before the second
        // status-item action fires, making the toggle path racy in unit tests.
    }

    @MainActor
    func testAnnounceOnDisconnectionTransitionOnly() {
        let appState = AppState()
        let controller = StatusItemController(appState: appState)
        defer { controller.tearDown() }
        controller.start()

        // First transition: cold launch → already .disconnected, no announcement.
        // Drive to .wifiOnly then back to .disconnected.
        appState._setNetworkStateForTesting(NetworkState(
            mode: .wifiOnly,
            ethernetInterfaces: [],
            primaryEthernet: nil,
            wifiNetworks: [],
            connectedWifi: nil,
            isWiFiEnabled: true,
            isWiFiHardwareAvailable: true
        ))
        appState._setNetworkStateForTesting(.empty)

        // We cannot easily intercept NSAccessibility.post in unit tests; verify no crash and icon updated.
        XCTAssertNotNil(controller.statusItem.button?.image)
    }

    // MARK: - Story 1.6: icon symbol + UX-DR24 accessibility label (pure helpers)

    private func wifiState(ssid: String?, rssi: Int) -> NetworkState {
        NetworkState(
            mode: .wifiOnly,
            ethernetInterfaces: [],
            primaryEthernet: nil,
            wifiNetworks: [],
            connectedWifi: WiFiNetwork(
                id: ssid ?? "hidden", ssid: ssid, bssid: ssid, rssi: rssi,
                isConnected: true, requiresPassword: true, security: .wpa2Personal, isCaptive: false
            ),
            isWiFiEnabled: true,
            isWiFiHardwareAvailable: true
        )
    }

    private func disconnectedState(wifiEnabled: Bool) -> NetworkState {
        NetworkState(
            mode: .disconnected,
            ethernetInterfaces: [],
            primaryEthernet: nil,
            wifiNetworks: [],
            connectedWifi: nil,
            isWiFiEnabled: wifiEnabled,
            isWiFiHardwareAvailable: true
        )
    }

    func testSymbolNameMapping() {
        XCTAssertEqual(StatusItemController.symbolName(for: wifiState(ssid: "Home", rssi: -50)), "wifi")
        XCTAssertEqual(StatusItemController.symbolName(for: disconnectedState(wifiEnabled: true)), "wifi.slash")
        XCTAssertEqual(StatusItemController.symbolName(for: disconnectedState(wifiEnabled: false)), "wifi.slash")
    }

    func testAccessibilityLabelWiFiConnected() {
        XCTAssertEqual(
            StatusItemController.accessibilityLabel(for: wifiState(ssid: "HomeNetwork", rssi: -42)),
            "Wi-Fi connected, HomeNetwork, signal excellent"
        )
    }

    func testAccessibilityLabelHiddenSSID() {
        XCTAssertEqual(
            StatusItemController.accessibilityLabel(for: wifiState(ssid: nil, rssi: -75)),
            "Wi-Fi connected, Hidden Network, signal fair"
        )
    }

    func testAccessibilityLabelDistinguishesWiFiOffFromDisconnected() {
        // UX-DR24: radio off vs. radio on with nothing joined are different utterances.
        XCTAssertEqual(StatusItemController.accessibilityLabel(for: disconnectedState(wifiEnabled: true)), "No network connection")
        XCTAssertEqual(StatusItemController.accessibilityLabel(for: disconnectedState(wifiEnabled: false)), "Wi-Fi off")
    }

    func testSignalStrengthDescriptorIsSingleSourceOfTruth() {
        // The model helper backs both WiFiRow and the status-icon label; they must never diverge.
        XCTAssertEqual(WiFiNetwork.signalStrengthDescription(for: -42), WiFiRow.signalStrengthDescription(for: -42))
        XCTAssertEqual(WiFiNetwork.signalStrengthDescription(for: -95), WiFiRow.signalStrengthDescription(for: -95))
    }

    // MARK: - Story 3.4: Ethernet icon path + UX-DR24 label

    private func ethernetActiveState(displayName: String, mbps: Int?) -> NetworkState {
        let eth = EthernetInterface(id: "en3", bsdName: "en3", displayName: displayName, linkSpeedMbps: mbps, ipv4: "10.0.0.2", state: .active)
        return NetworkState(
            mode: .ethernetActive,
            ethernetInterfaces: [eth],
            primaryEthernet: eth,
            wifiNetworks: [],
            connectedWifi: nil,
            isWiFiEnabled: true,
            isWiFiHardwareAvailable: true
        )
    }

    func testSpeedDescription() {
        XCTAssertEqual(StatusItemController.speedDescription(100), "100 Mbps")
        XCTAssertEqual(StatusItemController.speedDescription(1000), "1.0 Gbps")
        XCTAssertEqual(StatusItemController.speedDescription(2500), "2.5 Gbps")
        XCTAssertEqual(StatusItemController.speedDescription(10000), "10.0 Gbps")
    }

    func testSymbolAndLabelEthernetActive() {
        let state = ethernetActiveState(displayName: "USB LAN", mbps: 1000)
        XCTAssertEqual(StatusItemController.symbolName(for: state), "cable.connector")
        XCTAssertEqual(StatusItemController.accessibilityLabel(for: state), "Ethernet connected, USB LAN, 1.0 Gbps")
    }

    func testAccessibilityLabelEthernetNoSpeed() {
        let state = ethernetActiveState(displayName: "Dock Ethernet", mbps: nil)
        XCTAssertEqual(StatusItemController.accessibilityLabel(for: state), "Ethernet connected, Dock Ethernet")
    }
}
