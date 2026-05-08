# PRD 01 — Project & Architecture Setup

**Status:** ✅ Done  
**Depends on:** —  
**Blocks:** 02, 03, 04, 08

---

## Problem Statement

> What Xcode project structure, Swift version, deployment target, folder layout, dependency strategy, and build configuration should LinkHub use?

---

## Decision Log

| Decision | Options Considered | Choice | Rationale |
|----------|--------------------|--------|-----------|
| **Xcode target type** | Single App target; App + Framework targets; App + SPM local packages | Single macOS App target, no sub-frameworks | LinkHub has no reusable library surface to expose. Extra targets add build complexity with no benefit at this scale. |
| **Menu bar presence** | `LSUIElement = true`; `LSBackgroundOnly` (deprecated); Activation policy set in code | `LSUIElement = true` in Info.plist | Industry standard for menu-bar-only apps (Bartender, Amphetamine, Timing). Hides Dock icon and Cmd+Tab entry. `LSBackgroundOnly` is deprecated. Setting activation policy in code risks a brief Dock flicker at launch. |
| **App entry point** | SwiftUI `@main App` with `WindowGroup`; `NSApplicationDelegate` + manual `NSStatusItem` | `NSApplicationDelegate` + `NSStatusItem` | `WindowGroup` creates a standard window-centric app. Menu bar apps own the NSStatusItem lifecycle directly in the delegate; SwiftUI views live inside an `NSPopover`, not a Window. |
| **Minimum deployment target** | macOS 12.0; macOS 13.0; macOS 14.0 | **macOS 13.0 (Ventura)** | PLAN.md mandates "macOS 13+". Ventura (Oct 2022) is a widely adopted release; all required APIs (CoreWLAN, SCDynamicStore, AppKit, SwiftUI) are fully stable here. macOS 14 adds `@Observable`, but `ObservableObject` + `@Published` is used throughout (see Constraints). |
| **Swift version** | Swift 5.10; Swift 6.0 | **Swift 6.0** with `SWIFT_STRICT_CONCURRENCY = complete` | LinkHub runs continuously as a system service. Swift 6 enforces data-race safety at compile time, catching concurrency bugs in CoreWLAN/SCDynamicStore bridging early. Xcode 16 ships Swift 6 as the default. |
| **External dependencies** | Zero; Sparkle + KeychainAccess via SPM; Full SPM ecosystem | **Zero external packages at initial project creation** | CoreWLAN, SystemConfiguration, AppKit, SwiftUI, Foundation, os.log cover all functionality needed at project creation. SPM is the only approved package manager (CocoaPods and Carthage are not allowed). **Sparkle 2 is explicitly deferred to PRD 09** and will be added via SPM to the app target only when distribution implementation begins. No packages are added at project creation. |
| **Package manager** | SPM only; CocoaPods; Carthage | **SPM only** (when/if a package is ever added) | SPM is natively integrated with Xcode and Swift. CocoaPods and Carthage add toolchain dependencies and are declining in adoption. No packages are added at project creation. |
| **Build configurations** | Default Debug/Release only; Add Staging; Add Profile | **Debug and Release only** | Two configurations are sufficient for a solo/small-team project. Staging adds overhead without benefit at this stage. Instruments profiling runs against the default Release scheme. |
| **Folder layout** | Flat (all files at top level); Feature-based (WiFi/, Ethernet/); Layer-based (Network/, UI/, State/) | **Layer-based** (see layout below) | LinkHub's features share common network and state infrastructure. Layered grouping prevents duplication and makes the data flow (network → state → UI) legible. Feature folders would require the same monitor code to live in two places. |
| **.gitignore scope** | Minimal (DerivedData only); Full Xcode template | **Full Xcode template** (see below) | Xcuserdata, build artifacts, and OS metadata files are personal/machine-specific and should never be committed. The full template avoids accidental commits of generated files. |

---

## Target Inventory

