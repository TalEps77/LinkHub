---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/architecture.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
---

# LinkHub - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for LinkHub, decomposing the requirements from the PRD, UX Design Specification, and Architecture Decision Document into implementable stories.

## Requirements Inventory

### Functional Requirements

**Menu Bar Presence**
- FR1: User can see a single LinkHub icon in the macOS menu bar at all times while the app is running.
- FR2: System can display a Wi-Fi-style icon when no Ethernet interface has link, indicating Wi-Fi-only mode.
- FR3: System can display an Ethernet-style icon when at least one Ethernet interface has link, indicating Ethernet-active mode.
- FR4: System can display a disconnected-state icon when neither Wi-Fi nor Ethernet is providing connectivity.
- FR5: System can update the menu bar icon within 1.5 seconds of a network state change (cable in, cable out, Wi-Fi join, Wi-Fi leave).
- FR6: User can click the menu bar icon to open the LinkHub panel.
- FR7: User can click the menu bar icon while the panel is open to dismiss it.
- FR8: A VoiceOver user can perceive the current connection state via the menu bar icon's accessibility label.

**Panel Display & Layout**
- FR9: User can see a popover panel anchored to the menu bar icon when LinkHub is opened.
- FR10: User can dismiss the panel by pressing Escape.
- FR11: User can dismiss the panel by clicking outside it.
- FR12: System can present an Ethernet section above the Wi-Fi section whenever any Ethernet interface has link.
- FR13: System can hide the Ethernet section when no Ethernet interface has had link for at least 1.5 seconds (grace period).
- FR14: User can see the panel respect the active macOS appearance (light/dark mode) without per-app configuration.

**Ethernet Awareness**
- FR15: System can detect Ethernet interfaces present on the host (USB-C/Thunderbolt dongles, Thunderbolt docks).
- FR16: User can see, per Ethernet interface, the current operational state: Active, Obtaining address, DHCP timeout, or No link.
- FR17: User can see the IPv4 address of any active Ethernet interface.
- FR18: User can see the negotiated link speed of any active Ethernet interface (Mbps / Gbps).
- FR19: User can see a human-readable display name for each Ethernet interface.
- FR20: System can sort Ethernet interfaces with active interfaces first, ties broken by stable identifier order.
- FR21: User can see a summary entry pointing to System Settings when more Ethernet interfaces exist than the panel displays inline.
- FR22: User can open the macOS Network settings pane directly from the Ethernet section.

**Wi-Fi Network Discovery**
- FR23: User can see the list of nearby Wi-Fi networks discovered by the system.
- FR24: User can see, per Wi-Fi network: SSID (or "Hidden Network" label), signal strength, security marker, and connected state.
- FR25: User can see a captive-portal marker on networks that require sign-in.
- FR26: User can request a fresh Wi-Fi scan on demand.
- FR27: System can refresh the Wi-Fi network list automatically in response to system Wi-Fi events.
- FR28: User can see the currently connected Wi-Fi network distinguished from other networks.

**Wi-Fi Connection Management**
- FR29: User can connect to an open Wi-Fi network by tapping its row.
- FR30: User can connect to a password-protected Wi-Fi network by tapping its row, entering a password, and confirming.
- FR31: System can store Wi-Fi passwords securely in the macOS Keychain.
- FR32: User can connect to a hidden Wi-Fi network through a dedicated panel.
- FR33: User can be routed to the system captive-portal flow when joining a captive network.
- FR34: User can disconnect from the current Wi-Fi network by toggling Wi-Fi power off.
- FR35: User can turn Wi-Fi power on or off.
- FR36: User can initiate "Forget This Network" action, which routes them to the system Wi-Fi settings.
- FR37: User can see feedback identifying the failure cause when a Wi-Fi connection attempt fails.
- FR38: User can open the macOS Wi-Fi settings pane directly from the Wi-Fi section.

**Permissions & First-Run Experience**
- FR39: System can request macOS Location authorization on first attempt to scan Wi-Fi.
- FR40: User can see an empty state when Location authorization is denied or restricted, with one-tap path to Privacy settings.
- FR41: System can resume Wi-Fi scanning automatically when Location authorization changes from denied to granted.
- FR42: System can launch without a modal onboarding flow.

**Application Lifecycle & Persistence**
- FR43: User can configure LinkHub to launch automatically at login.
- FR44: User can disable launch-at-login at any time without restarting the app.
- FR45: System can run as a menu-bar-only app (no Dock icon, no Cmd+Tab entry).
- FR46: System can release Wi-Fi event subscriptions cleanly on app termination.
- FR47: System can persist the launch-at-login preference across reboots.

**Resource Discipline**
- FR48: System can run while consuming no more than 80 MB of resident memory at idle.
- FR49: System can run while consuming no more than 0.5% CPU averaged over 60s idle on Apple Silicon.
- FR50: System can avoid scheduled polling when the panel is closed.

**Distribution & Updates**
- FR51: User can install LinkHub from a downloaded disk image (DMG) signed for distribution outside the Mac App Store.
- FR52: User can verify the app is properly notarized — Gatekeeper does not warn or block.
- FR53: System can check for software updates on a periodic background cadence and notify the user.
- FR54: User can manually trigger an update check.
- FR55: User can install an update via the in-app update dialog with cryptographic verification.

**Accessibility**
- FR56: A VoiceOver user can perceive every Wi-Fi network row's information through accessibility labels.
- FR57: A VoiceOver user can perceive every Ethernet row's information through accessibility labels.
- FR58: A VoiceOver user can perceive transitions between Wi-Fi-only, Ethernet-active, and disconnected states.

