---
stepsCompleted: [step-01-init, step-02-context, step-03-starter, step-04-decisions, step-05-patterns, step-06-structure, step-07-validation, step-08-complete]
lastStep: 8
status: 'complete'
completedAt: '2026-05-04'
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/prd-validation-report.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
  - docs/01-project-architecture.md
  - docs/02-menubar-integration.md
  - docs/03-network-detection.md
  - docs/04-panel-ui-architecture.md
  - docs/05-ethernet-controls.md
  - docs/06-wifi-management.md
  - docs/07-state-data-management.md
  - docs/08-permissions-entitlements.md
  - docs/09-distribution-release.md
  - PLAN.md
  - EXECUTION_PLAN.md
  - README.md
workflowType: 'architecture'
project_name: 'LinkHub'
user_name: 'Tal'
date: '2026-05-04'
---

# Architecture Decision Document — LinkHub

_Built collaboratively through step-by-step discovery. Sections appended per step._

## Project Context Analysis

### Requirements Overview

**Functional Requirements:** 58 FRs across 9 clusters — Menu Bar Presence (8), Panel Layout (6), Ethernet Awareness (8), Wi-Fi Discovery (6), Wi-Fi Connection Management (10), Permissions/First-Run (4), Lifecycle (5), Resource Discipline (3), Distribution/Updates (5), Accessibility (3). Functionality split is heavily UX-side (panel + rows + modals); back-end logic is monitor wrappers only.

**Non-Functional Requirements:** 37 NFRs. Architecture-shaping: NFR1/NFR5 (push events + 300ms debounce, no polling); NFR2 (≤200ms cold popover — eager monitor warmup); NFR12 (Keychain-only password persistence); NFR17 (minimum entitlements; sandbox OFF; Hardened Runtime Release-only); NFR33 (zero Swift 6 strict-concurrency warnings); NFR35 (single MainActor AppState; UI never observes monitors directly); NFR48–50 (≤80MB RAM, ≤0.5% CPU, no scheduled polling).

**Scale & Complexity:**
- Primary domain: desktop_app (macOS-only native menu-bar utility)
- Complexity level: medium — no backend/multi-tenant/compliance; complexity is in ObjC↔Swift6 concurrency bridging, event debounce, retain-cycle hygiene, signing/notarization/Sparkle pipeline.
- Estimated architectural components: 7 layer buckets (App, MenuBar, Network, UI, State, Services, Utilities); ~20–30 source files at v1.

### Technical Constraints & Dependencies

- **Platform floor:** macOS 13.0 Ventura (forecloses `@Observable`; mandates `ObservableObject + @Published`).
- **Toolchain floor:** Xcode 16 / Swift 6 with `SWIFT_STRICT_CONCURRENCY = complete`.
- **Sandboxing:** App Sandbox permanently OFF (CWWiFiClient.associate is sandbox-blocked); MAS distribution thus excluded for v1.
- **Hardened Runtime:** Release-only; Debug ad-hoc signed.
- **Dependencies:** zero at project creation; Sparkle 2 (SPM) added at distribution wave only. No CocoaPods/Carthage. No closed-source binaries.
- **Frameworks (system-only):** AppKit, SwiftUI, Foundation, Combine, CoreWLAN, SystemConfiguration, Security, CoreLocation, ServiceManagement, os.log.
- **Init order:** StatusItemController must subscribe to AppState before AppState.startMonitors() — reversing loses first connectionMode event.
- **Privacy:** NSLocationWhenInUseUsageDescription required; PrivacyInfo.xcprivacy ships with Location + UserDefaults + boot-time API declarations.
- **Distribution:** Developer ID Application sign + notarytool + staple + DMG; EdDSA-signed Sparkle appcast at `talepstein.github.io/LinkHub/appcast.xml`.

### Cross-Cutting Concerns Identified

1. **ObjC↔Swift6 concurrency boundary.** CoreWLAN (`CWNetwork`, `CWInterface`) and SystemConfiguration (`SCNetworkInterface`) are non-Sendable. Mandatory pattern: extract to local `Sendable` value types (`WiFiNetwork`, `EthernetInterface`) before any actor hop. SCDynamicStore C-callbacks bridge via `Task { @MainActor in ... }`. Affects every monitor.
2. **Event debounce gate.** 300ms merged-stream debounce between monitors and AppState prevents icon flicker during dock-wake interface flapping. Single-source debounce, not per-monitor.
3. **Permission state propagation.** CLLocationManagerDelegate auth changes → AppState.wifiLocationDenied → LocationDeniedView empty-state. Auto-retry scan on grant; no app restart.
4. **Tear-down hygiene.** AppDelegate must `CWWiFiClient.shared().delegate = nil` and unregister SCDynamicStore source on terminate to avoid retain cycles flagged by Instruments.
5. **Build-config divergence.** Debug has no entitlements → CoreLocation/CoreWLAN scan unavailable → WiFiMonitor must support `#if DEBUG` mock data path. Release is signed, hardened, notarized.
6. **Apple HIG mimicry.** Stock-Wi-Fi-menu visual parity is the product. Forbids hardcoded colors, mandates semantic colors / system font / Reduce Motion respect / dark-light auto-adapt across every UI component.
7. **Distribution chain.** Sign → notarize → staple → DMG → EdDSA-sign appcast item → push to GitHub Pages → Sparkle picks up. Cuts across Info.plist, entitlements, build settings, repo workflows.
8. **Resource discipline.** No timers when popover closed; CWEventDelegate push-only between user-initiated scans. Affects every monitor's lifecycle.

## Starter Template Evaluation

### Primary Technology Domain

Desktop — macOS-native menu bar utility. No JS/web starter stack applies. Starter selection scope is Xcode project template + lifecycle pattern.

### Starter Options Considered

| Option | Verdict |
|---|---|
| Xcode "macOS App" template, SwiftUI `@main App` + `WindowGroup` lifecycle | Rejected (PRD 01). Window-centric. Menu-bar apps must own `NSStatusItem` lifecycle in `NSApplicationDelegate`. |
| Xcode "macOS App" template, AppKit `NSApplicationDelegate` lifecycle | **Selected** (PRD 01). Industry-standard menu-bar entry. SwiftUI views host inside `NSPopover`. |
| Community menu-bar starters (`MenuBarExtraAccess`, `swiftui-menu-bar-app`, etc.) | Rejected. Add dependency + hidden conventions. LinkHub commits to zero deps at creation; Sparkle 2 is the only SPM dep ever, deferred to PRD 09. |
| Tuist / XcodeGen | Rejected. Toolchain overhead with no benefit at solo-dev scale. `.xcodeproj` is committed to the repo. |
| `swift package init --type executable` | Rejected. No Xcode app target / Info.plist / entitlements / resource conventions required for menu-bar apps. |

### Selected Starter: Xcode 16 built-in macOS App template (AppKit App Delegate lifecycle)

**Rationale for Selection:** PRD 01 mandates `NSApplicationDelegate + NSStatusItem` entry. The default Xcode macOS App template provides the closest valid scaffold; the SwiftUI `@main App` boilerplate it produces is replaced with an `NSApplicationDelegate` subclass on first edit. Zero external starter dependency keeps the v1 dependency budget at one (Sparkle 2, added later).

**Initialization Command:**

```bash
# No CLI starter. Use Xcode GUI:
#   File → New → Project → macOS → App
#     Product Name:    LinkHub
#     Team:            (leave blank)
#     Org Identifier:  com.linkhub      (Bundle ID becomes com.linkhub.app)
#     Interface:       SwiftUI
#     Language:        Swift
#     Storage:         None
#     Include Tests:   ✓
#     Use Core Data:   ✗
```

Post-creation mutations (PRD 01):

1. Replace SwiftUI `@main App` with `@main NSApplicationDelegate` subclass at `App/AppDelegate.swift`.
2. Set `LSUIElement = true`, `NSLocationWhenInUseUsageDescription`, `CFBundleDisplayName=LinkHub`, `CFBundleVersion=1`, `CFBundleShortVersionString=1.0.0` in `Info.plist`.
3. Build settings: deployment target macOS 13.0; `SWIFT_VERSION = 6.0`; `SWIFT_STRICT_CONCURRENCY = complete`.
4. Reorganize into layer folders: `App/`, `MenuBar/`, `Network/`, `UI/`, `State/`, `Services/`, `Utilities/`. Bundle ID `com.linkhub.app`.
5. Add `PrivacyInfo.xcprivacy` (Location CA92.1).
6. Add `LinkHub.entitlements` applied to **Release config only**. Debug remains ad-hoc unsigned with no entitlements.
7. Configure Debug/Release build settings per PRD 01 § Build Configurations table.
8. Share scheme `LinkHub.xcscheme`; commit `xcshareddata/`.
9. `.gitignore` per PRD 01 (xcuserdata excluded; xcshareddata committed).