| Target | Type | Notes |
|--------|------|-------|
| `LinkHub` | macOS App | Single app target; no sub-frameworks or local SPM packages |
| `LinkHubTests` | XCTest unit test | Created at project creation; mirrors source folder structure as tests are added |

- **No XCUITest / XCUIApplication target** at project creation. UI/integration tests may be added in a later coding session once UI flows stabilize.
- No local Swift Package targets.
- No framework targets.
- App target links **system frameworks only** at project creation: AppKit, SwiftUI, Foundation, Combine, CoreWLAN, SystemConfiguration, Security, CoreLocation, ServiceManagement (required by PRD 09 — Login Item / Launch at Login).
- External SPM packages: **none at project creation.** Sparkle 2 is added when distribution implementation begins (PRD 09).

### Bundle Identifier & Team

| Field | Value at project creation |
|-------|--------------------------|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.linkhub.app` |
| `DEVELOPMENT_TEAM` | Leave blank — no real Developer ID required until PRD 09 |
| `CODE_SIGN_IDENTITY` (Debug) | `-` (ad-hoc) |
| `CODE_SIGN_IDENTITY` (Release) | `""` (blank placeholder; final value set in PRD 09) |

The bundle identifier `com.linkhub.app` must be used consistently from project creation so it matches the entitlements and provisioning profile added in PRD 09. Do not use Xcode's auto-generated identifier.

---

## Folder / Module Layout

The Xcode project group hierarchy mirrors the filesystem layout exactly (Xcode "folder references" disabled — use Groups with files):

```
LinkHub/                          ← Xcode project root
├── LinkHub/                      ← Main app source group
│   ├── App/
│   │   └── AppDelegate.swift     ← @main NSApplicationDelegate subclass; NSStatusItem creation, app lifecycle
│   │
│   ├── MenuBar/
│   │   ├── StatusItemController.swift   ← NSStatusItem lifecycle, icon swap trigger
│   │   └── PopoverController.swift      ← NSPopover open/close, event monitor
│   │
│   ├── Network/
│   │   ├── WiFiMonitor.swift            ← CoreWLAN wrapper, scanning, association
│   │   ├── EthernetMonitor.swift        ← SCDynamicStore / SystemConfiguration
│   │   └── Models/
│   │       ├── NetworkState.swift       ← Combined Wi-Fi + Ethernet snapshot
│   │       ├── WiFiNetwork.swift        ← Per-network value type (SSID, RSSI, security)
│   │       └── EthernetInterface.swift  ← Per-interface value type (name, IP, speed)
│   │
│   ├── UI/
│   │   ├── PopoverRootView.swift        ← Root SwiftUI type is `RootPanelView`. Note: some PRDs
│   │   │                                  reference this as "ContentView" — that is an error.
│   │   │                                  Canonical file name: PopoverRootView.swift, type: RootPanelView.
│   │   ├── Theme.swift                  ← `PanelLayout` constants enum (added by PRD 04)
│   │   ├── Panels/
│   │   │   ├── EthernetSection.swift    ← Ethernet status + controls section
│   │   │   └── WiFiSection.swift        ← Wi-Fi network list section
│   │   ├── Windows/
│   │   │   └── OtherNetworkPanel.swift  ← NSPanel subclass for hidden network join (added by PRD 06)
│   │   └── Components/                  ← Shared small views (signal bar, toggle row, etc.)
│   │
│   ├── State/
│   │   └── AppState.swift               ← Central `ObservableObject`; `@Observable` not allowed on macOS 13 (PRD 07)
│   │
│   ├── Services/
│   │   ├── KeychainService.swift        ← Wi-Fi password read/write via Security framework
│   │   └── SystemSettingsService.swift  ← Open Network Settings via URL scheme
│   │
│   ├── Utilities/
│   │   └── Logger.swift                 ← os.log subsystem wrapper
│   │
│   ├── Assets.xcassets                  ← App icon and non-menu-bar assets only. Menu bar icons use SF Symbols at runtime — no xcassets imagesets required (PRD 02)
│   ├── Info.plist
│   ├── PrivacyInfo.xcprivacy            ← Apple privacy manifest; required for CoreLocation (minimum content below; PRD 08 may expand it)
│   └── LinkHub.entitlements
│
├── LinkHubTests/                 ← Unit test target (XCTest)
│   └── (mirrors source structure as tests are added)
│
└── LinkHub.xcodeproj/
```

**PrivacyInfo.xcprivacy (minimum content at project creation):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryLocation</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyTracking</key>
    <false/>
</dict>
</plist>
```