### NonFunctional Requirements

**Performance**
- NFR1: Menu bar icon updates within 1.5 seconds of underlying network state change.
- NFR2: Popover reaches first paint with populated content within 200 ms cold / 100 ms warm on Apple Silicon.
- NFR3: User-initiated Wi-Fi scan returns results within 5 seconds or surfaces a visible scanning indicator.
- NFR4: Panel transitions run at display refresh rate without dropped frames on Apple Silicon.
- NFR5: Network state events debounced for at least 300 ms before driving UI update.

**Reliability**
- NFR6: Application runs continuously for ≥ 7 days without restart and without resource drift.
- NFR7: Crash-free session rate ≥ 99.5% across the first 30 days of release.
- NFR8: Instruments runs (Allocations, Leaks, Time Profiler) over a 1-hour induced session show zero leaks.
- NFR9: Application releases CoreWLAN delegates and SCDynamicStore callbacks cleanly on termination.
- NFR10: Failed Wi-Fi connection leaves the app in a clean state — user can retry without restart.
- NFR11: Application survives macOS sleep/wake, router resets, dock reconnects, VPN toggles without unresponsive state (panel responds within 1.5 s, icon updates within 1.5 s of next state change).

**Security**
- NFR12: Wi-Fi passwords stored in Keychain with `kSecClassGenericPassword` + `kSecAttrAccessibleAfterFirstUnlock`. Never in UserDefaults / plain files / persisted memory.
- NFR13: Distribution artifacts code-signed with valid Apple Developer ID Application certificate.
- NFR14: All distribution artifacts notarized by Apple with notarization tickets stapled.
- NFR15: Hardened Runtime enabled in Release builds.
- NFR16: Sparkle update artifacts EdDSA-signed; matching public key in `Info.plist` (`SUPublicEDKey`).
- NFR17: App requests only the entitlements it functionally requires (`com.apple.security.personal-information.location`). App Sandbox disabled. No other entitlement without PRD amendment.
- NFR18: Privacy manifest (`PrivacyInfo.xcprivacy`) declares every required-reason API in sync with codebase.

**Privacy**
- NFR19: Application does not collect, log, or transmit PII — no telemetry, analytics, crash reports, remote config.
- NFR20: macOS Location authorization used solely for Wi-Fi scanning per `NSLocationWhenInUseUsageDescription`. Not persisted to disk or transmitted off-device.
- NFR21: Wi-Fi network identifiers (SSID, BSSID, RSSI) remain on-device.
- NFR22: Captive-portal handoff URL opened via user's default browser, not in-app web view.

**Accessibility**
- NFR23: Every interactive control and informational row exposes `accessibilityLabel` consumable by VoiceOver.
- NFR24: Wi-Fi rows' accessibility labels include SSID, signal quality, security marker, connected state.
- NFR25: Ethernet rows' accessibility labels include display name, status, IP address, link speed.
- NFR26: Connection state transitions trigger `NSAccessibility` announcements.
- NFR27: Decorative graphics (signal bars, status dots) marked `accessibilityHidden(true)`.
- NFR28: Panel and interactive elements respect Reduce Motion — pulsing/animation disabled when on.

**Compatibility**
- NFR29: App builds and runs on macOS 13.0 (Ventura) and later.
- NFR30: App ships as Universal binary supporting Apple Silicon (arm64) and Intel (x86_64).
- NFR31: App respects active macOS appearance (Light, Dark, Auto) using only system semantic colors.
- NFR32: App respects active macOS accent color where it exposes accent-colored elements.
- NFR33: Build produces zero Swift 6 strict concurrency warnings or errors in Release configuration.

**Maintainability**
- NFR34: Codebase follows layer-based folder structure (`App/`, `MenuBar/`, `Network/`, `UI/`, `State/`, `Services/`, `Utilities/`).
- NFR35: All shared application state flows through a single `@MainActor` observable state container. UI never observes monitors directly.
- NFR36: Every framework dependency is either system framework or documented SPM dependency (only Sparkle 2). No CocoaPods/Carthage.
- NFR37: Diagnostic logging uses `os.Logger` with subsystem = `Bundle.main.bundleIdentifier`.

### Additional Requirements

**Starter Template (Architecture)**
- Xcode 16 built-in macOS App template (AppKit App Delegate lifecycle). Replace SwiftUI `@main App` with `@main NSApplicationDelegate` subclass.
- Bundle identifier: `com.linkhub.app`. Product name: `LinkHub`. Test target: `LinkHubTests`.
- Build settings: deployment target macOS 13.0; `SWIFT_VERSION = 6.0`; `SWIFT_STRICT_CONCURRENCY = complete`.
- Layer folders: `App/`, `MenuBar/`, `Network/`, `UI/`, `State/`, `Services/`, `Utilities/`.
- Info.plist: `LSUIElement=true`, `NSLocationWhenInUseUsageDescription`, version keys.
- `LinkHub.entitlements` (Location only) applied to **Release config only**. Debug ad-hoc unsigned, no entitlements.
- `PrivacyInfo.xcprivacy` declaring Location (CA92.1), UserDefaults, file timestamp, system boot time.
- Shared scheme `LinkHub.xcscheme`; commit `xcshareddata/`. `.gitignore` excludes `xcuserdata/`.

