import XCTest
import AppKit
@testable import LinkHub

/// Story 4.2 coverage. Asserts the right-click menu's item structure, titles, targets, and the
/// Launch-at-Login check-state binding — all inspectable from the built `NSMenu` without firing a
/// live mouse event (which is unreliable headless). We do NOT invoke the Sparkle or About/Quit
/// actions: `checkForUpdates` would start Sparkle and `quit` would terminate the test process.
final class StatusItemMenuTests: XCTestCase {
    private var savedLaunchPref: Bool!

    override func setUp() {
        super.setUp()
        savedLaunchPref = UserDefaults.standard.bool(forKey: LaunchAtLoginService.preferenceKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedLaunchPref, forKey: LaunchAtLoginService.preferenceKey)
        super.tearDown()
    }

    @MainActor
    func testMenuHasExpectedItemsInOrder() {
        let appState = AppState(wifiMonitor: MockWiFiMonitor())
        let menu = StatusItemMenu(appState: appState, updaterController: nil).makeMenu()

        // Items + 2 separators: Launch at Login, ----, Check for Updates…, About LinkHub, ----, Quit.
        let titles = menu.items.map { $0.isSeparatorItem ? "<sep>" : $0.title }
        XCTAssertEqual(titles, [
            "Launch at Login",
            "<sep>",
            "Check for Updates…",
            "About LinkHub",
            "<sep>",
            "Quit LinkHub"
        ])
    }

    @MainActor
    func testNonSeparatorItemsAreTargetedAtTheMenu() {
        let appState = AppState(wifiMonitor: MockWiFiMonitor())
        let menuFactory = StatusItemMenu(appState: appState, updaterController: nil)
        let menu = menuFactory.makeMenu()

        for item in menu.items where !item.isSeparatorItem {
            XCTAssertTrue(item.target === menuFactory, "\(item.title) must target the menu factory")
            XCTAssertNotNil(item.action, "\(item.title) must have an action")
        }
    }

    @MainActor
    func testLaunchAtLoginCheckStateReflectsAppStateOn() {
        UserDefaults.standard.set(true, forKey: LaunchAtLoginService.preferenceKey)
        let appState = AppState(wifiMonitor: MockWiFiMonitor())
        let menu = StatusItemMenu(appState: appState, updaterController: nil).makeMenu()
        let launchItem = menu.item(withTitle: "Launch at Login")
        XCTAssertEqual(launchItem?.state, .on)
    }

    @MainActor
    func testLaunchAtLoginCheckStateReflectsAppStateOff() {
        UserDefaults.standard.set(false, forKey: LaunchAtLoginService.preferenceKey)
        let appState = AppState(wifiMonitor: MockWiFiMonitor())
        let menu = StatusItemMenu(appState: appState, updaterController: nil).makeMenu()
        let launchItem = menu.item(withTitle: "Launch at Login")
        XCTAssertEqual(launchItem?.state, .off)
    }

    @MainActor
    func testCheckForUpdatesDisabledWhenUpdaterMissing() {
        let appState = AppState(wifiMonitor: MockWiFiMonitor())
        let menu = StatusItemMenu(appState: appState, updaterController: nil).makeMenu()
        let updatesItem = menu.item(withTitle: "Check for Updates…")
        XCTAssertEqual(updatesItem?.isEnabled, false, "No updater wired → item disabled, not crashing")
    }

    @MainActor
    func testMenuNeedsUpdateResyncsLaunchCheckState() {
        UserDefaults.standard.set(false, forKey: LaunchAtLoginService.preferenceKey)
        let appState = AppState(wifiMonitor: MockWiFiMonitor())
        let factory = StatusItemMenu(appState: appState, updaterController: nil)
        let menu = factory.makeMenu()

        // Preference changes out from under the built menu (e.g. via System Settings).
        appState.launchAtLogin = true
        factory.menuNeedsUpdate(menu)
        XCTAssertEqual(menu.item(withTitle: "Launch at Login")?.state, .on)
    }
}
