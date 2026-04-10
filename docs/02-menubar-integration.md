# PRD 02 — Menu Bar Integration

**Status:** ✅ Done  
**Depends on:** 01  
**Blocks:** 04

---

## Problem Statement

> How should LinkHub integrate with the macOS menu bar — lifecycle of the NSStatusItem,
> panel presentation approach, icon asset strategy, and the trigger contract for switching
> between Wi-Fi and Ethernet icons?

This PRD decides:

- **NSStatusItem lifecycle** — where and how the status item is created, retained, and
  torn down; what happens on login-item launch vs. normal launch
- **Panel presentation** — `NSMenu` vs. custom `NSPanel` vs. `NSPopover` attached to the
  status item; how the popover is dismissed (click-outside, Escape, second click on icon)
- **Icon asset pipeline** — SF Symbols vs. custom vector assets in `Assets.xcassets`;
  how icon variants (Wi-Fi active, Ethernet active, both active, disconnected) are named
  and loaded
- **Icon-swap trigger contract** — the exact signal (event type, data shape, caller) that
  causes the status item image to switch between representations; who owns this logic
- **Accessibility** — `accessibilityLabel` values for the status item in each state;
  VoiceOver announcement strategy when the icon changes

---

## Decision Log

| # | Decision | Options Considered | Choice | Rationale |
|---|----------|--------------------|--------|-----------|
| 1 | **NSStatusItem creation site** | `AppDelegate.applicationDidFinishLaunching`; lazy on first click; dedicated factory | `StatusItemController.init(appState:)` called from `AppDelegate.applicationDidFinishLaunching(_:)` | The status item must exist from first launch — there is no deferred use-case. Placing creation inside `StatusItemController` keeps lifecycle logic encapsulated in one file (`MenuBar/StatusItemController.swift`) and keeps `AppDelegate` thin. |
| 2 | **NSStatusItem length** | `NSStatusItem.squareLength`; `NSStatusItem.variableLength` | `NSStatusItem.variableLength` | Template SF Symbol images are 17 pt; `variableLength` sizes the item to the image width automatically. `squareLength` (22 pt) wastes horizontal space when the icon is narrower. |
| 3 | **NSStatusItem retention** | Local variable (leaks); stored on `AppDelegate`; stored on `StatusItemController` | Stored as `let statusItem: NSStatusItem` on `StatusItemController`, which is stored as `var statusItemController: StatusItemController?` on `AppDelegate` | `NSStatusItem` is not automatically retained by `NSStatusBar` on macOS 14+ — the caller must hold a strong reference. Two-level ownership (controller owns item, delegate owns controller) mirrors Apple's sample code and prevents accidental deallocation. |
| 4 | **Login-item launch behaviour** | Detect launch source and alter startup path; identical path for all launches | Identical `applicationDidFinishLaunching` path regardless of launch source | macOS 13+ `SMAppService.mainApp` launches the app exactly as if the user double-clicked it; `applicationDidFinishLaunching` fires normally. `LSUIElement = true` suppresses any visible activation. No special branch is needed. |
| 5 | **NSStatusItem teardown** | `applicationWillTerminate` only; `deinit` on controller; explicit `tearDown()` | `StatusItemController.tearDown()` called from `AppDelegate.applicationWillTerminate(_:)` | `deinit` timing is non-deterministic under ARC and can run after `NSStatusBar` is torn down. An explicit `tearDown()` called from a known lifecycle hook is predictable. `tearDown()` calls `NSStatusBar.system.removeStatusItem(statusItem)` and cancels all Combine subscriptions via `cancellables.removeAll()`. |
| 6 | **Panel presentation technology** | `NSMenu` (native dropdown); custom `NSPanel`; `NSPopover` | `NSPopover` hosting `NSHostingView<ContentView>` | `NSMenu` cannot host arbitrary SwiftUI — only text and action items. LinkHub needs signal-strength bars, IP addresses, and toggle controls that are impossible in `NSMenu` without undocumented hacks. A custom `NSPanel` requires manual positioning relative to the status item rect, custom vibrancy material, shadow management, and window-ordering code — `NSPopover` provides all of that natively with ~10 lines. `NSPopover` is the established AppKit idiom for rich menu-bar UI (used by Xcode's source control popover, Apple's own Clock popover on Ventura+). |
| 7 | **NSPopover dismissal — click outside / app switch** | Global `NSEvent` monitor; `NSPopover.behavior = .transient` | `NSPopover.behavior = .transient` | `.transient` makes AppKit close the popover automatically when the user clicks outside it or switches to another app. No global event monitor required for these cases, which simplifies teardown and avoids the accessibility/sandboxing complications that global monitors carry. |
| 8 | **NSPopover dismissal — Escape key** | Not supported; local `NSEvent` monitor; `NSResponder` chain | Local `NSEvent` monitor for `.keyDown` with `keyCode == 53` in `PopoverController`; calls `popover.performClose(_:)` | The popover's SwiftUI content intercepts key events before they bubble. A local monitor is the standard AppKit pattern for catching Escape without subclassing every responder. Using `performClose(_:)` (vs. `close()`) allows the `NSPopoverDelegate.popoverShouldClose(_:)` hook to fire if needed in future. |
| 9 | **NSPopover dismissal — second click on icon** | Not supported; toggle via button action | Status item button action checks `popover.isShown`; if true calls `popover.performClose(_:)`, else calls `showPopover()` | Consistent with user expectations established by system menu bar items (clicking again closes). Implemented in `StatusItemController.handleStatusItemClick()`. |
| 10 | **Icon technology** | Custom PDF/SVG assets in `Assets.xcassets`; SF Symbols as template images | SF Symbols as template images, loaded at runtime via `NSImage(systemSymbolName:accessibilityDescription:)` | SF Symbols 4 (macOS 13+) include `cable.connector`, `wifi`, and `wifi.slash` — exactly the three states LinkHub needs. Template images automatically adapt to light/dark menu bar tinting with no extra assets. No xcassets image sets are required for menu bar icons; the `Assets.xcassets` catalog remains for the app icon only. SF Symbols are accessibility-annotated by Apple and scale correctly at all display densities. |
| 11 | **Icon states and symbol mapping** | Four states (separate Wi-Fi-active and both-active icons); three states; two states | Three states with priority to Ethernet | PLAN.md specifies: "When Ethernet is active the icon switches to an Ethernet-style icon." Ethernet presence is the app's differentiating signal; showing `cable.connector` whenever any Ethernet interface has a link — regardless of Wi-Fi — honours that spec without a confusing fourth icon. See Icon State Table below. |
| 12 | **Icon rendering size** | 14 pt; 16 pt; 17 pt; 18 pt | `NSImage.SymbolConfiguration(pointSize: 17, weight: .regular, scale: .medium)` | Apple's HIG specifies menu bar icons at 18 × 18 pt. SF Symbols at 17 pt `medium` scale render comfortably within that grid. `.regular` weight matches the system Wi-Fi icon weight on Ventura. |
| 13 | **Icon-swap owner** | `AppState`; `AppDelegate`; `StatusItemController` | `StatusItemController` exclusively | `StatusItemController` already owns `NSStatusItem`; it is the natural place for all mutations to the status item's button. Neither `AppState` (pure data model) nor `AppDelegate` (thin coordinator) should import AppKit icon logic. This enforces unidirectional data flow: network monitors → `AppState` → `StatusItemController` → `NSStatusItem`. |
| 14 | **Icon-swap signal type** | Notification (`NSNotification`); direct method call; Combine publisher on `AppState` | `AppState.$connectionMode` Combine publisher; sink stored as `AnyCancellable` in `StatusItemController` | Combine fits the existing Swift 6 / `@MainActor` architecture from PRD 01. `@Published var connectionMode` on `AppState` gives a typed, memory-safe stream. `AnyCancellable` is cancelled in `tearDown()` — no dangling subscription risk. |
| 15 | **VoiceOver announcement strategy** | Announce every icon change; announce disconnection only; never announce | `accessibilityLabel` update on every change; active `NSAccessibility.announcementRequested` only on transition to `.disconnected` | Announcing every state change is noisy — signal-related icon updates can happen frequently. Announcing only disconnection aligns with Apple's own Wi-Fi menu behaviour and covers the safety-critical case (user has lost all connectivity). Reconnection is announced passively via the updated label when the user navigates back to the status item. |

