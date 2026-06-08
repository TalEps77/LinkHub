---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
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

---

## Epic 1: Foundation & Live Wi-Fi Visibility

User installs LinkHub, sees a single menu bar icon, opens the popover, and sees nearby Wi-Fi networks (read-only) with live updates from system events. Recovers from Location-permission denial in one click without restarting the app.

### Story 1.1: Project Initialization from Xcode 16 macOS Template

As a developer,
I want to scaffold the LinkHub Xcode project from the macOS App template with Swift 6 strict concurrency and the project's layer-based folder structure,
So that all subsequent stories can build on a consistent, lint-clean foundation that matches the architecture decisions.

**Acceptance Criteria:**

**Given** an empty repo
**When** the project is initialized from the Xcode 16 built-in macOS App template (AppKit App Delegate lifecycle)
**Then** bundle identifier is `com.linkhub.app`, product name is `LinkHub`, test target is `LinkHubTests`
**And** the SwiftUI `@main App` is replaced with a `@main NSApplicationDelegate` subclass

**Given** the project file
**When** build settings are inspected
**Then** deployment target is macOS 13.0, `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`
**And** Release builds produce zero strict-concurrency warnings or errors (NFR33)

**Given** the source tree
**When** folders are inspected
**Then** the layout contains `App/`, `MenuBar/`, `Network/` (with `Models/`), `UI/` (with `Components/`, `Panels/`, `Windows/`, `Theme.swift`), `State/`, `Services/`, `Utilities/` (NFR34)

**Given** the Info.plist
**When** keys are inspected
**Then** `LSUIElement = true`, `NSLocationWhenInUseUsageDescription` is present, `CFBundleShortVersionString` and `CFBundleVersion` are present
**And** the app has no Dock icon and no Cmd+Tab entry when launched (FR45)

**Given** the entitlements config
**When** Debug and Release configurations are compared
**Then** `LinkHub.entitlements` (Location only) is applied to Release config only
**And** Debug builds run ad-hoc unsigned with no entitlements
**And** App Sandbox is disabled (NFR17)

**Given** the privacy manifest
**When** `PrivacyInfo.xcprivacy` is inspected
**Then** it declares Location (CA92.1), UserDefaults, file timestamp, and system boot time required-reason APIs (NFR18)

**Given** the repo
**When** scheme and gitignore are inspected
**Then** `LinkHub.xcscheme` is shared (committed under `xcshareddata/`) and `xcuserdata/` is gitignored

---

### Story 1.2: AppState, StatusItemController, and Popover Skeleton

As a user,
I want to see the LinkHub icon in the menu bar and toggle a popover by clicking it,
So that I have a working app shell to drop content into and the foundational dismissal behaviors work before any network UI exists.

**Acceptance Criteria:**

**Given** the app launches
**When** `AppDelegate.applicationDidFinishLaunching` runs
**Then** init order is `AppState()` → `StatusItemController(appState:)` → `statusItemController.start()` → `appState.startMonitors()` (load-bearing)
**And** `AppState` is a single `@MainActor final class ObservableObject` with `@Published` state, instantiated once for process lifetime (NFR35)

**Given** the app is running
**When** the menu bar is inspected
**Then** a single `NSStatusItem` of length `.squareLength` (22 pt) is visible (FR1)
**And** the status-item button image is a SF Symbol template (`pointSize: 17, weight: .regular, scale: .medium`) — no xcassets imageset

**Given** the popover is closed
**When** the user clicks the status item
**Then** an `NSPopover` hosting `NSHostingController<RootPanelView>` opens anchored to the status item (FR6, FR9)
**And** `popover.behavior = .transient`

**Given** the popover is open
**When** the user clicks the status item again, presses Escape, or clicks outside the popover
**Then** the popover dismisses (FR7, FR10, FR11)
**And** the Escape key handler is installed via local `NSEvent` keyDown monitor (keyCode 53) in `show()` and removed in `close()`

**Given** the popover is visible
**When** the user toggles macOS Light/Dark/Auto appearance
**Then** the popover background uses `NSVisualEffectView` `.windowBackground` vibrancy (UX-DR6)
**And** all colors resolve via system semantic tokens, no hardcoded hex (NFR31, UX-DR4)
**And** when system Reduce Transparency is on, the panel falls back to opaque `.windowBackgroundColor`

**Given** no network signal yet
**When** popover content is inspected
**Then** `RootPanelView` renders an empty placeholder using `PanelLayout` constants from `UI/Theme.swift` (320 pt fixed width, 8 pt outer padding) (UX-DR5, UX-DR7)

---

### Story 1.3: WiFiMonitor — On-Demand Scan, Push Events, ScanStatus Timeout

As a user,
I want LinkHub to discover nearby Wi-Fi networks via the system and react to live system events,
So that the panel reflects current Wi-Fi reality without polling and surfaces a scanning indicator if a scan is slow.

**Acceptance Criteria:**

**Given** `WiFiMonitor` is started
**When** it initializes
**Then** it is a `@MainActor final class` exposing public state via `@Published` only (no AsyncStream)
**And** it owns a `CWWiFiClient.shared()` and registers itself as `CWEventDelegate`
**And** it subscribes to ssid, link, linkQuality, and power events

**Given** the app is running
**When** the panel is closed
**Then** no scheduled timer or polling fires for Wi-Fi (FR50, NFR50)