**Concurrency & State Architecture**
- Single `@MainActor final class AppState: ObservableObject` with `@Published` properties. No `@Observable` (macOS 13 floor).
- AppState created in `AppDelegate.applicationDidFinishLaunching`. Process lifetime, single instance.
- Single `Publishers.CombineLatest(ethernetMonitor.$interfaces, wifiPublisher).sink` rebuilds `networkState` and `connectionMode` atomically.
- Sendable model boundary: `EthernetInterface`, `WiFiNetwork`, `WiFiSecurity`, `ConnectionMode`, `NetworkState`, `WiFiConnectionFailure`, `ScanStatus` value types in `Network/Models/`.
- ObjC↔Swift6 boundary pattern: extract Sendable values on private queue/callback thread → `Task { @MainActor in ... }`. Never capture `CWNetwork`/`CWInterface`/`SCNetworkInterface`/`CFType` across actor boundary.
- Each monitor owns 300 ms `PassthroughSubject<Void, Never>.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)`.
- `@MainActor final class` for `WiFiMonitor` and `EthernetMonitor`. Public API via `@Published` only (no AsyncStream).
- UI subscribes only to `AppState` via `@EnvironmentObject` (NFR35). Direct monitor observation forbidden.

**System Framework Integrations**
- Ethernet: `SCDynamicStore` + `SCDynamicStoreSetDispatchQueue` on private serial queue. Watch keys `State:/Network/Interface/[^/]+/Link` AND `State:/Network/Interface/[^/]+/IPv4`. Re-enumerate via `SCNetworkInterfaceCopyAll()` inside every callback.
- Wi-Fi: `CoreWLAN` `CWWiFiClient` + `CWEventDelegate` push events for ssid/link/linkQuality/power. On-demand scan only (no polling).
- Permissions: `CLLocationManager.requestWhenInUseAuthorization()`. `CLLocationManagerDelegate` auto-retries `WiFiMonitor.requestScan()` on flip to `.authorized`.
- Keychain: account = SSID; service = `Bundle.main.bundleIdentifier`.
- Launch at Login: `SMAppService.mainApp.register()` / `.unregister()`. Persisted in UserDefaults (`launchAtLogin: Bool` only key).
- System deep links via `SystemSettingsService` + `NSWorkspace.shared.open(_:)`:
  - Wi-Fi settings: `x-apple.systempreferences:com.apple.wifi-settings-extension`
  - Network settings: `x-apple.systempreferences:com.apple.Network-Settings.extension`
  - Privacy/Location: `x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices`
  - Captive portal: `http://captive.apple.com`

**Init/Tear-down Order (load-bearing)**
- Init order: `AppState()` → `StatusItemController(appState:)` → `statusItemController.start()` → `appState.startMonitors()`. Reverse → first connectionMode event lost → wrong icon at launch.
- Tear-down (`applicationWillTerminate`): `appState.stopMonitors()` → `statusItemController.tearDown()`. Inside `WiFiMonitor.stop()`: `CWWiFiClient.shared().delegate = nil`. Inside `EthernetMonitor.stop()`: `SCDynamicStoreSetDispatchQueue(store, nil)`.

**Menu Bar / Popover Mechanics**
- `NSStatusItem` length = `.squareLength` (22 pt). SF Symbols template images via `NSImage(systemSymbolName:accessibilityDescription:)`. Symbol config: `pointSize: 17, weight: .regular, scale: .medium`. No xcassets imagesets for menu bar.
- Icons: `cable.connector` (Ethernet active) / `wifi` (Wi-Fi only) / `wifi.slash` (disconnected).
- `NSPopover` hosting `NSHostingController<RootPanelView>`. `behavior = .transient` for outside-click dismissal.
- Escape dismissal: local `NSEvent` monitor (`.keyDown`, keyCode 53) installed in `show()`, removed in `close()`.
- Status item button toggles popover based on `popover.isShown`.
- `PopoverController.show()` triggers fire-and-forget `Task { try? await appState.wifiMonitor.requestScan() }` immediately after `popover.show(...)`.
- VoiceOver: accessibility label updates on every `$networkState` change; `NSAccessibility.post(.announcementRequested)` only on transition to `.disconnected`.

**Architecture Amendments (v1 scope additions)**
- `App/UpdaterController.swift` — wraps Sparkle 2 `SPUStandardUpdaterController`. Wired in `AppDelegate.applicationDidFinishLaunching` after StatusItemController.
- `MenuBar/StatusItemMenu.swift` — right-click NSMenu factory. Items: Launch at Login (toggle bound to `appState.launchAtLogin`), Check for Updates… (bound to UpdaterController), About LinkHub, Quit LinkHub.
- `Network/Models/ScanStatus.swift` — `enum ScanStatus: Equatable, Sendable { case idle; case scanning; case timedOut }`. AppState exposes `@Published private(set) var scanStatus: ScanStatus = .idle`. `WiFiMonitor.requestScan()` enforces 5 s timeout via Task race.

**Distribution Pipeline**
- Developer ID Application sign + `xcrun notarytool submit ... --keychain-profile linkhub-notary --wait` + `xcrun stapler staple LinkHub.app`. Always staple.
- `ExportOptions.plist` for Developer ID export config.
- `scripts/notarize.sh` (notarize + wait + staple), `scripts/make-dmg.sh` (DMG with `/Applications` symlink), `scripts/update-appcast.sh` (EdDSA-sign + append entry).
- Sparkle 2 EdDSA: private key in macOS Keychain; public key in `Info.plist` (`SUPublicEDKey`).
- `appcast/appcast.xml` published to GitHub Pages at `https://talepstein.github.io/LinkHub/appcast.xml`.
- SemVer `CFBundleShortVersionString = MAJOR.MINOR.PATCH`; `CFBundleVersion` monotonic integer.
- DMG plain (no custom background).

