import Foundation
import ServiceManagement

/// Drives the macOS "open at login" registration for LinkHub via `SMAppService.mainApp`
/// (FR43, FR44, FR47) and persists the user's preference to `UserDefaults` key `"launchAtLogin"`
/// — the only key this app uses (read back by `AppState` at init so a bound `Toggle` reflects
/// the saved state on next launch).
///
/// Stateless `enum` namespace with `static` funcs, mirroring `SystemSettingsService` /
/// `KeychainService`. `SMAppService` errors are logged and swallowed so callers get a clean,
/// non-throwing API — a failed registration must never crash the menu-bar app.
///
/// `SMAppService` is the macOS 13+ replacement for the deprecated `SMLoginItemSetEnabled`; our
/// deployment floor is 13.0 so no availability fallback is needed.
enum LaunchAtLoginService {
    /// The single `UserDefaults` key the app uses. `AppState` reads it at init.
    static let preferenceKey = "launchAtLogin"

    /// Whether the app is currently registered as a login item (reads the live system status,
    /// not the persisted preference). The two can diverge if the user toggles the login item from
    /// System Settings while the app is running; callers that need the user-intent value should
    /// read the persisted preference instead.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers LinkHub to launch at login and persists `true` (FR43, FR47). A registration
    /// failure is logged and the preference is still written so the bound UI reflects user intent;
    /// the next `toggle()`/`register()` will retry.
    static func register() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            Log.servicesLaunch.error("SMAppService register failed: \(error.localizedDescription, privacy: .public)")
        }
        persist(true)
    }

    /// Unregisters the login item and persists `false` (FR44). The app keeps running normally.
    static func unregister() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            Log.servicesLaunch.error("SMAppService unregister failed: \(error.localizedDescription, privacy: .public)")
        }
        persist(false)
    }

    /// Applies `enabled`: register or unregister and persist the preference. Single entry point
    /// the menu's "Launch at Login" item calls so the system state and the stored bool stay in
    /// lockstep.
    static func setEnabled(_ enabled: Bool) {
        if enabled {
            register()
        } else {
            unregister()
        }
    }

    /// Flips the persisted preference and applies it. Returns the new value so the caller (menu)
    /// can update its check-state without re-reading.
    @discardableResult
    static func toggle() -> Bool {
        let next = !UserDefaults.standard.bool(forKey: preferenceKey)
        setEnabled(next)
        return next
    }

    private static func persist(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: preferenceKey)
    }
}