**Architectural Decisions Provided by Starter (post-mutations):**

| Aspect | Decision |
|---|---|
| **Language & Runtime** | Swift 6.0; `SWIFT_STRICT_CONCURRENCY = complete`; macOS 13 deployment target |
| **Lifecycle** | AppKit `NSApplicationDelegate`; SwiftUI views inside `NSPopover` (no `@main App`/`WindowGroup`) |
| **UI Framework** | SwiftUI (popover + sections) + AppKit (NSStatusItem, NSPopover, NSPanel for hidden network) |
| **State** | `@MainActor final class AppState: ObservableObject` + `@Published` (no `@Observable` — macOS 13 floor) |
| **Build Tooling** | Xcode 16, xcodebuild, Instruments; no third-party build tools |
| **Dependency Manager** | SPM-only; zero deps at creation; Sparkle 2 added at PRD 09 (distribution wave) |
| **Testing Framework** | XCTest unit-test target `LinkHubTests`; no XCUITest at creation |
| **Code Organization** | Layer-based: App/MenuBar/Network/UI/State/Services/Utilities |
| **Targets** | Single app target; no sub-frameworks; no local SPM packages |
| **Build Configs** | Debug + Release only |

**Note:** Project initialization per PRD 01 Acceptance Criteria is the first implementation story (Wave 1 of `EXECUTION_PLAN.md`).

## Core Architectural Decisions

PRDs 01–09 already locked decisions. This architecture doc consolidates and indexes them as the AI-agent implementation source of truth.

### Decision Priority Analysis

**Critical (block implementation):**
- AppState concurrency model (PRD 07 D1)
- Monitor framework selection: SCDynamicStore + CoreWLAN (PRD 03 D1, D5)
- ObjC↔Swift6 boundary pattern: extract to Sendable before actor hop (PRD 03 D10–12)
- Event debounce: 300ms Combine on PassthroughSubject (PRD 03 D7, D8)
- Init order: AppState → StatusItemController → startMonitors (PRD 02 D1, PRD 07 D8)
- Keychain-only password storage (PRD 06, NFR12)
- Code signing: Developer ID Application; sandbox OFF; Hardened Runtime Release-only (PRD 09 D1–3, NFR13–17)

**Important (shape architecture):**
- NSPopover hosting NSHostingController<RootPanelView> (PRD 02 D6)
- @EnvironmentObject injection for AppState (PRD 07 D3)
- CombineLatest single-sink networkState rebuild (PRD 07 D6)
- SF Symbols template images, no xcassets imagesets for menu bar (PRD 02 D10)
- Sparkle 2 EdDSA appcast on GitHub Pages (PRD 09 D7–9)
- DMG with /Applications symlink (PRD 09 D10)
- SemVer + monotonic CFBundleVersion (PRD 09 D11)

**Deferred (post-MVP):**
- @Observable migration (requires raising deployment to macOS 14)
- Mac App Store distribution (requires sandbox compatibility rework)
- Localization beyond English
- Telemetry (opt-in only, future)
- Sparkle delta updates

### Data & State Management

| Decision | Choice | Source |
|---|---|---|
| State container | `@MainActor final class AppState: ObservableObject` with `@Published` | PRD 07 D1 |
| State creation site | `AppDelegate.applicationDidFinishLaunching` | PRD 07 D2 |
| Lifetime | Process lifetime (single instance, owned by AppDelegate) | PRD 07 D2 |
| Monitor wiring | `Publishers.CombineLatest(ethernetMonitor.$interfaces, wifiPublisher).sink` — single sink rebuilds `networkState` and `connectionMode` atomically | PRD 07 D6 |
| `networkState` storage | Stored `@Published var networkState: NetworkState`, rebuilt once per debounced monitor event | PRD 07 D4 |
| `connectionMode` storage | Separate `@Published var connectionMode: ConnectionMode` (always equal to `networkState.mode`) — preserves PRD 02 contract | PRD 07 D5 |
| `primaryEthernet` derivation | Stored on `NetworkState`; `interfaces.first(where: { $0.isActive })` after stable BSD-name sort | PRD 07 D9 |
| AnyCancellable storage | `Set<AnyCancellable>` on `AppState`; cancelled in `stopMonitors()` | PRD 07 D7 |
| Monitor start timing | `appState.startMonitors()` called from AppDelegate **after** `StatusItemController` constructed | PRD 07 D8, PRD 02 D1 |
| Persistence | UserDefaults: `launchAtLogin: Bool` only. All network state transient | PRD 07 D10 |
| Memory budget | ≤ 30 MB steady-state (NFR48 spec is ≤80 MB; PRD 07 stricter) | PRD 07 D12, NFR48 |
| Background CPU | Near-zero with panel closed; no Timer / DispatchSourceTimer / Task.sleep loops | PRD 07 D13, NFR49 |

**Sendable model boundary (`Network/Models/`):**
- `EthernetInterface` — `Identifiable, Equatable, Sendable` value type. Fields: `id` (BSD), `displayName`, `isActive`, `hasLink`, `ipv4Address`, `macAddress`, `linkSpeed`.
- `WiFiNetwork` — `Identifiable, Equatable, Sendable` value type. Fields: `id`, `ssid`, `bssid`, `rssi`, `isConnected`, `requiresPassword`, `security`, `isCaptive`.
- `WiFiSecurity` enum — `Equatable, Sendable`. Cases: `none`, `wpa2Personal`, `wpa3Personal`, `enterprise`, `other`.
- `ConnectionMode` enum — `Equatable, Sendable`. Cases: `ethernetActive`, `wifiOnly`, `disconnected`.
- `NetworkState` — `Equatable, Sendable`. Fields: `mode`, `ethernetInterfaces` (sorted), `primaryEthernet`, `wifiNetworks`, `connectedWifi`, `isWiFiEnabled`.

### System Framework Integration & Concurrency Boundary

| Decision | Choice | Source |
|---|---|---|
| Ethernet detection | `SCDynamicStore` (`SystemConfiguration`) | PRD 03 D1 |
| Ethernet notification model | `SCDynamicStoreSetDispatchQueue` on private serial queue | PRD 03 D2 |
| Ethernet enumeration | `SCNetworkInterfaceCopyAll()` at start + re-enumerate inside every callback (handles hotplug) | PRD 03 D3 |
| Ethernet keys watched | `State:/Network/Interface/[^/]+/Link` AND `State:/Network/Interface/[^/]+/IPv4` (regex patterns) | PRD 03 D4 |
| Wi-Fi framework | `CoreWLAN` (`CWWiFiClient` + `CWEventDelegate`) exclusively | PRD 03 D5 |
| Wi-Fi events | `CWEventDelegate` push for connection events; on-demand scan for network list (no polling) | PRD 03 D6 |
| Debounce interval | 300 ms | PRD 03 D7, NFR5 |
| Debounce mechanism | `Combine .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)` on `PassthroughSubject<Void, Never>` inside each monitor | PRD 03 D8 |
| Monitor isolation | `@MainActor final class` for both `EthernetMonitor` and `WiFiMonitor` | PRD 03 D9 |
| SCDynamicStore → MainActor bridge | Extract all CF/SC values on private queue → produce `[EthernetInterface]` Sendable snapshot → `Task { @MainActor in ... }`; never cross with `SCNetworkInterface` | PRD 03 D10 |
| CWEventDelegate → MainActor bridge | Capture only `String` interface name in delegate callback → `Task { @MainActor in ... }` re-reads `CWInterface`; never capture `CWInterface`/`CWNetwork` | PRD 03 D11 |
| `CWNetwork` Sendable handling | Extract all fields to `WiFiNetwork` value type on the CoreWLAN callback/scan thread before any actor hop. No `@unchecked Sendable` wrappers | PRD 03 D12 |
| Public API surface from monitors | `@Published` on `@MainActor` monitor, consumed by `AppState` via `.sink` (no `AsyncStream`) | PRD 03 D13 |
| RSSI source | Use delegate-supplied `rssi` parameter for `linkQualityDidChange`; full re-read only for ssid/link/power events | PRD 03 D14 |
| Tear-down | `CWWiFiClient.shared().delegate = nil` + `SCDynamicStoreSetDispatchQueue(store, nil)` in `stopMonitors()`, called from `applicationWillTerminate` | PRD 02 D5, PRD 03 |