**Build-config Divergence**
- `#if DEBUG` mock data path in `WiFiMonitor` (Wi-Fi scanning unavailable in Debug because no Location entitlement). Opt-in via env var or compile-time flag — must not auto-engage in regular Debug builds without intent.
- Mock data files: `LinkHubTests/Fixtures/MockWiFiData.swift`, `MockEthernetData.swift`.

**Logging**
- `os.Logger` factory in `Utilities/Logger.swift`. Subsystem = `Bundle.main.bundleIdentifier`.
- Categories (lowerCamelCase, dot-separated): `app`, `menuBar`, `network.wifi`, `network.ethernet`, `state`, `services.keychain`, `services.settings`. No ad-hoc categories.
- String-interpolation privacy: SSIDs/BSSIDs/RSSIs `.private`. BSD names (en0/en3) `.public`. Errors `.public`. No `print(...)` in shipped code.

**Error Modeling**
- Each layer defines typed `enum SomethingError: Error`. No `NSError` rethrow.
- `Network/Models/WiFiConnectionFailure.swift` — cases `wrongPassword`, `outOfRange`, `associationTimeout`, `authenticationError`, `unknown(code:)`. Maps from `CWErrorDomain` codes (FR37).
- No global `NSAlert` / modal alerts. Errors live inline in panel UI.

### UX Design Requirements

**Design System Foundation**
- UX-DR1: Adopt Apple HIG + native SwiftUI/AppKit primitives as the design system. No third-party UI library, no custom design system. SwiftUI primitives: `Button`, `Toggle`, `SecureField`, `Label`, `Image(systemName:)`, `Divider`, `VStack/HStack/Spacer`. AppKit: `NSStatusItem`, `NSPopover`, `NSHostingController`, `NSVisualEffectView`, `.contextMenu { }`.
- UX-DR2: Iconography is SF Symbols only — `wifi`, `wifi.slash`, `cable.connector`, `lock.fill`, `globe`, `network`, `checkmark`. No custom glyphs, no SF Symbol replacements.
- UX-DR3: Typography uses system font (`.system(...)`) only. Type ramp: SSID/Ethernet name = `.body` 13pt regular; section header = `.caption` uppercase 10pt semibold; IP/link speed/links = `.callout` 12pt regular; status text = `.caption` 10pt regular; empty-state title = `.headline` 13pt semibold; empty-state body = `.callout` 12pt regular. No custom faces, no hardcoded pt values for text sizes.
- UX-DR4: Color uses system semantic tokens only — `Color.primary`, `Color.secondary`, `Color(nsColor: .tertiaryLabelColor)`, `Color.accentColor`, `Color(nsColor: .selectedContentBackgroundColor)`, `Color(nsColor: .separatorColor)`, `Color.red` for inline error text only. No hex literals, no `Color(red:green:blue:)`, no asset-catalog custom colors.
- UX-DR5: Spacing/layout — 320pt fixed panel width; 8pt outer top/bottom padding; 24pt single-line row height; 56pt expanded row (password); 16pt left/right row padding; 8pt internal column gap; 24pt section header height; 8pt inter-section gap; 16pt separator inset; signal-bar glyph 16×16pt; lock/captive marker 12×12pt; connected checkmark 16×16pt semibold accent; state dot 8pt circle; max ~480pt panel height before internal `ScrollView` engages.
- UX-DR6: Popover material via `NSVisualEffectView` `.windowBackground` vibrancy. Falls back to opaque `.windowBackgroundColor` when system Reduce Transparency is on.
- UX-DR7: Layer-based folder structure for UI per PRD 01 — components in `UI/Components/`, panels in `UI/Panels/`, windows in `UI/Windows/`. `UI/Theme.swift` for `PanelLayout` constants. No custom `ButtonStyle` / `LabelStyle`.

**Custom Components (8 LinkHub-specific compositions)**
- UX-DR8: `StatusBarIcon` — drives `NSStatusItem.button` image and accessibility label from `connectionMode`. States: `.wifiOnly(strength:)`, `.wifiOff`, `.ethernetActive(displayName:speed:)`, `.disconnected`. 300 ms crossfade on state change; instant under Reduce Motion.
- UX-DR9: `RootPanelView` — top-level SwiftUI view inside popover. Layout: `VStack(spacing: 8) { EthernetSection?; WiFiSection; FooterRows }`. States: Wi-Fi-only, Ethernet+Wi-Fi, location-denied, all-disconnected. 250 ms ease-in-out section reorder; instant under Reduce Motion. Posts `NSAccessibility.announcementRequested` on `connectionMode` change.
- UX-DR10: `EthernetSection` — caption-uppercase header → top-2 inline `EthernetRow` → optional "+ N more in Settings…" overflow row. Visible only when any interface has link; hides after 1.5 s grace timer.
- UX-DR11: `EthernetRow` — `HStack { StateDot; VStack(.leading) { displayName(.body); detail(.caption) } }`. States: `.active(ip:speed:)`, `.obtaining`, `.dhcpTimeout`, `.noLink`. Each state pairs dot color with plain-text label so color is never the only signal.
- UX-DR12: `WiFiSection` — header (`Label("WI-FI") + Toggle($isPowered)`) → connected row → other networks → "Other Network…" → "Open Network Settings…". States: powered-on-with-networks, powered-on-empty, powered-off (list hidden), location-denied (delegates to `LocationDeniedView`).
- UX-DR13: `WiFiRow` — `HStack { Checkmark?; SSIDText(.body); Spacer; LockIcon?; CaptiveIcon?; SignalBars }` + collapsible `SecureField` row when expanded. States: `.normal`, `.connected`, `.expanded(password:error:)`, `.connecting`. 250 ms expand/collapse; instant under Reduce Motion. `.contextMenu { Button("Forget"); Button("Open in Settings") }` on rows matching known SSID. Accessibility-combined label; VoiceOver announces error captions when they appear.
- UX-DR14: `LocationDeniedView` — centered `VStack` with lock icon + headline ("Location access required") + body ("LinkHub needs Location access to scan for Wi-Fi networks. Apple requires this on macOS 10.15+.") + "Open Privacy Settings" `.borderedProminent` button.
- UX-DR15: `OtherNetworkPanel` — replaces `RootPanelView` content (single-panel discipline). Title + SSID `TextField` + security `Picker` (Open / WPA / Enterprise) + conditional `SecureField` + Cancel / Join buttons. States: entry, validating, error.

