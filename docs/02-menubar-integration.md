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
  how icon variants (Wi-Fi active, Ethernet active, disconnected) are named and loaded
- **Icon-swap trigger contract** — the exact signal (event type, data shape, caller) that
  causes the status item image to switch between representations; who owns this logic
- **Tooltip and accessibility** — `toolTip` and `accessibilityLabel` values for the status
  item in each state; VoiceOver announcement strategy when the icon changes

---

## Decision Log

| # | Decision | Options Considered | Choice | Rationale |
|---|----------|--------------------|--------|-----------|
| 1 | **NSStatusItem creation site** | `AppDelegate.applicationDidFinishLaunching`; lazy on first click; dedicated factory | `StatusItemController.init(appState:)` called from `AppDelegate.applicationDidFinishLaunching(_:)` | The status item must exist from first launch — there is no deferred use-case. Placing creation inside `StatusItemController` keeps lifecycle logic encapsulated in one file (`MenuBar/StatusItemController.swift`) and keeps `AppDelegate` thin. |
| 2 | **NSStatusItem length** | `NSStatusItem.squareLength`; `NSStatusItem.variableLength` | `NSStatusItem.squareLength` | The menu bar item is icon-only at all times — no text appears beside the icon in any state. `squareLength` (22 pt) provides a stable, standard hit target that matches system menu bar extras (Clock, Control Center, Spotlight). `variableLength` is appropriate only when item width varies at runtime; since a single fixed SF Symbol image is used at all times, `squareLength` prevents unnecessary width negotiation with the menu bar layout engine. |
| 3 | **NSStatusItem retention** | Local variable (leaks); stored on `AppDelegate`; stored on `StatusItemController` | Stored as `let statusItem: NSStatusItem` on `StatusItemController`, which is stored as `var statusItemController: StatusItemController?` on `AppDelegate` | `NSStatusItem` is not automatically retained by `NSStatusBar` on macOS 14+ — the caller must hold a strong reference. Two-level ownership (controller owns item, delegate owns controller) mirrors Apple's sample code and prevents accidental deallocation. |
| 4 | **Login-item launch behaviour** | Detect launch source and alter startup path; identical path for all launches | Identical `applicationDidFinishLaunching` path regardless of launch source | macOS 13+ `SMAppService.mainApp` launches the app exactly as if the user double-clicked it; `applicationDidFinishLaunching` fires normally. `LSUIElement = true` suppresses any visible activation. No special branch is needed. |
| 5 | **NSStatusItem teardown** | `applicationWillTerminate` only; `deinit` on controller; explicit `tearDown()` | `StatusItemController.tearDown()` called from `AppDelegate.applicationWillTerminate(_:)` | `deinit` timing is non-deterministic under ARC and can run after `NSStatusBar` is torn down. An explicit `tearDown()` called from a known lifecycle hook is predictable. `tearDown()` calls `NSStatusBar.system.removeStatusItem(statusItem)` and cancels all Combine subscriptions via `cancellables.removeAll()`. |
| 6 | **Panel presentation technology** | `NSMenu` (native dropdown); custom `NSPanel`; `NSPopover` | `NSPopover` hosting `NSHostingController<RootPanelView>` | `NSMenu` cannot host arbitrary SwiftUI — only text and action items. LinkHub needs signal-strength bars, IP addresses, and toggle controls that are impossible in `NSMenu` without undocumented hacks. A custom `NSPanel` requires manual positioning relative to the status item rect, custom vibrancy material, shadow management, and window-ordering code — `NSPopover` provides all of that natively with ~10 lines. `NSHostingController<RootPanelView>` (resolved by PRD 04 Decision #7) is the canonical SwiftUI-in-AppKit integration point; it propagates the SwiftUI environment (color scheme, accent color, locale) automatically and handles `@EnvironmentObject` injection correctly. |
| 7 | **NSPopover dismissal — click outside / app switch** | Global `NSEvent` monitor; `NSPopover.behavior = .transient` | `NSPopover.behavior = .transient` | `.transient` makes AppKit close the popover automatically when the user clicks outside it or switches to another app. No global event monitor is required for these cases, which simplifies teardown and avoids the lifecycle complexity that global monitors carry. |
| 8 | **NSPopover dismissal — Escape key** | Not supported; local `NSEvent` monitor; `NSResponder` chain | Local `NSEvent` monitor for `.keyDown` with `keyCode == 53` in `PopoverController`; installed when the popover shows, removed when it closes; calls `popover.performClose(_:)` | The popover's SwiftUI content intercepts key events before they bubble. A local monitor is the standard AppKit pattern for catching Escape without subclassing every responder. The monitor must be installed in `show()` and removed in `close()` — not permanently in `init` — to avoid responding to Escape when the popover is not visible. Using `performClose(_:)` (vs. `close()`) allows `NSPopoverDelegate.popoverShouldClose(_:)` to fire if needed in future. |
| 9 | **NSPopover dismissal — second click on icon** | Not supported; toggle via button action | Status item button action checks `popover.isShown`; if true calls `popover.performClose(_:)`, else calls `popoverController.show()` | Consistent with user expectations established by system menu bar items (clicking again closes). Implemented in `StatusItemController.handleStatusItemClick()`. |
| 10 | **Icon technology** | Custom PDF/SVG assets in `Assets.xcassets`; SF Symbols as template images | SF Symbols as template images, loaded at runtime via `NSImage(systemSymbolName:accessibilityDescription:)` | SF Symbols 4 (macOS 13+) include `cable.connector`, `wifi`, and `wifi.slash` — exactly the three states LinkHub needs. Template images automatically adapt to light/dark menu bar tinting with no extra assets. No xcassets image sets are required for menu bar icons; the `Assets.xcassets` catalog remains for the app icon only. SF Symbols are accessibility-annotated by Apple and scale correctly at all display densities. |
| 11 | **Icon states and symbol mapping** | Four states (separate Wi-Fi-active and both-active icons); three states; two states | Three states with priority to Ethernet — Ethernet icon shown only when Ethernet is fully active (link + IP assigned) | PLAN.md specifies: "When Ethernet is active the icon switches to an Ethernet-style icon." The data model (PRD 03) defines `.ethernetActive` as `isActive == true`, which requires both a physical link and an assigned IP. Showing `cable.connector` for link-only Ethernet (cable in, no IP) would be misleading — the cable is present but the connection is not usable. See Icon State Table. |
| 12 | **Icon rendering size** | 14 pt; 16 pt; 17 pt; 18 pt | `NSImage.SymbolConfiguration(pointSize: 17, weight: .regular, scale: .medium)` | Apple's HIG specifies menu bar icons at 18 × 18 pt. SF Symbols at 17 pt `medium` scale render comfortably within that grid. `.regular` weight matches the system Wi-Fi icon weight on Ventura. |
| 13 | **Icon-swap owner** | `AppState`; `AppDelegate`; `StatusItemController` | `StatusItemController` exclusively | `StatusItemController` already owns `NSStatusItem`; it is the natural place for all mutations to the status item's button. Neither `AppState` (pure data model) nor `AppDelegate` (thin coordinator) should import AppKit icon logic. This enforces unidirectional data flow: network monitors → `AppState` → `StatusItemController` → `NSStatusItem`. |
| 14 | **Icon-swap and label signal type** | `AppState.$connectionMode` only; `AppState.$networkState`; separate publishers for icon vs. label | `AppState.$networkState` Combine publisher; sink stored as `AnyCancellable` in `StatusItemController` | `$connectionMode` carries only the `ConnectionMode` enum — it has no SSID or Ethernet display-name payload. Accessibility labels and tooltips require `NetworkState.connectedWifi?.ssid` and `NetworkState.primaryEthernet`. Subscribing to `$networkState` provides all required data in a single coherent snapshot: the icon is chosen from `networkState.mode`; labels and tooltips use the full `networkState`. `AppState.$connectionMode` continues to exist per PRD 07 Decision 5 but is insufficient as the sole signal when SSID-bearing labels are required. |
| 15 | **VoiceOver announcement strategy** | Announce every icon change; announce disconnection only; never announce | `accessibilityLabel` and `toolTip` update on every `$networkState` change; active `NSAccessibility.post(element:notification:userInfo:)` only on transition to `.disconnected` | Announcing every state change is noisy — signal-related icon updates can happen frequently. Announcing only disconnection aligns with Apple's own Wi-Fi menu behaviour and covers the safety-critical case (user has lost all connectivity). Reconnection is announced passively via the updated label when the user navigates back to the status item. No announcement for RSSI changes, network list updates, or intermediate Ethernet states. |
| 16 | **Panel-open Wi-Fi scan hook** | No hook (PopoverController unaware of WiFiMonitor); direct call via closure injection; direct call via `appState` | `PopoverController.show()` calls `Task { try? await appState.wifiMonitor.requestScan() }` immediately after `popover.show(...)` | PRD 06 Scan Trigger Summary and PRD 07 Data Flow diagram both specify that opening the panel triggers an immediate scan. `PopoverController` owns popover lifecycle and is the correct caller. The scan is a fire-and-forget `Task` — popover presentation is never delayed. Errors are handled by PRD 06's `WiFiSection` UI state; `PopoverController` does not inspect the scan result. |

---

## Icon State Table

| State | SF Symbol | `accessibilityLabel` | `toolTip` | When shown |
|-------|-----------|---------------------|-----------|------------|
| Ethernet active | `cable.connector` | `"LinkHub: Ethernet connected"` | `"LinkHub: Ethernet connected via [displayName]"` (append ` — [ipv4Address]` if non-nil) | `networkState.mode == .ethernetActive` (≥1 Ethernet interface has link + IP) |
| Wi-Fi only | `wifi` | `"LinkHub: Wi-Fi connected to [SSID]"` (falls back to `"LinkHub: Wi-Fi connected"` if SSID unavailable) | Same as `accessibilityLabel` | `networkState.mode == .wifiOnly` |
| Disconnected | `wifi.slash` | `"LinkHub: No network connection"` | `"LinkHub: No network connection"` | `networkState.mode == .disconnected` |
| Ethernet link-only, Wi-Fi connected | `wifi` | Same as Wi-Fi only row above | Same as Wi-Fi only row above | `hasLink == true`, `isActive == false` on Ethernet; `connectedWifi != nil` |
| Ethernet link-only, no Wi-Fi | `wifi.slash` | `"LinkHub: No network connection"` | `"LinkHub: No network connection"` | `hasLink == true`, `isActive == false` on Ethernet; `connectedWifi == nil` |

**Important:** Link-only Ethernet (`hasLink == true`, `isActive == false`) causes the
Ethernet panel section to appear (per PRD 05 Decision #2) but does **not** change the
menu bar icon. The icon switches to `cable.connector` only when `networkState.mode`
becomes `.ethernetActive` — i.e., when at least one Ethernet interface has both a
physical link and an assigned IP address.

---

## Icon-Swap Trigger Contract (normative)

### `NetworkState` and `ConnectionMode`

Defined in `Network/Models/NetworkState.swift` (content specified by PRD 03).
Reproduced here as the normative interface that PRD 02 depends on:

```swift
/// Drives the menu bar icon.
/// Computed by AppState from raw EthernetInterface / WiFiNetwork snapshots.
enum ConnectionMode: Equatable, Sendable {
    case ethernetActive   // ≥1 Ethernet interface has link + IP (isActive == true)
    case wifiOnly         // Wi-Fi associated; no active Ethernet
    case disconnected     // Neither active
}

/// Full snapshot of combined Ethernet + Wi-Fi state.
/// Provides all data StatusItemController needs for icon, label, and tooltip.
struct NetworkState: Equatable, Sendable {
    let mode: ConnectionMode
    let ethernetInterfaces: [EthernetInterface]   // sorted: active first, then BSD name
    let primaryEthernet: EthernetInterface?        // first where isActive == true
    let wifiNetworks: [WiFiNetwork]
    let connectedWifi: WiFiNetwork?
    let isWiFiEnabled: Bool
}
```

### Data flow

```
EthernetMonitor (Network/) ─┐
                             ├─► AppState.rebuildState()  (@MainActor, Combine CombineLatest sink)
WiFiMonitor     (Network/) ─┘         │
                                       ▼
                              AppState.networkState: NetworkState   (@Published)
                              AppState.connectionMode: ConnectionMode (@Published, == networkState.mode)
                                       │  $networkState Combine publisher
                                       ▼
                         StatusItemController.observeState()
                              .sink { [weak self] state in
                                  self?.updateIcon(for: state.mode)
                                  self?.updateLabel(for: state)
                                  self?.updateTooltip(for: state)
                                  self?.announceIfDisconnected(newMode: state.mode)
                              }
                              .store(in: &cancellables)
                                       │
                                       ▼
                         statusItem.button?.image = <SF Symbol image>
                         statusItem.button?.setAccessibilityLabel(...)
                         statusItem.button?.toolTip = ...
                         // NSAccessibility announcement only on transition → .disconnected
                         // (previousMode tracking prevents cold-launch false positives)
```

### Label and tooltip derivation (normative)

```swift
// In StatusItemController — called from the $networkState sink

func updateLabel(for state: NetworkState) {
    let label: String
    switch state.mode {
    case .ethernetActive:
        label = "LinkHub: Ethernet connected"
    case .wifiOnly:
        if let ssid = state.connectedWifi?.ssid {
            label = "LinkHub: Wi-Fi connected to \(ssid)"
        } else {
            label = "LinkHub: Wi-Fi connected"
        }
    case .disconnected:
        label = "LinkHub: No network connection"
    }
    statusItem.button?.setAccessibilityLabel(label)
}

func updateTooltip(for state: NetworkState) {
    let tip: String
    switch state.mode {
    case .ethernetActive:
        var detail = state.primaryEthernet?.displayName ?? "Ethernet"
        if let ip = state.primaryEthernet?.ipv4Address {
            detail += " \u{2014} \(ip)"
        }
        tip = "LinkHub: Ethernet connected via \(detail)"
    case .wifiOnly:
        if let ssid = state.connectedWifi?.ssid {
            tip = "LinkHub: Wi-Fi connected to \(ssid)"
        } else {
            tip = "LinkHub: Wi-Fi connected"
        }
    case .disconnected:
        tip = "LinkHub: No network connection"
    }
    statusItem.button?.toolTip = tip
}

private let symbolConfig = NSImage.SymbolConfiguration(
    pointSize: 17, weight: .regular, scale: .medium)

func updateIcon(for mode: ConnectionMode) {
    let symbolName: String
    let description: String
    switch mode {
    case .ethernetActive:
        symbolName = "cable.connector"
        description = "Ethernet connected"
    case .wifiOnly:
        symbolName = "wifi"
        description = "Wi-Fi connected"
    case .disconnected:
        symbolName = "wifi.slash"
        description = "No network connection"
    }
    let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
    statusItem.button?.image = base?.withSymbolConfiguration(symbolConfig)
}

// VoiceOver disconnection announcement — transition detection (Decision #15)
// previousMode tracks the last-seen mode so announcements fire only on change,
// not on cold launch or repeated disconnected states.
private var previousMode: ConnectionMode? = nil   // nil = first emission, never announce

func announceIfDisconnected(newMode: ConnectionMode) {
    if previousMode != .disconnected, newMode == .disconnected {
        NSAccessibility.post(
            element: statusItem.button as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: "LinkHub: No network connection",
                       .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
    previousMode = newMode
}
```

### File ownership

| Responsibility | Owner | File (from PRD 01 layout) |
|---------------|-------|--------------------------|
| Publish `networkState` and `connectionMode` | `AppState` | `State/AppState.swift` |
| Subscribe to `$networkState`; update icon, label, tooltip | `StatusItemController` | `MenuBar/StatusItemController.swift` |
| `isShown: Bool` computed property (`{ popover.isShown }`) | `PopoverController` | `MenuBar/PopoverController.swift` |
| `NSPopoverDelegate` conformance; `popoverDidClose(_:)` | `PopoverController` | `MenuBar/PopoverController.swift` |
| Open / close / dismiss the popover; trigger Wi-Fi scan on show | `PopoverController` | `MenuBar/PopoverController.swift` |
| Host SwiftUI root view (`NSHostingController<RootPanelView>`) | `PopoverController` | `MenuBar/PopoverController.swift` |

---

## Popover Lifecycle (sequence summary)

```
AppDelegate.applicationDidFinishLaunching
  └─► StatusItemController.init(appState:)
        ├─► NSStatusBar.system.statusItem(withLength: .squareLength)  → statusItem
        ├─► statusItem.button?.target = self
        ├─► statusItem.button?.action = #selector(handleStatusItemClick)
        ├─► PopoverController.init(appState:statusItemButton: statusItem.button)  → popoverController
        │     │         // button stored as: private weak var button: NSStatusItemButton?
        │     │         // weak avoids retain cycle; NSStatusItem outlives PopoverController
        │     ├─► NSPopover()  → popover
        │     ├─► popover.behavior = .transient
        │     ├─► private let hostingController = NSHostingController(
        │     │       rootView: RootPanelView().environmentObject(appState))
        │     │         // stored as property — belt-and-suspenders vs. relying solely on
        │     │         // NSPopover retaining contentViewController
        │     ├─► hostingController.sizingOptions = [.intrinsicContentSize]
        │     │         // NSHostingSizingOptions.intrinsicContentSize (macOS 13+)
        │     │         // .intrinsicContentSize per PRD 04 Decision #8 (normative source for sizingOptions)
        │     ├─► popover.delegate = self                  // PopoverController: NSPopoverDelegate
        │     ├─► popover.contentViewController = hostingController
        │     └─► popover.contentSize = CGSize(width: 320, height: 480)  // pre-show default
        └─► observeState()  → subscribes to AppState.$networkState
                              AnyCancellable stored in cancellables
                              then immediately (synchronously):
                              updateIcon(for: appState.networkState.mode)
                              updateLabel(for: appState.networkState)
                              updateTooltip(for: appState.networkState)
                              // sets initial icon before first publisher emission;
                              // without this, button?.image is nil until the next run-loop pass

handleStatusItemClick()
  ├─► popoverController.isShown → popoverController.close()   // second click dismisses
  │       // popoverController.isShown is a computed property: { popover.isShown }
  │       // StatusItemController never accesses popover directly
  └─► else                      → popoverController.show()

popoverController.show()   (normative)
  ├─► guard let button = self.button,   // self.button set from statusItemButton param in init
  │         button.window != nil
  │   else { os_log(.error, "StatusItem button has no window — skipping show"); return }
  ├─► popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  │         // button.bounds is in button's own coordinate system (required by AppKit)
  ├─► eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
  │       guard let self, self.popover.isShown, event.keyCode == 53 else { return event }
  │       self.popover.performClose(nil)
  │       return nil
  │   }                                                 // stored as var eventMonitor: Any?
  └─► Task { try? await appState.wifiMonitor.requestScan() }   // async, non-blocking

popoverController.close()   (normative)
  ├─► popover.performClose(nil)
  └─► removeEventMonitor()   // sets eventMonitor = nil

NSPopoverDelegate.popoverDidClose(_:)   // called by .transient path
  └─► removeEventMonitor()

AppDelegate.applicationWillTerminate
  └─► statusItemController.tearDown()
        ├─► cancellables.removeAll()
        ├─► popoverController.tearDown()
        │     ├─► removeEventMonitor()   // must run BEFORE popover.close():
        │     │       // popover.close() fires popoverDidClose(_:), which calls removeEventMonitor()
        │     │       // again — safe (guard on nil), but calling removeEventMonitor() first here
        │     │       // makes the delegate call a guaranteed no-op rather than a surprise side effect
        │     └─► if popover.isShown { popover.close() }
        └─► NSStatusBar.system.removeStatusItem(statusItem)

// PopoverController helper
private func removeEventMonitor() {
    if let monitor = eventMonitor {
        NSEvent.removeMonitor(monitor)
        eventMonitor = nil
    }
}
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
  on `$networkState` arrive on the main actor — no explicit
  `receive(on: DispatchQueue.main)` is needed inside `StatusItemController`.
- **`popover.show` requires `button.window != nil`**: Calling
  `popover.show(relativeTo:of:preferredEdge:)` when the button has no backing window
  causes a crash. `PopoverController.show()` must guard against this, log via `os_log`,
  and return without showing — never crash.
- **`popover.show` coordinate system**: The positioning rect must use `button.bounds`
  (in the button's own coordinate space), not `button.frame` (which is in the
  superview's coordinate space). Using `button.frame` positions the popover incorrectly.
- **Local key monitor lifecycle**: The Escape key monitor must be installed only when the
  popover is visible (in `show()`) and removed when it closes. Installing it permanently
  in `init` would cause Escape to be intercepted when the popover is closed. The token
  (`var eventMonitor: Any?`) is stored on `PopoverController` as an optional and set to
  `nil` after removal via `removeEventMonitor()`.
- **`NSPopover.behavior = .transient`**: Handles click-outside and app-switch dismissal.
  When `.transient` closes the popover, `popoverDidClose(_:)` fires — the key monitor
  must be removed there if it has not already been removed by `close()`.
- **Global event monitors**: This PRD deliberately avoids global `NSEvent` monitors.
  `.transient` handles click-outside and app-switch dismissal without any global monitor.
  A local monitor handles Escape. Global key monitors require Accessibility / trusted-process
  access (documented by Apple for key-related monitoring). Global mouse monitors add
  lifecycle complexity with no benefit given `.transient`. Neither is needed.
- **Wi-Fi scan must not block popover presentation**: The `requestScan()` call in
  `PopoverController.show()` is wrapped in `Task { try? await ... }`. The `Task` is
  created and the function returns immediately — popover presentation is synchronous and
  unaffected by scan latency (typically 1–3 s).
- **Swift 6 strict concurrency**: `StatusItemController` and `PopoverController` must be
  annotated `@MainActor` because they mutate non-`Sendable` AppKit types (`NSStatusItem`,
  `NSPopover`). `NetworkState` and `ConnectionMode` are value types with all-`Sendable`
  stored properties — conformance is automatic. No `@unchecked Sendable` wrappers are
  needed.
- **`NSPopover` initial `contentSize`**: Must be set non-zero before `show(relativeTo:…)`
  is called or the popover renders as a 0×0 window. `PopoverController` sets
  `contentSize = CGSize(width: 320, height: 480)` at init time. `NSHostingController.sizingOptions
  = .intrinsicContentSize` (PRD 04 Decision #8) overrides this after the first layout
  pass — the initial value prevents a 0×0 first-show flash only.
- **Full-screen space / Stage Manager**: `NSPopover.show(relativeTo:of:preferredEdge:)` can
  behave unexpectedly when the active space is a full-screen app — the popover may refuse
  to show or appear behind the full-screen window. This is a known AppKit limitation with
  no workaround in scope for this PRD. Do not file it as a bug against this document.

---

## Out of Scope

- **Panel UI layout and sizing** — decided in PRD 04 (Panel UI Architecture).
- **What `RootPanelView` renders inside the popover** — decided in PRDs 04, 05, 06.
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

None for PRD 02. Implementation verification items are listed below.

---

## Implementation Verification / Acceptance Criteria

- [ ] Status item appears in the menu bar at launch; no Dock icon is visible.
- [ ] Clicking the status item opens the popover.
- [ ] Clicking the status item a second time closes the popover.
- [ ] Clicking outside the popover or switching to another app closes it via `.transient`.
- [ ] Pressing Escape while the popover is open closes it; Escape has no effect when the popover is closed.
- [ ] Clicking a different menu bar item (e.g., system clock) while the popover is open closes it.
- [ ] Popover uses `NSHostingController<RootPanelView>` with `.environmentObject(appState)` and `sizingOptions = [.intrinsicContentSize]`.
- [ ] `PopoverController.init` sets `popover.contentSize = CGSize(width: 320, height: 480)` as the pre-show default; `sizingOptions = .intrinsicContentSize` overrides this after the first layout pass (no 0×0 first-show flash).
- [ ] `popover.show` uses `button.bounds` (not `button.frame`) and `preferredEdge: .minY`.
- [ ] `button.window != nil` is checked before calling `popover.show`; absent window logs an error and does not crash.
- [ ] Opening the popover triggers `WiFiMonitor.requestScan()` asynchronously; popover appearance is not delayed by scan latency.
- [ ] **Icon — cold launch**: the correct icon is visible immediately at launch with no blank-image flash (initial sync in `StatusItemController.init` fires before the first publisher emission).
- [ ] **Icon — Ethernet active**: `cable.connector` is shown when `networkState.mode == .ethernetActive`.
- [ ] **Icon — Wi-Fi only**: `wifi` is shown when `networkState.mode == .wifiOnly`.
- [ ] **Icon — Disconnected**: `wifi.slash` is shown when `networkState.mode == .disconnected`.
- [ ] **Icon — Ethernet link-only + Wi-Fi connected**: icon remains `wifi` (not `cable.connector`) until Ethernet `isActive` becomes true.
- [ ] **Icon — Ethernet link-only + no Wi-Fi**: icon remains `wifi.slash` until Ethernet `isActive` becomes true.
- [ ] Accessibility label updates correctly for all five icon states above.
- [ ] Tooltip updates correctly alongside the accessibility label for all five states.
- [ ] Ethernet tooltip includes `displayName`; appends ` — [ipv4Address]` when available.
- [ ] Wi-Fi tooltip includes SSID when available; falls back to generic label if SSID is nil.
- [ ] VoiceOver announces the transition to `.disconnected` once; does not announce every RSSI update or reconnection.
- [ ] VoiceOver announcement is NOT posted on cold launch when the initial network state is `.disconnected` (first emission is never announced).
- [ ] Code review confirms no call to `NSEvent.addGlobalMonitorForEvents(matching:handler:)` exists in the codebase.
- [ ] Escape key monitor token (`eventMonitor`) is `nil` when the popover is closed; set when shown; removed on close and in `tearDown()`.

---

## References

- [Apple Developer: NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem) — Status item API; note the retention requirement added in macOS 14.
- [Apple Developer: NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar) — `statusItem(withLength:)` and `removeStatusItem(_:)`.
- [Apple Developer: NSPopover](https://developer.apple.com/documentation/appkit/nspopover) — Popover lifecycle, `behavior`, `show(relativeTo:of:preferredEdge:)`.
- [Apple Developer: NSPopover.Behavior](https://developer.apple.com/documentation/appkit/nspopover/behavior) — `.transient`, `.semitransient`, `.applicationDefined` semantics.
- [Apple Developer: NSHostingController](https://developer.apple.com/documentation/swiftui/nshostingcontroller) — SwiftUI root view controller for AppKit containers; `sizingOptions` property (macOS 13+).
- [Apple Developer: NSImage.SymbolConfiguration](https://developer.apple.com/documentation/appkit/nsimage/symbolconfiguration) — Point size, weight, and scale for SF Symbol rendering.
- [Apple Developer: SF Symbols — cable.connector](https://developer.apple.com/sf-symbols/) — Available since SF Symbols 4 (macOS 13).
- [Apple Developer: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) — macOS 13+ login item registration via `SMAppService.mainApp`.
- [Apple Developer: NSAccessibility](https://developer.apple.com/documentation/appkit/nsaccessibility) — `setAccessibilityLabel`, `NSAccessibility.post(element:notification:userInfo:)`.
- [Apple HIG: Menu bar extras](https://developer.apple.com/design/human-interface-guidelines/menu-bar-extras) — Design guidance: icon sizing (18 × 18 pt), click behaviour, popover usage.
- [Apple HIG: SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) — Template image rendering, adaptive tinting, accessibility descriptions.
- [WWDC 2024: Migrate your app to Swift 6 (session 10169)](https://developer.apple.com/videos/play/wwdc2024/10169/) — `@MainActor` isolation patterns for AppKit types; directly applicable to `StatusItemController` and `PopoverController`.
- [WWDC 2023: Beyond the basics of structured concurrency (session 10170)](https://developer.apple.com/videos/play/wwdc2023/10170/) — Actor isolation and `@Sendable` patterns relevant to `NetworkState` crossing actor boundaries.
