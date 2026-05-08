---
date: '2026-05-04'
lastEdited: '2026-05-04'
editHistory:
  - date: '2026-05-04'
    changes: 'Validation-driven edits: tightened FR37/FR40/FR42 wording, removed Sparkle library name from FR55, defined NFR11 unresponsive-state criteria, scoped NFR23 to NFR24-25, abstracted NFR35 from class names, added N/A status lines to Domain and Innovation sections.'
stepsCompleted:
  - step-01-init
  - step-02-discovery
  - step-02b-vision
  - step-02c-executive-summary
  - step-03-success
  - step-04-journeys
  - step-05-domain
  - step-06-innovation
  - step-07-project-type
  - step-08-scoping
  - step-09-functional
  - step-10-nonfunctional
  - step-11-polish
  - step-12-complete
releaseMode: single-release
inputDocuments:
  - docs/01-project-architecture.md
  - docs/02-menubar-integration.md
  - docs/03-network-detection.md
  - docs/04-panel-ui-architecture.md
  - docs/05-ethernet-controls.md
  - docs/06-wifi-management.md
  - docs/07-state-data-management.md
  - docs/08-permissions-entitlements.md
  - docs/09-distribution-release.md
  - EXECUTION_PLAN.md
  - PLAN.md
  - README.md
workflowType: 'prd'
briefCount: 0
researchCount: 0
brainstormingCount: 0
projectDocsCount: 12
classification:
  projectType: desktop_app
  domain: general
  complexity: medium
  projectContext: brownfield
---

# Product Requirements Document - LinkHub

**Author:** Tal
**Date:** 2026-05-03

## Executive Summary

LinkHub is a macOS menu bar app that fills a gap Apple left open: a single control surface for both Wi-Fi and Ethernet. macOS today forces users to choose between the stock Wi-Fi menu (Wi-Fi only) or System Settings (everything, several clicks deep). LinkHub collapses that choice into one menu bar item that adapts to context — behaving as a drop-in replacement for the system Wi-Fi menu when no Ethernet is present, and promoting Ethernet status and controls to the top of the panel the moment a cable is plugged in.

The target user is the macOS power user who routinely switches between wired and wireless — desktop users with docks, developers on hybrid setups, anyone whose workflow already lives in the menu bar. The product is built from the author's own daily friction, not from market research, which keeps the scope honest and the feature set small.

### What Makes This Special

- **Adaptive familiarity, not replacement.** When no Ethernet is connected, LinkHub is visually and functionally indistinguishable from the stock Wi-Fi menu. Zero relearning cost. Users keep what they had and gain what they were missing.
- **The icon swap is the product moment.** Plugging in Ethernet triggers a visible icon change in the menu bar and a panel that reorders Ethernet on top, Wi-Fi below. That single transition is the "aha" — it makes the value tangible in under a second.
- **Tight scope is the differentiator.** No VPN, no Tailscale, no location profiles, no network history graphs. Resisting expansion is deliberate — "the feature Apple should have shipped already" is the bar, and anything beyond that dilutes the proposition.
- **Native, not Electron.** Swift 6 strict concurrency, SwiftUI + AppKit, CoreWLAN, SystemConfiguration. Persistent menu bar app with a low CPU/memory footprint, free of the cross-platform tax that bloats competing utilities.

## Project Classification

- **Project Type:** Desktop app (macOS native, menu bar utility)
- **Domain:** General — system/networking utility, no regulated domain
- **Complexity:** Medium — Swift 6 strict concurrency and CoreWLAN/SCDynamicStore bridging require precision, but no compliance or regulatory overhead
- **Project Context:** Brownfield — 9 detailed technical design docs and a 5-wave execution plan already exist; code implementation has not begun

## Success Criteria

### User Success

- **Replacement-grade familiarity:** A user can disable the system Wi-Fi menu (or simply ignore it) and use LinkHub instead with zero loss of capability. Every action they used to do in the stock menu — see networks, connect, disconnect, toggle Wi-Fi power, open Other Networks — is one click away in LinkHub.
- **Instant Ethernet awareness:** From cable insertion to icon swap + panel reorder is ≤ 1.5 seconds. The user does not have to click into a menu to discover Ethernet is up.
- **Cable-out grace:** Ethernet section disappears with a 1.5s fade after unplug — no jarring flicker on momentary disconnects (USB-C dock wakes, etc.).
- **No learning curve:** A first-time user, given LinkHub with no documentation, completes their first Wi-Fi connect within 10 seconds because the layout matches the stock macOS Wi-Fi menu.
- **Wi-Fi password flow without context loss:** Connecting to a WPA2 network (password expansion inline) does not require leaving the popover. Captive-portal handling routes to `captive.apple.com` automatically.

### Business Success

This is a personal-pain project, not a commercial product. "Business success" is reframed as **shipping and stewardship success**:

- **v1.0 shipped:** Notarized, Developer ID signed, Sparkle 2 auto-update wired, distributed via direct download. Not Mac App Store at v1.
- **Author uses it daily as their primary network UI** within 1 week of v1.0 release. Eating own dog food is the core viability test.
- **Zero-maintenance steady state:** After v1.0, no critical bugs requiring point releases for 30 days. Indicates the small/simple scope held.
- **Optional vanity metric:** ≥ 100 GitHub stars within 90 days of public release would suggest the gap LinkHub fills resonates beyond the author. Not a gating metric.

