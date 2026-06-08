import XCTest
import Combine
import CoreWLAN
@testable import LinkHub

final class WiFiMonitorTests: XCTestCase {
    override func tearDown() {
        // CWWiFiClient.shared() is a process-wide singleton; clear delegate between tests
        // to prevent cross-test bleed when a previous test forgot to call stop().
        // Non-isolated tearDown — CWWiFiClient mutation is documented thread-safe for
        // delegate-clear and the host runs tests serially on the main thread anyway.
        MainActor.assumeIsolated {
            CWWiFiClient.shared().delegate = nil
        }
        super.tearDown()
    }

    @MainActor
    func testInitialStateBeforeStart() {
        let monitor = WiFiMonitor()
        XCTAssertEqual(monitor.networks, [])
        XCTAssertNil(monitor.connectedNetwork)
        XCTAssertTrue(monitor.isEnabled)
        XCTAssertTrue(monitor.isHardwareAvailable)
        XCTAssertEqual(monitor.scanStatus, .idle)
    }

    @MainActor
    func testStartWhenNoHardwareAvailableSetsFlags() throws {
        try XCTSkipIf(
            CWWiFiClient.shared().interface() != nil,
            "Hardware Wi-Fi present; this test exercises the no-hardware branch only"
        )
        let monitor = WiFiMonitor()
        monitor.start()
        XCTAssertFalse(monitor.isHardwareAvailable)
        XCTAssertFalse(monitor.isEnabled)
        XCTAssertNil(monitor.connectedNetwork)
        monitor.stop()
    }

    #if DEBUG
    @MainActor
    func testRequestScanRespectsReentrancyGuard() async throws {
        try XCTSkipIf(
            CWWiFiClient.shared().interface() == nil,
            "requestScan early-returns when monitor is not started; needs hardware path or override-able start"
        )
        let monitor = WiFiMonitor(scanTimeoutNanoseconds: 1_000_000_000)
        monitor.start()
        defer { monitor.stop() }
        let counter = Counter()
        monitor._scanOverride = {
            await counter.bump()
            try await Task.sleep(nanoseconds: 100_000_000)
            return []
        }

        async let first: Void = monitor.requestScan()
        async let second: Void = monitor.requestScan()
        _ = await (first, second)

        let count = await counter.value
        XCTAssertEqual(count, 1, "Second concurrent requestScan must be a no-op")
    }

    @MainActor
    func testRequestScanTimesOutAfterParameterizedTimeout() async throws {
        try XCTSkipIf(
            CWWiFiClient.shared().interface() == nil,
            "requestScan early-returns when monitor is not started"
        )
        let monitor = WiFiMonitor(scanTimeoutNanoseconds: 200_000_000)
        monitor.start()
        defer { monitor.stop() }
        monitor._scanOverride = {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return []
        }
        await monitor.requestScan()
        XCTAssertEqual(monitor.scanStatus, .timedOut)
    }

    @MainActor
    func testRequestScanCompletesAndUpdatesNetworks() async throws {
        try XCTSkipIf(
            CWWiFiClient.shared().interface() == nil,
            "requestScan early-returns when monitor is not started"
        )
        let monitor = WiFiMonitor(scanTimeoutNanoseconds: 1_000_000_000)
        monitor.start()
        defer { monitor.stop() }
        let sample = WiFiNetwork(
            id: "aa:bb:cc:dd:ee:ff",
            ssid: "Test",
            bssid: "aa:bb:cc:dd:ee:ff",
            rssi: -40,
            isConnected: false,
            requiresPassword: true,
            security: .wpa2Personal,
            isCaptive: false
        )
        monitor._scanOverride = { [sample] in [sample] }
        await monitor.requestScan()
        XCTAssertEqual(monitor.scanStatus, .idle)
        XCTAssertEqual(monitor.networks, [sample])
    }

    @MainActor
    func testRequestScanIsNoOpBeforeStart() async {
        // Sanity: a stopped (or never-started) monitor must not transition through .scanning.
        let monitor = WiFiMonitor(scanTimeoutNanoseconds: 1_000_000_000)
        var observed: [ScanStatus] = []
        let cancellable = monitor.scanStatusPublisher.sink { observed.append($0) }
        defer { cancellable.cancel() }
        await monitor.requestScan()
        XCTAssertEqual(observed, [.idle])
    }
    #endif

    @MainActor
    func testStopClearsDelegateAndState() {
        let monitor = WiFiMonitor()
        monitor.start()
        monitor.stop()
        XCTAssertNil(monitor.connectedNetwork)
        XCTAssertEqual(monitor.networks, [])
        XCTAssertEqual(monitor.scanStatus, .idle)
        // AC #7 invariant: the CoreWLAN delegate is cleared so the retain edge is broken.
        XCTAssertNil(CWWiFiClient.shared().delegate as AnyObject?)
        // Stop also resets the optimistic "Wi-Fi enabled" defaults so subscribers do not see
        // a misleading "everything fine" emission during teardown.
        XCTAssertFalse(monitor.isEnabled)
        XCTAssertFalse(monitor.isHardwareAvailable)
    }
}

private actor Counter {
    private(set) var value: Int = 0
    func bump() { value += 1 }
}