> PRD 08 reviews this manifest and may add additional entries for any additional data types accessed. The file above satisfies Apple's requirement at project creation so the build does not fail validation.

---

**Key Info.plist entries (required at project creation):**

```xml
<!-- Hide from Dock and Cmd+Tab -->
<key>LSUIElement</key>
<true/>

<!-- Privacy strings — required before any Wi-Fi scanning call -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>LinkHub scans for nearby Wi-Fi networks. Apple requires location access for this on macOS 10.15 and later.</string>

<!-- App name shown in permission dialogs -->
<key>CFBundleDisplayName</key>
<string>LinkHub</string>

<!-- Required by PRD 09 versioning scheme: monotonically increasing integer -->
<key>CFBundleVersion</key>
<string>1</string>

<!-- Human-readable version string shown to users -->
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>
```

---

## Build Configurations

### Debug

| Setting | Value |
|---------|-------|
| `SWIFT_OPTIMIZATION_LEVEL` | `-Onone` |
| `SWIFT_STRICT_CONCURRENCY` | `complete` |
| `ENABLE_TESTABILITY` | `YES` |
| `GCC_PREPROCESSOR_DEFINITIONS` | `DEBUG=1` |
| `DEBUG_INFORMATION_FORMAT` | `dwarf` (no dSYM; fast builds) |
| `ENABLE_HARDENED_RUNTIME` | `NO` (skipping speeds up local iteration; notarization not required for Debug) |
| `CODE_SIGN_IDENTITY` | `-` (ad-hoc for local runs) |
| `STRIP_INSTALLED_PRODUCT` | `NO` |

### Release

| Setting | Value |
|---------|-------|
| `SWIFT_OPTIMIZATION_LEVEL` | `-Osize` (smaller binary preferred over speed for a UI app) |
| `SWIFT_STRICT_CONCURRENCY` | `complete` |
| `ENABLE_TESTABILITY` | `NO` |
| `GCC_PREPROCESSOR_DEFINITIONS` | _(empty)_ |
| `DEBUG_INFORMATION_FORMAT` | `dwarf-with-dsym` (required for crash report symbolication post-notarization) |
| `ENABLE_HARDENED_RUNTIME` | `YES` (required for notarization; location entitlement from PRD 08 applies) |
| `CODE_SIGN_IDENTITY` | `""` (blank at project creation; set to `Developer ID Application` in PRD 09) |
| `STRIP_INSTALLED_PRODUCT` | `YES` |

> **Note:** `LinkHub.entitlements` is applied to the **Release configuration only**. Debug builds are ad-hoc signed without Hardened Runtime.
>
> **Debug entitlements and Wi-Fi scanning:** Because Debug builds have no entitlements, CoreLocation is unavailable, and CoreWLAN network scanning will fail at runtime in Debug mode. This is by design. Wi-Fi scanning code must support a mock data path enabled via `#if DEBUG` so the feature can be developed and tested without real location access. PRD 03 (Network Detection) is responsible for defining the mock data protocol. Do not attempt to run real CoreWLAN scans in a Debug build without a real entitlements file applied to the Debug configuration.

### Active Compilation Conditions usage

```swift
#if DEBUG
    // Verbose logging, mock data injection
#endif
```

---

## Scheme Setup

One shared Xcode scheme: **`LinkHub`**

The scheme file (`LinkHub.xcscheme`) is committed to the repo so all contributors use identical build actions. Enable sharing in Xcode via Product → Scheme → Manage Schemes → tick "Shared" for `LinkHub`.

