---
stepsCompleted:
  - step-01-document-discovery
  - step-02-prd-analysis
  - step-03-epic-coverage-validation
  - step-04-ux-alignment
  - step-05-epic-quality-review
  - step-06-final-assessment
filesIncluded:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/prd-validation-report.md
  - _bmad-output/planning-artifacts/architecture.md
  - _bmad-output/planning-artifacts/epics.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
---

# Implementation Readiness Assessment Report

**Date:** 2026-05-09
**Project:** LinkHub

## Document Inventory

| Type | File | Size | Format |
|---|---|---|---|
| PRD | `_bmad-output/planning-artifacts/prd.md` | 42.8 KB | whole |
| PRD validation | `_bmad-output/planning-artifacts/prd-validation-report.md` | 24.0 KB | whole |
| Architecture | `_bmad-output/planning-artifacts/architecture.md` | 65.0 KB | whole |
| Epics & Stories | `_bmad-output/planning-artifacts/epics.md` | 40.8 KB | whole |
| UX Design | `_bmad-output/planning-artifacts/ux-design-specification.md` | 59.7 KB | whole |

**Duplicates:** none.
**Missing:** none.
**Supplementary (not used as canonical):** `docs/01-09` detailed sub-PRDs.

## PRD Analysis

### Functional Requirements

**Menu Bar Presence**
- FR1: User sees a single LinkHub icon in macOS menu bar at all times while app running.
- FR2: System displays Wi-Fi-style icon when no Ethernet interface has link (Wi-Fi-only mode).
- FR3: System displays Ethernet-style icon when ≥1 Ethernet interface has link (Ethernet-active mode).
- FR4: System displays disconnected-state icon when neither Wi-Fi nor Ethernet provides connectivity.
- FR5: System updates menu bar icon within 1.5 s of network state change (cable in/out, Wi-Fi join/leave).
- FR6: User clicks menu bar icon to open LinkHub panel.
- FR7: User clicks menu bar icon while panel open to dismiss it.
- FR8: VoiceOver user perceives current connection state via icon's accessibility label.

**Panel Display & Layout**
- FR9: User sees popover panel anchored to menu bar icon when LinkHub opened.
- FR10: User dismisses panel by pressing Escape.
- FR11: User dismisses panel by clicking outside it.
- FR12: System presents Ethernet section above Wi-Fi section whenever any Ethernet interface has link.
- FR13: System hides Ethernet section when no Ethernet interface has had link for ≥1.5 s (grace period for transient disconnects).
- FR14: User sees panel respect active macOS appearance (light/dark) without per-app config.

**Ethernet Awareness**
- FR15: System detects Ethernet interfaces present on host (USB-C/Thunderbolt dongles, TB docks).
- FR16: User sees per-interface state: Active / Obtaining address / DHCP timeout / No link.
- FR17: User sees IPv4 address of any active Ethernet interface.
- FR18: User sees negotiated link speed (Mbps/Gbps) of any active Ethernet interface.
- FR19: User sees human-readable display name for each Ethernet interface.
- FR20: System sorts Ethernet interfaces with active first, ties broken by stable identifier order.
- FR21: User sees summary entry pointing to System Settings when more interfaces exist than panel displays inline.
- FR22: User opens macOS Network settings pane directly from Ethernet section.

**Wi-Fi Network Discovery**
- FR23: User sees list of nearby Wi-Fi networks discovered by system.
- FR24: User sees per-network: SSID (or "Hidden Network"), signal strength, security marker (open/password/enterprise), connected state.
- FR25: User sees captive-portal marker on networks requiring sign-in.
- FR26: User requests fresh Wi-Fi scan on demand.
- FR27: System refreshes Wi-Fi list automatically on system events (SSID/link/signal/power changes).
- FR28: User sees currently connected Wi-Fi network distinguished from others in list.

**Wi-Fi Connection Management**
- FR29: User connects to open Wi-Fi by tapping its row.
- FR30: User connects to password-protected Wi-Fi by tapping row, entering password, confirming.
- FR31: System stores Wi-Fi passwords securely in macOS Keychain (no re-prompt for known networks).
- FR32: User connects to hidden Wi-Fi via dedicated panel (SSID + optional password).
- FR33: User routed to system captive-portal flow when joining captive network.
- FR34: User disconnects from current Wi-Fi by toggling Wi-Fi power off.
- FR35: User turns Wi-Fi power on or off.
- FR36: User initiates "Forget This Network" action — routes to system Wi-Fi settings to complete removal.
- FR37: User sees feedback identifying failure cause on failed Wi-Fi connection (wrong password / out of range / association timeout / auth error).
- FR38: User opens macOS Wi-Fi settings pane directly from Wi-Fi section.

