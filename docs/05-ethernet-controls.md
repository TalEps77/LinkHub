# PRD 05 — Ethernet Status & Controls

**Status:** ✅ Done  
**Depends on:** 03, 04  
**Blocks:** 07

---

## Problem Statement

> What Ethernet information and controls does the panel expose per interface, how are multiple adapters sorted and capped, and what are the row states and error states?

This PRD decides:

- **`linkSpeed` field** — whether `EthernetInterface` gains a negotiated link-speed field, which API reads it, and what format it stores (resolves PRD 03 Open Question #1)
- **Section visibility trigger** — when `EthernetSection` appears and disappears relative to `hasLink` vs. `isActive` state (resolves PRD 04 Open Question #3)
- **Row states** — the four interface states (active, link-only/obtaining, DHCP timeout, no link) and how each is visually represented
- **Status indicator style** — dot color and animation semantics
- **Controls exposed** — whether a per-interface toggle is shown; which deeplink opens Network Settings
- **Multiple adapter sort order** — which three interfaces are shown; sort tiers; what the "+N more" overflow row does
- **`EthernetRow` component spec** — exact layout, hover, accessibility
- **`EthernetSection` component spec** — section structure, DHCP timer ownership, overflow footnote
- **Empty / error states** — "obtaining address" animation, DHCP timeout threshold and display

---

## Decision Log

| # | Decision | Options Considered | Choice | Rationale |
|---|-----------|--------------------|--------|-----------|
| 1 | **Add `linkSpeed` to `EthernetInterface`** | No (exclude); Yes via `SCNetworkInterfaceCopyMediaOptions`; Yes via IOKit | **Yes — `linkSpeed: Int?` (raw Mbps) via `SCNetworkInterfaceCopyMediaOptions`** | Negotiated speed (1 Gbps vs. 100 Mbps vs. 2.5 Gbps) is actionable status information — it tells the user whether their cable negotiated the expected rate. `SCNetworkInterfaceCopyMediaOptions` returns this synchronously from SystemConfiguration, which is already a project dependency (PRD 03). IOKit would add a new framework dependency for no additional capability. Display name (e.g., "USB 10/100/1000 LAN") implies hardware capability, not runtime negotiated speed — a Cat 5 cable into a 1 Gbps port negotiates 100 Mbps. Storing raw `Int?` Mbps keeps the model layer unit-independent; the view formats "1 Gbps" vs. "100 Mbps" as a computed display string. `linkSpeed` is `nil` when the interface has no link. |
| 2 | **Section visibility trigger (resolves PRD 04 Q3)** | Show only when `isActive == true`; Show when `hasLink == true`; Show when any interface detected | **Show `EthernetSection` when ANY interface has `hasLink == true`** | Gating on `isActive` hides the section during DHCP negotiation — the user plugs in a cable, sees nothing, then 5–15 seconds later the section suddenly appears. `hasLink` fires immediately on cable insertion (no IP required), giving instant visual feedback with a meaningful "Obtaining address…" row. This matches macOS Network preference pane behavior, which shows all interfaces with a link regardless of IP assignment state. |
| 3 | **Section hide delay when `hasLink` goes false** | Immediate; 300 ms (matches debounce); 1.5 s grace period | **1.5 s grace period before slide-out** | Transient disconnections (cable jiggle, USB hub power event) often resolve within 1 second. A 1.5 s delay prevents the section from disappearing and reappearing during these events. The 300 ms debounce at the monitor level (PRD 03) absorbs event bursts; 1.5 s at the UI level absorbs brief physical interruptions. Implemented as a cancellable `Task` in `ContentView` — if `hasLink` returns true before 1.5 s elapses, the pending hide is cancelled. |
| 4 | **Ethernet interface toggle (enable/disable)** | Toggle via `ifconfig en0 down/up` with SMJobBless privileged helper; Deprecated `AuthorizationExecuteWithPrivileges`; No toggle | **No toggle. Show "Open Network Settings…" only.** | `ifconfig` requires root. SMJobBless requires an installer package, a privileged helper binary, a separate code-signing certificate, additional entitlements, and ongoing macOS-version maintenance — disproportionate complexity for a rarely-used feature. `AuthorizationExecuteWithPrivileges` is deprecated since macOS 10.7 and unavailable to hardened-runtime apps (PRD 08). The user can toggle an interface in System Settings in two clicks. Excluding the toggle keeps the app sandboxable. |
| 5 | **"Open Network Settings…" URL scheme** | `x-apple.systempreferences:com.apple.preference.network` (legacy, macOS 13+); `x-apple.systempreferences:com.apple.Network-Settings.extension` (macOS 14 only) | **`x-apple.systempreferences:com.apple.preference.network`** | The legacy pane identifier continues to work on macOS 13 and 14 — Apple silently redirects it to the new System Settings location on Sonoma. The `Network-Settings.extension` identifier does not work on macOS 13 (Ventura). Using the older URL is the safest cross-version choice. Routing through `SystemSettingsService.openNetworkSettings()` (planned in PRD 01 layout) isolates the URL string from the UI layer. |
| 6 | **Status indicator style** | Colored text label only; SF Symbol; Filled circle dot (`circle.fill`, 8 pt) | **8 pt `circle.fill` dot, leading of display name** | Matches the style used in the macOS Network preference pane (green/orange/red dots). Small, unambiguous, and encodes state via color at a glance. Color semantics: `systemGreen` (active), `systemOrange` pulsing (obtaining address), `systemOrange` steady (DHCP timeout), `.secondary` (no link). SF Symbols like `ethernet` communicate interface type, not live state; combining them with colored dots at this panel size would be redundant and cluttered. |
| 7 | **Fields shown per row** | Name only; Name + IP; Name + IP + speed; Name + IP + speed + MAC | **displayName (primary label), IP or status text (secondary label), speed string (trailing, active state only)** | MAC address is developer/diagnostic info — not useful for everyday status monitoring. BSD name (`en0`, `en3`) is surfaced as an accessibility hint and tooltip only, not inline. Speed is meaningful only when the link is active; showing "1 Gbps" in a disconnected row is misleading. The trailing position for speed matches the PRD 04 wireframe (State A) and the system Network preference pane layout. |
| 8 | **Multiple adapter sort order** | BSD name only; Active first, then BSD name; Active → link-only → no-link, BSD name tiebreak | **Three-tier: Active (`isActive`) → Link-only (`hasLink`, no IP) → No-link; BSD name tiebreak within each tier** | Deterministic sort prevents the list from reordering when a second adapter toggles state, which would be disorienting. Active interfaces are most relevant and appear at the top. PRD 03's `NetworkState.ethernetInterfaces` comment already specifies "active first, then by BSD name" — this PRD makes the three-tier ordering explicit and normative for PRD 07's sort implementation. |
| 9 | **"+N more" overflow row** | Open Network Settings; Expand section (remove 3-row cap); Show count label only (no action) | **Tappable row "Open Network Settings to see N more…" → `SystemSettingsService.openNetworkSettings()`** | A dedicated "show all" view inside the panel would require a scroll region in the Ethernet section, which PRD 04 Decision #4 explicitly rejected. Network Settings shows the full interface list natively. Making the footnote tappable gives the user a direct path to the full list. The copy makes the count and the action legible together. |
| 10 | **"Obtaining address…" animation** | Static text only; Pulsing dot + static text; ProgressView spinner row | **Pulsing opacity on the `systemOrange` status dot + static "Obtaining address…" secondary label** | A `ProgressView` spinner occupies more horizontal space inside the compact row and introduces a second visual vocabulary alongside the dot metaphor. A pulsing dot stays within the established indicator system, communicates "in progress" without a separate control, and is compact. Implemented with `.animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)` on the dot's opacity (0.4 → 1.0). |
| 11 | **DHCP timeout threshold** | 15 s; 30 s; 60 s; No timeout | **30 seconds from `hasLink` becoming true while `isActive == false`** | DHCP exchanges typically complete in 1–4 seconds on local networks. 15 s is too aggressive — it may show an error during normal DHCP renewal or a slow DHCP server. 60 s is too long — the user is stuck watching "Obtaining address…" with no actionable feedback. 30 s matches the system Network pane's implicit "Self-assigned IP" timeout behavior. |
| 12 | **DHCP timeout error display** | Remain on "Obtaining address…"; Inline error text; Alert sheet | **Inline: `systemOrange` dot (non-pulsing) + "Unable to obtain address" secondary label** | An alert sheet disrupts the menu bar popover workflow. Keeping the error inline maintains structural consistency — same dot position and text slot as "Obtaining address…"; the dot stops pulsing to signal a terminal state. Orange (not red) because the interface still has a physical link; it is not a hardware failure. |

---

## `EthernetInterface` Model Update

PRD 03 Open Question #1 is resolved by Decision #1. `linkSpeed` is added to `EthernetInterface`.

### Updated `EthernetInterface.swift`

```swift
/// Snapshot of a single Ethernet adapter's state.
/// Produced by EthernetMonitor, consumed by AppState and UI.
/// Updated from PRD 03 definition: adds linkSpeed field (PRD 05, Decision #1).
struct EthernetInterface: Identifiable, Equatable, Sendable {

    /// BSD interface name, e.g. "en3". Stable identity for the duration of a session.
    let id: String

    /// Human-readable display name from IOKit / SCNetworkInterface,
    /// e.g. "USB 10/100/1000 LAN" or "Thunderbolt Ethernet Slot 1".
    /// Falls back to `id` if unavailable.
    let displayName: String

    /// True when the interface has a link (cable in) AND an assigned IP address.
    let isActive: Bool

    /// True when the physical cable is inserted, even if DHCP has not yet assigned an IP.
    let hasLink: Bool

    /// Primary IPv4 address, nil until DHCP/manual assignment completes.
    let ipv4Address: String?

    /// Hardware MAC address, formatted as "xx:xx:xx:xx:xx:xx". Nil if unreadable.
    let macAddress: String?

    /// Negotiated link speed in megabits per second (e.g. 100, 1000, 2500, 10000).
    /// Nil when the interface has no link or the speed cannot be determined.
    /// Read via SCNetworkInterfaceCopyMediaOptions on the active media subtype.
    let linkSpeed: Int?
}
```

### Reading `linkSpeed` via `SCNetworkInterfaceCopyMediaOptions`

Called inside `EthernetMonitor`'s re-enumeration block (on the SCDynamicStore dispatch queue, before the `Task { @MainActor in ... }` hop — `SCNetworkInterface` references are valid within the re-enumeration call scope):

```swift
// scInterface: SCNetworkInterface obtained from SCNetworkInterfaceCopyAll()
func readLinkSpeed(from scInterface: SCNetworkInterface) -> Int? {
    // Pass nil for the `active` and `options` output params — only `current` is needed.
    var currentPtr: Unmanaged<CFDictionary>?
    guard SCNetworkInterfaceCopyMediaOptions(scInterface, &currentPtr, nil, nil, false),
          let current = currentPtr?.takeRetainedValue() as? [String: AnyObject],
          let subtype = current[kSCPropNetEthernetMediaSubType as String] as? String
    else { return nil }
    return megabitsFromSubtype(subtype)
}

// Map SCNetworkInterface media subtype strings to raw Mbps.
// Common values from Apple's SystemConfiguration headers:
private func megabitsFromSubtype(_ subtype: String) -> Int? {
    let table: [String: Int] = [
        "10baseT/UTP": 10,    "10base5": 10,
        "100baseTX": 100,     "100baseFX": 100,
        "1000baseT": 1000,    "1000baseSX": 1000,   "1000baseLX": 1000,
        "2500baseT": 2500,
        "5000baseT": 5000,
        "10GbaseT": 10_000,   "10GbaseSR": 10_000,  "10GbaseLR": 10_000,
        "25GbaseSR": 25_000,
        "40GbaseSR4": 40_000,
        "100GbaseSR4": 100_000,
    ]
    return table[subtype]  // nil for unknown or "none"
}
```

### Display string helper (view layer — not part of the model)

Placed on `EthernetInterface` (not `Int`) to avoid polluting the global `Int` namespace.

```swift
// Defined in UI/Components/EthernetRow.swift as a local extension.
extension EthernetInterface {
    /// Formatted link speed string for display. Nil when linkSpeed is nil (no link).
    var linkSpeedDisplayString: String? {
        guard let speed = linkSpeed else { return nil }
        switch speed {
        case 10:       return "10 Mbps"
        case 100:      return "100 Mbps"
        case 1000:     return "1 Gbps"
        case 2500:     return "2.5 Gbps"
        case 5000:     return "5 Gbps"
        case 10_000:   return "10 Gbps"
        case 25_000:   return "25 Gbps"
        case 40_000:   return "40 Gbps"
        case 100_000:  return "100 Gbps"
        default:
            return speed >= 1000 ? "\(speed / 1000) Gbps" : "\(speed) Mbps"
        }
    }
}
```

`linkSpeed` is read once per re-enumeration event (triggered by `SCDynamicStore` Link/IPv4 callbacks). No separate polling for speed changes is needed — speed only changes when a new link is negotiated, which always triggers a Link callback.

---

## Row States

| State | `hasLink` | `isActive` | Dot color | Dot animation | Secondary label | Trailing |
|-------|-----------|------------|-----------|---------------|-----------------|---------|
| **Active** | `true` | `true` | `systemGreen` | Steady | IPv4 address | Speed string |
| **Link-only / Obtaining** (< 30 s) | `true` | `false` | `systemOrange` | Pulsing (0.4↔1.0) | "Obtaining address…" | — |
| **DHCP timeout** (≥ 30 s) | `true` | `false` | `systemOrange` | Steady | "Unable to obtain address" | — |
| **No link** | `false` | `false` | `.secondary` | Steady (dim) | "Disconnected" | — |

---

## Section Visibility Logic

`EthernetSection` is shown when `appState.ethernetInterfaces.contains { $0.hasLink }`. The 1.5 s hide-grace pattern lives in `ContentView` (or `RootPanelView`):

```swift
// In ContentView.swift — owns showEthernetSection state
@State private var showEthernetSection = false
// Task is Sendable; DispatchWorkItem is not — required by Swift 6 strict concurrency.
@State private var hideTask: Task<Void, Never>?

func updateEthernetVisibility(_ interfaces: [EthernetInterface]) {
    let shouldShow = interfaces.contains { $0.hasLink }

    if shouldShow {
        // Cancel any pending hide; show immediately.
        hideTask?.cancel()
        hideTask = nil
        if !showEthernetSection {
            withAnimation(.easeInOut(duration: 0.25)) {
                showEthernetSection = true
            }
        }
    } else {
        // Schedule hide after 1.5 s grace period.
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showEthernetSection = false
                }
            }
        }
    }
}
```

Called from `.onChange(of: appState.ethernetInterfaces)` in `ContentView`.

---

## `EthernetRow` Component Spec

**File:** `UI/Components/EthernetRow.swift`

### Layout

```
┌──────────────────────────────────────────────────────────┐  320 pt
│  ●  USB 10/100/1000 LAN       192.168.1.5       1 Gbps   │  ← Active
│  ◉  Thunderbolt Ethernet      Obtaining address…          │  ← Link-only (pulsing)
│  ◉  USB-C LAN                 Unable to obtain address    │  ← DHCP timeout (steady)
│  ○  USB-C Ethernet            Disconnected                │  ← No link
└──────────────────────────────────────────────────────────┘

● = systemGreen circle.fill (8 pt)
◉ = systemOrange circle.fill (8 pt, pulsing or steady per state)
○ = .secondary circle.fill (8 pt)

Horizontal padding:  16 pt (PanelLayout.rowHPad)
Vertical padding:    11 pt (PanelLayout.rowVPad)
Row height:          44 pt minimum (PanelLayout.rowHeight)
Dot-to-label gap:     8 pt
Hover overlay:       Color(nsColor: .controlAccentColor).opacity(0.12)
```

### SwiftUI Pseudocode

```swift
struct EthernetRow: View {

    let interface: EthernetInterface

    /// True when this interface has been in hasLink=true / isActive=false
    /// for ≥ 30 seconds. Owned by EthernetSection's timer logic.
    let isDHCPTimedOut: Bool

    @State private var isHovered = false
    @State private var pulse = false   // drives pulsing dot animation

    var body: some View {
        HStack(spacing: 8) {
            statusDot

            VStack(alignment: .leading, spacing: 2) {
                Text(interface.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(secondaryLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if interface.isActive, let speedStr = interface.linkSpeedDisplayString {
                Text(speedStr)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, PanelLayout.rowHPad)
        .padding(.vertical, PanelLayout.rowVPad)
        .frame(maxWidth: .infinity, minHeight: PanelLayout.rowHeight)
        .background(
            isHovered
                ? Color(nsColor: .controlAccentColor).opacity(0.12)
                : Color.clear
        )
        .onHover { isHovered = $0 }
        .onAppear { if isObtaining { pulse = true } }
        .onChange(of: isObtaining) { obtaining in
            pulse = obtaining
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(interface.id)   // BSD name as hint, e.g. "en3"
        // Note: Ethernet rows are intentionally not keyboard-focusable.
        // Read-only informational rows with no action create dead-end focus states.
        // VoiceOver navigation works via swipe (accessibilityElement conformance)
        // without requiring keyboard focus. This is the authoritative decision:
        // PRD 04 tab order omits Ethernet rows for the same reason.
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .opacity(isObtaining ? (pulse ? 1.0 : 0.4) : 1.0)
            .animation(
                isObtaining
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: pulse
            )
    }

    // MARK: - Derived state

    private var isObtaining: Bool {
        interface.hasLink && !interface.isActive && !isDHCPTimedOut
    }

    private var dotColor: Color {
        if interface.isActive  { return Color(nsColor: .systemGreen) }
        if interface.hasLink   { return Color(nsColor: .systemOrange) }
        return .secondary
    }

    private var secondaryLabel: String {
        if interface.isActive {
            return interface.ipv4Address ?? "Connected"
        } else if interface.hasLink {
            return isDHCPTimedOut
                ? "Unable to obtain address"
                : "Obtaining address\u{2026}"
        } else {
            return "Disconnected"
        }
    }

    // Accessibility label template from PRD 04: "name, status, IP, speed"
    private var accessibilityLabel: String {
        var parts = [interface.displayName]
        if interface.isActive {
            parts.append("connected")
            if let ip = interface.ipv4Address { parts.append(ip) }
            if let speedStr = interface.linkSpeedDisplayString {
                parts.append(speedStr)
            }
        } else if interface.hasLink {
            parts.append(
                isDHCPTimedOut ? "unable to obtain address" : "obtaining address"
            )
        } else {
            parts.append("disconnected")
        }
        return parts.joined(separator: ", ")
    }
}
```

---

## `SectionHeader` Component Spec

**File:** `UI/Components/SectionHeader.swift`

PRD 04's file table assigns `SectionHeader` to this PRD. It is a reusable label used by both `EthernetSection` and `WiFiSection`.

```swift
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PanelLayout.rowHPad)
            .padding(.vertical, PanelLayout.sectionHeaderVPad)
    }
}
```

`PanelLayout.sectionHeaderVPad` is defined in `UI/Theme.swift` (PRD 04). Value: `6 pt`.

---

## `EthernetSection` Component Spec

**File:** `UI/Panels/EthernetSection.swift`

```swift
/// Conditional top section of the panel. Shown when ≥ 1 Ethernet interface has a link.
/// Capped at 3 rows + optional "+N more" footnote (PRD 04 Decision #4).
struct EthernetSection: View {

    let interfaces: [EthernetInterface]   // Sorted by AppState (PRD 07; sort contract below)

    /// link-start timestamps keyed by interface BSD name.
    /// Drives DHCP timeout evaluation without polluting the model layer.
    @State private var linkStartDates: [String: Date] = [:]

    /// Updated every second by the timer; reading this in body (via isDHCPTimedOut) causes
    /// SwiftUI to re-evaluate the view on each tick. Replaces the non-functional timerTick
    /// pattern (an Int that was incremented but never read in body).
    @State private var currentDate: Date = Date()

    /// Fires every second to re-evaluate isDHCPTimedOut after the 30-second threshold.
    /// Timer.publish is used (not TimelineView, which requires macOS 14).
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Ethernet")

            ForEach(displayedInterfaces) { iface in
                EthernetRow(
                    interface: iface,
                    isDHCPTimedOut: isDHCPTimedOut(iface)
                )
            }

            if overflowCount > 0 {
                OverflowFootnote(count: overflowCount)
            }
        }
        .onAppear {
            updateLinkStartDates(interfaces)
            startTimer()
        }
        .onDisappear {
            timerCancellable?.cancel()
        }
        .onChange(of: interfaces) { newInterfaces in
            updateLinkStartDates(newInterfaces)
        }
    }

    // MARK: - Helpers

    private var displayedInterfaces: [EthernetInterface] {
        Array(interfaces.prefix(3))
    }

    private var overflowCount: Int {
        max(0, interfaces.count - 3)
    }

    private func isDHCPTimedOut(_ iface: EthernetInterface) -> Bool {
        guard iface.hasLink && !iface.isActive else { return false }
        guard let start = linkStartDates[iface.id] else { return false }
        // Uses currentDate (a @State var read in body) rather than Date() so that SwiftUI
        // re-evaluates this function every time the timer fires and currentDate updates.
        return currentDate.timeIntervalSince(start) >= 30
    }

    private func updateLinkStartDates(_ interfaces: [EthernetInterface]) {
        for iface in interfaces {
            if iface.hasLink && !iface.isActive {
                if linkStartDates[iface.id] == nil {
                    linkStartDates[iface.id] = Date()   // start DHCP clock
                }
            } else {
                linkStartDates.removeValue(forKey: iface.id)   // reset on resolve
            }
        }
        // Purge entries for interfaces no longer in the array (e.g. USB adapter unplugged).
        // Without this, re-plugging the same adapter inherits the stale start date.
        let currentIds = Set(interfaces.map(\.id))
        linkStartDates = linkStartDates.filter { currentIds.contains($0.key) }
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [self] date in
                // Assigning currentDate triggers body re-evaluation because currentDate
                // is read in isDHCPTimedOut, which is called from body. SwiftUI tracks
                // @State reads within body and re-renders when they change.
                currentDate = date
            }
    }
}

// MARK: - Overflow footnote

private struct OverflowFootnote: View {
    let count: Int

    var body: some View {
        Button("Open Network Settings to see \(count) more\u{2026}") {
            SystemSettingsService.openNetworkSettings()
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.accentColor)
        .padding(.horizontal, PanelLayout.rowHPad)
        .padding(.bottom, 6)
        .focusable()
    }
}
```

---

## `SystemSettingsService`

**File:** `Services/SystemSettingsService.swift` (planned in PRD 01 folder layout)

This is the canonical definition. PRD 06 contributes `openWiFiSettings()` and `openLocationPrivacySettings()`; all three methods are merged here.

```swift
/// Opens macOS system panels via URL scheme.
enum SystemSettingsService {

    /// Opens the Network panel in System Settings.
    /// Works on macOS 13 (Ventura) and macOS 14 (Sonoma).
    /// Apple silently redirects the legacy pane ID on Sonoma.
    static func openNetworkSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.network") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the Wi-Fi pane in System Settings.
    /// Tries the Ventura+ direct URL first; falls back to the legacy network pane.
    static func openWiFiSettings() {
        let primary  = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!
        let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.network")!
        if !NSWorkspace.shared.open(primary) {
            NSWorkspace.shared.open(fallback)
        }
    }

    /// Opens Privacy → Location Services in System Settings.
    /// Used by LocationDenialView.
    static func openLocationPrivacySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
        NSWorkspace.shared.open(url)
    }
}
```

`openNetworkSettings()` is also called from `WiFiSectionFooter`'s "Open Network Settings…" button (PRD 06) and from the Ethernet overflow footnote row above.

---

## Sort Contract (normative for PRD 07)

`AppState` must sort `ethernetInterfaces` before exposing them to `EthernetSection`. Sort is normative here; implementation lives in PRD 07:

```swift
// In AppState (PRD 07 implementation)
private func sortedEthernetInterfaces(
    _ interfaces: [EthernetInterface]
) -> [EthernetInterface] {
    interfaces.sorted { a, b in
        let tierA = ethernetSortTier(a)
        let tierB = ethernetSortTier(b)
        if tierA != tierB { return tierA < tierB }
        return a.id < b.id   // BSD name tiebreak (stable, deterministic)
    }
}

private func ethernetSortTier(_ iface: EthernetInterface) -> Int {
    if iface.isActive { return 0 }   // Tier 0: active (link + IP)
    if iface.hasLink  { return 1 }   // Tier 1: link-only (obtaining / error)
    return 2                          // Tier 2: no link
}
```

`EthernetSection` receives an already-sorted array; it does not sort internally.

---

## Constraints

- **No Ethernet toggle.** Enabling/disabling a network interface requires root. SMJobBless and `AuthorizationExecuteWithPrivileges` are excluded per PRD 08. No per-interface toggle is exposed.
- **`SCNetworkInterfaceCopyMediaOptions` returns `nil` when no link.** `linkSpeed` must always be `nil` in that case. Do not attempt to derive speed from the display name string.
- **DHCP timer is UI-layer state.** `linkStartDates` lives in `@State` inside `EthernetSection`, not in `EthernetInterface`. Model types are pure `Sendable` snapshots; elapsed-time tracking is a presentation concern. The timer resets when an interface resolves its IP or when the section disappears.
- **`Timer.publish(every: 1, ...)` for DHCP re-evaluation.** `TimelineView` requires macOS 14 and is therefore excluded (PRD 01 target is macOS 13). The 1 s timer fires even when no interface is in the "obtaining" state; overhead is negligible for a menu bar app. The timer is started in `.onAppear` and cancelled in `.onDisappear`.
- **Dot pulse animation lifecycle.** The `pulse` `@State` variable must be set to `true` only when `isObtaining` is true. Use `.onChange(of: isObtaining)` in addition to `.onAppear` to handle the case where an already-visible row transitions into the "obtaining" state (e.g., IP revoked while cable remains).
- **`SCNetworkInterface` references and threading.** `readLinkSpeed(from:)` must be called on the SCDynamicStore dispatch queue, before the `Task { @MainActor in ... }` hop. `SCNetworkInterfaceCopyAll()` returns a `CFArray` that retains its elements; individual `SCNetworkInterface` refs are valid for as long as that array is alive. Hold the array in a local variable, call `readLinkSpeed` while it is in scope, then let the array go. Never pass `SCNetworkInterface` references across the actor boundary — pass the extracted `Int?` value only.
- **Swift 6 strict concurrency.** `EthernetRow` and `EthernetSection` are SwiftUI `View` structs — `Sendable` by default. `@State` properties are MainActor-isolated within the view lifecycle. No cross-isolation concerns exist in the UI layer.
- **`SCNetworkInterfaceCopyMediaOptions` availability.** Available since macOS 10.6; no `@available` guard needed given PRD 01's macOS 13 deployment target.
- **`linkSpeed` not separately monitored.** Speed is read on every `EthernetMonitor` re-enumeration, which is triggered by SCDynamicStore Link/IPv4 callbacks. Link speed only changes when a new link is negotiated, which always triggers a Link callback — no extra polling is required.

---

## Out of Scope

- **Ethernet interface toggle (enable/disable)** — requires root; excluded per Decision #4; deferred indefinitely.
- **IPv6 address display** — `EthernetInterface.ipv4Address` is IPv4 only per PRD 03. IPv6 is a future enhancement via an additional `State:/Network/Interface/+/IPv6` key pattern.
- **Per-interface DHCP renew/release button** — too technical for a menu bar widget; accessible via Network Settings.
- **Link duplex information** (half/full duplex) — not shown. `SCNetworkInterfaceCopyMediaOptions` includes duplex in the options dictionary but it is not useful for end users at this panel size.
- **Ethernet interface ordering preference** — sort order (active first, BSD name tiebreak) is fixed; no drag-to-reorder.
- **Connection diagnostics** (ping, traceroute, DNS lookup) — out of scope for LinkHub's panel.
- **VLAN and bonded interfaces** — appear as standard `en*` interfaces from the OS perspective; no special handling beyond the existing SCDynamicStore type filter.
- **802.1X / enterprise Ethernet credential management** — handled by macOS built-in credential store; LinkHub does not configure or cache 802.1X credentials.
- **Ethernet-specific notifications** (e.g., OS-level alerts for IP conflict) — LinkHub displays state only; it does not generate system-level notifications.

---

## Open Questions

| # | Question | Impact | To resolve before |
|---|----------|--------|-------------------|
| 1 | Should the 1 s `Timer.publish` in `EthernetSection` be replaced with a `TimelineView` once the minimum deployment target is raised to macOS 14? | Minor: `TimelineView` is cleaner than a `Timer` + `AnyCancellable` for periodic re-render. No behavioral difference. | Any future PRD that raises the macOS deployment floor. |

---

## Verification

### DHCP Timer Unit Tests

`isDHCPTimedOut` computes `currentDate.timeIntervalSince(start) >= 30`. The `currentDate: Date` pattern is directly testable: in unit tests, set `currentDate` to a specific `Date` value before calling `isDHCPTimedOut`, rather than injecting a closure. This is simpler than a `now: () -> Date` closure and avoids adding a non-production parameter to the view.

Key scenarios:

| Scenario | Expected result |
|----------|----------------|
| `linkStartDates[id]` set 10 s ago, interface has link, no IP | `isDHCPTimedOut` → `false`; dot pulsing |
| `linkStartDates[id]` set 31 s ago, interface has link, no IP | `isDHCPTimedOut` → `true`; dot steady orange, "Unable to obtain address" |
| DHCP succeeds mid-wait (`isActive` becomes `true`) | `linkStartDates[id]` removed; row shows green dot + IP |
| USB adapter physically removed mid-DHCP | Interface disappears from array; `linkStartDates` purged by `currentIds` filter |
| Same adapter re-plugged after removal | New `linkStartDates[id]` set to `Date()`; timer resets from zero |

### Section Visibility Integration Tests

| Scenario | Expected result |
|----------|----------------|
| Cable inserted | `hasLink` → `true` within 300 ms; `EthernetSection` appears immediately |
| Cable unplugged | 1.5 s grace → section slides out; re-plugging within 1.5 s cancels the hide |
| `hideTask` cancelled before firing | Section stays visible; no spurious animation |

---

## References

- [Apple Developer: SCNetworkInterfaceCopyMediaOptions](https://developer.apple.com/documentation/systemconfiguration/1517322-scnetworkinterfacecopymediaoption) — Returns current negotiated media type; `kSCPropNetEthernetMediaSubType` dictionary key.
- [Apple Developer: kSCPropNetEthernetMediaSubType](https://developer.apple.com/documentation/systemconfiguration/kscpropnetethernetermediasubtype) — Media subtype string constants (e.g., `"1000baseT"`, `"100baseTX"`).
- [Apple Developer: SCNetworkInterface](https://developer.apple.com/documentation/systemconfiguration/scnetworkinterface) — `SCNetworkInterfaceCopyAll()`, `SCNetworkInterfaceGetInterfaceType()`, `SCNetworkInterfaceGetHardwareAddressString()`.
- [Apple Developer: NSWorkspace.open(_:)](https://developer.apple.com/documentation/appkit/nsworkspace/1527149-open) — Opens a URL; used for the System Settings deeplink.
- [Apple HIG: Menu bar extras — Popovers](https://developer.apple.com/design/human-interface-guidelines/menu-bar-extras) — Width guidance, section layout, material usage.
- [Apple HIG: Color — System colors](https://developer.apple.com/design/human-interface-guidelines/color#system-colors) — `systemGreen` and `systemOrange` semantic meanings in macOS UI.
- [Apple HIG: Accessibility — VoiceOver](https://developer.apple.com/design/human-interface-guidelines/accessibility#VoiceOver) — Label synthesis guidelines; accessibilityHint for supplementary info.
- [WWDC 2021: SwiftUI on the Mac: Build the fundamentals (session 10062)](https://developer.apple.com/videos/play/wwdc2021/10062/) — Row layouts, hover effects, and `.onHover` on macOS.
- [WWDC 2023: Animate with springs (session 10158)](https://developer.apple.com/videos/play/wwdc2023/10158/) — `repeatForever(autoreverses:)` animation patterns; easeInOut timing curves.
- [WWDC 2024: Migrate your app to Swift 6 (session 10169)](https://developer.apple.com/videos/play/wwdc2024/10169/) — `SCNetworkInterface` and `Sendable` value extraction before actor hops.