**Given** a CWEventDelegate callback fires on a background thread
**When** values are read from `CWNetwork`/`CWInterface`
**Then** Sendable values are extracted on the callback thread
**And** the hop to MainActor uses `Task { @MainActor in ... }` — `CWNetwork`/`CWInterface` are never captured across the actor boundary

**Given** rapid system events
**When** events arrive in succession
**Then** they pass through a `PassthroughSubject<Void, Never>.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)` before driving any UI update (NFR5)

**Given** the user requests a scan
**When** `WiFiMonitor.requestScan()` is called
**Then** `AppState.scanStatus` transitions `idle` → `scanning` → either `idle` (results published) or `timedOut` (after 5 s)
**And** the 5 s timeout is enforced via a Task race (NFR3)

**Given** `#if DEBUG` builds
**When** an opt-in env var or compile-time flag is set
**Then** `WiFiMonitor` returns mock data from `LinkHubTests/Fixtures/MockWiFiData.swift` instead of calling CoreWLAN
**And** the mock path does not auto-engage in regular Debug builds

**Given** the app is terminating
**When** `applicationWillTerminate` runs
**Then** `WiFiMonitor.stop()` sets `CWWiFiClient.shared().delegate = nil` (NFR9, FR46)

---

### Story 1.4: RootPanelView, WiFiSection, WiFiRow (Read-Only)

As a user,
I want to open the panel and see the list of nearby Wi-Fi networks with their SSID, signal, security, and connected state,
So that I can read my current Wi-Fi context at a glance without taking any action.

**Acceptance Criteria:**

**Given** the popover opens
**When** `RootPanelView` renders
**Then** it lays out as `VStack(spacing: 8) { WiFiSection; FooterRows }` at 320 pt fixed width (UX-DR9)
**And** popover first paint is ≤200 ms cold / ≤100 ms warm on Apple Silicon (NFR2)

**Given** scanned Wi-Fi data is available
**When** `WiFiSection` renders
**Then** the section header is a `Label("WI-FI") + Toggle` (toggle is non-functional in Epic 1; bound to a stub) using `.caption` 10 pt semibold uppercase (UX-DR3, UX-DR12)
**And** the connected network row appears first, distinguished by a `checkmark` SF Symbol (FR28, UX-DR13)
**And** other networks follow

**Given** a Wi-Fi network row
**When** `WiFiRow` renders
**Then** it shows `HStack { Checkmark?; SSIDText(.body); Spacer; LockIcon?; CaptiveIcon?; SignalBars }` (UX-DR13)
**And** SSID uses `.body` 13 pt regular; hidden networks render as the literal "Hidden Network" (FR24)
**And** security marker uses `lock.fill` SF Symbol for password-protected networks; absent for open networks (FR24, UX-DR2)
**And** captive-portal networks show a `globe` SF Symbol (FR25)
**And** SignalBars is a 16×16 pt SF Symbol reflecting current RSSI bucket

**Given** scanned data updates
**When** `wifiMonitor.$networks` publishes
**Then** the list refreshes with no scheduled poll, driven by CWEventDelegate push events (FR27)

**Given** the user has the panel open
**When** the panel becomes visible via `PopoverController.show()`
**Then** a fire-and-forget `Task { try? await appState.wifiMonitor.requestScan() }` fires immediately after `popover.show(...)` (FR26)

**Given** `scanStatus == .scanning` and the existing list is empty
**When** the user observes the panel
**Then** a visible scanning indicator is displayed (NFR3)
**And** when the list is non-empty, results merge in without a loading state (UX-DR33)

**Given** Wi-Fi power is on but no networks were found
**When** the panel renders
**Then** a `.callout` centered "No networks found" empty-state appears with no action button (UX-DR33)

---

### Story 1.5: LocationDeniedView + CLLocationManager Authorization Flow

As a user,
I want LinkHub to request Location authorization on first scan and recover gracefully if I deny it,
So that I can grant access from a one-tap path to Privacy settings and resume scanning without restarting the app.

**Acceptance Criteria:**

**Given** the user opens the panel for the first time and Wi-Fi scanning is requested
**When** `WiFiMonitor.requestScan()` runs
**Then** `CLLocationManager.requestWhenInUseAuthorization()` is invoked (FR39)
**And** no modal onboarding is shown; the panel is the introduction (FR42)

**Given** Location authorization is `.denied` or `.restricted`
**When** `WiFiSection` would render
**Then** `LocationDeniedView` replaces the Wi-Fi list (UX-DR12, UX-DR14)
**And** the view shows a centered VStack with `lock` SF Symbol + headline "Location access required" + body explaining Apple's macOS 10.15+ requirement + a `.borderedProminent` "Open Privacy Settings" button (UX-DR14, UX-DR29, UX-DR34)

**Given** the user taps "Open Privacy Settings"
**When** the action fires
**Then** the popover dismisses and `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)` opens the Privacy/Location pane (FR40)

**Given** Location authorization flips from denied to `.authorized` (or `.authorizedWhenInUse`) while LinkHub is running
**When** the `CLLocationManagerDelegate.locationManagerDidChangeAuthorization` callback fires
**Then** `WiFiMonitor.requestScan()` is auto-retried (FR41)
**And** the panel transitions to the Wi-Fi list state without app restart

