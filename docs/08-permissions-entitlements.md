# PRD 08 — Permissions, Entitlements & Privacy

**Status:** ✅ Done  
**Depends on:** 01, 03, 06  
**Blocks:** 09

---

## Problem Statement

> What App Sandbox posture should LinkHub adopt, which entitlements are required, which
> Info.plist privacy keys are mandatory, and how should login-item registration work on
> macOS 13+?

This PRD decides:

- **App Sandbox** — on or off; implications for CoreWLAN and SCDynamicStore access
- **Hardened Runtime entitlements** — exact set of keys and values in `LinkHub.entitlements`
- **Info.plist privacy keys** — `NSLocationWhenInUseUsageDescription` and any others
  mandated by the APIs used
- **Location permission UX** — when to request, how to handle denial gracefully
- **Keychain strategy** — security attributes for storing user-entered Wi-Fi passwords
- **Login item registration** — `SMAppService` (macOS 13+) vs legacy LaunchAgent plist

---

## Decision Log

| # | Decision | Options Considered | Choice | Rationale |
|---|----------|--------------------|--------|-----------|
| 1 | **App Sandbox: on or off?** | App Sandbox enabled; App Sandbox disabled (Hardened Runtime only) | **App Sandbox OFF; Hardened Runtime ON** | `CWWiFiClient.associate(to:password:rememberCredentials:)` — the core "join network" feature — is blocked under App Sandbox. SCDynamicStore also requires `com.apple.security.network.client` inside sandbox, adding complexity without benefit. Mac App Store (which mandates sandbox) is ruled out in PRD 09. Hardened Runtime is still required for notarization and is always enabled in Release builds. |
| 2 | **Location entitlement (Hardened Runtime)** | No entitlement (allow all); `com.apple.security.personal-information.location` | `com.apple.security.personal-information.location = true` | Hardened Runtime restricts personal-information access by default. Without this key, `CLAuthorizationStatus` returns `.denied` regardless of the user's System Settings choice, causing all `CWWiFiClient.scanForNetworks` calls to silently return empty results. This is the only Hardened Runtime entitlement required. |
| 3 | **Network client entitlement** | Add `com.apple.security.network.client`; omit it | **Omit** | `com.apple.security.network.client` is a sandbox entitlement that unlocks outbound sockets within sandbox confinement. Outside sandbox it has no effect. Including it signals to code-signing reviewers that the app expected sandbox confinement — misleading. |
| 4 | **Location authorization level** | `requestWhenInUseAuthorization()`; `requestAlwaysAuthorization()` | `requestWhenInUseAuthorization()` | macOS 13 collapses "when in use" and "always" into a single `.authorized` CLAuthorizationStatus — there is no runtime distinction on macOS. `requestWhenInUseAuthorization()` is the correct call, matching the `NSLocationWhenInUseUsageDescription` Info.plist key. `requestAlwaysAuthorization()` triggers an Xcode deprecation warning on macOS targets. |
| 5 | **Location request timing** | On every app launch eagerly; lazily on first scan attempt; only after user explicitly clicks Scan | On first call to `WiFiMonitor.startScan()` — lazily, before the first `CWWiFiClient.scanForNetworks` call | Requesting location at launch without visible context ("why does a menu bar app need location?") damages user trust. Requesting it when the user opens the popover and triggers a scan is immediately comprehensible and contextual. `WiFiMonitor` checks `CLLocationManager.authorizationStatus` before each scan and triggers the request exactly once if `.notDetermined`. |
| 6 | **Location denial handling** | Crash / assert; show empty Wi-Fi list silently; show inline error with Settings deeplink | Show a non-fatal UI state: "Wi-Fi scanning requires Location access" with a button opening `x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices` | Denial must not break the Ethernet panel, which has no location dependency. Wi-Fi section degrades gracefully to a denial-state view (designed in PRD 06). The deeplink opens Privacy → Location Services directly, minimising friction for the user to fix it. |
| 7 | **Keychain accessibility attribute** | `kSecAttrAccessibleAlways` (deprecated); `kSecAttrAccessibleAfterFirstUnlock`; `kSecAttrAccessibleWhenUnlocked` | `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlock` | LinkHub runs as a login item and may need to read stored credentials after reboot but before first unlock (e.g., reconnecting to a Wi-Fi network during system startup). `AfterFirstUnlock` enables this while still encrypting the item under the user's keybag. `WhenUnlocked` blocks background access; `Always` is deprecated since macOS 12. |
| 8 | **Keychain access group** | App-default (bundle ID implicit group); explicit `keychain-access-groups` entitlement | **App-default — no `keychain-access-groups` entitlement** | Without sandbox, the app accesses its own keychain items via `kSecAttrService = bundleID` without an explicit access-group entitlement. Access-group entitlements are only required for cross-app sharing (App Extensions, App Clips) — not applicable to LinkHub. |
| 9 | **Login item strategy** | `SMAppService.mainApp` (macOS 13+); legacy LaunchAgent plist; `SMLoginItemSetEnabled` (deprecated since macOS 13) | `SMAppService.mainApp` | LaunchAgent plists require writing to `~/Library/LaunchAgents` and invoking `launchctl`, which Hardened Runtime may block. `SMLoginItemSetEnabled` is deprecated. `SMAppService.mainApp.register()` is the Apple-endorsed macOS 13+ API, requires no entitlement, integrates with System Settings → General → Login Items, and handles conflicts gracefully via `SMAppServiceErrorCode.alreadyRegistered`. |
| 10 | **Login item entitlement** | `com.apple.smserver`; no entitlement | **No entitlement** | `com.apple.smserver` is only required for registering a *helper* tool via `SMAppService.loginItem(identifier:)`. Registering the main app itself via `SMAppService.mainApp` requires no entitlement — Apple removed this requirement for main-app login item registration in macOS 13. |
| 11 | **Hardened Runtime — library validation** | Add `com.apple.security.cs.disable-library-validation`; leave default | **Leave default (library validation on)** | LinkHub loads no dynamically discovered plugins, bundles, or JIT-compiled code. All executable code is compiled into the main binary. Disabling library validation weakens code-signing guarantees without benefit. Add only if a future dependency explicitly requires it. |
| 12 | **Privacy manifest (`PrivacyInfo.xcprivacy`)** | Include now; omit until required | **Include now** | Apple phased in required privacy manifests starting in 2024 for apps using "required reason" APIs. CoreLocation is one such API. Including the manifest now silences Xcode 16 warnings, documents location usage reason with code `CA92.1` ("provide a feature clearly advertised to the user"), and positions the app for any future distribution path. |

