# Story 4.1: LaunchAtLoginService — SMAppService + UserDefaults Persistence

Status: done

## Story

As a user,
I want LinkHub to launch automatically at login, and I want to disable that without restarting the app,
so that LinkHub is just there when I log in and I can change my mind any time.

## Acceptance Criteria

1. **Enabling Launch at Login registers and persists `true`**
   - **Given** `LaunchAtLoginService` is created
   - **When** the user enables Launch at Login
   - **Then** `SMAppService.mainApp.register()` is invoked and the persisted preference flips to `true` (FR43)
   - **And** `UserDefaults.standard.set(true, forKey: "launchAtLogin")` writes the only key this app uses

2. **Disabling unregisters and persists `false` without quitting**
   - **Given** Launch at Login is enabled
   - **When** the user disables it
   - **Then** `SMAppService.mainApp.unregister()` is invoked while the app continues running normally (FR44)
   - **And** `UserDefaults.standard.set(false, forKey: "launchAtLogin")` updates the key

3. **Persisted preference survives reboot**
   - **Given** the user enables Launch at Login and reboots the Mac
   - **When** the system reaches the login session
   - **Then** LinkHub launches automatically (FR47)

4. **Bound Toggle reflects persisted state on next launch**
   - **Given** `appState.launchAtLogin` is bound to UI
   - **When** the value changes
   - **Then** the bound `Toggle` reflects the persisted state on next launch — read from UserDefaults during `AppState` init

## Tasks / Subtasks