**Given** the user grants Location after denial
**When** the next scan completes
**Then** `NSAccessibility.post(.announcementRequested, "Wi-Fi networks loading")` is posted (UX-DR25)

---

### Story 1.6: Wi-Fi Side VoiceOver, StatusBarIcon, and Idle Resource Baseline

As a VoiceOver user,
I want the menu bar icon and every Wi-Fi row to expose a meaningful accessibility label and announce state transitions,
So that I can perceive my Wi-Fi context entirely through assistive technology.

**Acceptance Criteria:**

**Given** the Wi-Fi-only `connectionMode` paths
**When** the status item renders
**Then** the SF Symbol image mapping is: Wi-Fi connected → `wifi`; Wi-Fi off or no Wi-Fi connection → `wifi.slash` (FR2, FR4, UX-DR2, UX-DR8)
**And** Ethernet-path image (`cable.connector`) is deferred to Epic 3 / Story 3.4

**Given** a Wi-Fi state change (Wi-Fi join / leave / power flip)
**When** the event propagates through the 300 ms debounced sink
**Then** the menu bar icon image updates within 1.5 s end-to-end (FR5 Wi-Fi path, NFR1)

**Given** the menu bar icon is rendered
**When** VoiceOver reads it
**Then** the icon's `accessibilityLabel` follows UX-DR24 templates: Wi-Fi only — `"Wi-Fi connected, {SSID}, signal {strength}"`; Wi-Fi off — `"Wi-Fi off"`; disconnected — `"No network connection"` (FR8, NFR23)
**And** the label updates on every `$networkState` change

**Given** `connectionMode` transitions to `.disconnected`
**When** the change fires
**Then** `NSAccessibility.post(.announcementRequested, "No network connection")` is posted (UX-DR25, NFR26)
**And** announcements are posted for Wi-Fi power on ("Wi-Fi turned on") and Wi-Fi power off ("Wi-Fi turned off")

**Given** a `WiFiRow` is read by VoiceOver
**When** the label is composed
**Then** it uses `.accessibilityElement(children: .combine)` and follows UX-DR22 templates — normal: `"{SSID}, {securityType}, signal {strength}"`; connected: `"{SSID}, connected, {securityType}, signal {strength}"` (FR56, NFR24)
**And** decorative glyphs (signal bars, security marker, captive marker) are marked `accessibilityHidden(true)` (NFR27)

**Given** macOS Reduce Motion is on
**When** the status icon would morph between states
**Then** the swap is instant (UX-DR16, NFR28)
**And** when off, the icon crossfades over 300 ms ease-in-out (UX-DR16)

**Given** keyboard-only operation
**When** the panel is open
**Then** Tab moves focus through Wi-Fi rows, Return activates, Esc dismisses, Space toggles Wi-Fi power (UX-DR27)
**And** the system focus ring is used; no custom focus styling

**Given** the app has been running idle with the panel closed for 60 s
**When** Activity Monitor / Instruments is sampled
**Then** resident memory is ≤80 MB and 60 s avg CPU is ≤0.5% on Apple Silicon (FR48, FR49 baseline)
**And** the measurement is recorded as the Epic 1 baseline for regression comparison

---

## Epic 2: Wi-Fi Connection Management

User connects to open, WPA, hidden, and captive Wi-Fi networks; retries failed attempts inline with cause-typed feedback; toggles Wi-Fi power; forgets known networks via System Settings handoff. Passwords persisted in Keychain with `AfterFirstUnlock` accessibility.

### Story 2.1: WiFiMonitor.associate + Cause-Typed Connection Failure

As a user,
I want LinkHub to attempt Wi-Fi connections via CoreWLAN and surface specific failure causes,
So that when a connection fails I can tell whether the password is wrong, the network is out of range, or something else is wrong.

**Acceptance Criteria:**

**Given** the user requests a connection to an open network
**When** `WiFiMonitor.associate(network:password:)` is called with `password == nil`
**Then** the call invokes `CWInterface.associate(to:password:)` (or open variant) and reports success or failure via a typed result (FR29)

**Given** a connection attempt fails
**When** the `CWErrorDomain` code is mapped
**Then** `Network/Models/WiFiConnectionFailure.swift` defines `enum WiFiConnectionFailure: Error { case wrongPassword; case outOfRange; case associationTimeout; case authenticationError; case unknown(code: Int) }` (FR37)
**And** mapping covers the relevant `CWErrorDomain` codes per architecture spec

**Given** a connection attempt completes (success or failure)
**When** the result lands on MainActor
**Then** the app remains in a clean state — the user can retry without restart (NFR10)
**And** any error is surfaced inline via `AppState`, never via `NSAlert` (UX-DR30)

**Given** a connection attempt
**When** errors propagate
**Then** layer-typed errors are used; no `NSError` rethrow leaks past the Network layer

---

### Story 2.2: KeychainService — Persist Wi-Fi Passwords

As a user,
I want LinkHub to remember my Wi-Fi passwords securely so I don't have to retype them,
So that re-joining a known network feels like the system Wi-Fi menu.

**Acceptance Criteria:**

**Given** a successful connection to a password-protected network
**When** the connection completes
**Then** `KeychainService.set(password:forSSID:)` writes the password with `kSecClass == kSecClassGenericPassword`, `kSecAttrAccount == SSID`, `kSecAttrService == Bundle.main.bundleIdentifier`, `kSecAttrAccessible == kSecAttrAccessibleAfterFirstUnlock` (FR31, NFR12)

