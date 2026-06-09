import AppKit
import Sparkle

/// Wraps Sparkle 2's `SPUStandardUpdaterController` (Story 4.3, FR53/FR54/FR55, NFR16/NFR36).
///
/// `SPUStandardUpdaterController` starts the updater on init (`startingUpdater: true`), which
/// schedules Sparkle's periodic background check and, on first launch, shows Sparkle's own opt-in
/// permission dialog (see docs/09 Open Question #2 — accepted behaviour). Update artifacts are
/// verified against the EdDSA public key in `Info.plist` (`SUPublicEDKey`) before install; the
/// feed URL comes from `Info.plist` (`SUFeedURL`). No appcast URL is set in code so the single
/// source of truth stays in `Info.plist`.
///
/// Retained for the app lifetime by `AppDelegate`. Instantiated after
/// `statusItemController.start()` and before `appState.startMonitors()` per the Story 4.3 AC.
@MainActor
final class UpdaterController {
    private let updaterController: SPUStandardUpdaterController

    init() {
        // `startingUpdater: true` begins the periodic update check immediately. No custom
        // updater/userDriver delegates in v1 — Sparkle's standard UI and scheduling suffice.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        Log.appUpdater.info("Sparkle updater started")
    }

    /// Triggers a user-initiated update check (FR54). Wired to the status-item menu's
    /// "Check for Updates…" item (Story 4.2). Sparkle presents its standard dialog with the result.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
