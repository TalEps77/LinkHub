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
}