**Given** a known SSID
**When** the user reconnects
**Then** `KeychainService.password(forSSID:)` returns the stored password (or nil)
**And** the user is not re-prompted for the password unless retrieval fails

**Given** any failure path (wrong password, association timeout, authentication error)
**When** the connection attempt fails
**Then** no Keychain write occurs; the entry is preserved only on success (UX-DR31)

**Given** the running app
**When** any code path persists a password
**Then** no password is written to UserDefaults, plain files, or any long-lived in-memory store outside the Keychain (NFR12)

---

### Story 2.3: WiFiRow Expanded State + Inline Password + Error Caption

As a user,
I want to tap a password-protected Wi-Fi row, type the password inline, and see a specific error if it fails,
So that I can join networks without leaving the panel and retry without losing context.

**Acceptance Criteria:**

**Given** a password-protected Wi-Fi row in `.normal` state
**When** the user taps it
**Then** the row transitions to `.expanded(password:error:)` and the row height grows from 24 pt to 56 pt (UX-DR5, UX-DR13)
**And** a `SecureField` is auto-focused; Return submits, Esc collapses without submit (UX-DR31)
**And** the expand animation runs 250 ms ease-in-out, instant under Reduce Motion (UX-DR18, UX-DR20)

**Given** the user submits a password
**When** the connection enters `.connecting`
**Then** the row visually reflects connecting state without a separate spinner (UX-DR30, UX-DR33)

**Given** the connection fails
**When** the failure type is `WiFiConnectionFailure`
**Then** an inline `.caption` `Color.red` error label appears below the field with copy mapped from the case — e.g., `wrongPassword` → "Incorrect password" (UX-DR30, UX-DR34)
**And** the field is cleared, focus is retained, and the row stays expanded (UX-DR31)

**Given** an expanded `WiFiRow` with an error
**When** VoiceOver reads it
**Then** it follows UX-DR22 expanded/error templates: `"{SSID}, {error}, password field"`, with field-level label `"Password for {SSID}"` (FR56)
**And** the error caption is announced when it appears

**Given** a successful connection
**When** the row transitions to `.connected`
**Then** `NSAccessibility.post(.announcementRequested, "Connected to {SSID}")` is posted (UX-DR25)

---

### Story 2.4: OtherNetworkPanel — Hidden Network Connect

As a user,
I want to connect to a hidden Wi-Fi network by typing its SSID and security details,
So that I can join networks that don't broadcast their SSID without leaving LinkHub.

**Acceptance Criteria:**

**Given** the Wi-Fi list is rendered
**When** the user taps the "Other Network…" footer entry
**Then** `OtherNetworkPanel` fully replaces `RootPanelView` content within the same popover (UX-DR15, UX-DR32)
**And** no modal sheet, NSWindow, or drill-down navigation is used

**Given** `OtherNetworkPanel` is visible
**When** the user inspects it
**Then** it shows a title, SSID `TextField`, security `Picker` (Open / WPA / Enterprise), conditional `SecureField` (shown when security != Open), and `Cancel` / `Join` buttons (FR32, UX-DR15)
**And** the SSID field is auto-focused on appear (UX-DR31)
**And** `Join` is `.bordered` (secondary), `Cancel` is `.bordered`, with no primary action shown alongside (UX-DR29)

**Given** the user taps `Join`
**When** the security is WPA/Enterprise
**Then** the entered password is passed to `WiFiMonitor.associate(...)` with the typed SSID
**And** validation is deferred to `CWInterface.associate` (no client-side regex) (UX-DR31)

**Given** the user taps `Cancel` or presses Esc
**When** the action fires
**Then** `OtherNetworkPanel` is replaced by `RootPanelView` content (UX-DR32)
**And** no Keychain write occurs

**Given** the join attempt fails
**When** the error returns
**Then** an inline error caption appears under the form, the field state is preserved per UX-DR31

---

### Story 2.5: Wi-Fi Power Toggle + Captive Portal Handoff

As a user,
I want to toggle Wi-Fi power directly from the panel and be routed to my browser when joining a captive network,
So that I can disable Wi-Fi without opening System Settings and complete captive sign-in in my own browser.

**Acceptance Criteria:**

**Given** the `WiFiSection` header is rendered
**When** the user clicks the `Toggle`
**Then** `WiFiMonitor.setPowered(_:)` flips the CoreWLAN interface power state (FR35)
**And** `appState.wifiMonitor.isPowered` reflects the change

**Given** Wi-Fi is powered off
**When** the user observes the panel
**Then** the network list is hidden; only the section header with `Toggle` remains and a "Wi-Fi: Off" plain-text label is shown (UX-DR12, UX-DR33)
**And** the user is no longer connected to any Wi-Fi network (FR34)

**Given** Wi-Fi power changes
**When** the change is observed
**Then** `NSAccessibility.post(.announcementRequested, ...)` posts "Wi-Fi turned on" or "Wi-Fi turned off" (UX-DR25)

**Given** the user attempts to connect to a captive network
**When** the post-association captive state is detected
**Then** `NSWorkspace.shared.open(URL(string: "http://captive.apple.com")!)` opens the user's default browser (FR33, NFR22)
**And** no in-app webview is rendered