**Permissions & First-Run Experience**
- FR39: System requests macOS Location authorization on first Wi-Fi scan attempt (Apple platform requirement).
- FR40: User sees empty state when Location authorization denied/restricted, identifying cause + one-tap path to Privacy settings.
- FR41: System resumes Wi-Fi scanning automatically when Location auth flips denied → granted (no app restart).
- FR42: System launches without modal onboarding flow; panel itself is the introduction.

**Application Lifecycle & Persistence**
- FR43: User configures LinkHub to launch automatically at login.
- FR44: User disables launch-at-login at any time without restarting app.
- FR45: System runs as menu-bar-only app — no Dock icon, no Cmd+Tab entry.
- FR46: System releases Wi-Fi event subscriptions cleanly on termination (no OS leak of process refs).
- FR47: System persists launch-at-login preference across reboots.

**Resource Discipline**
- FR48: System runs continuously in background consuming ≤ 80 MB resident memory at idle.
- FR49: System runs continuously consuming ≤ 0.5% CPU averaged over 60-s idle window on Apple Silicon.
- FR50: System avoids scheduled polling when panel closed (system-pushed events only).

**Distribution & Updates**
- FR51: User installs LinkHub from downloaded DMG signed for distribution outside Mac App Store.
- FR52: User verifies app properly notarized — Gatekeeper does not warn/block on first launch.
- FR53: System checks for updates on periodic background cadence + notifies user when available.
- FR54: User manually triggers update check.
- FR55: User installs update via in-app update dialog with cryptographic verification of artifact authenticity.

**Accessibility**
- FR56: VoiceOver user perceives every Wi-Fi network row's info (SSID, signal quality, security state, connected state) via labels.
- FR57: VoiceOver user perceives every Ethernet row's info (display name, status, IP, link speed) via labels.
- FR58: VoiceOver user perceives transitions between Wi-Fi-only / Ethernet-active / disconnected via accessibility announcements.

**Total FRs: 58**

### Non-Functional Requirements

**Performance**
- NFR1: Menu bar icon must update within 1.5 s of underlying network state change.
- NFR2: Popover must reach first paint with populated content within 200 ms cold open / 100 ms warm open on Apple Silicon.
- NFR3: User-initiated Wi-Fi scan must return results within 5 s under normal RF conditions, or surface visible scanning indicator.
- NFR4: Panel transitions must run at display refresh rate without dropped frames on Apple Silicon.
- NFR5: Network state events in rapid succession must be debounced ≥ 300 ms before driving UI update (no icon flicker).

**Reliability**
- NFR6: App must run continuously ≥ 7 days without restart and without measurable resource drift (memory/FD/CPU).
- NFR7: Crash-free session rate ≥ 99.5% across first 30 days of release.
- NFR8: Instruments runs (Allocations/Leaks/Time Profiler) over 1-hr session of induced state changes must show zero leaks attributable to LinkHub.
- NFR9: App must release CoreWLAN delegates and SCDynamicStore callbacks cleanly on termination.
- NFR10: Failed Wi-Fi connection must leave app in clean state — user can retry without restart.
- NFR11: App must survive macOS sleep/wake, router resets, dock reconnects, VPN toggles without entering unresponsive state (panel responds to click within 1.5 s; icon updates within 1.5 s of next state change).

