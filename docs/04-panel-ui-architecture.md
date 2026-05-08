# PRD 04 — Panel UI Architecture

**Status:** ✅ Done  
**Depends on:** 01, 02  
**Blocks:** 05, 06

---

## Problem Statement

> What technology, layout contract, sizing strategy, and behavioral rules govern the
> dropdown panel that appears when the menu bar item is clicked?

This PRD decides:

- **Popover sizing strategy** — fixed vs. adaptive width, height bounds, how the panel
  grows when many Wi-Fi networks are listed, and where `ScrollView` boundaries sit
- **Layout structure** — Ethernet vs. Wi-Fi section ordering, section headers, dividers,
  spacing conventions, and empty/error states
- **SwiftUI vs. AppKit boundary** — which layer owns which responsibility; whether any
  component requires AppKit on macOS 13
- **Dark/light mode and accent color** — which system materials and semantic colors to use
- **Animation and transitions** — how list updates and section show/hide animate
- **Accessibility** — VoiceOver labels, signal-strength descriptions, keyboard navigation

---

## Decision Log

| # | Decision | Options Considered | Choice | Rationale |
|---|----------|--------------------|--------|-----------|
| 1 | **Popover width** | Adaptive (grows with longest SSID); fixed 280 pt; fixed 320 pt; fixed 360 pt | **320 pt fixed** | Matches the width of the macOS Ventura/Sonoma system Wi-Fi popover. Adaptive width causes jarring horizontal reflows as networks appear. SSIDs longer than ~26 characters are truncated with an ellipsis — acceptable because the connected SSID is always fully readable in the status item tooltip. |
| 2 | **Popover height strategy** | Fully fixed (320 × 480); fully adaptive (no cap); adaptive with cap | **Adaptive, capped at 520 pt** — `NSHostingController.sizingOptions = .intrinsicContentSize` auto-sizes; outer `VStack` has `.frame(maxHeight: 520)` | A fixed height wastes space for short network lists and clips long ones. Fully adaptive can push the panel off-screen on laptops with a small menu bar. 520 pt fits comfortably above the menu bar at 1080 p and above; the scrollable Wi-Fi list absorbs any overflow without the panel growing further. |
| 3 | **Wi-Fi network list scrolling** | No scroll (truncate list); full-panel scroll; scroll only the network rows | **ScrollView wrapping only the Wi-Fi network rows, `.frame(maxHeight: 220)`** (~5 rows visible at 44 pt each) | Keeping headers, the Ethernet section, and footer actions outside the scroll region preserves their visibility at all times — consistent with the system Control Center panel. 220 pt ≈ 5 rows is enough for the common case (home networks); the full scan result is still reachable by scrolling. |
| 4 | **Ethernet section scrolling** | Scroll if >3 interfaces; never scroll; show all | **Never scroll; cap display at 3 interfaces; show "+N more" footnote if overflow** | Users rarely have more than 2 active Ethernet interfaces (built-in + one USB-C dongle). Showing 3 covers essentially all real-world cases. A "+2 more" note with a "Open Network Settings…" link handles edge cases without a second scroll region in the panel. |
| 5 | **Section layout order** | Wi-Fi top, Ethernet bottom; Ethernet top, Wi-Fi bottom; Ethernet top only when active | **Ethernet section top (conditional) → `Divider` → Wi-Fi section (always)** | PLAN.md is normative: "When Ethernet is active the panel presents Ethernet status/controls first, followed by Wi-Fi." Ethernet is the differentiating feature of LinkHub — surfacing it first matches the product identity and mirrors the priority expressed by the icon-swap logic in PRD 02. |
| 6 | **SwiftUI vs. AppKit for panel content** | Pure SwiftUI; AppKit sub-views for signal bars and row highlights; hybrid per component | **100% SwiftUI inside the `NSHostingController` boundary** | SwiftUI on macOS 13 supports `Canvas`, `Path`, custom gestures, `.onHover`, `Toggle(.switch)`, and `List`/`ForEach`-style layout — all required components. Custom signal-strength bars are straightforward `HStack` + `RoundedRectangle` in SwiftUI. No AppKit sub-view is needed. The AppKit boundary is `NSPopover` → `NSHostingController<RootPanelView>` only. |
| 7 | **`NSHostingController` vs. `NSViewController` wrapping `NSHostingView`** | `NSHostingController`; `NSViewController` + `NSHostingView` | **`NSHostingController<RootPanelView>`** | Resolves PRD 02 Open Question #1. `NSHostingController` is the canonical SwiftUI-in-AppKit integration point; it handles environment propagation (color scheme, accent color, locale) automatically. `NSHostingView` requires manual environment injection. |
| 8 | **`NSHostingController.sizingOptions`** | Default (fixed); `.intrinsicContentSize`; `.preferredContentSize` | **`.intrinsicContentSize`** | Available since macOS 13. Automatically propagates the SwiftUI layout's measured size to `NSPopover.contentSize`. The `VStack` `.frame(maxWidth: 320, maxHeight: 520)` clamps the reported intrinsic size — no manual `contentSize` updates required in `PopoverController`. The initial size set in PRD 02 (`320 × 480`) remains valid as a pre-show default. |
| 9 | **Panel background / material** | Explicit `.regularMaterial`; `.menu` material via `NSVisualEffectView`; inherit from `NSPopover` | **Inherit from `NSPopover` — no explicit background modifier on `RootPanelView`** | `NSPopover` already applies the `.popover` vibrancy material to its content view, which renders correctly in both light and dark mode. Adding a second `.background(.regularMaterial)` layered inside would double-apply the effect, producing a washed-out appearance. The root SwiftUI view must have a **transparent** background (default). |
| 10 | **Row hover highlight** | None; `.listRowBackground` on hover; custom `onHover` overlay | **`Color(nsColor: .controlAccentColor).opacity(0.12)` overlay on `.onHover`** | Matches the hover style of system preference panes and the Finder sidebar — a subtle tinted wash rather than a full opaque fill. `.controlAccentColor` automatically reflects the user's chosen accent color, respects dark mode, and requires no hardcoded hex values. |
| 11 | **Connected network row highlight** | Bold text only; checkmark only; checkmark + accent row background | **Checkmark (SF Symbol `checkmark`) in accent color + `.fontWeight(.semibold)` SSID label** | Matches the system Wi-Fi menu convention precisely: a checkmark left-aligned, slightly bolder SSID text, no filled row background. A filled background would visually conflict with the hover highlight (both using accent color). |
| 12 | **Section header style** | All-caps `.caption` + `.secondary`; mixed-case `.headline`; no headers | **Mixed-case `.subheadline` weight `.semibold` + `.foregroundStyle(.secondary)`, left-aligned** | Matches macOS Ventura Control Center section headers ("Wi-Fi", "Bluetooth"). All-caps reads as shouting inside a small panel. `.subheadline` is legible at the panel width without dominating the content rows. |
| 13 | **Dividers and spacing** | `Divider()` between all rows; only between sections; no dividers | **`Divider()` between sections only; no dividers between individual network rows** | The system Wi-Fi menu uses no inter-row dividers — rows rely on consistent row height and hover highlight to define boundaries. Dividers between sections clearly delineate Ethernet from Wi-Fi. Row padding: 11 pt top/bottom, 16 pt leading/trailing. |
| 14 | **Wi-Fi network list row insert/remove animation** | No animation (instant); fade only; slide + fade | **`.animation(.easeInOut(duration: 0.2), value: networks)`** on the `ForEach` container | Instant updates are jarring when scan results refresh — rows jump into position. A 0.2 s ease-in-out is fast enough to not feel sluggish, smooth enough to signal change. `value: networks` scopes the animation to list changes only, preventing unrelated state changes from triggering it. |
| 15 | **Ethernet section show/hide animation** | No animation; fade only; slide from top + fade | **`.transition(.opacity.combined(with: .move(edge: .top)))` + `.animation(.easeInOut(duration: 0.25), value: showEthernetSection)`** | A fade-only transition is disorienting — the Wi-Fi section appears to jump upward. Sliding the Ethernet section in from the top communicates that new content was inserted above. 0.25 s is slightly longer than row animations to emphasize the structural change. |
| 16 | **Keyboard navigation** | SwiftUI default focus only; custom `FocusState` ring; full tab-order override | **SwiftUI default focus system with explicit `.focusable()` on interactive rows and controls** | macOS 13 SwiftUI's focus engine supports tab navigation between focusable controls. Marking the Wi-Fi toggle, each network row, "Other Networks…", and "Open Network Settings…" as `.focusable()` provides correct tab order without building a custom focus ring. The popover's first focusable element (Wi-Fi toggle) receives focus automatically on open. |
| 17 | **Empty state — no networks found** | Hide list entirely; show spinner; show placeholder text row | **Placeholder row: SF Symbol `wifi.slash` + text "No Networks Found"** in the list area | Matches system Wi-Fi menu convention. A spinner is misleading if scanning completed but returned zero results. Hiding the list collapses the panel to an unexpected size. |
| 18 | **Empty state — scanning in progress** | No indicator; spinner in header; spinner row in list | **`ProgressView()` inline row at the top of the network list, below the connected network (if any)** | The connected network (if any) remains visible during a re-scan. A ProgressView spinner row communicates "loading more" rather than "empty". Matches the Bluetooth panel's scan-in-progress treatment. |
| 19 | **Empty state — Wi-Fi disabled** | Show empty list; hide list and show text; collapse Wi-Fi section | **Collapse network list; show single text row: "Turn on Wi-Fi to see nearby networks."** | Identical to the system Wi-Fi menu's disabled-state copy. Collapsing the list prevents wasted whitespace and makes the disabled state unambiguous. |
| 20 | **Accent color scope** | System accent only; hardcoded blue; configurable per user preference | **System accent color (`Color.accentColor`) exclusively** — no hardcoded color values | `Color.accentColor` respects the user's System Preferences choice (blue, graphite, green, etc.) and automatically adapts to dark mode. Hardcoding blue breaks for graphite users. No preference UI for a custom accent color is needed. |
| 21 | **Login-item toggle placement** | Preferences window (no window exists); Settings tab in popover; Footer of WiFiSection | **Footer of `WiFiSectionFooter`** — a `Toggle("Launch at Login", isOn: $appState.launchAtLogin)` below the two button rows | The popover has no separate preferences window (PRD 04 Out of Scope). Adding a footer toggle keeps login-item control accessible without a separate window. The toggle is always visible at the bottom of the panel. |