**Given** a captive network appears in the list
**When** `WiFiRow` renders
**Then** the captive marker (`globe` SF Symbol) is visible per FR25

---

### Story 2.6: Forget Network + Open Wi-Fi Settings Handoffs

As a user,
I want to forget a known network and open the system Wi-Fi settings pane from inside LinkHub,
So that I can complete management actions LinkHub intentionally hands off to Apple's UI without leaving my flow.

**Acceptance Criteria:**

**Given** a `WiFiRow` whose SSID is in the system's known networks
**When** the user right-clicks (or two-finger taps) the row
**Then** a `.contextMenu` shows `Forget` and `Open in Settings` items (UX-DR36)
**And** rows for unknown SSIDs do not show the context menu

**Given** the user selects `Forget`
**When** the action fires
**Then** the popover dismisses and `SystemSettingsService.openWiFiSettings()` opens `x-apple.systempreferences:com.apple.wifi-settings-extension` via `NSWorkspace.shared.open(_:)` (FR36, UX-DR32)
**And** no in-app removal of the system known-network entry is attempted

**Given** the `WiFiSection` footer
**When** the user inspects it
**Then** an `Open Network Settings…` link-style row (`.plain` button, ellipsis copy per UX-DR34) is present (UX-DR12, UX-DR29)
**And** tapping it opens `x-apple.systempreferences:com.apple.wifi-settings-extension` (FR38)
**And** the popover auto-dismisses before the system pane appears (UX-DR32)

**Given** any handoff
**When** `SystemSettingsService` is called
**Then** the deep-link URL matches the architecture-specified scheme; no other URLs are opened
**And** the call uses `NSWorkspace.shared.open(_:)`

**Given** the app has run a representative Epic 2 session (10 connect/disconnect/forget cycles)
**When** Activity Monitor / Instruments is sampled with panel closed for 60 s afterward
**Then** resident memory is ≤80 MB and 60 s avg CPU is ≤0.5% (FR48, FR49 baseline regression check vs Epic 1 baseline)

---

## Epic 3: Ethernet Awareness — The Cable Moment

User plugs an Ethernet cable → menu bar icon morphs to `cable.connector` within 1.5s → opens panel and sees Ethernet section promoted to top with display name, IP, link speed; sees all four interface states; multi-interface enumeration with overflow handoff. Symmetric grace on cable-out.

### Story 3.1: EthernetMonitor — SCDynamicStore + Sendable Extraction

As a user,
I want LinkHub to detect Ethernet interfaces (USB-C, Thunderbolt, dock) and react to link / IP changes immediately,
So that the panel and icon track cable plug/unplug without polling.

**Acceptance Criteria:**

**Given** the app launches
**When** `EthernetMonitor.start()` runs
**Then** an `SCDynamicStore` is created with `SCDynamicStoreSetDispatchQueue` bound to a private serial dispatch queue
**And** watch keys are `State:/Network/Interface/[^/]+/Link` AND `State:/Network/Interface/[^/]+/IPv4`
**And** every callback re-enumerates interfaces via `SCNetworkInterfaceCopyAll()` to handle hotplug (FR15)

**Given** an SCDynamicStore C callback fires
**When** values are read from `SCNetworkInterface`/`CFType`
**Then** Sendable values populate a `[EthernetInterface]` snapshot on the private queue
**And** the hop to MainActor uses `Task { @MainActor in ... }` — `SCNetworkInterface` and `CFType` are never captured across the actor (NFR8)

**Given** rapid Link/IPv4 events
**When** dock-wake or cable-flutter occurs
**Then** events pass through a `PassthroughSubject<Void, Never>.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)` (NFR5)

**Given** an active Ethernet interface
**When** the snapshot is built
**Then** each `EthernetInterface` exposes display name, BSD name (e.g., en3), IPv4 address, negotiated link speed (Mbps/Gbps), and state (`active`, `obtaining`, `dhcpTimeout`, `noLink`) (FR16, FR17, FR18, FR19)
**And** all model types in `Network/Models/` are value types and `Sendable`

**Given** `EthernetMonitor.stop()` is called on termination
**When** teardown runs
**Then** `SCDynamicStoreSetDispatchQueue(store, nil)` is invoked (NFR9, FR46)

---

### Story 3.2: AppState Dual-Monitor Sink Refactor

As a developer,
I want `AppState` to combine Wi-Fi and Ethernet streams into a single atomic state update,
So that `connectionMode` and `networkState` are always coherent and no Epic-2 connect/disconnect path regresses.

**Acceptance Criteria:**

**Given** Epic 1 shipped a single-monitor `Publishers.CombineLatest` sink (Wi-Fi only)
**When** Epic 3 expands the sink
**Then** the sink becomes `Publishers.CombineLatest(ethernetMonitor.$interfaces, wifiPublisher).debounce(...).sink { ... }` and rebuilds `networkState` and `connectionMode` atomically in one write
**And** `AppState` continues to be a single `@MainActor final class ObservableObject` (NFR35)

**Given** the sink rebuild
**When** the regression test pass runs
**Then** the following Epic-2 paths still pass: open-network connect, WPA password connect, hidden-network connect via `OtherNetworkPanel`, Wi-Fi power on/off, Forget handoff
**And** failed-connect retry leaves the app in a clean state (NFR10)