**Animation & Motion**
- UX-DR16: Status icon morph — 300 ms ease-in-out crossfade; instant swap under Reduce Motion.
- UX-DR17: Section reorder — 250 ms ease-in-out; instant under Reduce Motion.
- UX-DR18: Row expand/collapse (inline password) — 250 ms ease-in-out; instant under Reduce Motion.
- UX-DR19: Pulsing dot ("Obtaining…") — 1.2 s loop, opacity 0.4 → 1.0 ease-in-out; static dot at 1.0 under Reduce Motion.
- UX-DR20: All animations gated on `@Environment(\.accessibilityReduceMotion)` with instant fallback. No animation longer than 300 ms.

**VoiceOver Labels & Accessibility**
- UX-DR21: VoiceOver row coverage via combined `accessibilityLabel`; decorative glyphs (signal bars, dots) marked `accessibilityHidden(true)`. Use `.accessibilityElement(children: .combine)`.
- UX-DR22: `WiFiRow` label templates — normal: `"{SSID}, {securityType}, signal {strength}"`; connected: `"{SSID}, connected, {securityType}, signal {strength}"`; expanded: `"{SSID}, password field"` + field label "Password for {SSID}"; error: `"{SSID}, {error}, password field"`.
- UX-DR23: `EthernetRow` label templates — active: `"{displayName}, active, {ip}, {speed}"`; obtaining: `"{displayName}, obtaining address"`; DHCP timeout: `"{displayName}, DHCP timeout, no address"`; no link: `"{displayName}, no link"`.
- UX-DR24: `StatusBarIcon` label templates — Wi-Fi only: `"Wi-Fi connected, {SSID}, signal {strength}"`; Wi-Fi off: `"Wi-Fi off"`; Ethernet active: `"Ethernet connected, {displayName}, {speed}"`; disconnected: `"No network connection"`.
- UX-DR25: State-transition `NSAccessibility.post(.announcementRequested)` utterances — cable in: "Ethernet connected"; cable out: "Ethernet disconnected"; Wi-Fi power on: "Wi-Fi turned on"; Wi-Fi power off: "Wi-Fi turned off"; successful Wi-Fi connect: "Connected to {SSID}"; Location auth granted: "Wi-Fi networks loading". Failed connect surfaces inline caption (VoiceOver announces caption when it appears).
- UX-DR26: Color is never the sole signal — every state has plain-text label adjacent to its color/dot signal. Plain-text labels: "Active", "Obtaining…", "DHCP timeout", "No link".
- UX-DR27: Keyboard navigation — Tab through rows, Return to connect, Esc to dismiss, Space to toggle Wi-Fi power. System focus ring; no custom styling.
- UX-DR28: Three popover dismissal paths — Esc / click-outside / re-click status item; all equivalent.

**UX Patterns**
- UX-DR29: Button hierarchy — Primary `.borderedProminent` for single critical action in empty/recovery states ("Open Privacy Settings", "Turn Wi-Fi On"); Secondary `.bordered` for form submit alongside Cancel ("Join" in `OtherNetworkPanel`); Tertiary `.plain` link-styled for inline navigation/handoff ("Other Network…", "Open Network Settings…"); Cancel `.bordered` for form dismiss. At most one primary per view; main panel has none. No `.destructive`; Forget is context-menu item.
- UX-DR30: Feedback via inline caption (`.caption` text, `Color.red` for error or `Color.secondary` for info) — e.g., "Incorrect password". Status dot + plain-text label for persistent interface state. Checkmark for terminal-success state. No `NSAlert.runModal()`, no `UNUserNotification`, no Dock badges, no toast/banner, no spinners, no progress indicators, no warning tier.
- UX-DR31: Form patterns — auto-focus first input when form appears; Return submits primary action, Esc dismisses without submit; on error clear field, retain focus, surface inline caption below, keep row/panel open. No "type to confirm", no required-field asterisks. Validation deferred to system API (`CWInterface.associate`). Keychain writes on success only.
- UX-DR32: Single-panel navigation discipline — every flow lives in `RootPanelView` except `OtherNetworkPanel` which fully replaces it. No tabs, no segmented controls, no drill-down. State changes by data binding, not user navigation. No back chevrons; explicit Cancel button on `OtherNetworkPanel`. System Settings handoff auto-dismisses popover before system pane opens.
- UX-DR33: Empty/zero states — Wi-Fi list empty (powered on, no networks): `.callout` centered "No networks found", no action; Wi-Fi powered off: section header only, "Wi-Fi: Off" with toggle; All disconnected: centered zero-state "Wi-Fi is off / No Ethernet connected" with "Turn Wi-Fi On" primary button; Location denied: `LocationDeniedView`; Initial scan/connecting: no loading state — list shows existing data, new results merge in.
- UX-DR34: Copy & tone — Apple voice (short, definite, no marketing). Plain English ("Obtaining address", not "Acquiring DHCP lease"). No exclamation points. Sentence case for body; UPPERCASE caption for section headers. Avoid blame ("Incorrect password", not "You entered the wrong password"). Cite Apple when explaining constraints. Use ellipsis (…) for handoffs ("Other Network…", "Open Network Settings…", "Open Privacy Settings…").
- UX-DR35: Right-click status-item NSMenu (not panel) — Launch at Login (toggle), Check for Updates…, About LinkHub, Quit LinkHub.
- UX-DR36: Right-click `WiFiRow` `.contextMenu` on rows matching known SSID — Forget (handoff to System Settings), Open in Settings.