### Technical Success

- **Resource budget held:** Idle memory ≤ 80 MB resident; idle CPU ≤ 0.5% (60s avg, Apple Silicon).
- **Zero Swift 6 strict concurrency warnings or errors** in Release builds.
- **No data races, no leaks:** Instruments runs (Allocations, Leaks, Time Profiler) clean across a 1-hour session involving network change events, popover open/close cycles, and Wi-Fi scans.
- **CoreWLAN delegate retained correctly:** No crash on app quit (`CWWiFiClient.shared().delegate = nil` in tearDown).
- **First paint within 200 ms:** Popover opens to populated UI in ≤ 200 ms after status item click (cold). Subsequent opens ≤ 100 ms.
- **Accessibility:** VoiceOver labels match spec for every row state.

### Measurable Outcomes

| Metric | Target |
|--------|--------|
| Cable-in → icon swap latency | ≤ 1.5s |
| Cable-out → section hide grace | 1.5s |
| Idle memory (resident) | ≤ 80 MB |
| Idle CPU (60s avg, Apple Silicon) | ≤ 0.5% |
| Popover cold open → first paint | ≤ 200 ms |
| Popover warm open → first paint | ≤ 100 ms |
| Swift 6 strict-concurrency warnings | 0 |
| Crash-free sessions over first 30 days | ≥ 99.5% |
| First-time Wi-Fi connect (untrained user) | ≤ 10s |

## Product Scope

### Strategy & Philosophy

**Approach:** Single-release MVP. v1.0 ships everything PRDs 01–09 specify and nothing else. The MVP philosophy here is **experience MVP** — the user must walk away feeling LinkHub is the network UI macOS already had. Anything that breaks that illusion (half-finished states, missing rows, ugly empty states) disqualifies the release. Anything that goes beyond that illusion (VPN, profiles, dashboards) violates the scope thesis.

**Resource requirements:**
- 1 solo developer (the author) plus AI agents working through the 5-wave EXECUTION_PLAN.
- No design hire — design language is "match Apple," so reference material is the live macOS Wi-Fi menu plus Apple's HIG.
- No QA hire — author dogfoods on personal Mac; Sparkle telemetry catches v1.0+1 issues.
- One Apple Developer account, one GitHub Pages site for appcast hosting, one Sparkle EdDSA keypair.

### Must-Have Capabilities (v1.0)

Every item below blocks ship. Each maps directly to one or more PRDs in `docs/`.

| # | Capability | PRD |
|---|---|---|
| 1 | Xcode project, Swift 6 strict concurrency, macOS 13+ deployment target, layer-based folder structure | 01 |
| 2 | `NSStatusItem` with adaptive SF Symbol icon (`wifi`, `wifi.slash`, `cable.connector`) and accessibility labels | 02 |
| 3 | `NSPopover` with SwiftUI `RootPanelView`, escape-to-close, transient behavior | 02, 04 |
| 4 | Ethernet detection via `SCDynamicStore` (link + IPv4 keys), 300 ms debounce, multi-interface enumeration, link-speed via media options | 03, 05 |
| 5 | Wi-Fi monitoring via `CWWiFiClient`, `CWEventDelegate` (ssid/link/linkQuality/power), main-thread bridge | 03, 06 |
| 6 | Adaptive panel layout — Ethernet section above Wi-Fi when any interface has link; smooth transitions | 04 |
| 7 | Ethernet rows: 4 states (active / obtaining / DHCP-timeout / no-link), pulsing dots, IP, link speed, "Open Network Settings" | 05 |
| 8 | Wi-Fi rows: signal bars, SSID, lock icon, captive marker, enterprise marker, connect-via-inline-password | 06 |
| 9 | Wi-Fi power toggle, scan refresh, hidden network panel (`OtherNetworkPanel`), forget-via-Settings handoff, captive portal handoff to `captive.apple.com` | 06 |
| 10 | Keychain-backed Wi-Fi password storage (`kSecAttrAccessibleAfterFirstUnlock`) | 06, 08 |
| 11 | Location permission gate with `LocationDeniedView` empty state and Privacy Settings deep link | 06, 08 |
| 12 | Centralized `@MainActor AppState` with `Combine`-driven rebuild pipeline; correct AppDelegate init order | 07 |
| 13 | Resource budget held: ≤ 80 MB RAM, ≤ 0.5% CPU at idle | 07 |
| 14 | Entitlements: Location only; App Sandbox OFF; Hardened Runtime ON in Release | 01, 08 |
| 15 | `PrivacyInfo.xcprivacy` declaring required APIs | 08 |
| 16 | Launch at Login via `SMAppService.mainApp` | 08 |
| 17 | Code signing (Developer ID), notarization, stapling, DMG packaging | 09 |
| 18 | Sparkle 2 auto-update with EdDSA-signed appcast at `talepstein.github.io/LinkHub/appcast.xml` | 09 |
| 19 | Bundle versions set, `ExportOptions.plist` correct, build verified entitlement-clean | 09 |

### Nice-to-Have Capabilities (v1.0 — only if zero risk to ship date)

