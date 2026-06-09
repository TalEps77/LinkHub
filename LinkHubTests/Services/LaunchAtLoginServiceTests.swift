import XCTest
@testable import LinkHub

/// Story 4.1 coverage. We exercise only the UserDefaults persistence contract that `AppState`
/// reads at init — NOT `SMAppService.mainApp.register()/unregister()`, which mutate the real login
/// item registry and behave unpredictably on a headless test host. The `register()/unregister()/
/// setEnabled()/toggle()` paths each call `SMAppService` before persisting, so they are out of
/// scope for unit tests by design (the property `AppState.launchAtLogin`'s `didSet` persists
/// without touching `SMAppService`, and the system-side call is driven only from the menu).
final class LaunchAtLoginServiceTests: XCTestCase {
    private var savedValue: Bool!

    override func setUp() {
        super.setUp()
        // Snapshot so the test never clobbers the real user preference on a dev machine.
        savedValue = UserDefaults.standard.bool(forKey: LaunchAtLoginService.preferenceKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedValue, forKey: LaunchAtLoginService.preferenceKey)
        super.tearDown()
    }

    func testPreferenceKeyIsTheSingleAppKey() {
        // The one and only UserDefaults key the app uses; AppState reads it at init.
        XCTAssertEqual(LaunchAtLoginService.preferenceKey, "launchAtLogin")
    }

    func testAppStateInitReadsPersistedPreferenceTrue() {
        // The bound Toggle must reflect the persisted state on next launch — AppState reads the
        // key in init. Verify the round-trip through the same key the service writes.
        UserDefaults.standard.set(true, forKey: LaunchAtLoginService.preferenceKey)
        let state = AppState(wifiMonitor: MockWiFiMonitor())
        XCTAssertTrue(state.launchAtLogin)
    }

    func testAppStateInitReadsPersistedPreferenceFalse() {
        UserDefaults.standard.set(false, forKey: LaunchAtLoginService.preferenceKey)
        let state = AppState(wifiMonitor: MockWiFiMonitor())
        XCTAssertFalse(state.launchAtLogin)
    }

    @MainActor
    func testAppStateLaunchAtLoginDidSetPersistsWithoutTouchingSMAppService() {
        // AppState.launchAtLogin's didSet persists the bool ONLY (no SMAppService), so flipping the
        // property in a test is headless-safe and writes the key the service shares.
        let state = AppState(wifiMonitor: MockWiFiMonitor())
        state.launchAtLogin = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: LaunchAtLoginService.preferenceKey))
        state.launchAtLogin = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: LaunchAtLoginService.preferenceKey))
    }
}