---

## Layout Structure

### Component Hierarchy

```
RootPanelView                          ← VStack, width: 320, maxHeight: 520
├── EthernetSection                    ← conditional (shown when ≥1 Ethernet interface active)
│   ├── SectionHeader("Ethernet")
│   └── ForEach(interfaces, max 3)
│       └── EthernetRow               ← defined in PRD 05
│   └── ["+N more" footnote]           ← shown if >3 interfaces
├── Divider()                          ← shown only when EthernetSection is visible
└── WiFiSection                        ← always visible
    ├── WiFiSectionHeader              ← label + Toggle (Wi-Fi on/off)
    ├── ScrollView (maxHeight: 220)
    │   └── VStack(spacing: 0)
    │       ├── [ProgressView row]     ← shown during scan
    │       ├── NetworkRow (isConnected: true)  ← shown when associated (checkmark + semibold)
    │       ├── ForEach(otherNetworks)
    │       │   └── NetworkRow        ← defined in PRD 06
    │       └── [EmptyStateRow]       ← "No Networks Found" or "Turn on Wi-Fi…"
    └── WiFiSectionFooter
        ├── "Other Networks…"          ← hidden network join flow (PRD 06)
        ├── "Open Network Settings…"   ← calls SystemSettingsService (PRD 05/06)
        └── Toggle("Launch at Login", isOn: $appState.launchAtLogin)   ← Decision #21
```

