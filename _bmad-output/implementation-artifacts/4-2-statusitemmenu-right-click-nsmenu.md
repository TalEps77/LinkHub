# Story 4.2: StatusItemMenu — Right-Click NSMenu

Status: done

## Story

As a user,
I want a right-click menu on the LinkHub status item with Launch at Login, Check for Updates, About, and Quit,
so that I can manage app-level concerns without opening the panel.

## Acceptance Criteria

1. **Right-click presents the factory-built NSMenu**
   - **Given** the user right-clicks the status item
   - **When** the click handler fires
   - **Then** `MenuBar/StatusItemMenu.swift` factory builds an `NSMenu` and presents it on the status-item button (UX-DR35)
   - **And** items are: `Launch at Login` (toggle bound to `appState.launchAtLogin`), `Check for Updates…`, `About LinkHub`, `Quit LinkHub`

2. **Launch at Login item toggles and reflects state**
   - **Given** the user selects `Launch at Login`
   - **When** the toggle fires
   - **Then** `AppState.setLaunchAtLogin` runs (→ `LaunchAtLoginService`) and the menu item check-state reflects the new value on next open

3. **Quit runs the load-bearing teardown**
   - **Given** the user selects `Quit LinkHub`
   - **When** the action fires
   - **Then** `NSApp.terminate(_:)` runs and `applicationWillTerminate` performs the teardown order: `appState.stopMonitors()` → `statusItemController.tearDown()` (FR46, NFR9)

4. **About opens the standard panel**
   - **Given** the user selects `About LinkHub`
   - **When** the action fires
   - **Then** `NSApp.orderFrontStandardAboutPanel(_:)` opens the standard About panel (no custom About window in v1 scope)

5. **Left-click still toggles the popover**
   - **Given** the user left-clicks the status item
   - **When** the click is dispatched
   - **Then** the right-click NSMenu is not shown; the popover toggles per Epic 1 behavior

## Tasks / Subtasks