**Security**
- NFR12: Wi-Fi passwords stored in Keychain (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlock`); never in UserDefaults/files/long-lived memory.
- NFR13: DMG and .app must be code-signed with valid Developer ID Application cert.
- NFR14: All distribution artifacts must be notarized with stapled tickets.
- NFR15: Hardened Runtime must be enabled in Release builds.
- NFR16: Sparkle update artifacts must be EdDSA-signed; matching public key embedded in `Info.plist` (`SUPublicEDKey`).
- NFR17: App must request only entitlements it functionally requires (Location). App Sandbox stays disabled per `CWWiFiClient.associate` constraint; no other entitlement without PRD amendment.
- NFR18: `PrivacyInfo.xcprivacy` must declare every required-reason API used (UserDefaults, file timestamp, system boot time) — kept in sync with codebase.

**Privacy**
- NFR19: App must not collect/log/transmit PII about user/networks/device — no telemetry/analytics/crash reports/remote config.
- NFR20: macOS Location authorization used solely for declared purpose (Wi-Fi scanning); never persisted/transmitted.
- NFR21: Wi-Fi network identifiers (SSID/BSSID/RSSI) must remain on-device — no outbound HTTP including them.
- NFR22: Captive-portal handoff URL opened via user's default browser, not in-app webview.

**Accessibility**
- NFR23: Every interactive control and informational row must expose `accessibilityLabel` consumable by VoiceOver, content per NFR24–25.
- NFR24: Wi-Fi rows' a11y labels must include SSID, signal quality (excellent/good/fair/weak), security marker, connected state.
- NFR25: Ethernet rows' a11y labels must include display name, status, IP (or "no IP"), link speed.
- NFR26: Connection state transitions must trigger `NSAccessibility` announcements.
- NFR27: Decorative graphics (signal bars, status dots) marked `accessibilityHidden(true)`; info lives in parent row's combined label.
- NFR28: Panel and interactive elements must respect macOS Reduce Motion (disable pulsing/animation when on).

**Compatibility**
- NFR29: App must build and run on macOS 13.0 Ventura and all later releases through current.
- NFR30: App must ship as Universal binary supporting arm64 + x86_64.
- NFR31: App must respect active macOS appearance (Light/Dark/Auto) using only system semantic colors — no hardcoded colors.
- NFR32: App must respect active macOS accent color where it exposes accent-colored elements.
- NFR33: Build must produce zero Swift 6 strict concurrency warnings/errors in Release.

**Maintainability**
- NFR34: Codebase must follow layer-based folder structure (`App/`, `MenuBar/`, `Network/`, `UI/`, `State/`, `Services/`, `Utilities/`). New code placed by layer.
- NFR35: All shared application state must flow through single `@MainActor` observable state container. UI components observe only that container.
- NFR36: Every framework dependency must be either system framework or documented SPM dep (currently only Sparkle 2). No closed-source binary deps, no CocoaPods, no Carthage.
- NFR37: Diagnostic logging must use `os.Logger` with subsystem = `Bundle.main.bundleIdentifier`.

**Total NFRs: 37**

### Additional Requirements

**Technical constraints (load-bearing implementation rules from PRD):**
- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`); CoreWLAN/SCDynamicStore non-Sendable types extracted to Sendable model structs (`WiFiNetwork`, `EthernetInterface`) before actor hops.
- State model: single `@MainActor final class AppState: ObservableObject` with `@Published`. No `@Observable` (macOS 13 deployment predates it).
- Init order load-bearing: `StatusItemController` must subscribe before `AppState.startMonitors()` fires.
- Event bridging: SCDynamicStore C callbacks + CWEventDelegate callbacks bridge to `@MainActor` via `Task { @MainActor in ... }`. 300 ms debounce on merged stream.
- No timers while popover closed (event-driven only).
- `CWWiFiClient.shared().delegate = nil` on termination breaks retain cycle.

**Distribution constraints:**
- Direct download DMG (no MAS in v1 due to sandbox blocking `CWWiFiClient.associate`).
- Sparkle 2 from `talepstein.github.io/LinkHub/appcast.xml`, EdDSA-signed.
- No delta updates v1.
- No rollback mechanism.

**Explicit out-of-scope (scope guardrails):**
- Mac App Store distribution
- Localization beyond English
- Telemetry / crash reporting / analytics
- VPN / Tailscale / WireGuard
- Per-network location profiles
- Network history / traffic graphs / bandwidth usage
- Preferences window (only Launch at Login toggle in v1)
- Notification Center, Widgets, Shortcuts, AppleScript
- In-app captive portal browser
- Sparkle delta updates
- Per-interface advanced detail views (MTU, DNS, etc.)
- Right-click "Forget" in-app (must hand off to System Settings)