### Spacing Constants

```swift
// Defined in UI/Theme.swift (new file)
enum PanelLayout {
    static let panelWidth: CGFloat     = 320
    static let panelMaxHeight: CGFloat = 520
    static let rowHeight: CGFloat      = 44
    static let rowHPad: CGFloat        = 16    // leading/trailing
    static let rowVPad: CGFloat        = 11    // top/bottom
    static let networkListMaxHeight: CGFloat = 220   // ~5 rows
    static let sectionHeaderVPad: CGFloat = 8
}
```

---

## ASCII Wireframes

### State A — Ethernet active + Wi-Fi networks present

```
┌────────────────────────────────────────┐  320 pt
│                                        │
│  Ethernet                              │  ← SectionHeader (.subheadline/.secondary)
│  ┌──────────────────────────────────┐  │
│  │ ◉  en0      192.168.1.5  1 Gbit │  │  ← EthernetRow (connected, green dot)
│  └──────────────────────────────────┘  │
│  ┌──────────────────────────────────┐  │
│  │ ○  en3      Disconnected         │  │  ← EthernetRow (no link, grey dot)
│  └──────────────────────────────────┘  │
│                                        │
│ ────────────────────────────────────── │  ← Divider
│                                        │
│  Wi-Fi                       ●──○      │  ← WiFiSectionHeader + Toggle (on)
│                                        │
│  ✓  HomeNetwork       ████  🔒        │  ← NetworkRow(isConnected: true) — checkmark + semibold
│     ⋯ scanning…                        │  ← ProgressView row (during re-scan)
│  ─────────────────────────────────     │
│     GuestNetwork      ███░  🔒        │  ┐
│     CoffeeWifi        ██░░            │  │  network rows (ScrollView)
│     Neighbor5G        █░░░  🔒        │  │
│     OpenNet           █░░░            │  ┘
│                                        │
│  Other Networks…                       │  ← footer
│  Open Network Settings…                │
│                                        │
└────────────────────────────────────────┘
  (height ≈ 420 pt in this state)
```