- [x] **Task 1: Create `LinkHub/Services/LaunchAtLoginService.swift`** (AC: #1, #2, #3, #4)
  - [x] `enum LaunchAtLoginService` stateless namespace with `static` funcs, mirroring `SystemSettingsService` / `KeychainService`
  - [x] `import Foundation`, `import ServiceManagement` only
  - [x] `static let preferenceKey = "launchAtLogin"` — the single UserDefaults key the app uses
  - [x] `static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }` — reads live system status
  - [x] `static func register()` — `try SMAppService.mainApp.register()` in do/catch (log + swallow), then persist `true`
  - [x] `static func unregister()` — `try SMAppService.mainApp.unregister()` in do/catch (log + swallow), then persist `false`
  - [x] `static func setEnabled(_ enabled: Bool)` — single entry point: register or unregister
  - [x] `@discardableResult static func toggle() -> Bool` — flip persisted preference, apply, return new value
  - [x] `private static func persist(_ value: Bool)` — `UserDefaults.standard.set(value, forKey: preferenceKey)`
  - [x] Errors logged via `Log.servicesLaunch`, never thrown past the API (clean non-throwing surface)
- [x] **Task 2: Wire `AppState` ↔ SMAppService surgically** (AC: #1, #2, #4)
  - [x] `AppState.launchAtLogin`'s `didSet` persists the bool ONLY (no SMAppService) — keeps unit tests headless-safe
  - [x] `AppState.init` reads `UserDefaults.standard.bool(forKey: "launchAtLogin")` (already present from prior stories)
  - [x] Add `func setLaunchAtLogin(_ enabled: Bool)` — sets the published bool (persists via didSet) AND drives `LaunchAtLoginService.setEnabled(enabled)`. The status-item menu (Story 4.2) calls this; tests never do
- [x] **Task 3: Logger category** (cross-cutting)
  - [x] `Log.servicesLaunch = os.Logger(subsystem: subsystem, category: "services.launch")` present in `Utilities/Logger.swift`
- [x] **Task 4: Tests** (AC: #1, #2, #4)
  - [x] `LinkHubTests/Services/LaunchAtLoginServiceTests.swift` — guarded UserDefaults persistence contract only; SMAppService register/unregister NOT exercised on the headless host

## Dev Notes

### AppState ↔ SMAppService wiring choice (the load-bearing decision)

The recommended split was implemented and is the surgical choice:

- `AppState.launchAtLogin` is the single `@Published` source of truth bound to the UI. Its `didSet` persists the bool to `UserDefaults` and **deliberately does nothing else** — no `SMAppService` call. This keeps the property safe to flip in unit tests and SwiftUI previews on a headless host (where login-item registration is meaningless / unpredictable).
- The system-side register/unregister is driven only through `AppState.setLaunchAtLogin(_:)`, which the Story 4.2 status-item menu calls on user action. That method updates the published bool (persisting via didSet) and then calls `LaunchAtLoginService.setEnabled(_:)` once. Tests never call `setLaunchAtLogin`, so `SMAppService` is never exercised under XCTest.

Net effect: one user toggle → one persisted write + one `SMAppService.register()/unregister()`; one test flip → one persisted write, zero `SMAppService` calls. The persisted bool and the system state stay in lockstep on the real path, and the headless test path is isolated.

### Why errors are swallowed, not thrown

`SMAppService.register()`/`unregister()` throw. A failed login-item registration must never crash or block the menu-bar app, and the menu item has no good place to surface a thrown error synchronously. So both wrap the call in do/catch, log via `Log.servicesLaunch.error(...)`, and still persist the preference (so the bound UI reflects user intent and a subsequent toggle retries). This mirrors the `KeychainService` "log-and-continue on best-effort writes" pattern already in the codebase.

### macOS 13+ correctness

`SMAppService` is the macOS 13+ replacement for the deprecated `SMLoginItemSetEnabled`. The deployment floor is 13.0 (`project.yml` `deploymentTarget.macOS: "13.0"`), so no `@available` fallback is needed. `SMAppService.mainApp` is the correct target for a regular app bundle that wants to open itself at login (as opposed to `.agent(plistName:)` / `.daemon(plistName:)`, which are for bundled helpers).

### Testing approach (and what is intentionally NOT tested)

Only the UserDefaults persistence contract that `AppState` reads at init is unit-tested:

- `preferenceKey == "launchAtLogin"` (the single app key).
- `AppState(wifiMonitor:)` init reads the persisted key (true and false cases).
- `AppState.launchAtLogin`'s `didSet` persists without touching SMAppService.

Each test snapshots and restores the real `UserDefaults` value in `setUp`/`tearDown` so a dev machine's actual preference is never clobbered.

`register()`/`unregister()`/`setEnabled()`/`toggle()` are **not** unit-tested: they call `SMAppService`, which mutates the real per-user login-item registry and behaves unpredictably on a headless CI host. Per the brief, SMAppService registration is a local/manual gate, not a unit test.

### File-structure requirements

| File | Status | Purpose |
|---|---|---|
| `LinkHub/Services/LaunchAtLoginService.swift` | NEW | `enum` namespace; SMAppService register/unregister + UserDefaults persistence |
| `LinkHub/State/AppState.swift` | MODIFIED | `launchAtLogin` didSet persists bool only; `setLaunchAtLogin(_:)` drives SMAppService via the service |
| `LinkHub/Utilities/Logger.swift` | MODIFIED | `services.launch` category |
| `LinkHubTests/Services/LaunchAtLoginServiceTests.swift` | NEW | UserDefaults persistence contract (guarded; no SMAppService) |

### Local build/verification gates (cannot run here — no Xcode/swiftc on Linux)

- `xcodegen generate` then `xcodebuild -scheme LinkHub -configuration Debug build` must compile clean under `SWIFT_STRICT_CONCURRENCY = complete`.
- `xcodebuild -scheme LinkHub -configuration Debug test` — the four `LaunchAtLoginServiceTests` pass; no regression in existing tests.
- Manual: toggle Launch at Login from the right-click menu (Story 4.2), confirm the entry appears/disappears in System Settings → General → Login Items, and that the preference survives a reboot.

## Dev Agent Record

### Completion Notes

- Implemented per the recommended split: `didSet` persists only; `setLaunchAtLogin(_:)` is the sole SMAppService entry point.
- No AI model identifier appears in code, comments, or docs.
- No secrets introduced.