### UI Architecture

| Decision | Choice | Source |
|---|---|---|
| Panel presentation | `NSPopover` hosting `NSHostingController<RootPanelView>` | PRD 02 D6 |
| Popover dismissal — outside click / app switch | `NSPopover.behavior = .transient` (AppKit auto-closes) | PRD 02 D7 |
| Popover dismissal — Escape | Local `NSEvent` monitor (`.keyDown`, keyCode 53) installed in `show()`, removed in `close()`; calls `popover.performClose(_:)` | PRD 02 D8 |
| Popover dismissal — second status icon click | Status item button action toggles based on `popover.isShown` | PRD 02 D9 |
| Status item length | `NSStatusItem.squareLength` (22 pt fixed) | PRD 02 D2 |
| Status item retention | `let statusItem` on `StatusItemController`; controller stored on `AppDelegate` | PRD 02 D3 |
| Icon technology | SF Symbols template images via `NSImage(systemSymbolName:accessibilityDescription:)`. No xcassets imagesets for menu bar | PRD 02 D10 |
| Icon mapping | `cable.connector` (Ethernet active) / `wifi` (Wi-Fi only or Ethernet link-only with Wi-Fi connected) / `wifi.slash` (disconnected) | PRD 02 D11, Icon State Table |
| Icon symbol config | `pointSize: 17, weight: .regular, scale: .medium` | PRD 02 D12 |
| Icon-swap owner | `StatusItemController` exclusively; subscribes to `AppState.$networkState` | PRD 02 D13, D14 |
| Panel-open Wi-Fi scan hook | `PopoverController.show()` → fire-and-forget `Task { try? await appState.wifiMonitor.requestScan() }` immediately after `popover.show(...)` | PRD 02 D16 |
| AppState injection | `@EnvironmentObject` via `.environmentObject(appState)` on `RootPanelView` at NSHostingController creation | PRD 07 D3 |
| Root SwiftUI type | `RootPanelView` (canonical name; "ContentView" references in older PRDs are errors) | PRD 01 folder layout |
| VoiceOver announcement | Accessibility label/tooltip update on every `$networkState` change; active `NSAccessibility.post` only on transition to `.disconnected` | PRD 02 D15 |
| Color discipline | System semantic colors only; no hardcoded values; respect Light/Dark/Accent | NFR31, NFR32 |
| Reduce Motion | Disable pulsing/transitions when system Reduce Motion is on | NFR28 |

### Permissions & Security

| Decision | Choice | Source |
|---|---|---|
| Entitlement set | `com.apple.security.personal-information.location` only. App Sandbox **disabled**; Hardened Runtime **Release-only** | PRD 08, PRD 09, NFR17 |
| Location auth | `CLLocationManager.requestWhenInUseAuthorization()`; auth state propagates to `AppState.wifiLocationDenied` | PRD 08, PRD 07 D11 |
| Permission denied UX | `LocationDeniedView` empty state with "Open Privacy Settings" deep link via `x-apple.systempreferences:` URL | PRD 06, PRD 08, FR40 |
| Auth recovery | `CLLocationManagerDelegate` auto-retries `WiFiMonitor.requestScan()` on flip to `.authorized`; no app restart | PRD 08, FR41 |
| Wi-Fi password storage | macOS Keychain via Security framework; `kSecClassGenericPassword`; `kSecAttrAccessibleAfterFirstUnlock`; account = SSID | PRD 06, PRD 08, NFR12 |
| Privacy manifest | `PrivacyInfo.xcprivacy` declares Location (CA92.1); UserDefaults; file timestamp; system boot time | PRD 08, NFR18 |
| Telemetry / analytics | None. No outbound HTTP except Sparkle appcast and user-initiated captive portal browser handoff | NFR19–22 |
| Captive portal | Open `http://captive.apple.com` via `NSWorkspace.open(_:)` (default browser); no in-app web view | PRD 06, NFR22 |

### Distribution & Updates

| Decision | Choice | Source |
|---|---|---|
| Channel | Developer ID direct download | PRD 09 D1 |
| Certificate | `Developer ID Application: <Team Name> (<TEAMID>)` | PRD 09 D2 |
| Provisioning profile | None (Developer ID does not use profiles) | PRD 09 D3 |
| Notarization tool | `xcrun notarytool submit` (App Store Connect API key auth via `notarytool store-credentials`) | PRD 09 D4, D5 |
| Stapling | Always staple (`xcrun stapler staple LinkHub.app`) — offline Gatekeeper validation required for network-management tool | PRD 09 D6 |
| Auto-update | Sparkle 2 via SPM (`https://github.com/sparkle-project/Sparkle`); added at PRD 09 wave only | PRD 09 D7 |
| Sparkle signing | EdDSA (Ed25519); private key in macOS Keychain; public key in `Info.plist` `SUPublicEDKey` | PRD 09 D8, NFR16 |
| Appcast hosting | GitHub Pages: `https://talepstein.github.io/LinkHub/appcast.xml` | PRD 09 D9 |
| Release artifact | `.app` inside `.dmg` with `/Applications` symlink. Plain DMG, no custom background | PRD 09 D10, D12 |
| Versioning | SemVer `CFBundleShortVersionString = MAJOR.MINOR.PATCH`; `CFBundleVersion` monotonic integer | PRD 09 D11 |
| Launch at Login | `SMAppService.mainApp.register()` / `.unregister()`; persisted in UserDefaults | PRD 08, FR43–44, FR47 |
| Mac App Store | Out of scope for v1 (sandbox blocks `CWWiFiClient.associate`) | PRD 09 D1 |

### Observability

| Decision | Choice | Source |
|---|---|---|
| Logging framework | `os.Logger` only | NFR37 |
| Subsystem | `Bundle.main.bundleIdentifier` (= `com.linkhub.app`) | NFR37 |
| Filter command | `log show --predicate 'subsystem == "com.linkhub.app"'` | NFR37 |
| Categories (per layer) | `menuBar`, `network.wifi`, `network.ethernet`, `state`, `services.keychain`, `services.settings`, `app` | PRD 01 layer split |
| Crash reporting | None (no third-party crash reporter; rely on Apple-collected reports + .dSYM symbolication) | NFR19 |
| Telemetry | None | NFR19 |

### Decision Impact Analysis

**Implementation sequence (load-bearing):**

1. PRD 01 — Project init: Xcode project, Swift 6 strict concurrency, layer folders, Info.plist keys, PrivacyInfo, build configs, scheme.
2. PRD 02 — Menu bar shell: AppDelegate → StatusItemController → empty popover. Validates lifecycle, retention, teardown.
3. PRD 03 — Monitors: WiFiMonitor + EthernetMonitor with Sendable models, debounce, MainActor bridge. Standalone-testable with Debug mock data.
4. PRD 07 — AppState: CombineLatest sink, state rebuild, monitor wiring. Subscribes only after StatusItemController (init-order rule).
5. PRDs 04 + 05 + 06 — UI sections (RootPanelView, EthernetSection, WiFiSection, OtherNetworkPanel, LocationDeniedView). Read AppState via `@EnvironmentObject`.
6. PRD 08 — Permissions/entitlements: Location auth, Keychain, SMAppService, x-apple.systempreferences deep links.
7. PRD 09 — Distribution: Sparkle 2 dep added, Developer ID signing, notarytool, stapler, DMG, EdDSA appcast, GitHub Pages.

**Cross-component dependencies:**

- **AppState ↔ StatusItemController:** subscribe-before-start invariant. Reverse → first connectionMode event lost → wrong icon at launch.
- **Monitors → AppState:** single-sink atomic rebuild. Two sinks → inconsistent NetworkState window.
- **WiFiMonitor → CLLocationManagerDelegate:** auth flip triggers retry. Decoupling → user must restart app.
- **AppState.wifiLocationDenied → WiFiSection:** EnvironmentObject path. Direct WiFiMonitor coupling forbidden by NFR35.
- **AppDelegate.applicationWillTerminate → AppState.stopMonitors → CWWiFiClient.delegate=nil:** retain-cycle elimination. Skipping → Instruments leaks fail acceptance.
- **PRD 09 SPM Sparkle add ↔ PRD 01 zero-dep at creation:** Sparkle is added only at distribution wave; not at project init.
- **Hardened Runtime Release-only ↔ Debug ad-hoc unsigned:** Debug builds cannot scan Wi-Fi (no Location entitlement) → `#if DEBUG` mock data path mandatory in WiFiMonitor.

## Implementation Patterns & Consistency Rules

PRDs already lock most. Below covers AI-agent drift hazards explicitly.

### Critical Conflict Points Identified