---

## Entitlements File (normative)

Full content of `LinkHub/LinkHub.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!--
        Hardened Runtime: required for CoreLocation access.
        Without this key, CLAuthorizationStatus returns .denied regardless of
        the user's System Settings choice, causing CWWiFiClient.scanForNetworks
        to return empty results silently.
    -->
    <key>com.apple.security.personal-information.location</key>
    <true/>
</dict>
</plist>
```

### Build Settings by Configuration

**Release (notarised distribution build):**

| Setting | Value |
|---------|-------|
| `ENABLE_HARDENED_RUNTIME` | `YES` |
| `CODE_SIGN_ENTITLEMENTS` | `LinkHub/LinkHub.entitlements` |
| `CODE_SIGN_IDENTITY` | `Developer ID Application` (certificate configured in PRD 09) |

**Debug (local development):**

| Setting | Value |
|---------|-------|
| `ENABLE_HARDENED_RUNTIME` | `NO` (skipping speeds up local iteration; notarization not required) |
| `CODE_SIGN_ENTITLEMENTS` | _(empty)_ |
| `CODE_SIGN_IDENTITY` | `-` (ad-hoc) |

---

## Info.plist Privacy Keys (normative)

Additions to keys already established in PRD 01:

```xml
<!-- Required: CWWiFiClient.scanForNetworks triggers CLLocationManager on macOS 10.15+.
     String shown in System Settings Privacy panel and in the one-time permission dialog. -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>LinkHub scans for nearby Wi-Fi networks. Apple requires location access for this on macOS 10.15 and later.</string>
```

No other privacy keys are required:

| API | Privacy key needed? | Reason |
|-----|---------------------|--------|
| `CWWiFiClient.scanForNetworks` | Yes — `NSLocationWhenInUseUsageDescription` | CoreWLAN scanning invokes CoreLocation on macOS 10.15+ |
| `SCDynamicStore` (Ethernet) | No | Kernel network change notification; no privacy gating |
| `Security.framework` Keychain | No | App's own keychain items; no privacy key required |
| `SMAppService` | No | Login item registration; no privacy key required |

---

## Privacy Manifest (normative)

File: `LinkHub/PrivacyInfo.xcprivacy` (add to Xcode target membership):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryLocation</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <!-- CA92.1: Provide a feature that is clearly displayed to the user -->
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

---

## Location Permission UX Flow (normative)