**Resource budgets (success metrics):**
- Cable-in → icon swap latency ≤ 1.5 s
- Cable-out → section hide grace 1.5 s
- Idle memory ≤ 80 MB resident
- Idle CPU ≤ 0.5% (60 s avg, Apple Silicon)
- Popover cold open → first paint ≤ 200 ms
- Popover warm open → first paint ≤ 100 ms
- First-time Wi-Fi connect (untrained user) ≤ 10 s
- Crash-free sessions first 30 days ≥ 99.5%

### PRD Completeness Assessment

PRD is comprehensive and well-scoped. 58 FRs + 37 NFRs cover all four user journeys (First-Touch, Icon Swap, Dual-Network Daily, Permission Recovery). Out-of-scope list is explicit and enforced. PRD already underwent validation (separate `prd-validation-report.md` exists; PRD frontmatter notes validation-driven edits applied). No requirement gaps surfaced at extraction time. Coverage validation against epics in next step.

## Epic Coverage Validation

### Coverage Matrix

| FR | PRD Topic | Epic Coverage | Status |
|---|---|---|---|
| FR1 | Single icon visible | Epic 1 | ✓ Covered |
| FR2 | Wi-Fi-style icon (Wi-Fi-only) | Epic 1 | ✓ Covered |
| FR3 | Ethernet-style icon | Epic 3 | ✓ Covered |
| FR4 | Disconnected icon | Epic 1 | ✓ Covered |
| FR5 | Icon update ≤1.5 s | Epic 1 (Wi-Fi path) + Epic 3 (Ethernet path) | ✓ Covered |
| FR6 | Click icon → open panel | Epic 1 | ✓ Covered |
| FR7 | Click icon → dismiss | Epic 1 | ✓ Covered |
| FR8 | VoiceOver icon label | Epic 1 | ✓ Covered |
| FR9 | Popover anchored | Epic 1 | ✓ Covered |
| FR10 | Esc dismiss | Epic 1 | ✓ Covered |
| FR11 | Click-outside dismiss | Epic 1 | ✓ Covered |
| FR12 | Ethernet section above Wi-Fi | Epic 3 | ✓ Covered |
| FR13 | 1.5 s grace before hide | Epic 3 | ✓ Covered |
| FR14 | Light/Dark adapt | Epic 1 | ✓ Covered |
| FR15 | Detect Ethernet interfaces | Epic 3 | ✓ Covered |
| FR16 | 4 interface states | Epic 3 | ✓ Covered |
| FR17 | IPv4 per active interface | Epic 3 | ✓ Covered |
| FR18 | Link speed per active interface | Epic 3 | ✓ Covered |
| FR19 | Display name per interface | Epic 3 | ✓ Covered |
| FR20 | Sort active-first | Epic 3 | ✓ Covered |
| FR21 | Overflow → System Settings entry | Epic 3 | ✓ Covered |
| FR22 | Open Network Settings handoff | Epic 3 | ✓ Covered |
| FR23 | See nearby Wi-Fi list | Epic 1 | ✓ Covered |
| FR24 | Per-Wi-Fi info | Epic 1 | ✓ Covered |
| FR25 | Captive marker | Epic 1 | ✓ Covered |
| FR26 | On-demand Wi-Fi scan | Epic 1 | ✓ Covered |
| FR27 | Auto-refresh on system events | Epic 1 | ✓ Covered |
| FR28 | Connected Wi-Fi distinguished | Epic 1 | ✓ Covered |
| FR29 | Connect open Wi-Fi | Epic 2 | ✓ Covered |
| FR30 | Connect WPA inline password | Epic 2 | ✓ Covered |
| FR31 | Keychain password storage | Epic 2 | ✓ Covered |
| FR32 | Hidden Wi-Fi via dedicated panel | Epic 2 | ✓ Covered |
| FR33 | Captive portal handoff | Epic 2 | ✓ Covered |
| FR34 | Disconnect via Wi-Fi power off | Epic 2 | ✓ Covered |
| FR35 | Wi-Fi power on/off | Epic 2 | ✓ Covered |
| FR36 | Forget Network handoff | Epic 2 | ✓ Covered |
| FR37 | Cause-typed connection failure | Epic 2 | ✓ Covered |
| FR38 | Open Wi-Fi Settings handoff | Epic 2 | ✓ Covered |
| FR39 | Request Location auth | Epic 1 | ✓ Covered |
| FR40 | LocationDeniedView empty state | Epic 1 | ✓ Covered |
| FR41 | Auto-resume on auth flip | Epic 1 | ✓ Covered |
| FR42 | No modal onboarding | Epic 1 | ✓ Covered |
| FR43 | Launch at Login configuration | Epic 4 | ✓ Covered |
| FR44 | Disable Launch at Login w/o restart | Epic 4 | ✓ Covered |
| FR45 | Menu-bar-only (LSUIElement) | Epic 1 | ✓ Covered |
| FR46 | Clean subscription teardown | Epic 1 (Wi-Fi) + Epic 3 (Ethernet) | ✓ Covered |
| FR47 | Persist Launch at Login | Epic 4 | ✓ Covered |
| FR48 | ≤80 MB RAM idle | Epic 4 (final validation; baseline Epic 1) | ✓ Covered |
| FR49 | ≤0.5% CPU idle 60 s | Epic 4 (final validation; baseline Epic 1) | ✓ Covered |
| FR50 | No scheduled polling | Epic 1 | ✓ Covered |
| FR51 | Install signed DMG | Epic 4 | ✓ Covered |
| FR52 | Notarized — Gatekeeper clean | Epic 4 | ✓ Covered |
| FR53 | Background update check + notify | Epic 4 | ✓ Covered |
| FR54 | Manual update check | Epic 4 | ✓ Covered |
| FR55 | In-app update with crypto verification | Epic 4 | ✓ Covered |
| FR56 | VoiceOver Wi-Fi row | Epic 1 | ✓ Covered |
| FR57 | VoiceOver Ethernet row | Epic 3 | ✓ Covered |
| FR58 | VoiceOver state-transition announcements | Epic 3 | ✓ Covered |