These are *inside* the 9 PRDs as nice-to-have polish, not new scope. They drop first if anything slips:

- VoiceOver labels on every row and state. (Success Criteria says **must-have**; included here as the line item where polish is allowed to vary.)
- Smooth panel transitions (`.easeInOut(0.25)`) for Ethernet section show/hide. If buggy, ship with instant transitions.
- Right-click context menus on Wi-Fi rows. If unstable, ship without — user can use Forget via Settings.
- DHCP-timeout pulsing animation for Ethernet "Obtaining…" state. If glitchy, ship with steady dot.

### Explicitly Out of Scope for v1.0

These are the scope guardrails. Saying no to them *is* the product:

- Mac App Store distribution (sandbox blocker)
- Localization beyond English
- Telemetry, crash reporting, analytics
- VPN management, Tailscale, WireGuard
- Per-network location profiles
- Network history / traffic graphs / bandwidth usage
- Preferences window (no v1.0 user-configurable settings beyond Launch at Login toggle)
- Notification Center integration
- Widgets, Shortcuts actions, AppleScript dictionary
- Custom in-app captive portal browser (handoff to system browser is fine)
- Sparkle delta updates
- Per-interface advanced detail views (MTU, DNS, etc.)
- Right-click "Forget" in-app (must use System Settings handoff)

### Growth Features (Post-MVP)

Deliberately minimal — the scope discipline IS the product:

- Localization beyond English (future translations only)
- Accessibility polish: VoiceOver rotor support, full keyboard navigation of the popover
- Optional Mac App Store distribution as a parallel channel (would require sandboxing rework)
- Light telemetry (opt-in only) for crash reports and resource budget validation
- Per-interface advanced detail on right-click (MAC, MTU, etc.) — only if the author personally wants it

### Vision (Future)

- **Stay invisible.** Track macOS releases and adapt the panel to match new system Wi-Fi menu visual language as Apple evolves it. The product's job is to feel like it belongs.
- **No broader networking play.** No VPN management, no Tailscale/WireGuard integration, no location-based profiles, no traffic graphs. These are explicit non-goals — they are how this product would lose its identity.

### Risk Mitigation Strategy

**Technical Risks:**

| Risk | Likelihood | Mitigation |
|---|---|---|
| Swift 6 strict concurrency forces large rewrites of CoreWLAN/SCDynamicStore bridging | Medium | Wave 2B has explicit "extract to Sendable model before actor hop" guidance; PRD 03 documents the `CWNetwork`-not-Sendable trap |
| `CWWiFiClient.associate` blocked by sandbox forces App Store path closure | Already accepted | Decision documented: no MAS in v1.0; Developer ID direct download instead |
| `SCDynamicStore` C-callback retain-cycle leaks | Medium | PRD 03 spec: `Unmanaged<EthernetMonitor>` pattern with explicit teardown; Instruments leak run before ship |
| Apple changes Wi-Fi menu visual language in macOS 14/15 mid-development | Low | "Stay invisible" vision item — track and adapt; not a v1.0 blocker |
| First-launch Location permission UX is brittle (Itai journey) | High (most common failure mode) | `LocationDeniedView` is a must-have, not nice-to-have; validated in Journey 4 |

**Market Risks:**

| Risk | Likelihood | Mitigation |
|---|---|---|
| Nobody else hits the same pain → no adoption | Low | Author's own daily use is the viability test; broader adoption is bonus, not gating |
| Existing utilities (iStat Menus, Bartender add-ons) are "good enough" for the niche | Medium | Differentiator is *not being kitchen-sink*; resisting feature creep is the moat |

**Resource Risks:**

| Risk | Likelihood | Mitigation |
|---|---|---|
| Solo dev hits a Swift 6 dead-end on Wave 2B | Medium | EXECUTION_PLAN waves are independent; can fall back to Swift 5.10 mode if strict concurrency proves intractable (last resort, requires PRD 01 amendment) |
| Apple Developer account / signing cert friction at Wave 5 | Medium | Wave 5 PRD 09 explicitly leaves `PLACEHOLDER_TEAM_ID` so build is testable pre-signing; signing/notarization is the last step |
| Sparkle EdDSA key generation deferred | Low | Wave 5 task list reminds to run `generate_keys` and paste into Info.plist; one-time setup |

## User Journeys

### Journey 1 — First-Touch (Onboarding)

**Persona:** *Maya, 34, Mac developer.* Lives on a 14" MacBook Pro at a desk dock and at coffee shops. Hears about LinkHub from a Hacker News post. Already has the system Wi-Fi menu in muscle memory.

**Opening Scene.** Maya downloads the `.dmg`, drags LinkHub to Applications, opens it. No window appears — only a Wi-Fi-shaped icon in the menu bar, indistinguishable from the system one. She wonders briefly if the install worked.

**Rising Action.** She clicks the icon. A popover opens listing nearby Wi-Fi networks, exactly the layout she expected. No banner, no "Welcome to LinkHub" tour. She joins her usual network — same flow as the system menu, password expansion inline. macOS asks for Location permission (required for Wi-Fi scanning). She grants it.

**Climax.** She glances at the system Wi-Fi icon out of habit and realizes she's been using LinkHub for a minute without noticing. The product disappeared into her workflow — and that's the win.