---

## Icon State Table

| State | SF Symbol | `accessibilityLabel` | When shown |
|-------|-----------|---------------------|------------|
| Ethernet active | `cable.connector` | `"LinkHub: Ethernet connected"` | ≥1 Ethernet interface reports a link, regardless of Wi-Fi state |
| Wi-Fi only | `wifi` | `"LinkHub: Wi-Fi connected to <SSID>"` (falls back to `"LinkHub: Wi-Fi connected"` if SSID unavailable) | Wi-Fi associated, no active Ethernet |
| Disconnected | `wifi.slash` | `"LinkHub: No network connection"` | Neither Ethernet nor Wi-Fi active |

---

## Icon-Swap Trigger Contract (normative)

### `ConnectionMode` enum

Defined in `Network/Models/NetworkState.swift` (file established in PRD 01 folder layout;
content specified by PRD 03). Reproduced here as the normative interface that PRD 02 depends on:

```swift
/// Drives the status item icon and accessibility label.
/// Computed by AppState from raw EthernetInterface / WiFiState snapshots.
enum ConnectionMode: Equatable, Sendable {
    case ethernetActive   // ≥1 Ethernet interface has a link (Wi-Fi status irrelevant)
    case wifiOnly         // Wi-Fi associated, no active Ethernet
    case disconnected     // Neither active
}
```

