import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState: AppState = {
        let wifi = AppDelegate.makeWiFiMonitor()
        return AppState(wifiMonitor: wifi)
    }()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(appState: appState)
        statusItemController?.start()
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