### Missing Requirements

None. All 58 FRs from PRD have explicit epic mappings in the FR Coverage Map (epics.md:281–340).

No FRs found in epics that are absent from PRD.

### Coverage Statistics

- Total PRD FRs: **58**
- FRs covered in epics: **58**
- Coverage percentage: **100%**

### Observations (non-blocking)

- FR48 / FR49 (resource budgets) listed under Epic 4 as "final Instruments validation" with Epic 1 as baseline. This is correct (continuous discipline + final gate), but flag: ensure Epic 1 stories enforce the budget (e.g., no polling, no timers, lazy scan) rather than deferring all validation to Epic 4.
- FR5 split across Epic 1 (Wi-Fi path) and Epic 3 (Ethernet path) — both halves required for full FR satisfaction.
- FR46 split across Epic 1 (Wi-Fi teardown) and Epic 3 (Ethernet teardown) — both halves required.

## UX Alignment Assessment

### UX Document Status

**Found.** `_bmad-output/planning-artifacts/ux-design-specification.md` (59.7 KB). Workflow steps 01–14 complete. PRD + PRD validation report listed as input documents. Sub-PRDs in `docs/01-09` also referenced.

### UX ↔ PRD Alignment

| UX element | PRD anchor | Aligned |
|---|---|---|
| Three personas (Maya / Yossi / Itai) | PRD User Journeys 1, 3, 4 | ✓ |
| Defining experience: glance → read → close | PRD Success Criteria (no learning curve, instant Ethernet awareness) | ✓ |
| Icon-swap as product moment, ≤1.5 s | PRD FR5, NFR1 | ✓ |
| Reduce Motion fallback for every animation | PRD NFR28 | ✓ |
| Inline password expansion (no modal) | PRD FR30 | ✓ |
| Three popover dismissal paths | PRD FR7, FR10, FR11 | ✓ |
| `LocationDeniedView` with one-click recovery | PRD FR40, FR41 | ✓ |
| Right-click status item NSMenu (Launch at Login / Updates / About / Quit) | PRD FR43–44, FR53–55 | ✓ |
| Forget Network → System Settings handoff | PRD FR36 | ✓ |
| Pixel-parity with stock Wi-Fi menu | PRD Executive Summary "drop-in replacement" thesis | ✓ |
| Cable-out 1.5 s grace before section hide | PRD FR13 | ✓ |
| Light/Dark/Auto + accent color respect | PRD FR14, NFR31, NFR32 | ✓ |
| Empty state copy ("No networks found", etc.) | PRD FR40 + UX patterns extension | ✓ |