**Resolution.** Maya enables "Launch at Login" via right-click menu. She'll forget LinkHub is third-party until she plugs in Ethernet (Journey 2).

**Reveals requirements:**
- First-launch flow with no modal onboarding (deliberate — familiarity is the onboarding)
- Location permission prompt handling with clear OS-native dialog (PRD 08)
- Launch at Login via SMAppService (PRD 09)
- Visual + functional parity with stock Wi-Fi menu when Ethernet absent (PRDs 02, 04, 06)

---

### Journey 2 — The Icon Swap (The "Aha")

**Persona:** Same Maya, two days later. Returns from coffee shop, drops MacBook into the Thunderbolt dock at her desk. Ethernet cable runs from the dock to her switch.

**Opening Scene.** Mid-conversation in Slack, she barely looks at the screen as she docks.

**Rising Action.** Within ~1 second, the menu bar icon morphs from `wifi` to `cable.connector`. Peripheral vision catches the change. She stops typing.

**Climax.** She clicks the icon. The popover opens — but this time Ethernet is on top: `en3 Apple Thunderbolt 1 Gbps · 192.168.1.42`. Wi-Fi list is below. She didn't have to navigate, drill in, or open System Settings. The information found *her*.

**Resolution.** She closes the popover. For the next week, every dock → undock cycle reinforces the same micro-delight. This is the moment that converts a curious downloader into a daily user. She tells two colleagues.

**Reveals requirements:**
- `SCDynamicStore` Ethernet observation with ≤ 1.5s debounce (PRD 03)
- Atomic icon + panel ordering update via `AppState` (PRD 07)
- `EthernetSection` shows above `WiFiSection` whenever any interface has link (PRD 04 layout contract)
- Ethernet row shows IP, link speed, status dot — all four states (active / obtaining / DHCP timeout / no link) per PRD 05

---

### Journey 3 — Dual-Network Daily Workflow

**Persona:** *Yossi, 41, video editor.* Mac Studio with permanent Ethernet to NAS, plus Wi-Fi to the office router for internet. Both interfaces are always live. Has occasionally needed to forget a stale Wi-Fi after a router replacement and got tired of going to System Settings → Network → Wi-Fi → Advanced.

**Opening Scene.** Yossi notices his Mac is downloading a project file slowly. He suspects the Mac is routing through Wi-Fi instead of Ethernet and wants to check at a glance.

**Rising Action.** He clicks the LinkHub icon. The popover shows Ethernet at top with link speed 1 Gbps and IP — confirming Ethernet is up. Wi-Fi section below shows the office network connected with full bars. Both look healthy. Routing problem is elsewhere; he can rule out the network surface in 2 seconds.

**Climax.** Two weeks later, the office router gets replaced. He needs to forget the old SSID and join the new one. He right-clicks the old SSID in LinkHub's Wi-Fi list → "Forget This Network." Per PRD 06, this opens System Settings → Wi-Fi (because CoreWLAN doesn't expose a remove API). One click less than navigating from Apple menu.

**Resolution.** He joins the new SSID inline. Done in 30 seconds. Old workflow took 2 minutes of menu hunting.

**Reveals requirements:**
- Multi-interface Ethernet display, sorted by active status then BSD name (PRD 05)
- Live IP and link speed surfacing without panel reopen
- Right-click "Forget This Network" handoff to System Settings (PRD 06)
- Inline join flow for new SSIDs

---

### Journey 4 — Permission Denied / Recovery Path

**Persona:** *Itai, 27, designer.* New to macOS Ventura, declines every permission prompt by reflex. Installs LinkHub, hits "Don't Allow" on the Location permission for Wi-Fi scanning.

**Opening Scene.** Itai opens the LinkHub popover expecting Wi-Fi networks. Sees nothing.

**Rising Action.** Instead of an empty list with no explanation, he sees a `LocationDeniedView` (per PRD 06): a lock icon, the line "LinkHub needs Location access to scan for Wi-Fi networks (Apple requires this on macOS 10.15+)," and a button "Open Privacy Settings."

**Climax.** He clicks. macOS jumps straight to Privacy & Security → Location Services with the LinkHub row visible. He flips the toggle, switches back. The popover, on next open, shows networks. No app restart needed — `CLLocationManagerDelegate` picks up the auth change and `WiFiMonitor` retries the scan.

**Resolution.** Recovery from the most common first-launch failure mode is one click and zero error messages. Itai never feels lost.

**Reveals requirements:**
- `wifiLocationDenied` state in `AppState` (PRD 07/08)
- `LocationDeniedView` empty state with deep link via `SystemSettingsService.openLocationPrivacySettings()` (PRD 08)
- `CLLocationManagerDelegate` auto-retries scan when authorization flips to `.authorized` (PRD 08)
- Apple-mandated NSLocationWhenInUseUsageDescription string in Info.plist (PRD 08)

---

### Journey Requirements Summary

The four journeys converge on these capability clusters — each maps to existing technical PRDs:

| Capability Cluster | Driving Journeys | Backing PRDs |
|---|---|---|
| Adaptive menu bar icon (Wi-Fi ↔ Ethernet) with sub-second swap | 2 | 02, 03 |
| Stock-Wi-Fi-menu parity panel layout | 1, 3 | 02, 04, 06 |
| Ethernet-on-top reordering when link present | 2, 3 | 04, 05 |
| Multi-Ethernet enumeration + status states | 3 | 05 |
| Wi-Fi scan, list, connect, password-via-Keychain | 1, 3 | 06, 08 |
| Right-click Forget → System Settings handoff | 3 | 06 |
| First-launch permissions (Location) with recovery UX | 1, 4 | 08 |
| Launch at Login (SMAppService) | 1 | 09 |
| Zero-modal onboarding (familiarity = onboarding) | 1 | (UX principle, no PRD needed) |

All required capabilities are covered by existing PRDs 01–09. No new technical work surfaced by the journeys.

## Domain-Specific Requirements

**Status:** N/A — LinkHub operates in the general domain (system/networking utility) with no regulated compliance regime.

**Not applicable.** LinkHub operates in the general domain (system networking utility) with no regulated compliance regime — no HIPAA, PCI-DSS, GDPR data subject obligations beyond standard consumer software, no industry certifications, no third-party integration with regulated systems.

The only external constraints are **Apple platform requirements**, which are documented in their respective technical PRDs and explicitly *not* domain-specific:

- **App Store Review Guidelines compliance** (only if Mac App Store distribution is later pursued — currently out of scope per PRD 09)
- **Notarization requirements** for Developer ID distribution (PRD 09)
- **Privacy manifest** (`PrivacyInfo.xcprivacy`) declaring API usage (PRD 08)
- **Location permission** for Wi-Fi scanning, mandated by macOS 10.15+ (PRD 08)
- **Hardened Runtime** in Release builds (PRD 01, 09)

No additional regulatory, compliance, or domain-pattern requirements apply.

## Innovation & Novel Patterns

**Status:** N/A — Restraint, not novelty, is the differentiator. LinkHub is a missing-feature implementation of UX Apple already established.

**Not applicable.** LinkHub is intentionally *not* an innovation play. Its thesis is the opposite: it is a missing-feature implementation of UX Apple already established but never extended to Ethernet. The value is in execution and restraint, not novelty.

No novel protocols, no AI-driven behaviors, no system-automation experiments, no new interaction paradigms. The differentiation lives entirely in **scope discipline** — choosing not to build the things competing menu bar utilities pile on. That stance is documented in the Executive Summary and Product Scope sections; it does not need separate innovation analysis.

## Desktop App Specific Requirements

### Project-Type Overview

LinkHub is a macOS-only menu bar utility. It runs as a persistent background process (`LSUIElement = true`, no Dock presence, no Cmd+Tab entry) and exposes its entire UI through a single `NSStatusItem` and an `NSPopover`. It is not a windowed application — there is no main window, no menu bar (the macOS app menu bar), no preferences window in v1. Distribution is direct download with Sparkle 2 auto-update. Mac App Store is explicitly out of scope for v1 because the App Sandbox blocks `CWWiFiClient.associate`.

### Platform Support

| Item | Decision | Source |
|---|---|---|
| Operating systems | macOS only — no iOS, no Windows, no Linux | PLAN.md, PRD 01 |
| Minimum macOS version | macOS 13 Ventura | PRD 01 |
| Architectures | Universal binary (Apple Silicon + Intel) via standard Xcode build | PRD 09 |
| Tested target | Apple Silicon primary; Intel via universal binary | PRD 09 |
| Cross-platform port | None planned. Native frameworks (CoreWLAN, SCDynamicStore, AppKit) are macOS-exclusive and the product thesis depends on stock-Wi-Fi-menu visual parity | Vision |

### System Integration

LinkHub integrates with macOS through Apple's documented APIs only:

| Integration | Purpose | API |
|---|---|---|
| Menu bar | Primary surface | `NSStatusItem` on `NSStatusBar.system`, `.variableLength` |
| Wi-Fi | Scan, list, connect, monitor | `CoreWLAN` (`CWWiFiClient`, `CWInterface`, `CWNetwork`, `CWEventDelegate`) |
| Ethernet | Link/IP detection, link speed, multi-adapter enumeration | `SystemConfiguration` (`SCDynamicStore`, `SCNetworkInterfaceCopyMediaOptions`) |
| Permissions | Wi-Fi scanning gate | `CoreLocation` (`CLLocationManager.requestWhenInUseAuthorization`) |
| Settings deep links | Forget Network, Open Network Settings, Open Privacy Settings | `x-apple.systempreferences:` URL scheme via `NSWorkspace.open` |
| Login Item | Launch at login | `ServiceManagement.SMAppService.mainApp` |
| Wi-Fi password storage | Keychain | `Security` framework (`kSecClassGenericPassword`, accessibility = `kSecAttrAccessibleAfterFirstUnlock`) |
| Logging | Diagnostic logs | `os.Logger` with `subsystem = bundleIdentifier` |
| App lifecycle | Foundation | `NSApplicationDelegate` (no SwiftUI `@main App` — menu-bar pattern requires AppKit-driven entry) |

**No third-party services.** No analytics SDK, no crash reporter, no telemetry endpoint. Sparkle 2 is the only external dependency and it talks only to the appcast URL (`talepstein.github.io/LinkHub/appcast.xml`).

### Update Strategy