```
WiFiMonitor.startScan() ─► check CLLocationManager.authorizationStatus
                                │
         ┌──────────────────────┼──────────────────────────┐
         │                      │                          │
    .authorized            .notDetermined             .denied / .restricted
         │                      │                          │
    proceed with           call requestWhenIn-        AppState.wifiLocationDenied = true
    scanForNetworks()      UseAuthorization()              │
                                │                     WiFiSection renders
                    ┌───────────┴──────────┐          denial-state view (PRD 06)
                    │                      │          with "Open Privacy Settings"
                user grants           user denies     button → deeplink to
                    │                      │          Privacy → Location Services
               next startScan()     AppState.wifiLocationDenied = true
               succeeds
```

**`CLLocationManager` ownership:** `WiFiMonitor` owns one `CLLocationManager` instance. The delegate must not outlive the monitor. Because `CLLocationManagerDelegate` callbacks arrive on the main thread and `WiFiMonitor` is `@MainActor`-isolated (required by Swift 6 strict concurrency — see PRD 01 constraints), no explicit dispatch to main actor is needed inside the delegate methods.

---

## Login Item Registration (normative)

`SMAppService` API surface called from a "Launch at Login" toggle (UI placement decided in PRD 04):

```swift
import ServiceManagement

// Check status
var isLaunchAtLoginEnabled: Bool {
    SMAppService.mainApp.status == .enabled
}

// Enable
func enableLaunchAtLogin() {
    // Don't register if already registered
    guard SMAppService.mainApp.status != .enabled else { return }
    do {
        try SMAppService.mainApp.register()
    } catch {
        Logger.app.error("SMAppService register failed: \(error)")
    }
}

// Disable
func disableLaunchAtLogin() async {
    do {
        try await SMAppService.mainApp.unregister()
    } catch {
        Logger.app.error("SMAppService unregister failed: \(error)")
    }
}
```

**Important:** `SMAppService.mainApp.register()` succeeds silently when the app is run from an arbitrary path (e.g., Downloads folder), but macOS may not honour the login item at boot. At first launch, if the app is not in `/Applications` or `~/Applications`, surface a one-time notice: "Move LinkHub to your Applications folder for reliable launch-at-login behaviour."

**`AppState.launchAtLogin` initialization:** On app launch, `launchAtLogin` must be initialized from `SMAppService.mainApp.status == .enabled` (the authoritative source), NOT from `UserDefaults`. `UserDefaults` is used only as a write-through cache when the toggle changes. If the user removes the login item via System Settings → Login Items, `SMAppService.mainApp.status` will reflect `.notRegistered`, but the `UserDefaults` cache would remain stale. Always prefer `SMAppService` status at init time.

---

## Constraints

- **Hardened Runtime is non-optional for notarization:** Apple's notarization service rejects binaries without `ENABLE_HARDENED_RUNTIME = YES` since Xcode 13. This is orthogonal to App Sandbox — it adds runtime protection without confinement. The two are independent build settings.
- **CoreWLAN location dependency is macOS 10.15+:** `CWWiFiClient.scanForNetworks(withName:)` requires granted location access since Catalina. There is no workaround; apps that do not trigger the permission dialog return an empty scan list. The behaviour is not documented in the CoreWLAN header; it is confirmed by Apple's technote and community reports.
- **macOS `CLLocationManager` does not distinguish "when in use" vs "always":** Both `requestWhenInUseAuthorization()` and `requestAlwaysAuthorization()` produce the same `.authorized` status on macOS. `NSLocationWhenInUseUsageDescription` is the correct Info.plist key; `NSLocationAlwaysUsageDescription` and `NSLocationAlwaysAndWhenInUseUsageDescription` are iOS/iPadOS-only keys with no effect on macOS.
- **SCDynamicStore has no privacy dependency:** Ethernet monitoring requires no location permission and no Hardened Runtime entitlement. It uses kernel notifications and is unrestricted outside sandbox.
- **`SMAppService.mainApp` is macOS 13+:** Guaranteed by the PRD 01 deployment target. No `LaunchAgent` fallback is needed.
- **Keychain without sandbox:** Items stored by `kSecAttrService` + bundle ID are isolated to the app without an access-group entitlement. Other apps can still access Keychain through the Security framework if they know the service name — this is a macOS-wide security model, not a LinkHub-specific gap. Storing user-entered passwords (not system Wi-Fi passwords) is the scope here.
- **Swift 6 + CLLocationManagerDelegate:** Delegate callbacks arrive on the main thread. `WiFiMonitor` must be `@MainActor`-isolated to avoid strict-concurrency violations when delegate methods update `AppState`. An `@unchecked Sendable` wrapper is not needed here because `CLLocationManager` itself is `@MainActor`-annotated in the macOS 14 SDK; on macOS 13 use explicit `@MainActor` annotations on the delegate type.

---

## Out of Scope