### State B — Wi-Fi only (no Ethernet)

```
┌────────────────────────────────────────┐  320 pt
│                                        │
│  Wi-Fi                       ●──○      │  ← WiFiSectionHeader + Toggle (on)
│                                        │
│  ✓  HomeNetwork       ████  🔒        │  ← NetworkRow(isConnected: true)
│     GuestNetwork      ███░  🔒        │  ┐
│     CoffeeWifi        ██░░            │  │  network rows (ScrollView)
│     Neighbor5G        █░░░  🔒        │  │
│     OpenNet           █░░░            │  ┘
│                                        │
│  Other Networks…                       │
│  Open Network Settings…                │
│                                        │
└────────────────────────────────────────┘
  (height ≈ 300 pt in this state)
```

### State C — Wi-Fi disabled

```
┌────────────────────────────────────────┐  320 pt
│                                        │
│  Wi-Fi                       ○──●      │  ← Toggle (off)
│                                        │
│     Turn on Wi-Fi to see              │  ← EmptyStateRow
│     nearby networks.                  │
│                                        │
│  Open Network Settings…                │
│                                        │
└────────────────────────────────────────┘
  (height ≈ 160 pt in this state)
```

### State D — Scanning, no results yet

```
┌────────────────────────────────────────┐  320 pt
│                                        │
│  Wi-Fi                       ●──○      │  ← Toggle (on)
│                                        │
│     ◌  Searching for networks…        │  ← ProgressView + label
│                                        │
│  Other Networks…                       │
│  Open Network Settings…                │
│                                        │
└────────────────────────────────────────┘
  (height ≈ 180 pt in this state)
```

---

## SwiftUI / AppKit Boundary

```
PopoverController (AppKit / @MainActor)
└── NSHostingController<RootPanelView>
      sizingOptions = [.intrinsicContentSize]
      └── RootPanelView (SwiftUI)            ← BOUNDARY
            ├── EthernetSection (SwiftUI)    — defined in PRD 05
            └── WiFiSection (SwiftUI)        — defined in PRD 06
```

**Why nothing needs AppKit below the boundary on macOS 13:**