10 categories where agents could diverge: Swift naming, file layout, MainActor bridging, Combine vs async, error propagation, log subsystem/categories, view ↔ state coupling, password handling, deep-link URLs, build-config branching.

### Naming Patterns

**Swift identifiers (Apple-standard):**
- Types: `UpperCamelCase` — `WiFiMonitor`, `EthernetInterface`, `RootPanelView`
- Functions / methods / properties / vars: `lowerCamelCase` — `requestScan()`, `connectedNetwork`, `networkState`
- Enum cases: `lowerCamelCase` — `.ethernetActive`, `.wpa2Personal`
- Constants: `lowerCamelCase` (no `kSomething` prefix)
- Acronyms: `WiFi` (not `WIFI` or `Wifi`); `IPv4`; `BSSID`; `RSSI`; `SSID`; `MAC`. First-word lowercased: `ipv4Address`, `ssid`, `bssid`, `rssi`, `macAddress`.
- Booleans: `is`/`has`/`can` prefix — `isActive`, `hasLink`, `isWiFiEnabled`, `isCaptive`, `requiresPassword`.

**File naming:**
- One primary type per file. File name = type name + `.swift`. `WiFiMonitor.swift` contains `WiFiMonitor`. Exception: small co-located helper types/extensions for the same concept.
- Models in `Network/Models/` — one file per Sendable value type.
- View files end in `View` (`RootPanelView.swift`) or `Section` (`EthernetSection.swift`) or `Panel` (`OtherNetworkPanel.swift`).
- Service files end in `Service` (`KeychainService.swift`, `SystemSettingsService.swift`).
- Controllers end in `Controller` (`StatusItemController.swift`, `PopoverController.swift`).
- Monitors end in `Monitor` (`WiFiMonitor.swift`, `EthernetMonitor.swift`).

**Bundle / target:**
- Bundle identifier: `com.linkhub.app` (locked).
- Product name: `LinkHub`.
- Test target: `LinkHubTests`.

**Logger categories (`os.Logger`):**
- Subsystem: `Bundle.main.bundleIdentifier!` (resolves to `com.linkhub.app`).
- Categories (lowerCamelCase, dot-separated by layer): `app`, `menuBar`, `network.wifi`, `network.ethernet`, `state`, `services.keychain`, `services.settings`. No ad-hoc categories.

**UserDefaults keys:** `lowerCamelCase`. Allowed keys (whitelist): `launchAtLogin`. Adding any new key requires PRD amendment.

**Keychain account:** SSID string verbatim (no prefix). Service: `Bundle.main.bundleIdentifier`.

### Structure Patterns

**Folder layout (canonical, do not deviate):**

```
LinkHub/
├── App/                    AppDelegate
├── MenuBar/                StatusItemController, PopoverController
├── Network/
│   ├── WiFiMonitor.swift
│   ├── EthernetMonitor.swift
│   └── Models/             EthernetInterface, WiFiNetwork, WiFiSecurity, NetworkState, ConnectionMode
├── UI/
│   ├── PopoverRootView.swift   (type: RootPanelView)
│   ├── Theme.swift             (PanelLayout constants)
│   ├── Panels/                 EthernetSection, WiFiSection
│   ├── Windows/                OtherNetworkPanel
│   └── Components/             SignalBar, ToggleRow, etc.
├── State/                  AppState
├── Services/               KeychainService, SystemSettingsService
└── Utilities/              Logger
```

**Hard rules:**
- Layer-based, not feature-based. Wi-Fi code is split across `Network/`, `UI/`, `Services/` — never co-located in a `WiFi/` folder.
- New code goes in the layer it belongs to. Adding a new top-level folder requires PRD amendment.
- One Sendable type per file in `Network/Models/`.
- Tests in `LinkHubTests/`, mirror source structure (e.g. `LinkHubTests/Network/WiFiMonitorTests.swift`). No co-located `*.test.swift`.
- No nested SPM packages or sub-frameworks.

### Format Patterns

**Logging format (`os.Logger`):**
- Use string interpolation with privacy levels: `logger.info("Wi-Fi associated to \(ssid, privacy: .private)")`. SSIDs/BSSIDs/RSSIs all `.private`. Interface BSD names (en0, en3) `.public`. Errors `.public`.
- Levels: `.debug` (verbose, opt-in via `log show --level debug`); `.info` (state transitions); `.error` (recoverable failures); `.fault` (programmer errors / invariant breaks).
- No `print(...)` anywhere in shipped code.

**Error types:**
- Each layer defines a typed `enum SomethingError: Error` (e.g. `WiFiMonitorError`, `KeychainServiceError`). No throwing `NSError` directly. No untyped `Error` rethrow at API boundaries — convert to layer error.
- No `try!` outside `#if DEBUG` blocks. `try?` allowed only when nil-handling is explicit at call site.

**Date / time:** No serialization. App holds no dates. If a future feature needs them, ISO-8601 via `ISO8601DateFormatter`.

**Booleans:** Always Swift `Bool`. Never `Int 0/1`. Never `NSNumber`.

### Communication Patterns

**Combine pipeline shape (mandatory):**
- Monitors expose `@Published` properties only. Callers consume via `.sink`.
- Internal debounce in monitors uses `PassthroughSubject<Void, Never>` + `.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)`. No per-property debounce.
- `AppState` uses **one** `Publishers.CombineLatest(...).sink` to rebuild `networkState` and `connectionMode` atomically. Never two parallel sinks updating either property.
- All `AnyCancellable` tokens stored in `Set<AnyCancellable>` named `cancellables` on the subscriber. `cancellables.removeAll()` in `tearDown()` / `stopMonitors()`.

**MainActor bridge pattern (mandatory at every ObjC↔Swift boundary):**

```swift
// SCDynamicStore callback running on private serial queue:
let snapshot: [EthernetInterface] = extractAllFieldsHere()  // Sendable, no SC types
Task { @MainActor [weak self] in
    self?.interfaces = snapshot
}
```

```swift
// CWEventDelegate callback running on CoreWLAN private thread:
nonisolated func ssidDidChangeForWiFiInterface(withName name: String) {
    Task { @MainActor [weak self] in
        self?.refreshConnectedNetwork(interfaceName: name)  // re-reads CWInterface here
    }
}
```

**Forbidden bridging patterns:**
- `DispatchQueue.main.async { ... }` for actor crossing — bypasses Swift 6 isolation checking.
- `@unchecked Sendable` wrappers on `CWNetwork` / `CWInterface` / `SCNetworkInterface`.
- Capturing `CWNetwork` / `CWInterface` / `SCNetworkInterface` / `CFType` in `Task { @MainActor }` closures.
- `AsyncStream` from monitors — Combine `@Published` is the established public API.
- Direct UI observation of `WiFiMonitor` / `EthernetMonitor` properties. UI observes `AppState` only (NFR35).

**State update rule:** Mutations to `AppState.@Published` properties only inside `AppState` itself or in same-actor closures it owns. External writers go through method calls (`appState.setLaunchAtLogin(true)`, etc.), not direct property assignment, except for the `wifiLocationDenied` flag which `WiFiMonitor` owns the right to set.

### Process Patterns

**Init order (load-bearing — see `applicationDidFinishLaunching`):**

```swift
1. let appState = AppState()
2. let statusItemController = StatusItemController(appState: appState)
3. statusItemController.start()              // installs subscriptions
4. appState.startMonitors()                  // first events arrive after subscriptions wired
```

Reverse 3↔4 → first connectionMode event lost → wrong icon at launch. Lint check: `appState.startMonitors()` must appear after `statusItemController.start()` in `applicationDidFinishLaunching`.

**Tear-down order (in `applicationWillTerminate`):**

```swift
1. appState.stopMonitors()                   // cancellables.removeAll(), monitor.stop()
2. statusItemController.tearDown()           // remove statusItem, cancel subscriptions
```

Inside `WiFiMonitor.stop()`: `CWWiFiClient.shared().delegate = nil`. Inside `EthernetMonitor.stop()`: `SCDynamicStoreSetDispatchQueue(store, nil)`. Skipping → Instruments leaks.

**Error handling:**
- Monitor errors → log at `.error`, do not crash, do not surface to UI unless they are user-actionable (e.g. `wifiLocationDenied`).
- User-actionable errors surface via `AppState` flags consumed by UI sections (e.g. `wifiLocationDenied`, future: `lastConnectionFailure`).
- No global `NSAlert` or modal error dialogs. Errors live inline in the panel UI.
- Wi-Fi connection failures: cause-typed feedback (FR37 — wrong password / out of range / association timeout / authentication error). Map `CWErrorDomain` codes to LinkHub `WiFiConnectionFailure` enum.