**Given** UI components
**When** the codebase is inspected
**Then** UI subscribes only to `AppState` via `@EnvironmentObject` — no view directly observes `WiFiMonitor` or `EthernetMonitor` (NFR35)

**Given** Release builds
**When** the build runs
**Then** zero Swift 6 strict-concurrency warnings or errors are emitted (NFR33)

---

### Story 3.3: EthernetSection + EthernetRow with Four States

As a user,
I want to see a per-Ethernet-interface row with its display name, status, IP, and link speed,
So that I can understand at a glance whether each interface is healthy.

**Acceptance Criteria:**

**Given** at least one Ethernet interface has link
**When** `RootPanelView` renders
**Then** `EthernetSection` appears above `WiFiSection` (FR12, UX-DR9, UX-DR10)
**And** the section header is `.caption` UPPERCASE 10 pt semibold "ETHERNET" (UX-DR3)
**And** the top 2 active interfaces render inline as `EthernetRow`s

**Given** an `EthernetRow`
**When** it renders
**Then** layout is `HStack { StateDot; VStack(.leading) { displayName(.body); detail(.caption) } }` (UX-DR11)
**And** state dot is an 8 pt circle paired with a plain-text label so color is never the only signal (UX-DR26)
**And** four states are supported: `.active(ip:speed:)` ("Active", green dot, detail = `"{ip} • {speed}"`), `.obtaining` ("Obtaining…", pulsing yellow), `.dhcpTimeout` ("DHCP timeout", red), `.noLink` ("No link", gray) (FR16, UX-DR11)

**Given** a row in `.obtaining`
**When** Reduce Motion is off
**Then** the dot pulses on a 1.2 s loop, opacity 0.4 → 1.0 ease-in-out (UX-DR19)
**And** when Reduce Motion is on, the dot is static at 1.0 (UX-DR20)

**Given** the section is rendered
**When** colors are inspected
**Then** all colors resolve via system semantic tokens; no hex literals; `Color.red` only used for the DHCP-timeout dot's adjacent inline text (UX-DR4)

---

### Story 3.4: StatusBarIcon Ethernet Path + 300 ms Crossfade

As a user,
I want the menu bar icon to morph to a cable icon when I plug in Ethernet,
So that I get an instant visual signal of the cable moment without opening the panel.

**Acceptance Criteria:**

**Given** `connectionMode` transitions
**When** the next icon is selected
**Then** mapping is: Ethernet active → `cable.connector`; Wi-Fi only (or Ethernet link without IP, with Wi-Fi connected) → `wifi`; disconnected → `wifi.slash` (FR2, FR3, FR4, UX-DR2, UX-DR8)

**Given** an Ethernet cable is plugged in
**When** the link event fires
**Then** the menu bar icon updates within 1.5 s end-to-end (300 ms debounce + system event latency budget) (FR5, NFR1)

**Given** `connectionMode` changes
**When** the icon would morph
**Then** the change uses a 300 ms ease-in-out crossfade between SF Symbol template images (UX-DR8, UX-DR16)
**And** under Reduce Motion the swap is instant (UX-DR16, UX-DR20, NFR28)

**Given** Ethernet active state
**When** VoiceOver reads the icon
**Then** `accessibilityLabel` follows UX-DR24: `"Ethernet connected, {displayName}, {speed}"` (FR8)

**Given** the icon updates
**When** the path is inspected
**Then** SF Symbols are loaded via `NSImage(systemSymbolName:accessibilityDescription:)` with config `pointSize: 17, weight: .regular, scale: .medium` — no asset-catalog imageset

---

### Story 3.5: Cable-Out 1.5 s Grace + Section Reorder Animation

As a user,
I want the Ethernet section to remain visible for a brief grace period after I unplug,
So that transient dock disconnects don't make the UI flicker and I see the change as a smooth reorder when it lasts.

**Acceptance Criteria:**

**Given** a previously linked Ethernet interface loses link
**When** no Ethernet interface has had link for 1.5 s
**Then** `EthernetSection` is hidden (FR13)
**And** if link is restored before 1.5 s elapses, the section remains visible without flicker

**Given** the section appears or disappears
**When** the layout reorders
**Then** the reorder runs 250 ms ease-in-out (UX-DR9, UX-DR17)
**And** under Reduce Motion the change is instant (UX-DR20, NFR28)
**And** transitions run at display refresh rate without dropped frames on Apple Silicon (NFR4)

**Given** `connectionMode` transitions to or from Ethernet-active
**When** the change fires
**Then** `RootPanelView` posts `NSAccessibility.post(.announcementRequested, ...)` with "Ethernet connected" or "Ethernet disconnected" (UX-DR25, NFR26, FR58)

**Given** the app survives sleep/wake, router resets, dock reconnects, and VPN toggles
**When** the user opens the panel afterward
**Then** the panel responds to click within 1.5 s and the icon updates within 1.5 s of the next state change (NFR11)

---

### Story 3.6: Multi-Ethernet Enumeration, Overflow Row, VoiceOver, and Resource Baseline

As a user,
I want LinkHub to handle multiple Ethernet interfaces gracefully and let me jump to System Settings if I have more interfaces than the panel shows inline,
So that complex docking setups don't degrade the experience and assistive technology can perceive every interface.

**Acceptance Criteria:**

