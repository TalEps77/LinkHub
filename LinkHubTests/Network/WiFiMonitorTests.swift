import XCTest
import Combine
import CoreWLAN
import CoreLocation
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
    func testFirstScanRequestsAuthorizationExactlyOnce() async throws {
        try XCTSkipIf(
            CWWiFiClient.shared().interface() == nil,
            "requestScan early-returns before start; needs a started monitor to reach the auth request"
        )
        let monitor = WiFiMonitor(scanTimeoutNanoseconds: 1_000_000_000)
        monitor.start()
        defer { monitor.stop() }
        monitor._scanOverride = { [] }

        XCTAssertFalse(monitor._didRequestAuthorizationForTesting, "auth not requested before first scan")
        await monitor.requestScan()
        XCTAssertTrue(monitor._didRequestAuthorizationForTesting, "first requestScan must request authorization (FR39)")
        // Second scan must not re-arm the guard (it stays true; the system no-ops repeats).
        await monitor.requestScan()
        XCTAssertTrue(monitor._didRequestAuthorizationForTesting)
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

    // MARK: - associate(network:password:) (Story 2.1)

    private static let sampleNetwork = WiFiNetwork(
        id: "aa:bb:cc:dd:ee:ff",
        ssid: "TestNet",
        bssid: "aa:bb:cc:dd:ee:ff",
        rssi: -40,
        isConnected: false,
        requiresPassword: true,
        security: .wpa2Personal,
        isCaptive: false
    )

    @MainActor
    func testAssociateReturnsSuccessViaOverride() async {
        let monitor = WiFiMonitor()
        monitor._associateOverride = { _, _ in .success(()) }
        let result = await monitor.associate(network: Self.sampleNetwork, password: "hunter2")
        // .success(()) — Result<Void, _> isn't Equatable, so assert via isSuccess.
        guard case .success = result else {
            return XCTFail("expected .success, got \(result)")
        }
    }

    @MainActor
    func testAssociateOpenNetworkPassesNilPasswordToOverride() async {
        let monitor = WiFiMonitor()
        let captured = PasswordBox()
        monitor._associateOverride = { _, password in
            await captured.set(password)
            return .success(())
        }
        _ = await monitor.associate(network: Self.sampleNetwork, password: nil)
        let seen = await captured.value
        XCTAssertNil(seen, "open-network association must forward a nil password")
    }

    @MainActor
    func testAssociateForwardsTypedFailureFromOverride() async {
        let monitor = WiFiMonitor()
        monitor._associateOverride = { _, _ in .failure(.wrongPassword) }
        let result = await monitor.associate(network: Self.sampleNetwork, password: "bad")
        guard case .failure(let cause) = result else {
            return XCTFail("expected .failure, got \(result)")
        }
        XCTAssertEqual(cause, .wrongPassword)
    }

    @MainActor
    func testAssociateSurfacesEachCauseTypedFailure() async {
        let monitor = WiFiMonitor()
        let causes: [WiFiConnectionFailure] = [
            .wrongPassword, .outOfRange, .associationTimeout, .authenticationError, .unknown(code: 42)
        ]
        for cause in causes {
            monitor._associateOverride = { _, _ in .failure(cause) }
            let result = await monitor.associate(network: Self.sampleNetwork, password: "x")
            guard case .failure(let got) = result else {
                XCTFail("expected .failure(\(cause))")
                continue
            }
            XCTAssertEqual(got, cause)
        }
    }

    @MainActor
    func testAssociateIsRetryableAfterFailure() async {
        // NFR10: a failed attempt leaves the monitor clean — a subsequent attempt can succeed
        // without any restart / reset. We drive a failure then a success through the same monitor.
        let monitor = WiFiMonitor()
        monitor._associateOverride = { _, _ in .failure(.associationTimeout) }
        let first = await monitor.associate(network: Self.sampleNetwork, password: "x")
        guard case .failure = first else { return XCTFail("expected first attempt to fail") }

        monitor._associateOverride = { _, _ in .success(()) }
        let second = await monitor.associate(network: Self.sampleNetwork, password: "x")
        guard case .success = second else { return XCTFail("expected retry to succeed") }
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

    // MARK: - CoreLocation authorization mapping (Story 1.5, AC #2/#4)

    @MainActor
    func testIsDeniedMapsDeniedAndRestrictedToTrue() {
        XCTAssertTrue(WiFiMonitor.isDenied(.denied))
        XCTAssertTrue(WiFiMonitor.isDenied(.restricted))
    }

    @MainActor
    func testIsDeniedMapsAuthorizedAndNotDeterminedToFalse() {
        XCTAssertFalse(WiFiMonitor.isDenied(.notDetermined))
        XCTAssertFalse(WiFiMonitor.isDenied(.authorizedAlways))
        #if os(macOS)
        XCTAssertFalse(WiFiMonitor.isDenied(.authorized))
        #endif
        XCTAssertFalse(WiFiMonitor.isDenied(.authorizedWhenInUse))
    }

    @MainActor
    func testInitialLocationDeniedReflectsCurrentAuthorizationStatus() {
        // The monitor seeds isLocationDenied from the live CLLocationManager status at init so a
        // previously-denied state shows the denial view immediately on launch. We assert the
        // value agrees with the pure mapping for whatever status the host actually reports.
        let monitor = WiFiMonitor()
        let expected = WiFiMonitor.isDenied(CLLocationManager().authorizationStatus)
        XCTAssertEqual(monitor.isLocationDenied, expected)
    }
}

private actor Counter {
    private(set) var value: Int = 0
    func bump() { value += 1 }
}

/// Captures the password forwarded into the `_associateOverride` closure so the test can assert
/// the open-network path passes `nil`. Actor-isolated to satisfy the `@Sendable` closure.
private actor PasswordBox {
    private(set) var value: String?
    func set(_ password: String?) { value = password }
}