**Loading states:**
- Wi-Fi scan in flight → `WiFiSection` shows scan indicator, list remains. Never replace list with spinner — keep continuity.
- DHCP-pending Ethernet → row shows "Obtaining…" pulsing dot (or steady dot if Reduce Motion). Never blank row.
- Popover never shows global loading view. State containers populate eagerly on `AppDelegate` start; view bodies render whatever is current.

**Build-config branching:**
- `#if DEBUG` only for: mock Wi-Fi data injection (PRD 03), verbose logging gates. Never for behavior changes that affect user-visible features. No `#if RELEASE`.
- Mock data path in `WiFiMonitor` lives behind `#if DEBUG` and is opt-in via env var or compile-time flag — must not auto-engage in regular Debug builds without intent.

**System deep-links (canonical URLs):**
- Wi-Fi settings: `x-apple.systempreferences:com.apple.wifi-settings-extension`
- Network settings (Ethernet pane): `x-apple.systempreferences:com.apple.Network-Settings.extension`
- Privacy/Location: `x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices`
- Captive portal probe: `http://captive.apple.com`

All routed via `SystemSettingsService` + `NSWorkspace.shared.open(_:)`. No view code constructs these URLs directly.

### Enforcement Guidelines

**All AI agents MUST:**

1. Place new code in its existing layer folder; do not introduce a feature folder.
2. Cross every ObjC framework callback boundary by extracting Sendable values first, then `Task { @MainActor in ... }`.
3. Subscribe to `AppState`, never to monitors, in any UI code.
4. Use `os.Logger` with the canonical subsystem and the layer's category. Never `print`.
5. Mark CoreWLAN/SCDynamicStore types as confined to their monitor — they never appear in `Network/Models/`, `State/`, `UI/`, or `Services/`.
6. Apply `cancellables.removeAll()` in any class that stores Combine subscriptions, called from a deterministic teardown method.
7. Use SF Symbols for menu bar icons; never add menu bar icon imagesets to `Assets.xcassets`.
8. Use `kSecAttrAccessibleAfterFirstUnlock` for any Keychain item; never `kSecAttrAccessibleWhenUnlocked` or `Always`.
9. Apply Hardened Runtime + entitlements file to **Release config only**; Debug stays ad-hoc unsigned with no entitlements.
10. Use semantic colors (`Color.accentColor`, `Color.primary`, `.secondary`, `.tertiary`) only. No hex / RGB literals.

**Pattern enforcement:**
- Compiler-enforced where possible: `SWIFT_STRICT_CONCURRENCY = complete` flags most ObjC bridging mistakes at build time; zero warnings is a NFR33 acceptance criterion.
- Build-time check: `MAIN_THREAD_CHECKER_ENABLED = YES` in Debug catches main-thread violations during dev runs.
- Manual review checklist (architecture conformance) lives in this section — agents reference it at PR/commit time.
- Pattern violations → fix in code OR amend this PRD; never silently work around. PRD amendment is the accepted escape hatch.

### Pattern Examples

**Good — Sendable extraction before MainActor hop:**

```swift
// Inside SCDynamicStore callback on private serial queue
let snapshot: [EthernetInterface] = enumerated.compactMap { rawInterface in
    let bsdName = SCNetworkInterfaceGetBSDName(rawInterface) as String? ?? ""
    let displayName = SCNetworkInterfaceGetLocalizedDisplayName(rawInterface) as String? ?? bsdName
    let speed = mediaOptionsLinkSpeed(for: rawInterface)
    return EthernetInterface(id: bsdName, displayName: displayName, ...)
}
Task { @MainActor [weak self] in
    self?.interfaces = snapshot
}
```

**Anti-pattern — capturing SCNetworkInterface across actor boundary:**

```swift
// FORBIDDEN — SCNetworkInterface is not Sendable
Task { @MainActor [weak self] in
    let name = SCNetworkInterfaceGetBSDName(rawInterface)  // race
}
```

**Good — UI consumes AppState only:**

```swift
struct WiFiSection: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        if appState.wifiLocationDenied { LocationDeniedView() }
        else { List(appState.networkState.wifiNetworks) { ... } }
    }
}
```

**Anti-pattern — UI observing monitor directly:**

```swift
// FORBIDDEN — violates NFR35
struct WiFiSection: View {
    @ObservedObject var wifiMonitor: WiFiMonitor   // wrong layer
}
```

**Good — typed layer error:**

```swift
enum WiFiConnectionFailure: Error, Equatable {
    case wrongPassword
    case outOfRange
    case associationTimeout
    case authenticationError
    case unknown(code: Int)
}
```

**Anti-pattern — bare NSError rethrow:**

```swift
// FORBIDDEN — leaks ObjC error domain to UI
func connect(...) throws { try cwInterface.associate(...) }
```

## Project Structure & Boundaries

### Complete Project Directory Structure

```
LinkHub/                                      ← repo root
├── .gitignore                                ← per PRD 01 § .gitignore Conventions
├── README.md                                 ← exists
├── PLAN.md                                   ← exists (high-level master plan)
├── EXECUTION_PLAN.md                         ← exists (5-wave AI-agent plan)
├── ExportOptions.plist                       ← Developer ID export config (PRD 09)
├── docs/                                     ← exists (PRDs 01–09)
│   ├── 01-project-architecture.md
│   ├── 02-menubar-integration.md
│   ├── 03-network-detection.md
│   ├── 04-panel-ui-architecture.md
│   ├── 05-ethernet-controls.md
│   ├── 06-wifi-management.md
│   ├── 07-state-data-management.md
│   ├── 08-permissions-entitlements.md
│   └── 09-distribution-release.md
├── _bmad-output/
│   └── planning-artifacts/
│       ├── prd.md
│       ├── prd-validation-report.md
│       ├── ux-design-specification.md
│       └── architecture.md                   ← THIS document
├── scripts/                                  ← release helpers (added in PRD 09 wave)
│   ├── notarize.sh                           ← notarytool submit + wait + staple
│   ├── make-dmg.sh                           ← create-dmg or hdiutil wrapper
│   └── update-appcast.sh                     ← regenerates appcast.xml entry, signs with EdDSA
├── appcast/                                  ← published to GitHub Pages (PRD 09)
│   └── appcast.xml                           ← Sparkle 2 EdDSA-signed
├── LinkHub.xcodeproj/
│   ├── project.pbxproj                       ← committed
│   ├── project.xcworkspace/
│   │   └── contents.xcworkspacedata          ← committed
│   └── xcshareddata/                         ← committed (NOT ignored)
│       └── xcschemes/
│           └── LinkHub.xcscheme              ← shared scheme
├── LinkHub/                                  ← app target source
│   ├── Info.plist
│   ├── LinkHub.entitlements                  ← Release config only
│   ├── PrivacyInfo.xcprivacy
│   ├── Assets.xcassets/
│   │   └── AppIcon.appiconset/               ← app icon only; no menu-bar icons
│   │
│   ├── App/
│   │   └── AppDelegate.swift                 ← @main NSApplicationDelegate
│   │
│   ├── MenuBar/
│   │   ├── StatusItemController.swift        ← NSStatusItem owner; subscribes to AppState.$networkState
│   │   └── PopoverController.swift           ← NSPopover open/close; Escape monitor; scan trigger on show
│   │
│   ├── Network/
│   │   ├── WiFiMonitor.swift                 ← @MainActor; CWWiFiClient + CWEventDelegate; #if DEBUG mock
│   │   ├── EthernetMonitor.swift             ← @MainActor; SCDynamicStore on private serial queue
│   │   └── Models/
│   │       ├── NetworkState.swift            ← Sendable; mode, interfaces, primaryEthernet, networks, etc.
│   │       ├── ConnectionMode.swift          ← Sendable enum
│   │       ├── EthernetInterface.swift       ← Sendable value type
│   │       ├── WiFiNetwork.swift             ← Sendable value type
│   │       ├── WiFiSecurity.swift            ← Sendable enum
│   │       └── WiFiConnectionFailure.swift   ← typed error mapped from CWErrorDomain
│   │
│   ├── State/
│   │   └── AppState.swift                    ← @MainActor ObservableObject; CombineLatest sink
│   │
│   ├── UI/
│   │   ├── PopoverRootView.swift             ← contains type RootPanelView
│   │   ├── Theme.swift                       ← PanelLayout constants enum
│   │   ├── Panels/
│   │   │   ├── EthernetSection.swift         ← shown when any interface hasLink
│   │   │   ├── WiFiSection.swift             ← Wi-Fi list, toggle, scan
│   │   │   └── LocationDeniedView.swift      ← empty state when wifiLocationDenied
│   │   ├── Windows/
│   │   │   └── OtherNetworkPanel.swift       ← NSPanel subclass for hidden network join
│   │   └── Components/
│   │       ├── SignalBar.swift
│   │       ├── EthernetRow.swift             ← 4 states: active / obtaining / DHCP-timeout / no-link
│   │       ├── WiFiRow.swift                 ← bars, SSID, lock, captive marker, enterprise marker
│   │       ├── PasswordField.swift           ← inline password entry
│   │       ├── ToggleRow.swift               ← Wi-Fi power toggle
│   │       └── StatusDot.swift               ← pulsing/steady, respects Reduce Motion
│   │
│   ├── Services/
│   │   ├── KeychainService.swift             ← kSecClassGenericPassword + AfterFirstUnlock; account=SSID
│   │   ├── SystemSettingsService.swift       ← x-apple.systempreferences: deep links via NSWorkspace
│   │   ├── LaunchAtLoginService.swift        ← SMAppService.mainApp register/unregister
│   │   └── LocationService.swift             ← CLLocationManager + delegate; auth state → AppState
│   │
│   └── Utilities/
│       └── Logger.swift                      ← os.Logger factory; subsystem = bundleIdentifier
│
└── LinkHubTests/                             ← XCTest target; mirrors source
    ├── Network/
    │   ├── WiFiMonitorTests.swift
    │   ├── EthernetMonitorTests.swift
    │   └── Models/
    │       ├── NetworkStateTests.swift
    │       └── WiFiSecurityTests.swift
    ├── State/
    │   └── AppStateTests.swift               ← CombineLatest rebuild, primaryEthernet derivation
    ├── Services/
    │   ├── KeychainServiceTests.swift
    │   └── SystemSettingsServiceTests.swift
    ├── UI/
    │   └── (snapshot tests if added later)
    └── Fixtures/
        ├── MockWiFiData.swift                ← shared with #if DEBUG mock path
        └── MockEthernetData.swift
```