- [x] **Task 1: Create `LinkHub/MenuBar/StatusItemMenu.swift`** (AC: #1, #2, #3, #4)
  - [x] `@MainActor final class StatusItemMenu: NSObject, NSMenuDelegate` — owns the `@objc` action targets; held by `StatusItemController`
  - [x] `import AppKit` only
  - [x] `init(appState:updaterController:)` — `updaterController` optional so the menu degrades gracefully (Check for Updates disabled) when Sparkle isn't wired
  - [x] `func makeMenu() -> NSMenu` builds: `Launch at Login` (check-state = `appState.launchAtLogin`), separator, `Check for Updates…` (enabled iff updater present), `About LinkHub`, separator, `Quit LinkHub`
  - [x] Sets `menu.delegate = self`; each non-separator item `target = self`
  - [x] `menuNeedsUpdate(_:)` re-syncs the Launch-at-Login check-state on every open (preference can change via System Settings)
  - [x] `@objc toggleLaunchAtLogin` → `appState.setLaunchAtLogin(!appState.launchAtLogin)`
  - [x] `@objc checkForUpdates` → `updaterController?.checkForUpdates()`
  - [x] `@objc showAbout` → `NSApp.activate(ignoringOtherApps: true)` then `NSApp.orderFrontStandardAboutPanel(nil)`
  - [x] `@objc quit` → `NSApp.terminate(nil)`
- [x] **Task 2: Wire right-click into `StatusItemController`** (AC: #1, #5)
  - [x] `statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])` so one handler can branch
  - [x] `handleStatusItemClick` reads `NSApp.currentEvent`; right-click OR control+left-click → `showMenu()`, else toggle popover (Epic 1 unchanged)
  - [x] `showMenu()` builds the menu, assigns `statusItem.menu`, `button.performClick(nil)`, then clears `statusItem.menu = nil` (transient menu, so it doesn't hijack left-clicks)
  - [x] `setUpdaterController(_:)` lets `AppDelegate` hand in the Sparkle updater after launch
- [x] **Task 3: Verify teardown is not duplicated** (AC: #3)
  - [x] `applicationWillTerminate` already does `appState.stopMonitors()` → `statusItemController.tearDown()` — verified, not duplicated
- [x] **Task 4: Tests** (AC: #1, #2, #4)
  - [x] `LinkHubTests/MenuBar/StatusItemMenuTests.swift` — item order/titles, targets, Launch-at-Login check-state binding, Check-for-Updates disabled when updater nil, `menuNeedsUpdate` re-sync

## Dev Notes

### Right-click menu approach (the load-bearing decision)

The status item uses the **transient `statusItem.menu`** pattern, not a persistent `statusItem.menu`:

- `statusItem.button.sendAction(on: [.leftMouseUp, .rightMouseUp])` routes both click types to a single `@objc handleStatusItemClick`.
- The handler inspects `NSApp.currentEvent?.type`. A `.rightMouseUp`, or a `.leftMouseUp` with `.control` held (AppKit reports control-click as a left event), is treated as "show menu". Everything else toggles the popover exactly as Epic 1 did.
- `showMenu()` assigns `statusItem.menu = menu`, calls `button.performClick(nil)` to pop it open at the status item, then immediately sets `statusItem.menu = nil`.

**Why transient and not a persistent `statusItem.menu`?** If `statusItem.menu` is set persistently, AppKit routes *every* click (including left-clicks) to the menu and never fires the button's target/action — so the Epic 1 left-click popover toggle would silently break. Clearing the menu right after `performClick` restores left-click → action for the next click. This is the standard idiom for "left-click does X, right-click shows a menu" on an `NSStatusItem`.

### StatusItemMenu ownership / retain

`StatusItemMenu` is the `target` for its `@objc` items and the menu's `delegate`, so it must outlive any moment the menu can fire. `StatusItemController.showMenu()` builds a fresh `StatusItemMenu` each right-click; it lives for the synchronous `performClick` duration (the menu run loop is modal), which is sufficient — the menu and its factory are both retained on the stack across the modal `performClick` call, and the selected action fires before `showMenu()` returns.

### Check-state freshness

The menu is rebuilt on every right-click, so the initial Launch-at-Login check-state is always current. `menuNeedsUpdate(_:)` additionally re-syncs it at open time, covering the case where the preference changed (e.g. the user toggled the login item in System Settings) between build and present.

### About panel + LSUIElement

LinkHub is `LSUIElement` (no Dock icon), so the standard About panel can open behind other apps. `showAbout` calls `NSApp.activate(ignoringOtherApps: true)` first so the panel comes to the front.

### Teardown (AC #3) — verified, untouched

`AppDelegate.applicationWillTerminate` already performs `appState.stopMonitors()` then `statusItemController.tearDown()`, in that order, with the documented rationale (clear `CWWiFiClient.delegate` before UI subscriptions drop). `Quit LinkHub` → `NSApp.terminate(nil)` triggers exactly this path. No teardown logic was added or duplicated in this story.

### Testing approach

Tests inspect the built `NSMenu` directly on `@MainActor` rather than firing a live mouse event (unreliable headless): item order, titles, targets/actions, Launch-at-Login `.on`/`.off` check-state vs. `appState.launchAtLogin`, Check-for-Updates disabled when `updaterController == nil`, and `menuNeedsUpdate` re-sync after a preference change. The action methods themselves are NOT invoked in tests: `checkForUpdates` would start Sparkle and `quit` would terminate the test process. The right-click-vs-left-click branch in `StatusItemController` is covered by the existing `StatusItemControllerTests` popover test plus manual verification (live `NSStatusItem` event routing is not deterministic under XCTest).

### File-structure requirements

| File | Status | Purpose |
|---|---|---|
| `LinkHub/MenuBar/StatusItemMenu.swift` | NEW | NSMenu factory + `@objc` action targets |
| `LinkHub/MenuBar/StatusItemController.swift` | MODIFIED | right-click branch in `handleStatusItemClick`; `showMenu()`; `setUpdaterController(_:)` |
| `LinkHubTests/MenuBar/StatusItemMenuTests.swift` | NEW | menu structure / check-state / disabled-state tests |

### Local build/verification gates

- Build clean under strict concurrency; menu tests pass.
- Manual: right-click the status item → menu with the four items; left-click → popover toggles (Epic 1 unchanged); control-click → menu; toggle Launch at Login and reopen to confirm the checkmark flips.

## Dev Agent Record

### Completion Notes

- Transient-`statusItem.menu` pattern preserves Epic 1 left-click behavior while adding the right-click menu.
- No AI model identifier in code/comments/docs. No secrets.
- code-review (orchestrator) fix: `showMenu()` created the `StatusItemMenu` as a throwaway temporary, but `NSMenuItem.target` / `NSMenu.delegate` are weak — the controller would deallocate before any action or `menuNeedsUpdate` could fire. Added a `StatusItemController.menuController` stored property to retain it while the menu tracks. Status → done.