**Given** multiple Ethernet interfaces exist
**When** `EthernetSection` renders
**Then** interfaces are sorted active-first; ties are broken by stable identifier order (BSD name) (FR20)
**And** the top 2 render inline; remaining interfaces collapse into a single "+ N more in Settings…" overflow row (UX-DR10, FR21)

**Given** the user taps the overflow row or the section's "Open Network Settings…" footer link
**When** the action fires
**Then** the popover dismisses and `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!)` opens the macOS Network Settings pane (FR22, UX-DR32)

**Given** a VoiceOver user reads an `EthernetRow`
**When** the label is composed
**Then** it follows UX-DR23 templates by state — active: `"{displayName}, active, {ip}, {speed}"`; obtaining: `"{displayName}, obtaining address"`; DHCP timeout: `"{displayName}, DHCP timeout, no address"`; no link: `"{displayName}, no link"` (FR57, NFR25)
**And** decorative state dots are marked `accessibilityHidden(true)` (NFR27)

**Given** state transitions (cable in / cable out / Wi-Fi-only ↔ Ethernet-active)
**When** the change fires
**Then** announcements are posted per UX-DR25 utterances (FR58, NFR26)

**Given** the app has run a representative Epic 3 session (10 cable in/out cycles, dock reconnect, sleep/wake)
**When** Instruments is sampled with panel closed for 60 s afterward
**Then** resident memory is ≤80 MB, 60 s avg CPU is ≤0.5%, and 1-hour Allocations/Leaks shows zero leaks attributable to LinkHub (FR48, FR49, NFR8 baseline regression check vs Epic 1/2 baselines)

---

## Epic 4: Lifecycle, Distribution & Updates

User installs LinkHub from a signed and notarized DMG (Gatekeeper clean), configures Launch at Login, receives auto-update notifications via Sparkle 2 with EdDSA verification, and accesses Quit / About / Check for Updates / Launch at Login from a status-item right-click menu.

### Story 4.1: LaunchAtLoginService — SMAppService + UserDefaults Persistence

As a user,
I want LinkHub to launch automatically at login, and I want to disable that without restarting the app,
So that LinkHub is just there when I log in and I can change my mind any time.

**Acceptance Criteria:**

**Given** `LaunchAtLoginService` is created
**When** the user enables Launch at Login
**Then** `SMAppService.mainApp.register()` is invoked and the persisted preference flips to `true` (FR43)
**And** `UserDefaults.standard.set(true, forKey: "launchAtLogin")` writes the only key this app uses

**Given** Launch at Login is enabled
**When** the user disables it
**Then** `SMAppService.mainApp.unregister()` is invoked while the app continues running normally (FR44)
**And** `UserDefaults.standard.set(false, forKey: "launchAtLogin")` updates the key

**Given** the user enables Launch at Login and reboots the Mac
**When** the system reaches the login session
**Then** LinkHub launches automatically (FR47)

**Given** `appState.launchAtLogin` is bound to UI
**When** the value changes
**Then** the bound `Toggle` reflects the persisted state on next launch — read from UserDefaults during `AppState` init

---

### Story 4.2: StatusItemMenu — Right-Click NSMenu

As a user,
I want a right-click menu on the LinkHub status item with Launch at Login, Check for Updates, About, and Quit,
So that I can manage app-level concerns without opening the panel.

**Acceptance Criteria:**

**Given** the user right-clicks the status item
**When** the click handler fires
**Then** `MenuBar/StatusItemMenu.swift` factory builds an `NSMenu` and presents it on the status-item button (UX-DR35)
**And** items are: `Launch at Login` (toggle bound to `appState.launchAtLogin`), `Check for Updates…`, `About LinkHub`, `Quit LinkHub`

**Given** the user selects `Launch at Login`
**When** the toggle fires
**Then** `LaunchAtLoginService.toggle()` runs and the menu item check-state reflects the new value on next open

**Given** the user selects `Quit LinkHub`
**When** the action fires
**Then** `NSApp.terminate(_:)` runs and `applicationWillTerminate` performs the load-bearing teardown order: `appState.stopMonitors()` → `statusItemController.tearDown()` (FR46, NFR9)

**Given** the user selects `About LinkHub`
**When** the action fires
**Then** `NSApp.orderFrontStandardAboutPanel(_:)` opens the standard About panel (no custom About window in v1 scope)

**Given** the user left-clicks the status item
**When** the click is dispatched
**Then** the right-click NSMenu is not shown; the popover toggles per Epic 1 behavior

---

### Story 4.3: Sparkle 2 SPM Dep + UpdaterController

As a user,
I want LinkHub to check for updates in the background and let me trigger a check on demand, then install updates with cryptographic verification,
So that I get fixes and improvements without manually downloading new builds.

**Acceptance Criteria:**

**Given** the project's package dependencies
**When** they are inspected
**Then** Sparkle 2 (`https://github.com/sparkle-project/Sparkle`) is added as the first and only SPM dependency (NFR36)

**Given** the app launches
**When** `AppDelegate.applicationDidFinishLaunching` runs
**Then** `App/UpdaterController.swift` instantiates `SPUStandardUpdaterController` after `statusItemController.start()` and before `appState.startMonitors()`
**And** the updater is wired with the appcast feed `https://talepstein.github.io/LinkHub/appcast.xml`

**Given** `Info.plist`
**When** keys are inspected
**Then** `SUPublicEDKey` contains the EdDSA public key matching the private key used to sign appcast items (NFR16)
**And** `SUFeedURL` (or equivalent appcast configuration) points at the GitHub Pages URL

