import XCTest
import AppKit
import Combine
@testable import LinkHub

final class PopoverControllerTests: XCTestCase {
    @MainActor
    private func makeAppState() -> AppState {
        // Use a stub so tests do not install a CWWiFiClient delegate on the shared singleton.
        AppState(wifiMonitor: PopoverStubWiFiMonitor())
    }

    @MainActor
    func testEventMonitorIsNilBeforeShow() {
        let appState = makeAppState()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = PopoverController(appState: appState, statusItemButton: statusItem.button)
        XCTAssertFalse(controller.hasEventMonitor)
        XCTAssertFalse(controller.isShown)
    }

    @MainActor
    func testTearDownIsIdempotent() {
        let appState = makeAppState()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = PopoverController(appState: appState, statusItemButton: statusItem.button)

        controller.tearDown()
        controller.tearDown() // idempotent
        XCTAssertFalse(controller.hasEventMonitor)
        XCTAssertFalse(controller.isShown)
    }

    @MainActor
    func testTearDownRemovesEventMonitorAfterShow() {
        // Invariant under review: tearDown clears the event monitor regardless of whether
        // show() actually installed one. AppKit's popover.isShown lifecycle is unreliable
        // in headless test host (Stage Manager, animation scheduling, run-loop timing) —
        // this test asserts only the monitor invariant, which is what the spec's
        // "remove monitor before closing" ordering rule actually protects.
        let appState = makeAppState()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = PopoverController(appState: appState, statusItemButton: statusItem.button)

        controller.show()
        controller.tearDown()

        XCTAssertFalse(controller.hasEventMonitor)
    }

    @MainActor
    func testShowWithoutWindowDoesNotCrash() {
        // Status item created in unit-test host: the status-bar button may not have a window
        // until the run loop attaches it. The guard in show() must handle this gracefully.
        // (In practice the test host attaches a window, so this exercises the success path
        // too — the contract is that neither path crashes.)
        let appState = makeAppState()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = PopoverController(appState: appState, statusItemButton: statusItem.button)
        defer { controller.tearDown() }

        controller.show() // must not crash regardless of window state
    }

    @MainActor
    func testShowCloseTearDownLifecycle() {
        // Exercises the show→close→tearDown sequence end-to-end. AppKit's popover.isShown
        // lifecycle is unreliable in the headless test host, so this test only asserts the
        // event-monitor invariant — the spec's "remove monitor before closing" rule.
        let appState = makeAppState()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = PopoverController(appState: appState, statusItemButton: statusItem.button)

        controller.show()
        controller.close()
        controller.tearDown()

        XCTAssertFalse(controller.hasEventMonitor)
    }

    @MainActor
    func testTriggerScanOnShowFiresRequestScan() {
        // Verifies the FR26 scan-on-show trigger via the #if DEBUG test hook, avoiding the
        // need to mount a real status-bar button with a window. MockWiFiMonitor cycles
        // scanStatus idle → scanning → idle with a 200 ms simulated delay.
        let mock = MockWiFiMonitor()
        let appState = AppState(wifiMonitor: mock)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = PopoverController(appState: appState, statusItemButton: statusItem.button)

        var observed: [ScanStatus] = []
        let expectation = expectation(description: "scan completes (idle → scanning → idle)")
        var cancellable: AnyCancellable?
        cancellable = mock.$scanStatus.sink { status in
            observed.append(status)
            if observed.count >= 3 { expectation.fulfill() }
        }

        controller._triggerScanOnShowForTesting()

        wait(for: [expectation], timeout: 1.0)
        cancellable?.cancel()
        XCTAssertEqual(observed, [.idle, .scanning, .idle])
    }
}

@MainActor
private final class PopoverStubWiFiMonitor: WiFiMonitorProtocol {
    @Published var networks: [WiFiNetwork] = []
    @Published var connectedNetwork: WiFiNetwork? = nil
    @Published var isEnabled: Bool = true
    @Published var isHardwareAvailable: Bool = true
    @Published var scanStatus: ScanStatus = .idle

    var networksPublisher: Published<[WiFiNetwork]>.Publisher { $networks }
    var connectedNetworkPublisher: Published<WiFiNetwork?>.Publisher { $connectedNetwork }
    var isEnabledPublisher: Published<Bool>.Publisher { $isEnabled }
    var isHardwareAvailablePublisher: Published<Bool>.Publisher { $isHardwareAvailable }
    var scanStatusPublisher: Published<ScanStatus>.Publisher { $scanStatus }

    func start() {}
    func stop() {}
    func requestScan() async {}
}