### Data flow

```
EthernetMonitor (Network/) ─┐
                             ├─► AppState.updateNetworkState()  (@MainActor)
WiFiMonitor     (Network/) ─┘         │
                                       ▼
                              AppState.connectionMode: ConnectionMode
                              (@Published, computed from raw snapshots)
                                       │  Combine publisher
                                       ▼
                         StatusItemController.observeState()
                              .sink { [weak self] mode in
                                  self?.updateIcon(for: mode)
                              }
                              .store(in: &cancellables)
                                       │
                                       ▼
                         statusItem.button?.image = <SF Symbol image>
                         statusItem.button?.setAccessibilityLabel(...)
                         // + NSAccessibility announcement if transitioning to .disconnected
```

### File ownership

| Responsibility | Owner | File (from PRD 01 layout) |
|---------------|-------|--------------------------|
| Publish `connectionMode` changes | `AppState` | `State/AppState.swift` |
| Subscribe and update icon / label | `StatusItemController` | `MenuBar/StatusItemController.swift` |
| Open / close / dismiss the popover | `PopoverController` | `MenuBar/PopoverController.swift` |
| Host SwiftUI root view | `PopoverController` | `MenuBar/PopoverController.swift` |

---

## Popover Lifecycle (sequence summary)

```
AppDelegate.applicationDidFinishLaunching
  └─► StatusItemController.init(appState:)
        ├─► NSStatusBar.system.statusItem(withLength: .variableLength)  → statusItem
        ├─► statusItem.button?.target = self
        ├─► statusItem.button?.action = #selector(handleStatusItemClick)
        ├─► PopoverController.init(appState:)  → popoverController
        │     ├─► NSPopover()  → popover
        │     ├─► popover.behavior = .transient
        │     ├─► popover.contentViewController = NSHostingController(rootView: ContentView(appState:))
        │     └─► install local keyDown monitor (keyCode 53 → performClose)
        └─► observeState()  → AnyCancellable stored in cancellables

handleStatusItemClick()
  ├─► popover.isShown → popoverController.close()      // second click dismisses
  └─► else            → popoverController.show(relativeTo: button.frame, of: button)

AppDelegate.applicationWillTerminate
  └─► statusItemController.tearDown()
        ├─► cancellables.removeAll()
        ├─► popoverController.tearDown()   // removes local key monitor
        └─► NSStatusBar.system.removeStatusItem(statusItem)
```

---

## Constraints

- **macOS 13+ only**: `NSImage(systemSymbolName:accessibilityDescription:)` is available
  since macOS 11; `cable.connector` SF Symbol requires SF Symbols 4 / macOS 13. No
  back-deployment needed given the PRD 01 deployment target.
- **`NSStatusItem` retention**: On macOS 14+, `NSStatusBar` no longer retains the status
  item after creation. The owning object (`StatusItemController`) must remain alive for
  the lifetime of the app. This is guaranteed by `AppDelegate` holding
  `statusItemController` as a stored property.
- **`NSPopover` must be driven from the main thread**: All `NSPopover` API calls must
  occur on the main thread. Because `AppState` is `@MainActor`-isolated, Combine sinks
  on `$connectionMode` arrive on the main actor — no explicit
  `receive(on: DispatchQueue.main)` is needed inside `StatusItemController`.
- **Global event monitors require Accessibility permission (macOS 14+)**: This PRD
  deliberately avoids a global `NSEvent` monitor. The `.transient` popover behaviour
  handles click-outside without requiring the user to grant Accessibility access.
- **Swift 6 strict concurrency**: `ConnectionMode` is a value-type enum with no
  associated payload, so `Sendable` conformance is automatic. `StatusItemController` and
  `PopoverController` must be annotated `@MainActor` because they mutate
  non-`Sendable` AppKit types (`NSStatusItem`, `NSPopover`).