**Responsive & Accessibility System Integration**
- UX-DR37: Responsive — fixed-width 320pt popover; height grows with content; max ~480pt before internal `ScrollView`. No CSS-style breakpoints. Panel adapts to: display scale (Retina via vector SF Symbols), Light/Dark/Auto (semantic tokens), accent color (`Color.accentColor`), Dynamic Type (system styles), Reduce Motion, Reduce Transparency, Increase Contrast, multi-monitor (system-anchored), status-item-near-edge repositioning.
- UX-DR38: Accessibility compliance target — WCAG 2.1 AA + Apple Accessibility Inspector clean. Manual release pass: VoiceOver, keyboard-only, Reduce Motion, Reduce Transparency, Increase Contrast, Light/Dark/Auto, all 8 system accent colors, color-blindness simulation, multi-monitor, Dynamic Type at max system size.

### FR Coverage Map

| FR | Epic | Hook |
|---|---|---|
| FR1 | Epic 1 | Menu bar icon visible |
| FR2 | Epic 1 | Wi-Fi-only icon state |
| FR3 | Epic 3 | Ethernet-active icon state |
| FR4 | Epic 1 | Disconnected icon state |
| FR5 | Epic 1 (Wi-Fi path) + Epic 3 (Ethernet path) | ≤1.5s icon update |
| FR6 | Epic 1 | Click status item to open panel |
| FR7 | Epic 1 | Click status item to dismiss panel |
| FR8 | Epic 1 | VoiceOver icon accessibility label |
| FR9 | Epic 1 | Popover anchored to menu bar icon |
| FR10 | Epic 1 | Esc dismisses panel |
| FR11 | Epic 1 | Click-outside dismisses panel |
| FR12 | Epic 3 | Ethernet section above Wi-Fi when link present |
| FR13 | Epic 3 | 1.5s grace before hiding Ethernet section |
| FR14 | Epic 1 | Light/Dark mode auto-adapt |
| FR15 | Epic 3 | Detect Ethernet interfaces (USB-C/Thunderbolt/dock) |
| FR16 | Epic 3 | Per-interface state (Active/Obtaining/DHCP timeout/No link) |
| FR17 | Epic 3 | IPv4 address per active interface |
| FR18 | Epic 3 | Negotiated link speed per active interface |
| FR19 | Epic 3 | Display name per Ethernet interface |
| FR20 | Epic 3 | Sort active-first, ties by stable identifier |
| FR21 | Epic 3 | Overflow summary entry to System Settings |
| FR22 | Epic 3 | Open Network Settings handoff |
| FR23 | Epic 1 | See nearby Wi-Fi networks list |
| FR24 | Epic 1 | Per-network SSID/signal/security/connected info |
| FR25 | Epic 1 | Captive-portal marker |
| FR26 | Epic 1 | On-demand Wi-Fi scan |
| FR27 | Epic 1 | Auto-refresh on system Wi-Fi events |
| FR28 | Epic 1 | Connected Wi-Fi distinguished |
| FR29 | Epic 2 | Connect to open Wi-Fi by tap |
| FR30 | Epic 2 | Connect to WPA Wi-Fi via inline password |
| FR31 | Epic 2 | Keychain-backed password storage |
| FR32 | Epic 2 | Hidden Wi-Fi via OtherNetworkPanel |
| FR33 | Epic 2 | Captive portal browser handoff |
| FR34 | Epic 2 | Disconnect via Wi-Fi power off |
| FR35 | Epic 2 | Wi-Fi power on/off toggle |
| FR36 | Epic 2 | Forget Network handoff to System Settings |
| FR37 | Epic 2 | Cause-typed connection failure feedback |
| FR38 | Epic 2 | Open Wi-Fi Settings handoff |
| FR39 | Epic 1 | Request Location auth on first scan |
| FR40 | Epic 1 | LocationDeniedView with one-tap Privacy path |
| FR41 | Epic 1 | Auto-resume scan on auth flip |
| FR42 | Epic 1 | No modal onboarding |
| FR43 | Epic 4 | Launch at Login configuration |
| FR44 | Epic 4 | Disable Launch at Login without restart |
| FR45 | Epic 1 | Menu-bar-only (LSUIElement, no Dock, no Cmd+Tab) |
| FR46 | Epic 1 (Wi-Fi) + Epic 3 (Ethernet) | Clean subscription teardown on terminate |
| FR47 | Epic 4 | Persist Launch at Login across reboots |
| FR48 | Epic 4 | ≤80 MB resident idle (final Instruments validation; baseline in Epic 1) |
| FR49 | Epic 4 | ≤0.5% CPU idle 60s avg (final Instruments validation; baseline in Epic 1) |
| FR50 | Epic 1 | No scheduled polling |
| FR51 | Epic 4 | Install from signed DMG outside MAS |
| FR52 | Epic 4 | Notarized — Gatekeeper clean |
| FR53 | Epic 4 | Background update check + notification |
| FR54 | Epic 4 | Manual update check |
| FR55 | Epic 4 | In-app update install with EdDSA verification |
| FR56 | Epic 1 | VoiceOver Wi-Fi row coverage |
| FR57 | Epic 3 | VoiceOver Ethernet row coverage |
| FR58 | Epic 3 | VoiceOver state-transition announcements |

