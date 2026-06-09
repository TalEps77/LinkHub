import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState: AppState = {
        let wifi = AppDelegate.makeWiFiMonitor()
        return AppState(wifiMonitor: wifi)
    }()
    private var statusItemController: StatusItemController?
    /// Retained for the app lifetime so Sparkle's scheduled background checks keep running
    /// (Story 4.3). Released only at process exit. Instantiated after the status item is up and
    /// before the monitors start, per the Story 4.3 AC ordering.
    private var updaterController: UpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItemController = StatusItemController(appState: appState)
        self.statusItemController = statusItemController
        statusItemController.start()

        // Story 4.3: bring up the Sparkle updater after the status item is started and before the
        // monitors, then hand it to the status-item menu so "Check for Updates…" is enabled.
        let updaterController = UpdaterController()
        self.updaterController = updaterController
        statusItemController.setUpdaterController(updaterController)

        appState.startMonitors()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop monitors first so CWWiFiClient.delegate clears before UI subscriptions drop;
        // otherwise late delegate callbacks can land on a half-torn-down AppState.
        appState.stopMonitors()
        statusItemController?.tearDown()
    }

    private static func makeWiFiMonitor() -> any WiFiMonitorProtocol {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LINKHUB_MOCK_WIFI"] == "1" {
            return MockWiFiMonitor()
        }
        #endif
        return WiFiMonitor()
    }
}