- **`NSPopover` initial `contentSize`**: Must be set non-zero before `show(relativeTo:…)`
  is called or the popover renders as a 0×0 window. `PopoverController` sets a reasonable
  initial size (e.g., 320 × 480 pt). Final sizing is decided in PRD 04.

---

## Out of Scope

- **Panel UI layout and sizing** — decided in PRD 04 (Panel UI Architecture).
- **What `ContentView` renders inside the popover** — decided in PRDs 04, 05, 06.
- **How `EthernetMonitor` and `WiFiMonitor` detect and publish state** — decided in PRD 03.
- **`AppState` concurrency model and `@Published` vs. `@Observable`** — decided in PRD 07.
- **Login Item registration UI** ("Launch at Login" preference toggle) — deferred to a
  future coding session; the `SMAppService` call is not a menu-bar-integration decision.
- **App icon** (`AppIcon` imageset in `Assets.xcassets`) — unrelated to the status item icon.
- **Right-click context menu on the status item** — not planned; single left-click toggles
  the popover.
- **Accessibility Inspector integration testing** — implementation concern, not a PRD
  decision.

---

## Open Questions

| # | Question | Impact | To resolve before |
|---|----------|--------|-------------------|
| 1 | Should `NSHostingController` or a plain `NSViewController` wrapping `NSHostingView` be used as `popover.contentViewController`? `NSHostingController` propagates the SwiftUI environment correctly but carries extra overhead on macOS 13. | Affects how `AppState` (as an `@EnvironmentObject` or passed directly) is injected into the view hierarchy. | PRD 04 (Panel UI Architecture) |
| 2 | Does `popover.behavior = .transient` reliably close the popover when the user clicks a *different* menu bar item (e.g., system clock) on macOS 14 / 15? Behaviour on Ventura is confirmed correct; Sonoma introduced menu bar layout changes. | If `.transient` does not close the popover in this case, a scoped global `NSEvent` monitor for `.leftMouseDown` must be re-introduced (targeting only clicks outside the popover frame). | First UI coding session — verify empirically on macOS 13 and 14 before shipping. |
| 3 | Is `cable.connector` universally recognised as "Ethernet" without a text label? An alternative symbol is `network` (globe), which is less specific but more widely known. | Icon discoverability and first-run comprehension. | UX review; fallback is a short text label beside the icon (`variableLength` supports this). |

---

## References

- [Apple Developer: NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem) — Status item API; note the retention requirement added in macOS 14.
- [Apple Developer: NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar) — `statusItem(withLength:)` and `removeStatusItem(_:)`.
- [Apple Developer: NSPopover](https://developer.apple.com/documentation/appkit/nspopover) — Popover lifecycle, `behavior`, `show(relativeTo:of:preferredEdge:)`.
- [Apple Developer: NSPopover.Behavior](https://developer.apple.com/documentation/appkit/nspopover/behavior) — `.transient`, `.semitransient`, `.applicationDefined` semantics.
- [Apple Developer: NSHostingController](https://developer.apple.com/documentation/swiftui/nshostingcontroller) — SwiftUI root view controller for AppKit containers.
- [Apple Developer: NSImage.SymbolConfiguration](https://developer.apple.com/documentation/appkit/nsimage/symbolconfiguration) — Point size, weight, and scale for SF Symbol rendering.
- [Apple Developer: SF Symbols — cable.connector](https://developer.apple.com/sf-symbols/) — Available since SF Symbols 4 (macOS 13).
- [Apple Developer: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) — macOS 13+ login item registration via `SMAppService.mainApp`.
- [Apple Developer: NSAccessibility](https://developer.apple.com/documentation/appkit/nsaccessibility) — `setAccessibilityLabel`, `NSAccessibility.post(element:notification:userInfo:)`.
- [Apple HIG: Menu bar extras](https://developer.apple.com/design/human-interface-guidelines/menu-bar-extras) — Design guidance: icon sizing (18 × 18 pt), click behaviour, popover usage.
- [Apple HIG: SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) — Template image rendering, adaptive tinting, accessibility descriptions.
- [WWDC 2024: Migrate your app to Swift 6 (session 10169)](https://developer.apple.com/videos/play/wwdc2024/10169/) — `@MainActor` isolation patterns for AppKit types; directly applicable to `StatusItemController` and `PopoverController`.
- [WWDC 2023: Beyond the basics of structured concurrency (session 10170)](https://developer.apple.com/videos/play/wwdc2023/10170/) — Actor isolation and `@Sendable` patterns relevant to `ConnectionMode` crossing actor boundaries.