## Epic List

### Epic 1: Foundation & Live Wi-Fi Visibility

User installs LinkHub, sees a single menu bar icon, opens the popover, and sees nearby Wi-Fi networks (read-only) with live updates from system events. Recovers from Location-permission denial in one click without restarting the app.

**FRs covered:** FR1, FR2, FR4, FR5 (Wi-Fi path), FR6, FR7, FR8, FR9, FR10, FR11, FR14, FR23, FR24, FR25, FR26, FR27, FR28, FR39, FR40, FR41, FR42, FR45, FR46 (Wi-Fi teardown), FR50, FR56

**Anchors NFRs:** NFR2 (popover ≤200ms cold / ≤100ms warm), NFR3 (5s scan timeout via `scanStatus`), NFR4, NFR5 (300ms debounce), NFR19–21 (no telemetry, on-device only), NFR23, NFR24, NFR26 (Wi-Fi/disconnected announcements), NFR27, NFR28, NFR29 (macOS 13 floor), NFR30 (Universal binary), NFR31 (semantic colors), NFR32 (accent), NFR33 (zero strict-concurrency warnings), NFR34 (layer folders), NFR35 (single MainActor AppState), NFR36 (zero deps at creation), NFR37 (os.Logger conventions)

**UX-DRs anchored:** UX-DR1–7 (foundation), UX-DR8 (StatusBarIcon Wi-Fi states), UX-DR9 (RootPanelView), UX-DR12 (WiFiSection read-side), UX-DR13 (WiFiRow normal/connected), UX-DR14 (LocationDeniedView), UX-DR16 (icon morph for Wi-Fi states), UX-DR21 (a11y combined labels), UX-DR22 (Wi-Fi VoiceOver templates normal/connected), UX-DR24 (StatusBarIcon labels Wi-Fi/off/disconnected), UX-DR25 (Wi-Fi power + Location auth announcements), UX-DR26 (color never sole signal), UX-DR27 (keyboard navigation), UX-DR28 (three dismissal paths), UX-DR32 (single-panel discipline), UX-DR33 (empty/zero states), UX-DR34 (copy & tone), UX-DR37 (responsive — 320pt fixed), UX-DR38 (a11y compliance baseline)

**Implementation notes:**
- Story 1.1 = project init per PRD 01 acceptance criteria (Xcode 16 macOS App template + AppKit AppDelegate lifecycle, Swift 6 strict concurrency, layer folders, Info.plist, `LinkHub.entitlements` Release-only, `PrivacyInfo.xcprivacy`, shared scheme).
- AppState built with single-monitor CombineLatest pattern (Wi-Fi only). Epic 3 expands to dual-monitor — small additive refactor of the same single sink.
- Init order load-bearing: AppState → StatusItemController → start() → startMonitors().
- WiFiMonitor read-only in Epic 1: scan + `CWEventDelegate` push events + `#if DEBUG` mock data path. Connection management surface comes in Epic 2.

---

### Epic 2: Wi-Fi Connection Management

User connects to open, WPA, hidden, and captive Wi-Fi networks; retries failed attempts inline with cause-typed feedback; toggles Wi-Fi power; forgets known networks via System Settings handoff. Passwords persisted in Keychain with `AfterFirstUnlock` accessibility.

**FRs covered:** FR29, FR30, FR31, FR32, FR33, FR34, FR35, FR36, FR37, FR38

