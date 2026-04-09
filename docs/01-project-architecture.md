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
| **Minimum deployment target** | macOS 12.0; macOS 13.0; macOS 14.0 | **macOS 13.0 (Ventura)** | PLAN.md mandates "macOS 13+". Ventura (Oct 2022) covers ~90 % of the Mac fleet in 2026. All required APIs (CoreWLAN, SCDynamicStore, AppKit, SwiftUI) are fully stable here. macOS 14 adds `@Observable` but it is not required — `ObservableObject`/Combine works on 13. |
| **Swift version** | Swift 5.10; Swift 6.0 | **Swift 6.0** with `SWIFT_STRICT_CONCURRENCY = complete` | LinkHub runs continuously as a system service. Swift 6 enforces data-race safety at compile time, catching concurrency bugs in CoreWLAN/SCDynamicStore bridging early. Xcode 16 ships Swift 6 as the default. |
| **External dependencies** | Zero; Sparkle + KeychainAccess via SPM; Full SPM ecosystem | **Zero external packages** at project start | CoreWLAN, SystemConfiguration, AppKit, SwiftUI, Foundation, os.log cover all needed functionality. Adding packages now would be speculative. Sparkle (auto-update) and any others will be evaluated per-PRD when the concrete need arises. |
| **Package manager** | SPM only; CocoaPods; Carthage | **SPM only** (when/if a package is ever added) | SPM is natively integrated with Xcode and Swift. CocoaPods and Carthage add toolchain dependencies and are declining in adoption. No packages are added at project creation. |
| **Build configurations** | Default Debug/Release only; Add Staging; Add Profile | **Debug and Release only** | Two configurations are sufficient for a solo/small-team project. Staging adds overhead without benefit at this stage. Instruments profiling runs against the default Release scheme. |
| **Folder layout** | Flat (all files at top level); Feature-based (WiFi/, Ethernet/); Layer-based (Network/, UI/, State/) | **Layer-based** (see layout below) | LinkHub's features share common network and state infrastructure. Layered grouping prevents duplication and makes the data flow (network → state → UI) legible. Feature folders would require the same monitor code to live in two places. |
| **.gitignore scope** | Minimal (DerivedData only); Full Xcode template | **Full Xcode template** (see below) | Xcuserdata, build artifacts, and OS metadata files are personal/machine-specific and should never be committed. The full template avoids accidental commits of generated files. |

---

## Folder / Module Layout

The Xcode project group hierarchy mirrors the filesystem layout exactly (Xcode "folder references" disabled — use Groups with files):

```
LinkHub/                          ← Xcode project root
├── LinkHub/                      ← Main app source group
│   ├── App/
│   │   ├── LinkHubApp.swift      ← @main NSApplicationDelegate subclass
│   │   └── AppDelegate.swift     ← NSStatusItem creation, app lifecycle
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
│   │   ├── ContentView.swift            ← Root SwiftUI view hosted in NSPopover
│   │   ├── Panels/
│   │   │   ├── EthernetSection.swift    ← Ethernet status + controls section
│   │   │   └── WiFiSection.swift        ← Wi-Fi network list section
│   │   └── Components/                  ← Shared small views (signal bar, toggle row, etc.)
│   │
│   ├── State/
│   │   └── AppState.swift               ← Central ObservableObject (or @Observable on 14+)
│   │
│   ├── Services/
│   │   ├── KeychainService.swift        ← Wi-Fi password read/write via Security framework
│   │   └── SystemSettingsService.swift  ← Open Network Settings via URL scheme
│   │
│   ├── Utilities/
│   │   └── Logger.swift                 ← os.log subsystem wrapper
│   │
│   ├── Assets.xcassets                  ← App icon + menu bar icon imagesets
│   ├── Info.plist
│   └── LinkHub.entitlements
│
├── LinkHubTests/                 ← Unit test target (XCTest)
│   └── (mirrors source structure as tests are added)
│
└── LinkHub.xcodeproj/
```

**Key Info.plist entries (required at project creation):**

```xml
<!-- Hide from Dock and Cmd+Tab -->
<key>LSUIElement</key>
<true/>

<!-- Privacy strings — required before any Wi-Fi scanning call -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>LinkHub scans nearby Wi-Fi networks, which may use your location.</string>

<!-- App name shown in permission dialogs -->
<key>CFBundleDisplayName</key>
<string>LinkHub</string>
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
| `CODE_SIGN_IDENTITY` | Developer ID Application (configured in PRD 09) |
| `STRIP_INSTALLED_PRODUCT` | `YES` |

### Active Compilation Conditions usage

```swift
#if DEBUG
    // Verbose logging, mock data injection
#endif
```

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
# (Uncomment if SPM packages are ever added)
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
- All `.swift` source files
- `Info.plist`, `*.entitlements`, `Assets.xcassets`
- `PLAN.md`, `docs/*.md`, `README.md`

---

## Constraints

- **CoreWLAN threading:** CoreWLAN is an Objective-C framework with no `async`/`await` surface. All scanning calls must be dispatched on a serial background queue and results published to the main actor. This is a Swift 6 strict-concurrency requirement.
- **SCDynamicStore notifications:** SCDynamicStore uses a `CFRunLoop`-based callback mechanism. The callback runs on a designated dispatch queue, not on `MainActor`. State updates must be explicitly routed to the main actor before touching UI.
- **Wi-Fi scanning and location privacy:** Since macOS 10.15, `CoreWLAN` network scanning requires the user to grant "When In Use" location access. The app must handle denial gracefully (show a limited UI, not crash or block).
- **Sandboxing and CoreWLAN:** Full App Sandbox restricts CoreWLAN and SystemConfiguration access. Distribution channel (App Store vs. Developer ID) is deferred to PRD 09, but the architecture must not assume sandbox safety — keep network monitor code in a layer that can be toggled if entitlements change.
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

| # | Question | Impact | To resolve before |
|---|----------|--------|-------------------|
| 1 | Should `AppState` use `ObservableObject` + `@Published` (works on macOS 13) or the `@Observable` macro (requires macOS 14)? | Affects which OS features the app can use and how SwiftUI views bind to state. | PRD 07 (State & Data Management) |
| 2 | Will the app be distributed via the Mac App Store (requires sandbox) or Developer ID direct (no sandbox required)? Sandbox changes which entitlements are mandatory from day one. | Entitlement set, CoreWLAN access level, Keychain group configuration. | PRD 08 (Permissions & Entitlements) → PRD 09 (Distribution) |
| 3 | Should the unit test target include UI/integration tests (XCUITest) from the start, or unit tests only? | Affects how the Xcode scheme's Test action is configured and what mock infrastructure is needed. | First coding session |

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