| Action | Configuration | Includes |
|--------|--------------|---------|
| Run | Debug | App target |
| Test | Debug | `LinkHubTests` (no XCUITest target) |
| Profile | Release | App target |
| Analyze | Debug | App target |
| Archive | Release | App target |

### Debug Diagnostics (Run action)

| Diagnostic | Setting |
|-----------|---------|
| Main Thread Checker | **Enabled** |
| Thread Sanitizer | Off by default. Enable manually when auditing `WiFiMonitor` or `EthernetMonitor` for data races. Disable before profiling or running normal test suites (produces false positives with AppKit/CoreWLAN). |
| Swift strict concurrency | `SWIFT_STRICT_CONCURRENCY = complete` (enforced via build setting, not a scheme toggle) |

The scheme must support local run, unit test, profile, and archive without requiring any restructuring of the project.

---

## .gitignore Conventions

```gitignore
# === Xcode ===
build/
DerivedData/
*.xcarchive

# User-specific Xcode settings (never shared)
xcuserdata/
*.xcworkspace/xcuserdata/
*.xcodeproj/xcuserdata/
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3

# === Swift Package Manager ===
# Uncomment when Sparkle 2 is added via SPM in PRD 09:
# .build/
# .swiftpm/
# Packages/

# === macOS ===
.DS_Store
.AppleDouble
.LSOverride

# === IDE ===
.vscode/
.idea/
*.swp
*.swo

# === Build artifacts ===
*.o
*.a
*.dylib
*.app/

# === Secrets / Environment ===
.env
secrets.plist
```