- **Mac App Store sandbox entitlements** — ruled out in PRD 09; not applicable.
- **App Extensions or XPC helpers** — LinkHub has no helper process; `com.apple.security.application-groups` and `keychain-access-groups` are not needed.
- **Camera, microphone, contacts, calendar, photos** — LinkHub does not access these APIs. No corresponding Info.plist keys are needed.
- **Full Disk Access** — not required; LinkHub reads no files outside its container.
- **Network Extension framework** — `NEHotspotHelper` and `NEAppProxyProvider` require a special provisioning entitlement obtained by written request to Apple. LinkHub uses CoreWLAN (user-space), which does not require this entitlement.
- **Captive portal detection entitlements** — `CWNetwork.captiveNetwork` is a read-only property; no extra entitlement required. Detailed captive portal handling is deferred to PRD 06.
- **First-run onboarding UI design** — permission request timing is decided here; the visual design of any onboarding screen is PRD 04/06 scope.

---

## Open Questions

| # | Question | Impact | To resolve before |
|---|----------|--------|-------------------|
| 1 | Does `CWWiFiClient.scanForNetworks(withName: nil)` require an active `CLLocationManager` session at scan time, or is it sufficient to have `.authorized` status granted previously? If an active session is required, `WiFiMonitor` must call `locationManager.startUpdatingLocation()` continuously — adding battery cost. | Determines whether `WiFiMonitor` is a persistent location client or a one-shot authorizer. | **Resolved — default assumption: `.authorized` status is sufficient; no active session needed. `WiFiMonitor` does NOT call `startUpdatingLocation()` continuously. This matches the pattern used by macOS Wi-Fi utilities (including macOS's own Wi-Fi menu bar item). Fallback: if empirical testing during the first coding session shows scans return empty results despite `.authorized` status, call `locationManager.startUpdatingLocation()` in `WiFiMonitor.start()` and `locationManager.stopUpdatingLocation()` in `WiFiMonitor.stop()`. This fallback is a known contingency, not the expected path.** ~~First coding session — verify empirically on macOS 13 and 14.~~ |
| 2 | Should the "Launch at Login" toggle live in the popover UI or in a separate Preferences window? Neither exists yet. | Determines where `SMAppService.mainApp.register()` is called and how registration errors are surfaced to the user. | **Resolved: `WiFiSectionFooter` in the popover panel (PRD 04 Decision #21). The `AppState.launchAtLogin` property drives the toggle. On launch, `AppState.init()` reads the authoritative state from `SMAppService.mainApp.status == .enabled` rather than from UserDefaults.** | ~~PRD 04 (Panel UI Architecture).~~ |

---

## References

- [Apple Developer: Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime) — Entitlement keys, build setting, notarization relationship.
- [Apple Developer: App Sandbox](https://developer.apple.com/documentation/security/app_sandbox) — `com.apple.security.network.client` and why it is sandbox-only.
- [Apple Developer: CWWiFiClient](https://developer.apple.com/documentation/corewlan/cwwificlient) — `scanForNetworks(withName:)`, `associate(to:password:rememberCredentials:)`.
- [Apple Developer: CLLocationManager](https://developer.apple.com/documentation/corelocation/cllocationmanager) — `requestWhenInUseAuthorization()`, `authorizationStatus`.
- [Apple Developer: CLAuthorizationStatus](https://developer.apple.com/documentation/corelocation/clauthorizationstatus) — macOS values: `.notDetermined`, `.restricted`, `.denied`, `.authorized`.
- [Apple Developer: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) — `mainApp`, `register()`, `unregister()`, `status`.
- [Apple Developer: Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files) — `PrivacyInfo.xcprivacy` format, required reason APIs, location reason codes.
- [Apple Developer: Keychain Services](https://developer.apple.com/documentation/security/keychain_services) — `kSecAttrAccessible`, `kSecAttrService`, `SecItemAdd`, `SecItemCopyMatching`.
- [Apple Developer: NSLocationWhenInUseUsageDescription](https://developer.apple.com/documentation/bundleresources/information_property_list/nslocationwheninuseusagedescription) — Info.plist key required before `requestWhenInUseAuthorization()`.
- [WWDC 2023: What's new in privacy (session 10053)](https://developer.apple.com/videos/play/wwdc2023/10053/) — Privacy manifests, required reason APIs, phased enforcement timeline.
- [WWDC 2022: What's new in notarization for Mac software (session 10109)](https://developer.apple.com/videos/play/wwdc2022/10109/) — Hardened Runtime requirements; `notarytool` migration from `altool`.
- [Apple Tech Note TN3135: Inside Code Signing: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3135-inside-code-signing-provisioning-profiles) — Why Developer ID apps require no provisioning profile.