**No UX requirements absent from PRD.** No PRD UX-side requirements absent from UX spec. UX expands on PRD with implementation-grade detail (UX-DR1–38) — covered in epics' UX-DR mapping.

### UX ↔ Architecture Alignment

| UX requirement | Architecture support | Aligned |
|---|---|---|
| 320 pt fixed-width popover | `NSPopover` hosting `NSHostingController<RootPanelView>`; PanelLayout constants in `UI/Theme.swift` | ✓ |
| ≤200 ms cold / ≤100 ms warm popover open | Eager monitor warmup via `appState.startMonitors()` at launch; popover content pre-bound via `@EnvironmentObject` | ✓ |
| 300 ms icon morph crossfade + 250 ms section reorder | SwiftUI animation + `@Environment(\.accessibilityReduceMotion)` gating | ✓ |
| 300 ms event debounce (no flicker) | `Publishers.CombineLatest(...).debounce(for: .milliseconds(300))` in AppState | ✓ |
| Reduce Motion / Reduce Transparency / Increase Contrast | System semantic-tokens-only mandate; no hardcoded colors | ✓ |
| `NSAccessibility.announcementRequested` on transitions | `RootPanelView` posts on `connectionMode` change; UX-DR25 utterances mapped | ✓ |
| Single-panel discipline (`OtherNetworkPanel` replaces root content) | UI/Panels/ layer; state-binding navigation, no `NSWindow`/sheet | ✓ |
| Inline password row expand/collapse | `WiFiRow` `.expanded(password:error:)` state in SwiftUI | ✓ |
| Right-click status item NSMenu | `MenuBar/StatusItemMenu.swift` factory wired to status-item button right-click handler | ✓ |
| SF Symbols only iconography | `NSImage(systemSymbolName:)` for menu bar icons; `Image(systemName:)` in SwiftUI | ✓ |
| `NSVisualEffectView` `.windowBackground` vibrancy | Architecture explicitly notes Apple HIG mimicry as cross-cutting concern | ✓ |
| Keychain-backed password (UX form pattern: write on success only) | `Services/KeychainService` with `kSecClassGenericPassword` + `AfterFirstUnlock` | ✓ |
| Captive portal opens default browser | `NSWorkspace.shared.open(http://captive.apple.com)`; no in-app webview component | ✓ |

**No UX requirements unsupported by architecture.** Architecture explicitly lists the UX spec among input documents and epics map UX-DR1–38 across the four epics.

### Alignment Issues

None blocking.

### Warnings

None.

## Epic Quality Review

### Epic Structure Validation

**A. User Value Focus — all 4 epics pass.**

| Epic | Title | User Value? |
|---|---|---|
| Epic 1 | Foundation & Live Wi-Fi Visibility | ✓ User installs, sees status, reads Wi-Fi list, recovers from permission denial |
| Epic 2 | Wi-Fi Connection Management | ✓ User connects/disconnects/forgets Wi-Fi networks |
| Epic 3 | Ethernet Awareness — The Cable Moment | ✓ User experiences icon swap + Ethernet promotion (the "aha") |
| Epic 4 | Lifecycle, Distribution & Updates | ✓ User installs the real product, auto-updates, configures Launch at Login |

No epic is a technical milestone in disguise. Epic 1 includes project init (Story 1.1) but is framed around user-perceptible outcomes (visible icon, populated panel, recoverable permission denial), not "set up the project."

**B. Epic Independence — passes with one note.**

| Epic | Depends on | Independent of |
|---|---|---|
| Epic 1 | — | All others |
| Epic 2 | Epic 1 (WiFiMonitor, AppState, WiFiSection) | Epic 3, Epic 4 |
| Epic 3 | Epic 1 (AppState, StatusItemController, RootPanelView) | Epic 2, Epic 4 |
| Epic 4 | Epics 1–3 (functional features to package) | — |

No forward dependencies. Epic 2 and Epic 3 are siblings on top of Epic 1 — could ship in either order.

**Note:** Epic 3 expands the `Publishers.CombineLatest(...)` sink in AppState from single-monitor (Wi-Fi only) to dual-monitor. If Epic 2 ships between Epic 1 and Epic 3, Epic 2 builds against the single-monitor sink. The Epic 3 expansion is described as "small additive refactor of the same single sink" — should not break Epic 2 functionality, but the dual-monitor sink rebuild needs Epic 2 regression coverage when Epic 3 lands.