**Sparkle 2 SPM dep** added at PRD 09 wave only — appears in `LinkHub.xcodeproj/project.pbxproj` SPM section with URL `https://github.com/sparkle-project/Sparkle`. No `Package.swift` at repo root (not an SPM-resolved package itself).

### Architectural Boundaries

**Layer ownership graph:**

```
App/  AppDelegate
 │
 ▼ owns
MenuBar/  StatusItemController, PopoverController
 │                ▲
 ▼ reads          │ subscribes via .sink
State/  AppState ─┘
 │                ▲
 ▼ owns           │ subscribes via .sink (CombineLatest)
Network/  WiFiMonitor, EthernetMonitor
 │
 ▼ produces
Network/Models/  Sendable value types ─────────► UI/

Services/  KeychainService, SystemSettingsService,
           LaunchAtLoginService, LocationService
 ▲
 │ called from
State/, Network/, UI/  (via injection or static)

Utilities/  Logger  (used everywhere)
```

**Forbidden cross-boundary moves:**
- UI imports `CoreWLAN` or `SystemConfiguration` — forbidden. Only `Network/` may.
- UI subscribes to `WiFiMonitor` / `EthernetMonitor` — forbidden (NFR35). UI subscribes to `AppState` only.
- `Network/Models/` imports `AppKit`, `SwiftUI`, or `Combine` — forbidden. Pure Foundation + Sendable.
- `State/` imports `AppKit` or `SwiftUI` — forbidden. State is UI-framework-agnostic.
- `Services/` imports `AppKit` for UI — forbidden, except `SystemSettingsService` which uses `NSWorkspace` (system-shell utility, not UI).
- Any layer except `App/` accesses `NSApplication` or `NSStatusBar` directly — forbidden. AppDelegate routes lifecycle.

**Component communication:**

| Direction | Mechanism | Notes |
|---|---|---|
| Monitor → AppState | Combine `@Published` + `Publishers.CombineLatest.sink` | Single sink, atomic rebuild |
| AppState → StatusItemController | `appState.$networkState.sink` | Drives icon, label, tooltip |
| AppState → SwiftUI views | `@EnvironmentObject` injected at `NSHostingController(rootView:)` | One injection point in PopoverController |
| UI action → AppState | Method calls (e.g. `appState.connect(to: network, password:)`); never direct property mutation | Mutation surface gated |
| AppState → System (Keychain, Location, Settings) | Inject `Service` instances at AppState init | Mockable in tests |
| AppDelegate → AppState | Direct property; `startMonitors()`, `stopMonitors()` lifecycle calls | Two lifecycle hooks only |

### Data Flow (canonical)

```
[ Cable insert ]              [ User clicks SSID ]            [ App launch ]
       │                              │                              │
       ▼                              ▼                              ▼
SCDynamicStore                  WiFiSection.connect()         AppDelegate
callback (private queue)              │                       .applicationDidFinishLaunching
       │                              ▼                              │
extract Sendable             appState.connect(network,               ▼
[EthernetInterface]           password)                       AppState() → StatusItemController(appState:)
       │                              │                              │
       ▼                              ▼                       statusItemController.start()
Task { @MainActor }          WiFiMonitor.associate(...)      (subscribes to $networkState)
       │                              │                              │
       ▼                       Keychain.save(ssid, password)   appState.startMonitors()
EthernetMonitor.$interfaces           │                              │
       │                              ▼                              ▼
       └────► AppState               CWInterface.associate    Monitors emit first events
              .CombineLatest         (background; main-actor    │
              .sink                   completion)               ▼
              │                              │              CombineLatest.sink fires
              ▼                              ▼                     │
        rebuildState()                @MainActor update        rebuildState()
              │                       AppState                     │
              ▼                              │                     ▼
        $networkState                        ▼               First $networkState publish
        $connectionMode                publish               StatusItemController updates icon
              │                              │
              ▼                              ▼
        StatusItemController          WiFiSection (via @EnvironmentObject)
        (icon, label, tooltip)        re-renders connected state
```

### Requirements → Structure Mapping

**By FR cluster:**

| FR cluster | Primary files | Supporting |
|---|---|---|
| Menu Bar Presence (FR1–8) | `MenuBar/StatusItemController.swift` | `Network/Models/ConnectionMode.swift`, `NetworkState.swift` |
| Panel Display & Layout (FR9–14) | `MenuBar/PopoverController.swift`, `UI/PopoverRootView.swift` | `UI/Theme.swift` |
| Ethernet Awareness (FR15–22) | `Network/EthernetMonitor.swift`, `UI/Panels/EthernetSection.swift`, `UI/Components/EthernetRow.swift` | `Network/Models/EthernetInterface.swift`, `Services/SystemSettingsService.swift` |
| Wi-Fi Discovery (FR23–28) | `Network/WiFiMonitor.swift`, `UI/Panels/WiFiSection.swift`, `UI/Components/WiFiRow.swift` | `Network/Models/WiFiNetwork.swift`, `WiFiSecurity.swift` |
| Wi-Fi Connection Mgmt (FR29–38) | `Network/WiFiMonitor.swift`, `UI/Panels/WiFiSection.swift`, `UI/Components/PasswordField.swift`, `UI/Windows/OtherNetworkPanel.swift` | `Services/KeychainService.swift`, `Services/SystemSettingsService.swift`, `Network/Models/WiFiConnectionFailure.swift` |
| Permissions & First-Run (FR39–42) | `Services/LocationService.swift`, `UI/Panels/LocationDeniedView.swift` | `State/AppState.swift` (`wifiLocationDenied`) |
| Lifecycle & Persistence (FR43–47) | `App/AppDelegate.swift`, `Services/LaunchAtLoginService.swift`, `State/AppState.swift` | `Info.plist` (LSUIElement) |
| Resource Discipline (FR48–50) | All monitors (push-only); `State/AppState.swift` | NFR48–50 verified by Instruments |
| Distribution & Updates (FR51–55) | `LinkHub.entitlements`, `Info.plist` (`SUPublicEDKey`), `scripts/`, `appcast/appcast.xml`, Sparkle 2 SPM dep | `ExportOptions.plist` |
| Accessibility (FR56–58) | All `UI/Components/*.swift`, `UI/Panels/*.swift`, `MenuBar/StatusItemController.swift` | NFR23–28 |

**Cross-cutting concerns:**

