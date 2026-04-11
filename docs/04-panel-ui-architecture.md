# PRD 04 — Panel UI Architecture

**Status:** ✅ Done  
**Depends on:** 01, 02  
**Blocks:** 05, 06

---

## Problem Statement

> What technology, layout contract, sizing strategy, and behavioral rules govern the dropdown
> panel that appears when the menu bar item is clicked?

This PRD decides:

- **Hosting technology** — whether to use `NSHostingController` directly or wrap
  `NSHostingView` in a plain `NSViewController`; how `AppState` is injected into the
  SwiftUI hierarchy (resolves PRD 02 Open Question #1)
- **Panel width** — fixed vs. variable; exact value
- **Panel height strategy** — fixed vs. adaptive; mechanism for communicating SwiftUI content
  height back to `NSPopover.contentSize`; minimum and maximum bounds
- **Section layout contract** — which sections exist, their order, when each is visible,
  spacing and divider rules, scrollability
- **Section visibility rules** — the exact conditions under which the Ethernet section
  appears or disappears; behavior when both, one, or neither network type is active
- **Empty / disconnected state** — what the panel shows when there is no network at all
- **Appearance** — NSPopover background material, color strategy, dark/light mode
- **Open/close animation** — NSPopover built-in vs. custom; in-panel transitions when
  sections appear or disappear
- **Size-change behavior** — what happens visually when the Ethernet section is added or
  removed dynamically

---

## Decision Log

| # | Decision | Options Considered | Choice | Rationale |
|---|----------|--------------------|--------|-----------|
| 1 | **Hosting controller type** | `NSHostingController<ContentView>` directly; `NSViewController` subclass wrapping `NSHostingView` | **`NSHostingController<AnyView>`** wrapping the preference-change modifier chain | `NSHostingController` is the proper AppKit-integrated view controller for SwiftUI. It correctly wires the responder chain, focus ring, safe area, and SwiftUI environment. An extra `NSViewController` wrapper adds boilerplate with no benefit. The root view is type-erased to `AnyView` so that `PopoverController` can hold a typed stored property without carrying a complex generic parameter. |
| 2 | **AppState injection** | `@EnvironmentObject` via `.environmentObject()` modifier; direct `@ObservedObject` parameter; `@StateObject` owned by ContentView | **Direct `@ObservedObject var appState: AppState` parameter, passed at `NSHostingController` construction time** | `@StateObject` is wrong here — the hosting controller (not SwiftUI) owns `AppState`'s lifetime. `@EnvironmentObject` works but fails at runtime without the modifier and is harder to test. An explicit `@ObservedObject` parameter is type-safe, explicit, and easily testable without a host app. |
| 3 | **Panel width** | 280 pt; 300 pt; 320 pt; 340 pt | **Fixed 320 pt** | Apple's own Wi-Fi menu bar popover is ~320 pt wide on Ventura/Sonoma. 320 pt accommodates a 15-character SSID + signal icon + lock icon on one line without truncation at the system font size. A full IPv4 address (`255.255.255.255`) also fits in the Ethernet section without truncation. Width never changes — `NSPopover.contentSize.width = 320` is set once at init. |
| 4 | **Panel height strategy** | Fixed height; fully adaptive via SwiftUI `fixedSize`; adaptive with clamp via `PreferenceKey` | **Adaptive with height clamp via `ContentSizePreferenceKey`** | A fixed height wastes space when only Wi-Fi is shown and clips content when many networks appear. `fixedSize` does not propagate back through `NSHostingController` to `NSPopover.contentSize` automatically. A `PreferenceKey` that reads `GeometryReader` size and calls `popover.contentSize = …` from `PopoverController` is the established SwiftUI/AppKit pattern for this problem. |
| 5 | **Panel height bounds** | Min 120/Max 480; Min 160/Max 500; Min 200/Max 520 | **Min 200 pt, max 520 pt** | 200 pt is the minimum that renders the Wi-Fi section header + one network row + footer controls without clipping. 520 pt fits comfortably on a 768 pt display (MacBook Air 13-inch default scaling) with the menu bar occupying ~24 pt. Wi-Fi lists taller than the available height become scrollable (Decision #9). |
| 6 | **Ethernet section visibility** | Always visible; visible only when link is up; visible when any interface is detected (even link-down) | **Visible whenever `appState.ethernet` is non-empty** | An `EthernetInterface` enters the array when the OS reports the interface present, before link negotiation. Showing the section with a "Cable unplugged" state is more informative than hiding it — the user can see the adapter is detected. Hiding a present adapter on cable-unplug produces a jarring layout jump. PRD 05 owns what is rendered per interface state. |
| 7 | **Section order** | Ethernet above Wi-Fi always; Wi-Fi above Ethernet; dynamic reorder by active state | **Ethernet always above Wi-Fi** | PLAN.md specifies: "the panel presents Ethernet status/controls first, followed by Wi-Fi networks and controls." A static order prevents the panel from restructuring under the user's cursor when network state changes. |
| 8 | **Divider between sections** | No divider; `Divider()` when both visible; always-present headers act as separator | **`Divider()` between sections when both are visible; section header labels always present** | A divider provides clear visual separation between sections of different types. Section headers ("ETHERNET", "WI-FI") in small-caps secondary text mirror the system Wi-Fi menu style and aid VoiceOver navigation. Both together follow macOS HIG list conventions. |
| 9 | **Wi-Fi list scrollability** | Whole panel scrollable; only Wi-Fi list rows scrollable; no scroll, fixed list height | **Only the Wi-Fi network list rows are in a `ScrollView`; Ethernet section and panel footer are outside it** | Scrolling the entire panel moves headers and controls out of view. The Ethernet section (typically 1–2 rows) needs no scroll. Isolating the scroll region to the Wi-Fi network list matches the system Wi-Fi menu behavior. |
| 10 | **Panel background material** | Custom `NSVisualEffectView` with `.sidebar` material; default NSPopover vibrancy; plain fill | **Default NSPopover vibrancy — no custom material** | `NSPopover` already applies the system popover material (translucent vibrancy, correct for menu bar extras). Overriding it requires replacing the popover's backing view layer — fragile across OS updates. SwiftUI content inside adapts to `NSApp.effectiveAppearance` automatically. |
| 11 | **Color / typography strategy** | Hard-coded light/dark values; SwiftUI semantic colors; mixed | **SwiftUI semantic colors throughout** (`Color.primary`, `Color.secondary`, `Color(.tertiaryLabelColor)`, `Color.accentColor`) | Semantic colors adapt automatically to light mode, dark mode, and high-contrast mode. Hard-coded literals break in high-contrast mode and on custom accent colors. Never use `Color(red:green:blue:)` literals inside panel views. |
| 12 | **Open/close animation** | `NSPopover.animates = false`; `NSPopover.animates = true` (default) | **`NSPopover.animates = true` (default, unchanged)** | AppKit's built-in scale-in/scale-out animation matches the system Wi-Fi menu exactly. No benefit to overriding it. |
| 13 | **In-panel transition on section change** | No animation; `.animation(.default)`; explicit `.transition(.opacity)` | **`.transition(.opacity).animation(.easeInOut(duration: 0.2))`** on the Ethernet `VStack` | A 0.2 s opacity fade is subtle and non-distracting. It is shorter than the 300 ms debounce window (PRD 03), so no transition is ever interrupted by a second event. Panel height animates via AppKit's implicit `contentSize` animation — no additional SwiftUI animation on height is needed. |
| 14 | **Empty / disconnected state** | Individual sections own empty states; dedicated full-panel `DisconnectedView`; small placeholder row | **`DisconnectedView` when `appState.ethernet.isEmpty && appState.wifi == .disabled`; otherwise sections own their own empty states** | When neither Wi-Fi hardware nor Ethernet hardware is detected, there is no meaningful sectioned content. A single `DisconnectedView` (icon + message + "Open Network Settings" button) is cleaner than two empty sections. All other partial states — Wi-Fi not associated, Ethernet link-down — are owned by the respective section PRDs. |
| 15 | **Panel footer** | No footer; per-section footer; shared footer with "Open Network Settings" | **Shared `PanelFooterView` always rendered below all sections** | "Open Network Settings" applies to the whole app, not a specific interface. A single shared footer avoids duplicating the button in both sections and matches the system Wi-Fi menu layout. The footer is outside the `ScrollView`. When `DisconnectedView` is shown, the footer is suppressed to avoid showing two identical "Open Network Settings" buttons. |

---

## View Hierarchy

```
ContentView  (@ObservedObject appState: AppState)
└── VStack(spacing: 0)
    │
    ├── if !appState.ethernet.isEmpty
    │       EthernetSection(interfaces: appState.ethernet)   ← PRD 05
    │           .transition(.opacity)
    │           .animation(.easeInOut(duration: 0.2), value: appState.ethernet.isEmpty)
    │
    ├── if !appState.ethernet.isEmpty && appState.wifi != .disabled
    │       Divider()
    │           .padding(.vertical, PanelLayout.dividerVerticalPadding)
    │
    ├── if appState.ethernet.isEmpty && appState.wifi == .disabled
    │       DisconnectedView()
    │
    ├── else   // at least one of ethernet or wifi is available
    │       WiFiSection(status: appState.wifi)               ← PRD 06
    │
    └── if !(appState.ethernet.isEmpty && appState.wifi == .disabled)
            Divider()
            PanelFooterView()
```

**Sub-components (stubs — internals owned by PRDs 05 and 06):**

```
EthernetSection
├── SectionHeaderView(title: "ETHERNET")
└── ForEach(interfaces) { EthernetRowView(interface:) }     // PRD 05

WiFiSection
├── SectionHeaderView(title: "WI-FI")
├── ScrollView {
│       // network list rows                                 // PRD 06
│   }
│   .frame(maxHeight: scrollableListMaxHeight)              // PRD 06 decides exact value
└── WiFiFooterControlsView()                                // PRD 06

DisconnectedView
├── Image(systemName: "wifi.slash")  +  label
└── Button("Open Network Settings…") { SystemSettingsService.openNetworkSettings() }

PanelFooterView
└── Button("Open Network Settings…") { SystemSettingsService.openNetworkSettings() }
    .padding(.vertical, PanelLayout.footerVerticalPadding)
```

All of the above, plus the `GeometryReader` preference reporter, are composed in `ContentView.swift`:

```swift
struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // ... sections per hierarchy above ...
        }
        .frame(width: 320)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: ContentSizePreferenceKey.self, value: geo.size)
            }
        )
    }
}
```

---

## Sizing Contract

### Width

| Property | Value |
|----------|-------|
| `ContentView` fixed frame width | 320 pt |
| `NSPopover.contentSize.width` | 320 pt (set once at init, never changes) |

### Height

| Property | Value |
|----------|-------|
| Minimum clamped height | 200 pt |
| Maximum clamped height | 520 pt |
| Default initial height (before first layout pass) | 300 pt |
| Re-measured | On every SwiftUI layout pass that produces a different total height |

### `ContentSizePreferenceKey`

Lives in `UI/Components/PanelLayout.swift`:

```swift
/// Propagates the SwiftUI content height back to PopoverController.
struct ContentSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
```

### `PopoverController` sizing update

`PopoverController` attaches the preference observer at construction time:

```swift
// PopoverController.init(appState:)
let rootView = ContentView(appState: appState)
    .onPreferenceChange(ContentSizePreferenceKey.self) { [weak self] size in
        self?.updatePopoverSize(size)
    }
hostingController = NSHostingController(rootView: AnyView(rootView))
popover.contentViewController = hostingController
popover.contentSize = CGSize(width: 320, height: 300)   // initial size
```

```swift
// PopoverController
@MainActor
private func updatePopoverSize(_ size: CGSize) {
    let clamped = min(max(size.height, 200), 520)
    guard abs(popover.contentSize.height - clamped) > 0.5 else { return }
    popover.contentSize = CGSize(width: 320, height: clamped)
}
```

The `0.5 pt` guard prevents a feedback loop: floating-point rounding in the layout pass can
cause the height to oscillate between two nearly-equal values, producing a visible shimmer.

---

## Section Header Convention

All section headers use a shared component that matches macOS system menu style:

```swift
// UI/Components/SectionHeaderView.swift
struct SectionHeaderView: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color(.tertiaryLabelColor))
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PanelLayout.horizontalPadding)
            .padding(.top, PanelLayout.sectionHeaderTopPadding)
            .padding(.bottom, PanelLayout.sectionHeaderBottomPadding)
    }
}
```

---

## Spacing & Padding Tokens

Defined in `UI/Components/PanelLayout.swift` as a caseless enum namespace:

```swift
enum PanelLayout {
    static let horizontalPadding: CGFloat        = 16   // left/right inset for content rows
    static let rowHeight: CGFloat                = 44   // minimum tappable height
    static let sectionHeaderTopPadding: CGFloat  = 12   // space above section header text
    static let sectionHeaderBottomPadding: CGFloat = 4  // space between header and first row
    static let footerVerticalPadding: CGFloat    =  8   // top/bottom inside footer
    static let dividerVerticalPadding: CGFloat   =  4   // padding above/below inter-section Divider
}
```

---

## Appearance Rules

| Rule | Specification |
|------|---------------|
| Background material | NSPopover default vibrancy. Do not set a custom `NSVisualEffectView`. |
| Text colors | SwiftUI semantic only: `Color.primary`, `Color.secondary`, `Color(.tertiaryLabelColor)` |
| Icon colors | `Color.primary` for template SF Symbols; `Color.accentColor` for tinted interactive icons |
| Interactive controls | `Color.accentColor` for tinted buttons and toggles |
| High-contrast mode | Semantic colors adapt automatically; no `@Environment(\.colorScheme)` branching needed |
| Dark mode | NSPopover and SwiftUI content adapt via `NSApp.effectiveAppearance`. No explicit dark-mode overrides. |
| Hard-coded color literals | **Forbidden** inside any view in `UI/`. Use semantic colors or asset catalog named colors only. |

---

## Constraints

- **macOS 13.0 minimum**: `PreferenceKey`, `GeometryReader`, `.onPreferenceChange`, and
  `NSHostingController` are all fully stable on macOS 13. No back-deployment needed.
- **`NSHostingController` generic type erasure**: `NSHostingController` is generic over
  `<Content: View>`. Wrapping the root view in `AnyView` allows `PopoverController` to
  hold `var hostingController: NSHostingController<AnyView>?` without leaking the concrete
  type into `PopoverController`'s public interface.
- **`popover.contentSize` is not animatable via SwiftUI**: The height change is applied by
  AppKit with its own implicit animation when `popover.animates = true`. Do not wrap
  `updatePopoverSize` in a `withAnimation` block — it has no effect and can cause double animation.
- **Preference key feedback loop**: The `0.5 pt` guard in `updatePopoverSize` is required.
  Without it, floating-point precision causes the popover height to oscillate on every layout
  pass, producing a visible shimmer on macOS 13.
- **ScrollView height inside a preference-sized popover**: The Wi-Fi `ScrollView` must have a
  bounded `maxHeight`. An unbounded `ScrollView` reports its scroll-content height as its
  preferred size, which would keep the panel at 520 pt even for a two-item list. PRD 06
  decides the exact `maxHeight` value (see Open Question #2).
- **`@ObservedObject` lifetime**: `AppState` is owned by `AppDelegate` and lives for the full
  duration of the process. The `@ObservedObject` reference in `ContentView` is safe — there is
  no scenario in which `AppState` is deallocated before the view hierarchy.
- **Swift 6 strict concurrency**: `ContentSizePreferenceKey.reduce` runs during the SwiftUI
  layout pass on the main actor. `.onPreferenceChange` dispatches its closure on the main actor.
  `PopoverController` is `@MainActor` (established in PRD 02). No concurrency special-casing
  is needed for the sizing path.

---

## Out of Scope

- **What `EthernetSection` renders per interface** (IP address row, link-speed badge,
  "Cable unplugged" state, toggle control) — owned by PRD 05.
- **What `WiFiSection` renders** (network list rows, signal bars, connect/disconnect flow,
  scan controls, password prompt) — owned by PRD 06.
- **`AppState` concurrency model** (`@Observable` macro vs. `ObservableObject` + `@Published`) —
  owned by PRD 07. PRD 04 uses `@ObservedObject` as the binding mechanism; PRD 07 may
  change the macro without altering the view hierarchy.
- **Permissions prompt and first-launch UX** — owned by PRD 08.
- **Keyboard navigation within the panel** (Tab between rows, arrow-key Wi-Fi selection) —
  deferred to PRD 06 for Wi-Fi rows. Not required by Apple HIG for menu bar popovers.
- **Custom `NSPanel` subclass** — this architecture uses `NSPopover` exclusively as decided
  in PRD 02. No `NSPanel` consideration is needed.
- **Window dragging / popover detach** — `NSPopover` in `.transient` mode cannot be dragged
  or detached; no decision required.
- **Touch Bar** — discontinued with M-series MacBook Pro before LinkHub's target OS.

---

## Open Questions

| # | Question | Owner PRD |
|---|----------|-----------|
| 1 | When Wi-Fi hardware is present but not associated (`wifi == .notAssociated`) AND no Ethernet is detected, should the panel show `WiFiSection` (with an empty/scanning network list) or `DisconnectedView`? The current rule shows `WiFiSection` in this case — is an empty list a better affordance than the disconnected screen? | PRD 06 |
| 2 | What is the exact `maxHeight` for the Wi-Fi `ScrollView`? The available height depends on the Ethernet section height (variable, based on number of interfaces). Should Wi-Fi use a fixed upper bound (e.g. 260 pt), or dynamically compute remaining height using a second `PreferenceKey` from `EthernetSection`? | PRD 06 |
| 3 | Should `PanelFooterView` be suppressed when `DisconnectedView` is shown? `DisconnectedView` already contains an "Open Network Settings" button — showing a second identical button in the footer would be redundant. The current hierarchy suppresses the footer in this case, but the `DisconnectedView` copy of the button may also be redundant if the footer always shows. | Resolve at first UI coding session. |

---

## References

- [Apple Developer: NSHostingController](https://developer.apple.com/documentation/swiftui/nshostingcontroller) — SwiftUI root view controller for AppKit containers; correct type for `popover.contentViewController`.
- [Apple Developer: NSPopover](https://developer.apple.com/documentation/appkit/nspopover) — `contentSize`, `animates`, `contentViewController`.
- [Apple Developer: PreferenceKey](https://developer.apple.com/documentation/swiftui/preferencekey) — Protocol for propagating values up the SwiftUI view tree.
- [Apple Developer: GeometryReader](https://developer.apple.com/documentation/swiftui/geometryreader) — Reading layout-pass frame sizes in SwiftUI.
- [Apple HIG: Menu bar extras](https://developer.apple.com/design/human-interface-guidelines/menu-bar-extras) — Panel width conventions, list layout, footer button placement.
- [Apple HIG: Lists and tables — macOS](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) — Row height (44 pt minimum), section header typography.
- [Apple HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color) — Semantic color usage, high-contrast requirements, dark mode guidance.
- [WWDC 2021: SwiftUI on the Mac: Build the fundamentals (session 10062)](https://developer.apple.com/videos/play/wwdc2021/10062/) — `NSHostingController` integration patterns; `PreferenceKey` for size communication back to AppKit.
- [WWDC 2024: Migrate your app to Swift 6 (session 10169)](https://developer.apple.com/videos/play/wwdc2024/10169/) — `@MainActor` isolation for AppKit types; directly applicable to `PopoverController.updatePopoverSize`.