### Story Quality Assessment

**Stories are not enumerated at the epic doc level.** Per BMad workflow, story breakdown happens at sprint planning (`bmad-sprint-planning`) and individual story files are produced via `bmad-create-story`. Epics.md provides:
- FR coverage map per epic
- NFR + UX-DR anchors per epic
- Implementation notes (architecture references, key components added)

**Story 1.1 alone is referenced** in Epic 1's implementation notes ("project init per PRD 01 acceptance criteria"). This is correct given the Architecture mandates a starter template (Xcode 16 macOS App template + AppKit AppDelegate lifecycle).

**Acceptance criteria are not present** at the epic level — they will land in per-story files via `bmad-create-story`. Per-PRD acceptance criteria already exist in `docs/01-09` and PRD.md, ready to be lifted into story ACs.

### Dependency Analysis

**Within-epic dependencies (forecast, since stories are not yet split):**

- **Epic 1 expected story order:** 1.1 project init → 1.2 AppState scaffold + StatusItemController → 1.3 WiFiMonitor scan + push events → 1.4 RootPanelView + WiFiSection (read-only) → 1.5 LocationDeniedView + auth flow → 1.6 VoiceOver labels + announcements. Each story builds on prior; no forward dependency.
- **Epic 2 expected story order:** 2.1 WiFiMonitor.associate + WiFiConnectionFailure → 2.2 KeychainService + password persistence → 2.3 WiFiRow expanded state + inline error → 2.4 OtherNetworkPanel (hidden network) → 2.5 Wi-Fi power Toggle → 2.6 Forget/Open Settings handoffs.
- **Epic 3 expected story order:** 3.1 EthernetMonitor + Sendable extraction → 3.2 AppState dual-monitor sink refactor → 3.3 EthernetSection + EthernetRow 4-state UI → 3.4 StatusBarIcon Ethernet path + crossfade → 3.5 Cable-out grace + section reorder animation → 3.6 multi-Ethernet enumeration + overflow row.
- **Epic 4 expected story order:** 4.1 LaunchAtLoginService + UserDefaults → 4.2 StatusItemMenu (right-click NSMenu) → 4.3 Sparkle 2 SPM dep + UpdaterController → 4.4 Notarization + signing scripts → 4.5 DMG packaging script → 4.6 Appcast EdDSA pipeline → 4.7 Final Instruments validation pass (NFR48, NFR49, NFR8).

These are forecasts — actual story split happens at sprint planning. Useful as a reasonableness check on epic scope.

**B. Database/Entity creation timing:** N/A. LinkHub has no database; only `UserDefaults` (`launchAtLogin: Bool` only key) and Keychain (per SSID). UserDefaults usage created at point of need (Epic 4); Keychain service created at point of need (Epic 2).

### Special Implementation Checks

**A. Starter template requirement:** ✓ Architecture specifies Xcode 16 macOS App template + AppKit AppDelegate lifecycle. Story 1.1 = project init per PRD 01 acceptance criteria. Story includes all post-creation mutations (AppDelegate replace, Info.plist keys, build settings, layer folders, entitlements Release-only, PrivacyInfo, shared scheme, .gitignore). ✓

**B. Project context:** Brownfield — 9 detailed sub-PRDs (`docs/01-09`) and an EXECUTION_PLAN.md exist. Code implementation has not started. Story creation can pull acceptance criteria directly from sub-PRDs — high-quality material already in place.

### Compliance Checklist

| Criterion | Epic 1 | Epic 2 | Epic 3 | Epic 4 |
|---|---|---|---|---|
| Delivers user value | ✓ | ✓ | ✓ | ✓ |
| Functions independently (after deps) | ✓ | ✓ | ✓ | ✓ |
| FRs traceable | ✓ | ✓ | ✓ | ✓ |
| NFRs anchored | ✓ | ✓ | ✓ | ✓ |
| UX-DRs anchored | ✓ | ✓ | ✓ | ✓ |
| Implementation notes specific | ✓ | ✓ | ✓ | ✓ |
| Stories enumerated | — (sprint planning) | — | — | — |
| Acceptance criteria present | — (per-story) | — | — | — |

