import AppKit

/// Hands off to macOS System Settings panes via `x-apple.systempreferences` deep links
/// (FR36, FR38). LinkHub intentionally delegates known-network management to Apple's UI rather
/// than mutating the system network configuration itself (UX-DR32) — there is no in-app removal
/// of a system known-network entry. Stateless `enum` namespace; `NSWorkspace` is AppKit so this
/// lives in the Services layer, called from the UI via static methods.
enum SystemSettingsService {
    /// Wi-Fi settings pane (Forget / known-network management; FR36, FR38).
    static let wifiSettingsURL = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!

    /// Opens the Wi-Fi settings pane. Callers dismiss the popover first (UX-DR32).
    @MainActor
    static func openWiFiSettings() {
        NSWorkspace.shared.open(wifiSettingsURL)
    }
}