| Concern | Locations |
|---|---|
| Concurrency boundary (ObjC↔Swift6) | Every monitor at SCDynamicStore callback + every CWEventDelegate method |
| 300ms debounce | `WiFiMonitor`, `EthernetMonitor` (each owns its own PassthroughSubject) |
| Permission gate | `LocationService` → `AppState.wifiLocationDenied` → `WiFiSection` |
| Tear-down | `AppDelegate.applicationWillTerminate` → `AppState.stopMonitors` → individual monitor `.stop()` |
| Build-config divergence | `WiFiMonitor` (`#if DEBUG` mock), `LinkHub.entitlements` (Release-only) |
| Apple HIG mimicry | Every `UI/` file — semantic colors, system font, Reduce Motion |
| Distribution chain | `LinkHub.entitlements`, `Info.plist`, `ExportOptions.plist`, `scripts/`, `appcast/`, GitHub Pages |
| Resource discipline | Every monitor (no Timer/DispatchSourceTimer/Task.sleep) |

### Integration Points

**Internal communication:**
- Combine `@Published` + `.sink` for monitor → state and state → controller.
- `@EnvironmentObject` for state → SwiftUI views.
- Method calls for view → state mutations.
- Direct lifecycle calls (`startMonitors`, `stopMonitors`) for AppDelegate → state.

**External integrations:**
- **CoreWLAN** — `WiFiMonitor` only. Wraps `CWWiFiClient`, `CWInterface`, `CWNetwork`.
- **SystemConfiguration** — `EthernetMonitor` only. Wraps `SCDynamicStore`, `SCNetworkInterface`.
- **CoreLocation** — `LocationService` only. Wraps `CLLocationManager`, `CLLocationManagerDelegate`.
- **Security (Keychain)** — `KeychainService` only. SSID-keyed `kSecClassGenericPassword`.
- **ServiceManagement** — `LaunchAtLoginService` only. `SMAppService.mainApp`.
- **NSWorkspace** — `SystemSettingsService` only. `x-apple.systempreferences:` URLs.
- **Sparkle 2** — wired in `AppDelegate` (or dedicated `UpdaterController`); reads appcast at `talepstein.github.io/LinkHub/appcast.xml`.
- **GitHub Pages** — hosts `appcast/appcast.xml`. Updated per release.

### File Organization Patterns

**Configuration files (repo root):**
- `.gitignore` (PRD 01 spec).
- `ExportOptions.plist` (PRD 09 spec).

**App target resources:**
- `Info.plist` — `LSUIElement=true`, version keys, location usage description, `SUPublicEDKey` (added at PRD 09).
- `LinkHub.entitlements` — Location entitlement only; applied to Release config only.
- `PrivacyInfo.xcprivacy` — Apple privacy manifest (PRD 01 + PRD 08).
- `Assets.xcassets` — `AppIcon.appiconset` only; no menu bar icons.

**Source organization:** Layer-based (App/MenuBar/Network/UI/State/Services/Utilities). One primary type per file. Tests mirror source folder hierarchy.

**Static assets:** App icon in `Assets.xcassets/AppIcon.appiconset/`. SF Symbols used at runtime for everything else (no PDF/SVG imports).

### Development Workflow Integration

**Local dev:**
- Open `LinkHub.xcodeproj` in Xcode 16+.
- Build scheme `LinkHub`, configuration Debug. Ad-hoc signed, no entitlements.
- Wi-Fi scanning unavailable in Debug → `#if DEBUG` mock path engages; UI exercises real layout against canned data.
- Tests run via `LinkHub` scheme Test action, target `LinkHubTests`.

**Build process:**
- Debug: `xcodebuild -scheme LinkHub -configuration Debug build`.
- Release archive: `xcodebuild archive -project LinkHub.xcodeproj -scheme LinkHub -configuration Release -archivePath build/LinkHub.xcarchive`.
- Export: `xcodebuild -exportArchive -archivePath build/LinkHub.xcarchive -exportPath build/export -exportOptionsPlist ExportOptions.plist`.
- Notarize: `scripts/notarize.sh` → `xcrun notarytool submit ... --keychain-profile linkhub-notary --wait` → `xcrun stapler staple LinkHub.app`.
- Package: `scripts/make-dmg.sh` → DMG with `/Applications` symlink.
- Publish appcast: `scripts/update-appcast.sh` → EdDSA-sign, append to `appcast/appcast.xml`, commit + push to GitHub Pages branch.

**Deployment:**
- DMG uploaded as GitHub Release asset.
- `appcast/appcast.xml` updated on `gh-pages` branch (or `main` if Pages serves `/`).
- Sparkle picks up new entry on next user check.

## Architecture Validation Results

### Coherence Validation ✅

**Decision Compatibility:**
- Swift 6 strict concurrency + AppKit App Delegate + SwiftUI inside NSPopover: compatible. AppKit lifecycle owns NSStatusItem; SwiftUI views isolated to popover content via NSHostingController.
- `@MainActor ObservableObject + @Published` consistent across `AppState`, `WiFiMonitor`, `EthernetMonitor`. No `@Observable` (would require macOS 14 — explicitly forbidden by PRD 01).
- 300 ms Combine debounce inside each monitor + single CombineLatest sink in AppState: no double-debounce, no stale-window race.
- Sandbox OFF + Hardened Runtime Release-only: compatible with Developer ID + notarytool + stapler chain. MAS impossibility acknowledged.
- Sparkle 2 EdDSA + GitHub Pages appcast: compatible with PRD 09 D8/D9. Public key in Info.plist; private key in Keychain.
- macOS 13 floor + SF Symbols 4 + SMAppService.mainApp: all available on Ventura. No back-deploy gaps.

**Pattern Consistency:**
- Naming: lowerCamelCase methods/vars, UpperCamelCase types, acronym casing rule (`WiFi`, `ipv4Address`) applied uniformly across PRD spec types and architecture's added types (`WiFiConnectionFailure`, `LocationService`, `LaunchAtLoginService`).
- File-name = primary-type-name rule observed throughout tree.
- Logger subsystem + per-layer category map matches layer folder set.
- Sendable extraction pattern (Task @MainActor) consistent for both SCDynamicStore and CWEventDelegate boundaries.
- @EnvironmentObject injection point single (`NSHostingController.rootView`).

**Structure Alignment:**
- Layer folders match PRD 01 layout exactly.
- New files (`LaunchAtLoginService`, `LocationService`, `WiFiConnectionFailure`) placed in correct existing layers; no new top-level folders required.
- Test target mirror enforced.
- `xcshareddata/` committed; `xcuserdata/` ignored — matches PRD 01 .gitignore.

### Requirements Coverage Validation ✅

**Functional Requirements (58 FRs):**

| Cluster | Count | Coverage |
|---|---|---|
| Menu Bar Presence (FR1–8) | 8 | ✅ `StatusItemController`, icon state table |
| Panel Display & Layout (FR9–14) | 6 | ✅ `PopoverController`, `RootPanelView` |
| Ethernet Awareness (FR15–22) | 8 | ✅ `EthernetMonitor`, `EthernetSection`, `EthernetRow`, multi-interface enum + summary entry (FR21), Open Network Settings (FR22) |
| Wi-Fi Discovery (FR23–28) | 6 | ✅ `WiFiMonitor`, `WiFiSection`, `WiFiRow` |
| Wi-Fi Connection Mgmt (FR29–38) | 10 | ✅ `WiFiMonitor`, `KeychainService`, `OtherNetworkPanel` (FR32 hidden), `WiFiConnectionFailure` (FR37), Forget handoff via `SystemSettingsService` (FR36) |
| Permissions & First-Run (FR39–42) | 4 | ✅ `LocationService`, `LocationDeniedView`, auto-retry on auth flip |
| Lifecycle & Persistence (FR43–47) | 5 | ✅ `LaunchAtLoginService`, `AppState.launchAtLogin`, AppDelegate teardown |
| Resource Discipline (FR48–50) | 3 | ✅ Push-only monitors, no Timer, NFR48–50 budget |
| Distribution & Updates (FR51–55) | 5 | ✅ DMG, Developer ID + notarize + staple, Sparkle 2 EdDSA, manual + automatic update check |
| Accessibility (FR56–58) | 3 | ✅ Per-row labels, transition announcements (NSAccessibility.post on .disconnected) |

**58/58 covered.**

**Non-Functional Requirements (37 NFRs):**

