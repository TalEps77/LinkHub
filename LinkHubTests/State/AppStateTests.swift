import XCTest
import Combine
@testable import LinkHub

final class AppStateTests: XCTestCase {
    private let launchAtLoginKey = "launchAtLogin"
    private var savedLaunchAtLogin: Bool = false

    override func setUp() {
        super.setUp()
        savedLaunchAtLogin = UserDefaults.standard.bool(forKey: launchAtLoginKey)
        UserDefaults.standard.removeObject(forKey: launchAtLoginKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedLaunchAtLogin, forKey: launchAtLoginKey)
        super.tearDown()
    }

    @MainActor
    func testInitializerSetsDefaultPublishedValues() {
        let state = AppState(wifiMonitor: StubWiFiMonitor())
        XCTAssertEqual(state.networkState, .empty)
        XCTAssertEqual(state.networkState.mode, .disconnected)
        XCTAssertEqual(state.connectionMode, .disconnected)
        XCTAssertEqual(state.scanStatus, .idle)
        XCTAssertFalse(state.wifiLocationDenied)
        XCTAssertFalse(state.launchAtLogin)
    }

    @MainActor
    func testLaunchAtLoginPersistsToUserDefaults() {
        let state = AppState(wifiMonitor: StubWiFiMonitor())
        state.launchAtLogin = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: launchAtLoginKey))
        state.launchAtLogin = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: launchAtLoginKey))
    }

    @MainActor
    func testLaunchAtLoginInitialReadsFromUserDefaults() {
        UserDefaults.standard.set(true, forKey: launchAtLoginKey)
        let state = AppState(wifiMonitor: StubWiFiMonitor())
        XCTAssertTrue(state.launchAtLogin)
    }

    #if DEBUG
    @MainActor
    func testInitWithMockWiFiMonitorWiresPublishedState() async {
        let mock = MockWiFiMonitor()
        let state = AppState(wifiMonitor: mock)
        state.startMonitors()
        defer { state.stopMonitors() }

        let expectation = XCTestExpectation(description: "networkState reflects mock sample")
        var cancellables: Set<AnyCancellable> = []
        state.$networkState
            .sink { ns in
                if ns.wifiNetworks == MockWiFiMonitor.sampleNetworks,
                   ns.connectedWifi != nil,
                   ns.mode == .wifiOnly {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(state.connectionMode, .wifiOnly)
    }
    #endif

    @MainActor
    func testStopMonitorsClearsCancellablesAndStopsWiFiMonitor() {
        let stub = StubWiFiMonitor()
        let state = AppState(wifiMonitor: stub)
        state.startMonitors()
        #if DEBUG
        XCTAssertTrue(state._hasActiveSubscriptionsForTesting, "startMonitors must wire subscriptions")
        #endif
        state.stopMonitors()
        XCTAssertEqual(stub.stopCallCount, 1)
        #if DEBUG
        XCTAssertFalse(state._hasActiveSubscriptionsForTesting, "stopMonitors must clear cancellables")
        #endif
    }

    #if DEBUG
    @MainActor
    func testScanStatusMirrorsWiFiMonitor() async {
        let mock = MockWiFiMonitor()
        let state = AppState(wifiMonitor: mock)
        state.startMonitors()
        defer { state.stopMonitors() }

        mock.scanStatus = .scanning
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(state.scanStatus, .scanning)

        mock.scanStatus = .idle
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(state.scanStatus, .idle)
    }

    @MainActor
    func testConnectionModeRuleWifiOnly() async {
        let mock = MockWiFiMonitor()
        let state = AppState(wifiMonitor: mock)
        state.startMonitors()
        defer { state.stopMonitors() }

        let expectation = XCTestExpectation(description: "wifiOnly")
        var cancellables: Set<AnyCancellable> = []
        state.$connectionMode
            .sink { if $0 == .wifiOnly { expectation.fulfill() } }
            .store(in: &cancellables)
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    @MainActor
    func testConnectionModeRuleDisconnected() async {
        let mock = MockWiFiMonitor()
        mock.connectedNetwork = nil
        mock.networks = []
        let state = AppState(wifiMonitor: mock)
        state.startMonitors()
        defer { state.stopMonitors() }

        let expectation = XCTestExpectation(description: "disconnected stable")
        var cancellables: Set<AnyCancellable> = []
        // Need to wait long enough for debounce to fire and emit the rebuilt state.
        state.$connectionMode
            .dropFirst()
            .sink { if $0 == .disconnected { expectation.fulfill() } }
            .store(in: &cancellables)
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    #endif

    #if DEBUG
    @MainActor
    func testLocationDeniedPropagatesFromMonitor() async {
        let mock = MockWiFiMonitor()
        let state = AppState(wifiMonitor: mock)
        state.startMonitors()
        defer { state.stopMonitors() }

        XCTAssertFalse(state.wifiLocationDenied)

        mock.isLocationDenied = true
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(state.wifiLocationDenied, "denied flag must propagate to AppState")

        mock.isLocationDenied = false
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(state.wifiLocationDenied, "grant must propagate to AppState")
    }

    @MainActor
    func testLocationDeniedSinkSeveredAfterStop() async {
        let mock = MockWiFiMonitor()
        let state = AppState(wifiMonitor: mock)
        state.startMonitors()
        state.stopMonitors()

        mock.isLocationDenied = true
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(
            state.wifiLocationDenied,
            "stopMonitors must sever the isLocationDenied sink so post-stop mutations do not leak"
        )
    }
    #endif

    @MainActor
    func testStartMonitorsCallsWiFiMonitorStart() {
        let stub = StubWiFiMonitor()
        let state = AppState(wifiMonitor: stub)
        state.startMonitors()
        defer { state.stopMonitors() }
        XCTAssertEqual(stub.startCallCount, 1)
    }

    // MARK: - Story 2.3 — connect orchestration

    private func passwordNetwork(id: String = "net-1", ssid: String? = "GuestNetwork") -> WiFiNetwork {
        WiFiNetwork(
            id: id, ssid: ssid, bssid: id, rssi: -55, isConnected: false,
            requiresPassword: true, security: .wpa2Personal, isCaptive: false
        )
    }

    #if DEBUG
    @MainActor
    func testConnectReturnsSuccessFromMonitor() async {
        let mock = MockWiFiMonitor()
        mock.nextAssociateResult = .success(())
        let state = AppState(wifiMonitor: mock)

        // Use a nil-SSID network so the success path does NOT write to the real Keychain
        // (no stable account → skipped per the persist-only-on-success rule).
        let hidden = passwordNetwork(id: "hidden-1", ssid: nil)
        let result = await state.connect(to: hidden, password: "secret")

        guard case .success = result else {
            return XCTFail("expected .success, got \(result)")
        }
        XCTAssertNil(state.connectingNetworkID, "connectingNetworkID must clear after the attempt")
    }

    @MainActor
    func testConnectReturnsFailureUnchanged() async {
        let mock = MockWiFiMonitor()
        mock.nextAssociateResult = .failure(.wrongPassword)
        let state = AppState(wifiMonitor: mock)

        let result = await state.connect(to: passwordNetwork(), password: "wrong")

        guard case .failure(let failure) = result else {
            return XCTFail("expected .failure, got \(result)")
        }
        XCTAssertEqual(failure, .wrongPassword)
        XCTAssertNil(state.connectingNetworkID, "connectingNetworkID must clear even on failure")
    }

    @MainActor
    func testConnectSetsConnectingNetworkIDDuringAttempt() async {
        let mock = MockWiFiMonitor()
        mock.nextAssociateResult = .success(())
        let state = AppState(wifiMonitor: mock)
        let hidden = passwordNetwork(id: "hidden-2", ssid: nil)

        XCTAssertNil(state.connectingNetworkID)

        // The mock's associate has a ~200 ms delay; observe the ID is set mid-flight.
        // The Task inherits MainActor isolation from this test, so capturing `state` is safe.
        let attempt = Task { @MainActor in await state.connect(to: hidden, password: nil) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.connectingNetworkID, hidden.id, "ID must be set while connecting")

        _ = await attempt.value
        XCTAssertNil(state.connectingNetworkID, "ID must clear after the attempt resolves")
    }

    @MainActor
    func testIsRememberedFalseForHiddenNetwork() {
        // Story 2.6: a nil/empty SSID is never "known" (no stable Keychain account) — no menu.
        let state = AppState(wifiMonitor: StubWiFiMonitor())
        let hidden = WiFiNetwork(id: "h", ssid: nil, bssid: "h", rssi: -70, isConnected: false, requiresPassword: true, security: .wpa3Personal, isCaptive: false)
        XCTAssertFalse(state.isRemembered(hidden))
    }

    @MainActor
    func testForgetUnknownSSIDDoesNotThrow() {
        // Forgetting a network LinkHub never stored is a no-op (errSecItemNotFound treated as success).
        let state = AppState(wifiMonitor: StubWiFiMonitor())
        state.forget(ssid: "NeverStored-\(UUID().uuidString)")
    }

    @MainActor
    func testSetWiFiPowerForwardsToMonitor() async {
        let stub = StubWiFiMonitor()
        let state = AppState(wifiMonitor: stub)
        await state.setWiFiPower(false)
        await state.setWiFiPower(true)
        XCTAssertEqual(stub.setPoweredCalls, [false, true], "setWiFiPower must forward to the monitor (NFR35)")
    }
    #endif
}

@MainActor
private final class StubWiFiMonitor: WiFiMonitorProtocol {
    @Published var networks: [WiFiNetwork] = []
    @Published var connectedNetwork: WiFiNetwork? = nil
    @Published var isEnabled: Bool = true
    @Published var isHardwareAvailable: Bool = true
    @Published var scanStatus: ScanStatus = .idle
    @Published var isLocationDenied: Bool = false

    var networksPublisher: Published<[WiFiNetwork]>.Publisher { $networks }
    var connectedNetworkPublisher: Published<WiFiNetwork?>.Publisher { $connectedNetwork }
    var isEnabledPublisher: Published<Bool>.Publisher { $isEnabled }
    var isHardwareAvailablePublisher: Published<Bool>.Publisher { $isHardwareAvailable }
    var scanStatusPublisher: Published<ScanStatus>.Publisher { $scanStatus }
    var isLocationDeniedPublisher: Published<Bool>.Publisher { $isLocationDenied }

    var startCallCount = 0
    var stopCallCount = 0

    func start() { startCallCount += 1 }
    func stop() { stopCallCount += 1 }
    func requestScan() async {}
    func associate(network: WiFiNetwork, password: String?) async -> Result<Void, WiFiConnectionFailure> { .success(()) }
    private(set) var setPoweredCalls: [Bool] = []
    func setPowered(_ on: Bool) async { setPoweredCalls.append(on) }
}