**Anchors NFRs:** NFR10 (failed connect retryable, no global state corruption), NFR12 (Keychain `kSecClassGenericPassword` + `AfterFirstUnlock`, account=SSID), NFR22 (captive opens user's default browser, not in-app web view)

**UX-DRs anchored:** UX-DR13 (WiFiRow expanded/error/connecting states), UX-DR15 (OtherNetworkPanel), UX-DR18 (row expand/collapse 250ms), UX-DR22 (VoiceOver expanded/error templates), UX-DR26 (state-transition announcements for connect), UX-DR29 (button hierarchy primary/secondary/cancel), UX-DR30 (inline-caption feedback, no modal alerts), UX-DR31 (form patterns: auto-focus, Return submits, Esc dismisses, error preserves context, Keychain on success only), UX-DR34 (copy: "Incorrect password", no blame), UX-DR36 (Wi-Fi row right-click context: Forget + Open in Settings)

**Implementation notes:**
- Adds `WiFiMonitor.associate(...)`, `KeychainService`, `WiFiConnectionFailure` typed error mapping `CWErrorDomain` codes (`wrongPassword`, `outOfRange`, `associationTimeout`, `authenticationError`, `unknown(code:)`).
- Wi-Fi power `Toggle` in `WiFiSection` header bound to `WiFiMonitor.isPowered`.
- `OtherNetworkPanel` replaces `RootPanelView` content (single-panel discipline, not modal sheet).
- Captive routing handed off via `NSWorkspace.open(http://captive.apple.com)`.
- Forget handoff: `x-apple.systempreferences:com.apple.wifi-settings-extension` via `SystemSettingsService`.

---

### Epic 3: Ethernet Awareness — The Cable Moment

User plugs an Ethernet cable → menu bar icon morphs to `cable.connector` within 1.5s → opens panel and sees Ethernet section promoted to top with display name, IP, link speed; sees all four interface states; multi-interface enumeration with overflow handoff. Symmetric grace on cable-out.

**FRs covered:** FR3, FR5 (Ethernet path), FR12, FR13, FR15, FR16, FR17, FR18, FR19, FR20, FR21, FR22, FR46 (Ethernet teardown), FR57, FR58

**Anchors NFRs:** NFR1 (icon ≤1.5s), NFR4 (60fps section reorder), NFR5 (300ms debounce on dock-wake flutter), NFR6 (no resource drift over 7 days), NFR8 (zero leaks via Sendable extraction + weak self), NFR9 (clean SCDynamicStore + CWWiFiClient teardown), NFR11 (sleep/wake/router/VPN survival), NFR25 (Ethernet VoiceOver labels), NFR26 (NSAccessibility transition announcements), NFR27 (decorative dots hidden), NFR28 (Reduce Motion fallback)

**UX-DRs anchored:** UX-DR8 (StatusBarIcon Ethernet states + crossfade), UX-DR9 (RootPanelView section reorder + accessibility announcement), UX-DR10 (EthernetSection caption header + top-2 inline + overflow row), UX-DR11 (EthernetRow 4 states + state dot + plain-text label), UX-DR16 (300ms icon morph), UX-DR17 (250ms section reorder), UX-DR19 (1.2s pulsing-dot loop), UX-DR20 (Reduce Motion gating), UX-DR23 (Ethernet VoiceOver templates all 4 states), UX-DR24 (StatusBarIcon Ethernet active label), UX-DR25 (cable in/out announcements), UX-DR26 (color never sole signal — plain-text labels mandatory)

**Implementation notes:**
- Adds `EthernetMonitor` on private serial dispatch queue using `SCDynamicStoreSetDispatchQueue`, watching keys `State:/Network/Interface/[^/]+/Link` AND `State:/Network/Interface/[^/]+/IPv4`. Re-enumerate via `SCNetworkInterfaceCopyAll()` inside every callback (handles hotplug).
- Sendable extraction: build `[EthernetInterface]` snapshot on private queue → `Task { @MainActor in ... }`. Never capture `SCNetworkInterface`/`CFType` across actor.
- AppState refactor: expand `Publishers.CombineLatest(ethernetMonitor.$interfaces, wifiPublisher).sink` to dual-monitor; rebuild `networkState` and `connectionMode` atomically.
- StatusBarIcon adds Ethernet state path; icon mapping: `cable.connector` (Ethernet active) / `wifi` (Wi-Fi only or Ethernet link-only with Wi-Fi connected) / `wifi.slash` (disconnected).
- Cable-in → icon swap latency budget: 300ms debounce + ≤1.5s end-to-end (NFR1).
- Cable-out grace: 1.5s before section hide.

---

### Epic 4: Lifecycle, Distribution & Updates

User installs LinkHub from a signed and notarized DMG (Gatekeeper clean), configures Launch at Login, receives auto-update notifications via Sparkle 2 with EdDSA verification, and accesses Quit / About / Check for Updates / Launch at Login from a status-item right-click menu.

**FRs covered:** FR43, FR44, FR47, FR51, FR52, FR53, FR54, FR55, FR48 (final validation), FR49 (final validation)

**Anchors NFRs:** NFR7 (≥99.5% crash-free over 30 days, validated post-release via Apple-collected reports), NFR13 (Developer ID Application signing), NFR14 (notarytool + stapling), NFR15 (Hardened Runtime Release-only), NFR16 (Sparkle EdDSA + `SUPublicEDKey`), NFR17 (entitlement minimum: Location only, sandbox off), NFR18 (`PrivacyInfo.xcprivacy` in sync), NFR36 (Sparkle 2 SPM dep added at this wave only)

**UX-DRs anchored:** UX-DR35 (status-item right-click NSMenu: Launch at Login / Check for Updates… / About LinkHub / Quit LinkHub)

**Implementation notes:**
- Adds `LaunchAtLoginService` (`SMAppService.mainApp.register()` / `.unregister()`); persistence in UserDefaults `launchAtLogin: Bool`.
- Adds `App/UpdaterController.swift` wrapping Sparkle 2 `SPUStandardUpdaterController`; wired in `AppDelegate.applicationDidFinishLaunching` after `StatusItemController.start()` and before `appState.startMonitors()`.
- Adds `MenuBar/StatusItemMenu.swift` right-click `NSMenu` factory bound by `StatusItemController` to status-item button via right-click handler.
- Sparkle 2 added as **first and only** SPM dep (`https://github.com/sparkle-project/Sparkle`) — preserves zero-deps-at-creation discipline (NFR36).
- Distribution chain: `xcodebuild archive` → `xcodebuild -exportArchive` (with `ExportOptions.plist`) → `scripts/notarize.sh` (`notarytool submit ... --wait` + `stapler staple`) → `scripts/make-dmg.sh` (DMG with `/Applications` symlink) → `scripts/update-appcast.sh` (EdDSA-sign appcast item + commit to GitHub Pages).
- Sparkle EdDSA: private key in macOS Keychain; public key in `Info.plist` (`SUPublicEDKey`).
- Versioning: SemVer `CFBundleShortVersionString = MAJOR.MINOR.PATCH`; monotonic integer `CFBundleVersion`.
- Final Instruments validation pass: 1-hour induced state-change session — Allocations, Leaks, Time Profiler — verifying NFR48 (≤80 MB), NFR49 (≤0.5% CPU), NFR8 (zero leaks).