- **NFR1** icon ≤1.5 s — ✅ push events + 300 ms debounce
- **NFR2** popover ≤200 ms cold / ≤100 ms warm — ✅ eager AppState hydration; SwiftUI body draws current state. **Minor:** explicit pre-warm of NSHostingController not specified in architecture; default lazy is likely sufficient but not measured. Verify with Instruments at first build.
- **NFR3** scan ≤5 s OR visible indicator — ⚠️ **Minor gap.** WiFiMonitor scan timeout not architecturally specified. Resolution: see Architecture Amendments (`scanStatus` enum + 5 s Task race).
- **NFR4** 60 fps transitions — ✅ SwiftUI default; Reduce Motion respect codified.
- **NFR5** 300 ms debounce — ✅
- **NFR6** 7-day no drift — ✅ no Timer, weak self everywhere, cancellables removed
- **NFR7** ≥ 99.5 % crash-free — ⚠️ **Acknowledged limitation.** No telemetry per NFR19. Measurement relies on Apple-collected crash reports + user reports. Architectural choice consistent; cannot self-validate metric without violating NFR19.
- **NFR8** zero leaks — ✅ Sendable extraction, weak self, cancellables, delegate=nil teardown
- **NFR9** clean tear-down — ✅ AppState.stopMonitors → CWWiFiClient.delegate=nil + SCDynamicStoreSetDispatchQueue(store, nil)
- **NFR10** failed connect retryable — ✅ typed `WiFiConnectionFailure`, no global state corruption
- **NFR11** sleep/wake/router-reset survival — ✅ push events fire on wake; CombineLatest sink rebuilds on next event
- **NFR12** Keychain `AfterFirstUnlock` — ✅
- **NFR13–18** signing/notarization/manifest — ✅
- **NFR19–22** no telemetry/PII/outbound — ✅
- **NFR23–28** a11y labels + Reduce Motion — ✅ codified per layer
- **NFR29–32** macOS 13+, Universal binary, semantic colors, accent — ✅
- **NFR33** zero strict-concurrency warnings — ✅ Sendable boundary pattern, no `@unchecked Sendable`
- **NFR34** layer folders — ✅
- **NFR35** single MainActor state — ✅ enforcement rule #3 in patterns
- **NFR36** SPM only / Sparkle only — ✅
- **NFR37** os.Logger subsystem — ✅

**35/37 fully addressed; 2 minor flags (NFR3 scan timeout, NFR2 cold-open prewarm) — neither blocks ship.**

### Implementation Readiness Validation ✅

**Decision Completeness:** Every locked decision indexed back to PRD source (PRD 01–09 + NFR/FR refs). No undocumented assumptions.

**Structure Completeness:** Full tree from repo root → app target → tests target → release scripts. Every type from data model + every PRD-named class has a file location. Sparkle wiring location flagged below.

**Pattern Completeness:** 10 enforcement rules + Sendable bridge code + good/anti-pattern examples per category. Compiler-enforced via `SWIFT_STRICT_CONCURRENCY = complete` + `MAIN_THREAD_CHECKER_ENABLED`.

### Gap Analysis Results

**Critical Gaps:** None.

**Important Gaps:**

1. **Sparkle UpdaterController location** — PRD 09 specifies Sparkle 2 + appcast + EdDSA, but no file in tree owns the Sparkle controller. Resolution: add `App/UpdaterController.swift` (wraps `SPUStandardUpdaterController` from Sparkle SPM). Wired in `AppDelegate.applicationDidFinishLaunching` after StatusItemController. Exposes "Check for Updates…" action consumed by status-item right-click NSMenu.
2. **Status item right-click menu** — PRD 02 D9 covers left-click toggle but right-click NSMenu (Launch at Login toggle, Check for Updates, Quit) not specified in tree. Resolution: add `MenuBar/StatusItemMenu.swift` (NSMenu factory). Bound by StatusItemController to status-item button via right-click handler. Items: Launch at Login (toggle, bound to `appState.launchAtLogin`), Check for Updates… (bound to UpdaterController), About LinkHub (`NSAboutWindow`), Quit LinkHub.
3. **NFR3 scan timeout** — `WiFiMonitor.requestScan()` should enforce 5 s timeout and publish a `scanStatus` flag on AppState. Current architecture doesn't define this state.

**Nice-to-Have Gaps:**

- `Utilities/Logger.swift` factory pattern not specified beyond subsystem/category convention. Suggested: `Logger.menuBar`, `Logger.network.wifi` static accessors.
- `Theme.swift` `PanelLayout` constant set not enumerated. Defer to PRD 04 (already shipped).
- Snapshot testing infra for `UI/` deferred. Acceptable; XCTest unit-only at v1 per PRD 01.
- No CI workflow file (`.github/workflows/ci.yml`). Per PRD 01 § Out of Scope: Xcode Cloud / CI deferred until project builds locally. Acceptable.

### Validation Issues Addressed

The three Important Gaps above are resolved by adding two files (`UpdaterController.swift`, `StatusItemMenu.swift`) and one AppState property (`scanStatus`).

**Architecture Amendments (this validation):**

1. Add `LinkHub/App/UpdaterController.swift` — Sparkle 2 wrapper. Wired in AppDelegate after StatusItemController; before `appState.startMonitors()`.
2. Add `LinkHub/MenuBar/StatusItemMenu.swift` — right-click NSMenu factory. Items: Launch at Login (toggle), Check for Updates…, About LinkHub, Quit. Bound by StatusItemController.
3. Add to `AppState`: `@Published private(set) var scanStatus: ScanStatus = .idle` where `enum ScanStatus: Equatable, Sendable { case idle; case scanning; case timedOut }`. WiFiMonitor.requestScan() implements 5 s timeout via Task race; publishes status changes.
4. Add `LinkHub/Network/Models/ScanStatus.swift`.
5. Update `LinkHubTests/State/AppStateTests.swift` to cover scanStatus transitions.

### Architecture Completeness Checklist

**Requirements Analysis**

- [x] Project context thoroughly analyzed
- [x] Scale and complexity assessed
- [x] Technical constraints identified
- [x] Cross-cutting concerns mapped

**Architectural Decisions**

- [x] Critical decisions documented with versions
- [x] Technology stack fully specified
- [x] Integration patterns defined
- [x] Performance considerations addressed

**Implementation Patterns**

- [x] Naming conventions established
- [x] Structure patterns defined
- [x] Communication patterns specified
- [x] Process patterns documented

**Project Structure**

- [x] Complete directory structure defined
- [x] Component boundaries established
- [x] Integration points mapped
- [x] Requirements to structure mapping complete

### Architecture Readiness Assessment

**Overall Status:** READY WITH MINOR GAPS

Reason: All 16 checklist items checked. Important Gaps (Sparkle controller location, status-item right-click NSMenu, NFR3 scan timeout) addressed via the **Architecture Amendments** above — agents have authoritative file paths and contracts. Two informational NFR caveats (NFR2 cold-open prewarm; NFR7 measurement under no-telemetry constraint) acknowledged, not blocking.

**Confidence Level:** High.

**Key Strengths:**
- Single source of truth — every architectural choice traces back to a PRD decision number or NFR ID.
- ObjC ↔ Swift 6 boundary pattern compiler-enforced (`SWIFT_STRICT_CONCURRENCY = complete`, NFR33 zero-warning gate).
- Single-direction data flow (Monitor → AppState → UI/StatusItemController) with one CombineLatest atomic rebuild.
- Layer-based folders prevent feature-folder duplication; every cross-layer rule is statable as "X imports Y forbidden."
- Zero-dep at creation; one (Sparkle 2) at distribution.
- No telemetry; no outbound HTTP except Sparkle appcast — privacy-default, audit-friendly.

**Areas for Future Enhancement:**
- `@Observable` migration when macOS 14 floor adopted.
- Mac App Store distribution path if CWWiFiClient.associate ever gains sandbox-compatible alternative.
- Snapshot testing for UI components.
- CI workflow once first stable archive exists.
- Crash reporting (opt-in, post-MVP) per Growth Features list.

### Implementation Handoff

**AI Agent Guidelines:**

- Follow architectural decisions and patterns in this document verbatim.
- Use the canonical tree from § Project Structure as the file-placement source of truth.
- Apply Sendable extraction + `Task { @MainActor }` at every ObjC framework boundary.
- Respect layer ownership graph — no UI ↔ Monitor direct coupling.
- Architecture amendments listed above are part of v1 scope.
- Pattern violations → fix, or amend this document; never silently work around.

**First Implementation Priority:** Wave 1 of `EXECUTION_PLAN.md` — PRD 01 acceptance criteria. Specifically: create Xcode project, configure Swift 6 strict concurrency, mutate to AppKit App Delegate lifecycle, write minimal `AppDelegate` + folder skeleton + `Info.plist` + `LinkHub.entitlements` (Release-only) + `PrivacyInfo.xcprivacy` + shared scheme + commit.