| UI Need | SwiftUI Solution | AppKit needed? |
|---------|-----------------|---------------|
| Signal strength bars | `HStack` of `RoundedRectangle` shapes | No |
| Row hover highlight | `.onHover` + `@State var isHovered` overlay | No |
| Wi-Fi on/off toggle | `Toggle(isOn:)` with `.toggleStyle(.switch)` | No |
| Animated list updates | `ForEach` + `.animation(_:value:)` | No |
| Section slide-in | `.transition(.opacity.combined(with: .move))` | No |
| Keyboard focus ring | `.focusable()` + SwiftUI focus engine | No |
| Lock icon | `Image(systemName: "lock.fill")` SF Symbol | No |
| Progress spinner | `ProgressView()` | No |

---

## Dark / Light Mode

`NSPopover` sets the `NSAppearance` of its content view to match the menu bar's current appearance (dark or light). SwiftUI's `@Environment(\.colorScheme)` reflects this automatically. No manual appearance switching is needed.

**Semantic color usage (normative):**

| Element | SwiftUI Color | Rationale |
|---------|---------------|-----------|
| Primary text (SSID, IP) | `.primary` | Adapts to dark/light automatically |
| Secondary text (speed, signal dBm) | `.secondary` | System-standard muted label |
| Section headers | `.secondary` | Matches Control Center header style |
| Row hover overlay | `Color(nsColor: .controlAccentColor).opacity(0.12)` | Accent-aware, not hardcoded |
| Connected row checkmark | `Color.accentColor` | Matches system Wi-Fi menu |
| Connected SSID | `.primary` + `.fontWeight(.semibold)` | Differentiated without color |
| Signal bar fill (active) | `.primary` | High contrast, mode-agnostic |
| Signal bar fill (inactive) | `.primary.opacity(0.25)` | Standard inactive-segment opacity |
| Ethernet status dot (up) | `Color(nsColor: .systemGreen)` | System semantic green |
| Ethernet status dot (down) | `.secondary` | Neutral for disconnected |
| Footer actions | `.accentColor` | Tappable link convention |
| Lock icon | `.secondary` | Non-primary; supplementary info |

**Do not use:**
- Hardcoded hex colors
- `.white` / `.black` directly
- `.menu` or `.hudWindow` NSVisualEffectView materials — `NSPopover` already provides `.popover` material

---

## Animation Specification

### Network list row insertion / removal

```swift
// In WiFiSection body
ForEach(networks) { network in
    NetworkRow(network: network)
}
.animation(.easeInOut(duration: 0.2), value: networks)
```

- Duration: 0.2 s — fast enough to not feel slow; smooth enough to track insertion
- Curve: `easeInOut` — consistent with system list animations
- Scope: `value: networks` — only the `networks` array change triggers this animation; unrelated state mutations (e.g., signal RSSI update on an existing row) do not

### RSSI / signal strength updates on existing rows

No animation. RSSI changes on an already-visible row update instantly. Animating bar-fill changes every few seconds would create visual noise.

### Ethernet section show / hide

```swift
// In RootPanelView body
if showEthernetSection {
    EthernetSection(interfaces: ethernetInterfaces)
        .transition(.opacity.combined(with: .move(edge: .top)))
    Divider()
        .transition(.opacity)
}
// ...
.animation(.easeInOut(duration: 0.25), value: showEthernetSection)
```

- Duration: 0.25 s — slightly longer than row animations; structural change deserves more emphasis
- `Divider` fades independently (`.opacity` only) so it doesn't slide in a confusing direction

### Popover resize

Handled automatically. When `EthernetSection` appears/disappears or the network list changes length within the scroll cap, `NSHostingController.sizingOptions = .intrinsicContentSize` propagates the new intrinsic size to `NSPopover.contentSize`. `NSPopover` animates the frame change natively — no manual `contentSize` mutation needed.

---

## Accessibility

### VoiceOver labels

**Network row** (`accessibilityLabel` synthesis, normative):

```swift
// Example: "HomeNetwork, signal excellent, password required, connected"
// Example: "GuestNetwork, signal good, open network"
// Example: "FarRouter, signal weak, password required"

var accessibilityLabel: String {
    var parts: [String] = [network.ssid]
    parts.append(network.rssi.signalQuality.accessibilityDescription)
    parts.append(network.requiresPassword ? "password required" : "open network")
    if network.isConnected { parts.append("connected") }
    return parts.joined(separator: ", ")
}
```

