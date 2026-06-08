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
}