**Given** the user selects `Check for Updates…` from the status-item menu
**When** the action fires
**Then** `SPUStandardUpdaterController.checkForUpdates(_:)` runs (FR54)

**Given** an update is available on the periodic background cadence
**When** Sparkle's check fires
**Then** the user is notified via the standard Sparkle dialog (FR53)
**And** the update artifact's EdDSA signature is verified before install; install proceeds only on signature match (FR55, NFR16)

**Given** an update install dialog is open
**When** the user installs
**Then** Sparkle relaunches LinkHub with the new version

---

### Story 4.4: Notarization + Signing Scripts

As a developer,
I want a reproducible script that code-signs, notarizes, and staples the LinkHub.app,
So that distribution artifacts are Gatekeeper-clean and the release process is one command.

**Acceptance Criteria:**

**Given** a Release archive
**When** export runs
**Then** `xcodebuild archive` produces an `.xcarchive` and `xcodebuild -exportArchive -exportOptionsPlist ExportOptions.plist` produces `LinkHub.app` (NFR13, NFR15)
**And** `ExportOptions.plist` is configured for Developer ID export (not Mac App Store)

**Given** the exported `LinkHub.app`
**When** `scripts/notarize.sh` runs
**Then** the script invokes `xcrun notarytool submit ... --keychain-profile linkhub-notary --wait` and returns success (NFR14)
**And** on success, `xcrun stapler staple LinkHub.app` runs and the staple is verified

**Given** the signed and notarized `LinkHub.app`
**When** `codesign --verify --deep --strict --verbose=2 LinkHub.app` runs
**Then** the signature is valid with a Developer ID Application certificate (NFR13)
**And** `codesign --display --entitlements -` shows Hardened Runtime enabled and Location entitlement only (NFR15, NFR17)

**Given** an end-user downloads and opens the app
**When** Gatekeeper evaluates it
**Then** no warning or block dialog appears (FR52)

---

### Story 4.5: DMG Packaging Script

As a user,
I want to download a DMG with a single drag-to-Applications affordance,
So that installing LinkHub feels like installing any other Mac app.

**Acceptance Criteria:**

**Given** a stapled `LinkHub.app`
**When** `scripts/make-dmg.sh` runs
**Then** the output is `LinkHub-{version}.dmg` containing `LinkHub.app` and an `/Applications` symlink (FR51)
**And** the DMG is plain (no custom background image)

**Given** the DMG
**When** `codesign --verify --deep --strict` runs against the contained app
**Then** the signature and stapled notarization ticket are intact

**Given** the user double-clicks the DMG
**When** the volume mounts
**Then** the user can drag `LinkHub.app` onto the `/Applications` symlink and run it without Gatekeeper warnings (FR52)

---

### Story 4.6: Appcast EdDSA Pipeline + GitHub Pages Publish

As a user,
I want updates served from a stable, public appcast feed signed with a key only the maintainer holds,
So that update authenticity is verifiable end-to-end.

**Acceptance Criteria:**

**Given** a new release DMG
**When** `scripts/update-appcast.sh` runs
**Then** the script computes the EdDSA signature using the private key stored in macOS Keychain (NFR16)
**And** appends a new `<item>` to `appcast/appcast.xml` with version, release notes link, enclosure URL, length, and `sparkle:edSignature`

**Given** `appcast/appcast.xml`
**When** committed and pushed
**Then** GitHub Pages publishes it at `https://talepstein.github.io/LinkHub/appcast.xml`

**Given** versioning
**When** the release is tagged
**Then** `CFBundleShortVersionString` is `MAJOR.MINOR.PATCH` (SemVer) and `CFBundleVersion` is a monotonic integer

**Given** the published feed
**When** Sparkle on a running LinkHub fetches it
**Then** EdDSA signature verification against `SUPublicEDKey` from `Info.plist` succeeds (NFR16)
**And** signature mismatch causes Sparkle to reject the update

---

### Story 4.7: Final Instruments Validation Pass

As the maintainer,
I want a final 1-hour Instruments session validating memory, CPU, and leaks against representative state-change traffic,
So that NFR48, NFR49, and NFR8 are confirmed before tagging a release.

**Acceptance Criteria:**

**Given** a Release-built LinkHub
**When** an Instruments Allocations + Leaks + Time Profiler session runs for 1 hour with induced state changes (Wi-Fi scan loop, Wi-Fi connect/disconnect, cable in/out cycles, sleep/wake)
**Then** zero leaks are attributable to LinkHub (NFR8)

**Given** the same session
**When** memory is sampled at the end with the panel closed for 60 s
**Then** resident memory is ≤80 MB (FR48)
**And** the 60 s average CPU on Apple Silicon is ≤0.5% (FR49)

**Given** the prior epic baselines
**When** Epic 4 measurements are compared
**Then** no regression beyond ±5% relative to Epic 1 / Epic 2 / Epic 3 baselines is observed
**And** any regression is flagged for resolution before release tag

**Given** post-release telemetry collection is intentionally absent (NFR19)
**When** crash-free session rate is measured for the first 30 days
**Then** Apple-collected crash reports show ≥99.5% crash-free sessions (NFR7)
**And** the verification method is documented in the release notes (Apple Crash Reports via Console / Xcode Organizer; no in-app collection)