**Signal quality descriptor mapping (`RSSI → String`):**

| RSSI range (dBm) | `signalQuality` | `accessibilityDescription` |
|------------------|-----------------|---------------------------|
| ≥ −60 | `.excellent` | `"signal excellent"` |
| −61 … −70 | `.good` | `"signal good"` |
| −71 … −80 | `.fair` | `"signal fair"` |
| < −80 | `.weak` | `"signal weak"` |

**Lock icon** — not separately focusable; its meaning is expressed in the row's `accessibilityLabel` ("password required" / "open network").

**Signal bar view** — `.accessibilityHidden(true)`. Signal strength information is communicated through the row label, not the graphical bars.

**Wi-Fi toggle** — standard SwiftUI `Toggle` accessibility: `accessibilityLabel("Wi-Fi")` explicit.

**Ethernet row** — `accessibilityLabel`: `"\(interfaceName), \(status), \(ipAddress ?? "no IP address"), \(speed ?? "")"`. Example: `"en0, connected, 192.168.1.5, 1 Gigabit"`.

### Keyboard navigation

- Tab order: Wi-Fi toggle → connected network row → other network rows (top to bottom) → "Other Networks…" → "Open Network Settings…" → "Launch at Login" toggle. Ethernet rows are not keyboard-focusable (see Decision #16 rationale and PRD 05 note) and are therefore omitted from tab order.
- All rows are `.focusable()`. Focus ring rendered by SwiftUI's default system.
- `Return` / `Space` on a network row triggers the primary action (connect or show info).
- `Escape` closes the popover (handled by the local key monitor in `PopoverController` per PRD 02).
- `Tab` within the popover cycles through focusable controls without closing the popover.

---

## File Ownership

| File | Responsibility |
|------|---------------|
| `UI/PopoverRootView.swift` | `RootPanelView` — top-level `VStack`, conditional Ethernet section, `Divider`, `WiFiSection`; hosts the `showEthernetSection` animation logic |
| `UI/Panels/EthernetSection.swift` | `EthernetSection` — Ethernet rows, "+N more" footnote; consumes `SectionHeader` from `UI/Components/` — defined in PRD 05 |
| `UI/Panels/WiFiSection.swift` | `WiFiSection`, `WiFiSectionHeader`, `WiFiSectionFooter` — defined in PRD 06 |
| `UI/Components/` | `NetworkRow` (handles both connected and unconnected states via `isConnected` property — no separate `ConnectedNetworkRow` type), `EthernetRow`, `SignalBarsView`, `SectionHeader` — each in its own file |
| `UI/Theme.swift` | `PanelLayout` constants enum (widths, heights, padding) |
| `MenuBar/PopoverController.swift` | `NSHostingController<RootPanelView>`, `sizingOptions = .intrinsicContentSize`, initial `contentSize` |

---

## Constraints

- **`NSHostingController.sizingOptions`** is available since macOS 13 — no back-deployment shim needed given PRD 01's deployment target.
- **`NSPopover` must remain the sizing authority.** Do not call `popover.contentSize =` after initial setup. `sizingOptions = .intrinsicContentSize` takes over; manual mutations race with SwiftUI layout.
- **Swift 6 strict concurrency:** `RootPanelView` and all child views are SwiftUI `View` structs — value types, implicitly `Sendable`. The `AppState` reference passed in must remain `@MainActor`-isolated per PRD 07.
- **No `List` view.** SwiftUI `List` on macOS 13 applies its own background and separator styling that conflicts with the popover material and cannot be fully suppressed without private API. Use `ScrollView` + `ForEach` + `VStack(spacing: 0)` with explicit row backgrounds.
- **`.animation(_:value:)` over `.withAnimation`.** Using the `value:`-parameterised modifier prevents unintended animation of unrelated state mutations. `.withAnimation` blocks in callbacks can fire on the wrong change.
- **No `NavigationStack` inside the popover.** Navigation-driven flows (captive portal, hidden network join) must be implemented as sheet presentations from the popover or as separate windows — not `NavigationStack` push, which is unsupported inside `NSPopover` on macOS 13.
- **`sizingOptions` and initial `contentSize` coexistence.** `NSHostingController.sizingOptions = .intrinsicContentSize` overrides the `contentSize` property after the first layout pass. Setting an initial `contentSize = CGSize(width: 320, height: 480)` in `PopoverController` (per PRD 02) is still required to avoid a 0×0 first-show flash; SwiftUI corrects it on the first layout cycle.

---

## Out of Scope

- **Per-section controls and data** (IP display format, Ethernet toggle, Wi-Fi connect flow, password sheet) — decided in PRDs 05 and 06.
- **`AppState` concurrency model** (`@Observable` vs. `ObservableObject`) — decided in PRD 07. This PRD treats `AppState` as an opaque observable object passed by reference.
- **Login-item preference toggle** in the panel — placement decided in Decision #21: `Toggle("Launch at Login")` in `WiFiSectionFooter`. Implementation in PRD 08.
- **Settings / preferences window** — LinkHub has no separate preferences window; all controls live in the popover.
- **Custom window shadows or vibrancy overrides** — `NSPopover`'s defaults are correct; no customisation needed.
- **Right-to-left layout** — `.leading`/`.trailing` alignment is used throughout (no hardcoded `.left`/`.right`), so RTL adaptation is inherited for free when/if needed.
- **Dynamic Type / font size preferences** — macOS menu bar panels do not respond to Accessibility font size preferences; the panel uses fixed `.subheadline` / `.body` / `.caption` sizes per system convention.

---

## Open Questions

All questions resolved.

| # | Question | Resolution | Resolved in |
|---|----------|-----------|-------------|
| 1 | Should `RootPanelView` receive `AppState` as an `@EnvironmentObject` or as a direct `@ObservedObject` constructor argument? | `@EnvironmentObject` via `.environmentObject(appState)` at `NSHostingController` creation site. Child views declare `@EnvironmentObject var appState: AppState`. No prop-drilling through `RootPanelView`. | PRD 07 Decision #3 |
| 2 | Does the "Other Networks…" footer row open a sheet presented from the popover or trigger a standalone `NSWindow`? | `NSPanel` — `OtherNetworkPanel` (`NSPanel` subclass with `isFloatingPanel = true`, `becomesKeyOnlyIfNeeded = true`). Sheet from `NSPopover` is unsupported on macOS 13. `NavigationStack` push is unsupported inside `NSPopover`. Details in `UI/Windows/OtherNetworkPanel.swift`. | PRD 06 Decision #11 |
| 3 | Is the Ethernet section always shown for *all* Ethernet interfaces (including those with no IP — only a link) or only for interfaces with an active IP? | Section shown for link-only interfaces too. Visibility trigger: `hasLink == true` (not `isActive == true`). Row shows a "no IP" state for link-only interfaces. Details in PRD 05 Decision #2. | PRD 05 Decision #2 |

---

## Acceptance Criteria

- [ ] `RootPanelView` lives in `UI/PopoverRootView.swift` and renders as a `VStack` with `frame(width: 320, maxHeight: 520)`.
- [ ] `NSHostingController.sizingOptions = [.intrinsicContentSize]` — not `.preferredContentSize`.
- [ ] `RootPanelView` has no explicit `.background()` modifier — background is transparent; no double-material wash in dark mode.
- [ ] Ethernet section renders above the `Divider` and Wi-Fi section when ≥1 Ethernet interface has `hasLink == true`. Hidden (with animation) otherwise.
- [ ] `EthernetSection` show/hide uses `.transition(.opacity.combined(with: .move(edge: .top)))` + `.animation(.easeInOut(duration: 0.25), value: showEthernetSection)`.
- [ ] Wi-Fi network list is in a `ScrollView` with `frame(maxHeight: 220)`. Panel height adapts; scrollable region never exceeds 220 pt.
- [ ] `ForEach(networks)` animates with `.animation(.easeInOut(duration: 0.2), value: networks)`. RSSI updates on existing rows do not trigger animation.
- [ ] Row padding: 11 pt top/bottom, 16 pt leading/trailing (matches `PanelLayout.rowVPad` / `PanelLayout.rowHPad`).
- [ ] Section headers use `.subheadline` + `.fontWeight(.semibold)` + `.foregroundStyle(.secondary)`, left-aligned.
- [ ] Connected network row shows `checkmark` SF Symbol in `Color.accentColor` + `.fontWeight(.semibold)` SSID label. No filled row background.
- [ ] Hover highlight: `Color(nsColor: .controlAccentColor).opacity(0.12)` overlay on `.onHover`. No hardcoded hex colors anywhere in the panel.
- [ ] State C (Wi-Fi off): network list collapses; shows single text row "Turn on Wi-Fi to see nearby networks."; "Other Networks…" footer is hidden.
- [ ] State D (scanning, no results): `ProgressView()` inline row visible; "No Networks Found" placeholder not simultaneously shown.
- [ ] `PanelLayout` constants enum exists in `UI/Theme.swift` with all six values: `panelWidth`, `panelMaxHeight`, `rowHeight`, `rowHPad`, `rowVPad`, `networkListMaxHeight`, `sectionHeaderVPad`.
- [ ] No `List` view anywhere in the panel hierarchy.
- [ ] No `NavigationStack` inside the popover.
- [ ] VoiceOver: network row `accessibilityLabel` reads "[SSID], signal [excellent|good|fair|weak], [password required|open network][, connected]".
- [ ] Signal bar view is `.accessibilityHidden(true)`. Wi-Fi `Toggle` has explicit `.accessibilityLabel("Wi-Fi")`.
- [ ] Tab order: Wi-Fi toggle → connected network row → other network rows (top to bottom) → "Other Networks…" → "Open Network Settings…" → "Launch at Login" toggle. Ethernet rows are not `.focusable()` and are omitted.
- [ ] `UI/Components/SectionHeader.swift` exists as a standalone reusable component; not duplicated inside `EthernetSection.swift`.
- [ ] No separate `ConnectedNetworkRow` type exists; `NetworkRow` handles both states via an `isConnected` property.

---

## References

- [Apple Developer: NSHostingController](https://developer.apple.com/documentation/swiftui/nshostingcontroller) — SwiftUI root view controller; `sizingOptions` property (macOS 13+).
- [Apple Developer: NSPopover](https://developer.apple.com/documentation/appkit/nspopover) — `contentSize`, `behavior`, vibrancy material.
- [Apple Developer: NSVisualEffectView.Material.popover](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material/popover) — The material `NSPopover` applies automatically.
- [Apple Developer: Color.accentColor](https://developer.apple.com/documentation/swiftui/color/accentcolor) — System-resolved accent color in SwiftUI.
- [Apple Developer: AccessibilityFocus (SwiftUI)](https://developer.apple.com/documentation/swiftui/accessibilityfocusstate) — Focus management within SwiftUI views.
- [Apple HIG: Menu bar extras — Popovers](https://developer.apple.com/design/human-interface-guidelines/menu-bar-extras) — Width guidance, section layout, material usage.
- [Apple HIG: Color — System colors](https://developer.apple.com/design/human-interface-guidelines/color#system-colors) — Semantic color list; `systemGreen`, `controlAccentColor`.
- [Apple HIG: Accessibility — VoiceOver](https://developer.apple.com/design/human-interface-guidelines/accessibility#VoiceOver) — Label synthesis guidelines; avoid redundant role announcements.
- [WWDC 2021: SwiftUI on the Mac: Build the fundamentals (session 10062)](https://developer.apple.com/videos/play/wwdc2021/10062/) — `List` vs. `ScrollView+ForEach` trade-offs on macOS.
- [WWDC 2022: Compose custom layouts with SwiftUI (session 10056)](https://developer.apple.com/videos/play/wwdc2022/10056/) — `ViewThatFits`, `VStack` intrinsic size; relevant to popover auto-sizing.
- [WWDC 2023: Animate with springs (session 10158)](https://developer.apple.com/videos/play/wwdc2023/10158/) — Animation curve guidance; `easeInOut` vs. spring for list transitions.