### Findings

#### 🔴 Critical Violations

None.

#### 🟠 Major Issues

None.

#### 🟡 Minor Concerns

1. **Resource-budget validation centralized in Epic 4 (FR48, FR49).** Risk: if validation fails at Epic 4, may force rework in Epic 1/2/3. Recommendation: each epic should include a "baseline measurement" sub-task in its closing story (resident memory + idle CPU snapshot) so regressions are caught at epic boundaries, not at final validation.

2. **AppState single-→dual-monitor refactor in Epic 3.** Risk: silent regression of Epic 2 connect flow when sink expands. Recommendation: Epic 3 story for AppState refactor must include explicit Epic-2 regression coverage in ACs (Wi-Fi connect/forget paths still work).

3. **Stories not enumerated in epics.md.** This matches BMad workflow norms (stories created via `bmad-create-story` per-file, sprint plan groups them). Not a defect — but the next gate is sprint planning. Surface this so reviewers know the absence is by design.

4. **Acceptance criteria deferred to per-story files.** Same note. The sub-PRDs in `docs/01-09` already contain testable AC-grade material that should be lifted directly during story creation rather than re-derived.

### Quality Assessment Summary

The epic breakdown is high-quality:
- All 4 epics are user-value framed.
- Independence verified.
- FR/NFR/UX-DR traceability is explicit per epic.
- Implementation notes ground each epic in specific architecture decisions and module names.
- Brownfield context is honored — sub-PRDs are the source of truth and epics index against them rather than re-author.

The work needed before sprint kickoff is **story creation** (`bmad-create-story` per story) and **AC authoring** (lift from sub-PRDs). No restructuring required.

## Summary and Recommendations

### Overall Readiness Status

**READY** — with minor recommendations to apply during sprint planning + story creation. No blockers.

### Findings Tally

| Category | Critical | Major | Minor |
|---|---|---|---|
| Document discovery | 0 | 0 | 0 |
| PRD analysis | 0 | 0 | 0 |
| Epic FR coverage | 0 (100% coverage) | 0 | 0 |
| UX alignment | 0 | 0 | 0 |
| Epic quality | 0 | 0 | 4 |

**Total: 4 minor concerns. 0 blockers.**

### Critical Issues Requiring Immediate Action

None.

### Minor Recommendations (apply during sprint planning + story creation)

1. **Resource-budget baseline measurements per epic.** Add a closing sub-task to each epic's last story: snapshot resident memory + idle CPU. Catches NFR48/NFR49 regressions at epic boundaries instead of at Epic 4's final Instruments pass.

2. **AppState dual-monitor refactor regression coverage.** Epic 3's AppState sink-expansion story must include explicit Epic-2 regression ACs (Wi-Fi connect/disconnect/forget paths still pass). Without it, silent regression risk when sink moves from single- to dual-monitor.

3. **Lift AC material directly from sub-PRDs.** `docs/01-09` already contain testable AC-grade material per PRD. During `bmad-create-story`, pull ACs verbatim where possible rather than re-derive.

4. **Document Story 1.1 visibility.** Story 1.1 (project init from Xcode template) is currently buried in Epic 1 implementation notes. Surface it as the explicit first story when sprint planning runs.

### Recommended Next Steps

1. Run `bmad-sprint-planning` (`[SP]`) — produces sprint plan listing every story across the four epics in execution order.
2. Begin story cycle: `bmad-create-story` (`[CS]`) → `bmad-dev-story` (`[DS]`) → `bmad-code-review` (`[CR]`). Loop. Optional `bmad-create-story:validate` between CS and DS.
3. At end of each epic, optional `bmad-retrospective` (`[ER]`).
4. During story creation, lift ACs from `docs/01-09` sub-PRDs and PRD.md directly.
5. Apply the 4 minor recommendations above as the stories are created — they're cheap to apply early, expensive to retrofit.

### Final Note

This assessment identified 0 critical and 4 minor concerns across 5 review categories. The planning artifacts (PRD, UX spec, Architecture, Epics) are coherent, fully traceable, and ready to drive implementation. No restructuring required. Proceed to sprint planning.

**Date:** 2026-05-09
**Assessor:** Claude (BMad implementation-readiness skill)