**Always commit (do NOT ignore):**
- `*.xcodeproj/project.pbxproj` — the project definition
- `*.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- `xcshareddata/` — **do NOT ignore this directory**; it contains the shared scheme (`LinkHub.xcscheme`) which must be committed
- All `.swift` source files
- `Info.plist`, `*.entitlements`, `Assets.xcassets`
- `PLAN.md`, `docs/*.md`, `README.md`

---

## Constraints

- **Minimum toolchain: Xcode 16.** Swift 6 language mode (`SWIFT_STRICT_CONCURRENCY = complete`) is not available in Xcode 15 or earlier. Do not open this project in Xcode 15.
- **`@Observable` is prohibited while the deployment target is macOS 13:** The `@Observable` macro (Observation framework) requires macOS 14. Use `@MainActor final class AppState: ObservableObject` with `@Published` throughout (PRD 07 decision #1). This constraint is lifted only if a future PRD explicitly raises the deployment target.
- **CoreWLAN threading:** CoreWLAN is an Objective-C framework with no `async`/`await` surface. All scanning calls must be dispatched on a serial background queue and results published to the main actor. This is a Swift 6 strict-concurrency requirement.
- **SCDynamicStore notifications:** SCDynamicStore uses a `CFRunLoop`-based callback mechanism. The callback runs on a designated dispatch queue, not on `MainActor`. State updates must be explicitly routed to the main actor before touching UI.
- **Wi-Fi scanning and location privacy:** Since macOS 10.15, `CoreWLAN` network scanning requires the user to grant "When In Use" location access. The app must handle denial gracefully (show a limited UI, not crash or block).
- **Sandboxing and CoreWLAN:** Full App Sandbox restricts CoreWLAN and SystemConfiguration access. PRDs 08 and 09 resolve this: App Sandbox is OFF; Hardened Runtime is ON for Release. The app does not need to accommodate sandbox entitlement constraints. Keep network monitor code in a discrete layer regardless, as it improves testability.
- **macOS 13 concurrency runtime:** Swift 6's strict concurrency model is fully supported on macOS 13+. No back-deployment workarounds needed.
- **Swift 6 + ObjC bridging:** Any CoreWLAN or SystemConfiguration types crossing isolation boundaries must be either `Sendable`-conforming value types or explicitly dispatched to avoid data races. Plan for `@unchecked Sendable` wrappers on CWNetwork until Apple annotates them.

---

## Out of Scope

- **iOS / iPadOS support** — LinkHub is macOS-only; no multiplatform targets.
- **macOS Catalyst** — not applicable; native AppKit/SwiftUI suffices.
- **Local Swift packages / frameworks** — no modularisation beyond folder groups at this stage.
- **Xcode Cloud / CI configuration** — deferred; can be added once the project builds successfully locally.
- **Code signing identity and provisioning profiles** — decided in PRD 09 (Distribution & Release).
- **Sparkle or any update mechanism** — deferred to PRD 09.
- **Actual Xcode project file creation** — PRD 01 defines what the project must look like; the project file is created in the first coding session.

---

## Open Questions

None for PRD 01. All architecture-level decisions are resolved:

- **`ObservableObject` vs `@Observable`** → resolved by PRD 07: use `@MainActor final class AppState: ObservableObject` with `@Published`. `@Observable` is not allowed while the deployment target remains macOS 13.
- **Distribution channel / sandbox** → resolved by PRDs 08 and 09: Developer ID direct distribution, App Sandbox OFF, Hardened Runtime ON for Release builds.
- **Test target setup** → resolved in the Target Inventory section above: `LinkHubTests` XCTest unit-test target is created at project creation; no XCUITest target initially.

Later PRDs own feature-level behavioral questions.

---

## Acceptance Criteria

PRD 01 is satisfied when a freshly created Xcode project meets all of the following:

- [ ] App target builds with macOS 13.0 deployment target and Swift 6.
- [ ] `SWIFT_STRICT_CONCURRENCY = complete` is set on the app target.
- [ ] `LSUIElement = true` is present in `Info.plist`.
- [ ] Shared `LinkHub` scheme exists and is committed (`.xcscheme` in `xcshareddata/`).
- [ ] `LinkHubTests` XCTest target exists and its test action runs under the shared scheme.
- [ ] No external SPM packages are present in the project file at initial creation.
- [ ] Folder/group structure matches the layout in this PRD.
- [ ] `PrivacyInfo.xcprivacy` is added to the app target with the minimum content specified in the PrivacyInfo.xcprivacy section of this PRD.
- [ ] Release `CODE_SIGN_IDENTITY` is blank (`""`) at project creation; ad-hoc signing (`-`) is used for Debug. No real Developer ID cert is required in the repo (final signing configured in PRD 09).
- [ ] `Info.plist` privacy string and entitlements do not conflict with PRD 08.
- [ ] `Assets.xcassets` contains only the app icon set; no menu-bar-icon imagesets.
- [ ] Info.plist contains CFBundleVersion = 1 and CFBundleShortVersionString = 1.0.0.

---

## References

- [Apple Developer: LSUIElement key](https://developer.apple.com/documentation/bundleresources/information_property_list/lsuielement) — Info.plist key that suppresses Dock presence.
- [Apple Developer: NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem) — Menu bar item API.
- [Apple Developer: CoreWLAN framework](https://developer.apple.com/documentation/corewlan) — Wi-Fi scanning and association.
- [Apple Developer: SystemConfiguration framework](https://developer.apple.com/documentation/systemconfiguration) — SCDynamicStore for network interface monitoring.
- [WWDC 2022: Meet Swift Async Algorithms](https://developer.apple.com/videos/play/wwdc2022/110355/) — Async debounce patterns relevant to network event observation.
- [WWDC 2023: Beyond the basics of structured concurrency](https://developer.apple.com/videos/play/wwdc2023/10170/) — Swift 6 actor isolation and `@Sendable` patterns.
- [WWDC 2024: Migrate your app to Swift 6](https://developer.apple.com/videos/play/wwdc2024/10169/) — Strict concurrency migration guide, relevant for ObjC bridge wrappers around CoreWLAN.
- [Swift.org: Swift 6 Language Mode](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/) — Official migration guide for enabling `SWIFT_STRICT_CONCURRENCY = complete`.
- [github.com/github/gitignore — Swift.gitignore](https://github.com/github/gitignore/blob/main/Swift.gitignore) — Reference template for the `.gitignore` above.
