import AppKit

/// Builds and backs the status-item right-click menu (Story 4.2, UX-DR35). Owns the `@objc`
/// action targets for its items, so it must be retained for as long as the menu can fire — the
/// `StatusItemController` holds the single instance.
///
/// Items (FR46, FR53/FR54): **Launch at Login** (check-state reflects `appState.launchAtLogin`,
/// toggles via `AppState.setLaunchAtLogin` → `LaunchAtLoginService`), **Check for Updates…**
/// (Sparkle, Story 4.3), **About LinkHub** (standard About panel), **Quit LinkHub**
/// (`NSApp.terminate` → the load-bearing teardown in `applicationWillTerminate`).
@MainActor
final class StatusItemMenu: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let updaterController: UpdaterController?

    /// `updaterController` is optional so the menu degrades gracefully when Sparkle isn't wired
    /// (e.g. a build where the updater failed to start); the "Check for Updates…" item is disabled
    /// in that case rather than crashing.
    init(appState: AppState, updaterController: UpdaterController?) {
        self.appState = appState
        self.updaterController = updaterController
        super.init()
    }

    /// Builds a fresh `NSMenu` whose delegate is `self`, so `menuNeedsUpdate(_:)` can refresh the
    /// Launch-at-Login check-state each time the menu opens (the preference can change out from
    /// under us via System Settings).
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = appState.launchAtLogin ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let updatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updatesItem.target = self
        updatesItem.isEnabled = (updaterController != nil)
        menu.addItem(updatesItem)

        let aboutItem = NSMenuItem(
            title: "About LinkHub",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit LinkHub",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - NSMenuDelegate

    /// Re-sync the Launch-at-Login check-state on every open so it reflects the persisted
    /// preference even if it changed since the menu was built (UX-DR35).
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let launchItem = menu.item(withTitle: "Launch at Login") else { return }
        launchItem.state = appState.launchAtLogin ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin() {
        appState.setLaunchAtLogin(!appState.launchAtLogin)
    }

    @objc private func checkForUpdates() {
        updaterController?.checkForUpdates()
    }

    @objc private func showAbout() {
        // Bring LinkHub forward so the panel is key before the standard About window opens —
        // an LSUIElement app has no Dock icon, so without this the panel can appear behind other
        // apps.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