| Item | Decision |
|---|---|
| Mechanism | Sparkle 2 (SPM) |
| Update channel | Direct from `https://talepstein.github.io/LinkHub/appcast.xml` |
| Signing | EdDSA signature on appcast items, public key in `Info.plist` (`SUPublicEDKey`) |
| Cadence | User-initiated check + automatic background check (Sparkle defaults) |
| Delta updates | Not in v1 — full DMG/ZIP each release |
| Rollback | None — users stay on current version if they decline an update |

### Offline Capabilities

LinkHub is **fully offline by design**. It manages local network interfaces, so it has no reason to make outbound HTTP calls of its own. The only network traffic the app generates:

- **Sparkle update checks** (background, infrequent — Sparkle's default cadence)
- **Captive portal probe** when user taps a captive Wi-Fi (`http://captive.apple.com`, opened in default browser, not by the app itself)

No telemetry, no crash reports, no remote config, no auth backend, no user accounts. The product works identically on a machine that has never had internet access (after install) — relevant for air-gapped or restricted environments.

### Code Signing & Distribution

| Item | Decision |
|---|---|
| Distribution channel | Direct download (DMG) from project site |
| Signing identity | Developer ID Application |
| Notarization | Required, via `notarytool`; ticket stapled to the app |
| Hardened Runtime | Enabled in Release; disabled in Debug |
| App Sandbox | **Disabled** — required because `CWWiFiClient.associate` is blocked under sandbox |
| Mac App Store | Out of scope for v1 (sandbox blocker) |
| Privacy manifest | `PrivacyInfo.xcprivacy` declares Location, UserDefaults, file timestamp, system boot time API usage |

### Implementation Considerations

- **Concurrency:** Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`). All AppKit and CoreWLAN interaction is `@MainActor`-isolated. `CWNetwork` and `SCNetworkInterface` are not `Sendable` — fields must be extracted to `Sendable` model structs (`WiFiNetwork`, `EthernetInterface`) before any actor hop. (PRD 03, 06, 07)
- **State model:** Single `@MainActor final class AppState: ObservableObject` with `@Published` properties driving SwiftUI views. No `@Observable` — macOS 13 deployment target predates it. (PRD 07)
- **Init order is load-bearing:** `StatusItemController` must subscribe before `AppState.startMonitors()` fires. Reversing order loses the first `connectionMode` event and leaves the icon wrong on launch. (PRD 07)
- **Event bridging:** SCDynamicStore C callbacks and CWEventDelegate callbacks bridge to `@MainActor` via `Task { @MainActor in ... }`. Debounce (300 ms) on the merged stream avoids icon flicker during interface flapping. (PRD 03)
- **No `@Observable` migration in v1.** Keep `ObservableObject + @Published` consistent across all monitor classes and `AppState`.
- **Resource discipline:** No timers running while popover is closed (Wi-Fi scans only on demand or via CWEventDelegate push events). (PRD 07)
- **Tear-down hygiene:** `CWWiFiClient.shared().delegate = nil` on app termination breaks a retain cycle; otherwise Instruments shows leaks. (PRD 03)

## Functional Requirements

### Menu Bar Presence

- **FR1:** The user can see a single LinkHub icon in the macOS menu bar at all times while the app is running.
- **FR2:** The system can display a Wi-Fi-style icon when no Ethernet interface has link, indicating Wi-Fi-only mode.
- **FR3:** The system can display an Ethernet-style icon when at least one Ethernet interface has link, indicating Ethernet-active mode.
- **FR4:** The system can display a disconnected-state icon when neither Wi-Fi nor Ethernet is providing connectivity.
- **FR5:** The system can update the menu bar icon within 1.5 seconds of a network state change (cable in, cable out, Wi-Fi join, Wi-Fi leave).
- **FR6:** The user can click the menu bar icon to open the LinkHub panel.
- **FR7:** The user can click the menu bar icon while the panel is open to dismiss it.
- **FR8:** A VoiceOver user can perceive the current connection state via the menu bar icon's accessibility label.

### Panel Display & Layout

- **FR9:** The user can see a popover panel anchored to the menu bar icon when LinkHub is opened.
- **FR10:** The user can dismiss the panel by pressing Escape.
- **FR11:** The user can dismiss the panel by clicking outside it.
- **FR12:** The system can present an Ethernet section above the Wi-Fi section whenever any Ethernet interface has link.
- **FR13:** The system can hide the Ethernet section when no Ethernet interface has had link for at least 1.5 seconds (grace period to absorb transient disconnects).
- **FR14:** The user can see the panel respect the active macOS appearance (light/dark mode) without per-app configuration.

### Ethernet Awareness

- **FR15:** The system can detect Ethernet interfaces present on the host, including USB-C/Thunderbolt dongles and Thunderbolt docks.
- **FR16:** The user can see, per Ethernet interface, the current operational state: Active, Obtaining address, DHCP timeout, or No link.
- **FR17:** The user can see the IPv4 address of any active Ethernet interface.
- **FR18:** The user can see the negotiated link speed of any active Ethernet interface, expressed in human-readable units (Mbps / Gbps).
- **FR19:** The user can see a human-readable display name for each Ethernet interface.
- **FR20:** The system can sort Ethernet interfaces with active interfaces first, ties broken by stable identifier order.
- **FR21:** The user can see a summary entry pointing to System Settings when more Ethernet interfaces exist than the panel displays inline.
- **FR22:** The user can open the macOS Network settings pane directly from the Ethernet section.

### Wi-Fi Network Discovery

- **FR23:** The user can see the list of nearby Wi-Fi networks discovered by the system.
- **FR24:** The user can see, per Wi-Fi network: SSID (or a "Hidden Network" label), signal strength, security marker (open / password-required / enterprise), and connected state.
- **FR25:** The user can see a captive-portal marker on networks that require sign-in.
- **FR26:** The user can request a fresh Wi-Fi scan on demand.
- **FR27:** The system can refresh the Wi-Fi network list automatically in response to system Wi-Fi events (SSID change, link change, signal change, power change).
- **FR28:** The user can see the currently connected Wi-Fi network distinguished from other networks in the list.

### Wi-Fi Connection Management

- **FR29:** The user can connect to an open Wi-Fi network by tapping its row.
- **FR30:** The user can connect to a password-protected Wi-Fi network by tapping its row, entering a password, and confirming.
- **FR31:** The system can store Wi-Fi passwords securely in the macOS Keychain so the user is not asked again for a known network.
- **FR32:** The user can connect to a hidden Wi-Fi network by entering an SSID and (if applicable) a password through a dedicated panel.
- **FR33:** The user can be routed to the system captive-portal flow when joining a captive network.
- **FR34:** The user can disconnect from the current Wi-Fi network by toggling Wi-Fi power off.
- **FR35:** The user can turn Wi-Fi power on or off.
- **FR36:** The user can initiate a "Forget This Network" action on a known Wi-Fi network, which routes them to the system Wi-Fi settings to complete removal.
- **FR37:** The user can see feedback identifying the failure cause when a Wi-Fi connection attempt fails: wrong password, out of range, association timeout, or authentication error.
- **FR38:** The user can open the macOS Wi-Fi settings pane directly from the Wi-Fi section.

### Permissions & First-Run Experience

- **FR39:** The system can request macOS Location authorization on first attempt to scan Wi-Fi, as required by Apple platform policy.
- **FR40:** The user can see an empty state when Location authorization is denied or restricted, identifying the cause and offering a one-tap path to the relevant Privacy settings.
- **FR41:** The system can resume Wi-Fi scanning automatically when Location authorization changes from denied to granted, without requiring an app restart.
- **FR42:** The system can launch without a modal onboarding flow; the panel itself is the introduction.

### Application Lifecycle & Persistence

- **FR43:** The user can configure LinkHub to launch automatically at login.
- **FR44:** The user can disable launch-at-login at any time without restarting the app.
- **FR45:** The system can run as a menu-bar-only app, with no Dock icon and no entry in the Cmd+Tab application switcher.
- **FR46:** The system can release Wi-Fi event subscriptions cleanly on app termination so the OS does not leak references to the app process.
- **FR47:** The system can persist the launch-at-login preference across reboots.

### Resource Discipline

- **FR48:** The system can run continuously in the background while consuming no more than 80 MB of resident memory at idle.
- **FR49:** The system can run continuously in the background while consuming no more than 0.5% CPU averaged over a 60-second idle window on Apple Silicon hardware.
- **FR50:** The system can avoid scheduled polling when the panel is closed, relying on system-pushed events for state changes.

### Distribution & Updates

- **FR51:** The user can install LinkHub from a downloaded disk image (DMG) signed for distribution outside the Mac App Store.
- **FR52:** The user can verify the app is properly notarized — macOS Gatekeeper does not warn or block on first launch.
- **FR53:** The system can check for software updates on a periodic background cadence and notify the user when an update is available.
- **FR54:** The user can manually trigger an update check.
- **FR55:** The user can install an update via the in-app update dialog, with cryptographic verification of the update artifact's authenticity.

### Accessibility

- **FR56:** A VoiceOver user can perceive every Wi-Fi network row's information (SSID, signal quality, security state, connected state) through accessibility labels.
- **FR57:** A VoiceOver user can perceive every Ethernet row's information (display name, status, IP, link speed) through accessibility labels.
- **FR58:** A VoiceOver user can perceive transitions between Wi-Fi-only, Ethernet-active, and disconnected states via accessibility announcements.

## Non-Functional Requirements

### Performance

- **NFR1:** The menu bar icon must update within 1.5 seconds of an underlying network state change (cable insert/remove, Wi-Fi associate/disassociate, Wi-Fi power toggle).
- **NFR2:** The popover panel must reach first paint with populated content within 200 ms of cold open (first open after launch) on Apple Silicon. Subsequent opens must paint within 100 ms.
- **NFR3:** A user-initiated Wi-Fi scan must return results within 5 seconds under normal RF conditions, or surface a visible scanning indicator until results arrive.
- **NFR4:** Panel transitions (Ethernet section show/hide, network list updates) must run at the display refresh rate without dropped frames on Apple Silicon.
- **NFR5:** Network state events arriving in rapid succession (e.g., USB-C dock wake fluttering interfaces) must not cause icon flicker — events must be debounced for at least 300 ms before driving a UI update.

### Reliability

- **NFR6:** The application must run continuously for at least 7 days without restart and without measurable resource drift (memory growth, FD leaks, CPU creep).
- **NFR7:** Crash-free session rate must be ≥ 99.5% across the first 30 days of release, measured via Sparkle telemetry and direct user reports.
- **NFR8:** Instruments runs (Allocations, Leaks, Time Profiler) over a 1-hour session of induced state changes (cable in/out, scans, panel open/close, sleep/wake) must show zero leaks attributable to LinkHub code.
- **NFR9:** The application must release CoreWLAN delegates and SCDynamicStore callbacks cleanly on termination so the host process exits without dangling references.
- **NFR10:** A failed Wi-Fi connection (wrong password, beacon drop, captive portal not navigable) must leave the app in a clean state — the user can retry the same network without restart.
- **NFR11:** The application must survive macOS sleep/wake cycles, Wi-Fi router resets, Ethernet dock reconnects, and VPN toggles without entering an unresponsive state — defined as: the panel must respond to a click within 1.5 s and the menu bar icon must update within 1.5 s of the next state change after the disturbance.

### Security

- **NFR12:** Wi-Fi passwords must be stored in the macOS Keychain using `kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlock`. They must never be persisted in `UserDefaults`, plain files, or in-memory beyond the duration of a connection attempt.
- **NFR13:** Distribution artifacts (DMG, .app) must be code-signed with a valid Apple Developer ID Application certificate.
- **NFR14:** All distribution artifacts must be notarized by Apple and have notarization tickets stapled to the app bundle.
- **NFR15:** The Hardened Runtime must be enabled in Release builds.
- **NFR16:** Sparkle update artifacts must be EdDSA-signed; the matching public key must be embedded in the app bundle's `Info.plist` (`SUPublicEDKey`) so updates with invalid signatures are rejected.
- **NFR17:** The app must request only the entitlements it functionally requires (`com.apple.security.personal-information.location`). The App Sandbox entitlement must remain disabled per the documented `CWWiFiClient.associate` constraint, but no other entitlement may be added without an explicit PRD amendment.
- **NFR18:** The privacy manifest (`PrivacyInfo.xcprivacy`) must declare every required-reason API the app uses (UserDefaults access, file timestamp, system boot time) and must remain in sync with the codebase.

### Privacy

- **NFR19:** The application must not collect, log, or transmit personally identifying information about the user, their networks, or their device — no telemetry, no analytics, no crash reports, no remote configuration.
- **NFR20:** The macOS Location authorization must be used solely for the purpose declared in `NSLocationWhenInUseUsageDescription` (Wi-Fi scanning) and must never be persisted to disk or transmitted off-device.
- **NFR21:** Wi-Fi network identifiers (SSID, BSSID, RSSI) must remain on-device. The app must make no outbound HTTP request that includes them.
- **NFR22:** The captive-portal handoff URL (`http://captive.apple.com`) must be opened via the user's default browser, not via an in-app web view, so cookies and credentials remain in their normal browser context.

### Accessibility

- **NFR23:** Every interactive control and informational row in the panel must expose an `accessibilityLabel` consumable by VoiceOver, with content specified per row type in NFR24–NFR25.
- **NFR24:** Wi-Fi rows' accessibility labels must include SSID, signal quality (excellent / good / fair / weak), security marker, and connected state.
- **NFR25:** Ethernet rows' accessibility labels must include display name, status, IP address (or "no IP"), and link speed.
- **NFR26:** Connection state transitions (Wi-Fi-only → Ethernet-active, → disconnected) must trigger `NSAccessibility` announcements so a VoiceOver user is informed of state changes happening outside the panel.
- **NFR27:** Decorative graphics (signal bars, status dots) must be marked `accessibilityHidden(true)` — their information must instead live in the parent row's combined label.
- **NFR28:** The panel and its interactive elements must respect the user's macOS Reduce Motion preference; pulsing/animation must be disabled when Reduce Motion is on.

### Compatibility

- **NFR29:** The app must build and run on macOS 13.0 (Ventura) and all later macOS releases through current.
- **NFR30:** The app must ship as a Universal binary supporting Apple Silicon (arm64) and Intel (x86_64).
- **NFR31:** The app must respect the active macOS appearance (Light, Dark, Auto) and use only system semantic colors — no hardcoded color values.
- **NFR32:** The app must respect the active macOS accent color where it exposes accent-colored elements (connected checkmark, footer links).
- **NFR33:** The build must produce zero Swift 6 strict concurrency warnings or errors in Release configuration.

### Maintainability

- **NFR34:** The codebase must follow the layer-based folder structure defined in PRD 01 (`App/`, `MenuBar/`, `Network/`, `UI/`, `State/`, `Services/`, `Utilities/`). New code must place itself by layer, not by feature.
- **NFR35:** All shared application state must flow through a single `@MainActor` observable state container. UI components must observe only that container, never the source monitors directly.
- **NFR36:** Every framework dependency must be either a system framework or a documented SPM dependency (currently: only Sparkle 2). No closed-source binary dependencies, no CocoaPods, no Carthage.
- **NFR37:** Diagnostic logging must use `os.Logger` with subsystem = `Bundle.main.bundleIdentifier`, so users and developers can filter LinkHub events with `log show --predicate 'subsystem == "com.talepstein.LinkHub"'`.
