# Story 1.4: RootPanelView, WiFiSection, WiFiRow (Read-Only)

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user,
I want to open the panel and see the list of nearby Wi-Fi networks with their SSID, signal, security, and connected state,
so that I can read my current Wi-Fi context at a glance without taking any action.

## Acceptance Criteria

1. **`RootPanelView` lays out as `VStack(spacing: 8) { WiFiSection }` at 320 pt fixed width**
   - **Given** the popover opens
   - **When** `RootPanelView` renders
   - **Then** its body is `VStack(spacing: 8) { WiFiSection() }` clamped to `frame(width: PanelLayout.panelWidth, alignment: .top)` (UX-DR9)
   - **And** popover first paint is ≤200 ms cold / ≤100 ms warm on Apple Silicon (NFR2) — verified manually via Instruments Time Profiler trace
   - **And** existing `PopoverBackground` (Story 1.2) is preserved — no double material, no explicit `.background(.regularMaterial)` (PRD 04 D9)
   - **And** `FooterRows` mentioned in epic AC are **deferred to Epic 2 / PRD 06** (see Dev Notes — Scope Boundaries) — Story 1.4 ships only `WiFiSection`

2. **`WiFiSection` header — `Label("WI-FI") + Toggle` (toggle non-functional in Epic 1)**
   - **Given** scanned Wi-Fi data is available
   - **When** `WiFiSection` renders
   - **Then** the section header is an `HStack` with `Text("WI-FI")` left-aligned + `Spacer()` + `Toggle("", isOn: $wifiPowerStub)` (right-aligned, `.toggleStyle(.switch)`, `.labelsHidden()`)
   - **And** the header text style is `.caption` 10 pt semibold uppercase via `.font(.system(size: 10, weight: .semibold))` + `.foregroundStyle(.secondary)` + `.textCase(.uppercase)` (UX-DR3, UX-DR12, epic AC #2)
   - **And** the toggle is bound to `@State private var wifiPowerStub: Bool = true` owned by `WiFiSection` — **non-functional**; epic 2 / PRD 06 wires it to `WiFiMonitor.setPower(_:)` (epic AC #2 explicit; do not touch `WiFiMonitor` from here)
   - **And** the toggle has `.accessibilityLabel("Wi-Fi")` explicit (PRD 04 AC, Decision #16 keyboard tab order)
   - **And** the header has vertical padding `PanelLayout.sectionHeaderVerticalPadding`

3. **Connected network row first; checkmark distinguishes it; other networks follow**
   - **Given** `appState.networkState.connectedWifi` is non-nil
   - **When** `WiFiSection` renders the network list
   - **Then** the connected row appears **first**, distinguished by an `Image(systemName: "checkmark")` in `Color.accentColor` at the leading edge (FR28, UX-DR13, epic AC #2)
   - **And** the connected SSID label uses `.fontWeight(.semibold)` (PRD 04 D11)
   - **And** **other networks follow** in the order produced by `WiFiMonitor` (sorted by RSSI desc per Story 1.3 `performScan`)
   - **And** if a scan-result network has `id == connectedWifi.id`, it is **omitted** from the "other networks" list to prevent SwiftUI `Identifiable` duplicate-id warning (Story 1.3 deferred this dedupe to Story 1.4 — see "Review Findings → Deferred" in `1-3-…-scanstatus-timeout.md`)
   - **And** when `connectedWifi == nil`, only the "other networks" loop renders (no checkmark row)

4. **`WiFiRow` anatomy and per-field rendering**
   - **Given** a Wi-Fi network row
   - **When** `WiFiRow` renders
   - **Then** it is an `HStack(spacing: 8)` with leading-to-trailing order: `Checkmark?` → `SSIDText(.body)` → `Spacer()` → `LockIcon?` → `CaptiveIcon?` → `SignalBars` (UX-DR13, epic AC #3)
   - **And** SSID uses `.body` 13 pt regular (`.font(.body)`); hidden networks (where `ssid == nil`) render the **literal string `"Hidden Network"`** (FR24, epic AC #3)
   - **And** the security marker is `Image(systemName: "lock.fill")` for `requiresPassword == true`; **absent entirely** (no placeholder space) when `requiresPassword == false` (FR24, UX-DR2)
   - **And** captive-portal networks (where `isCaptive == true`) show `Image(systemName: "globe")` (FR25)
   - **And** `SignalBars` is a 16 × 16 pt SF Symbol picked by RSSI bucket — see "RSSI → SF Symbol mapping" table in Dev Notes (epic AC #3)
   - **And** row padding is `PanelLayout.rowVerticalPadding` top/bottom + `PanelLayout.rowHorizontalPadding` leading/trailing
   - **And** `LockIcon`, `CaptiveIcon`, and `SignalBars` are decorative — each marked `.accessibilityHidden(true)` (NFR27)
   - **And** the row container uses `.accessibilityElement(children: .combine)` and exposes a single `.accessibilityLabel(...)` per UX-DR22 templates — normal: `"{SSID}, {securityType}, signal {strength}"`; connected: `"{SSID}, connected, {securityType}, signal {strength}"` (NFR24, FR56) — see "VoiceOver label composition" table in Dev Notes for `securityType` and `strength` strings

5. **List refreshes on `wifiMonitor.$networks` push (no polling)**
   - **Given** scanned data updates
   - **When** `wifiMonitor.$networks` publishes (via the AppState `CombineLatest4` sink → `rebuildState` from Story 1.3)
   - **Then** the `WiFiSection` `ForEach` re-renders with no scheduled poll, no `Timer`, no `Task.sleep` (FR27, FR50, NFR50)
   - **And** the row insertion / removal animation is `.animation(.easeInOut(duration: 0.2), value: appState.networkState.wifiNetworks)` on the `ForEach` container (PRD 04 D14)
   - **And** the animation is **suppressed** when `@Environment(\.accessibilityReduceMotion)` is true — use `.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: ...)` (NFR28, UX-DR16)

6. **Scan-on-show — `PopoverController.show()` triggers `requestScan()` immediately after `popover.show(...)`**
   - **Given** the user has the panel open
   - **When** the panel becomes visible via `PopoverController.show()`
   - **Then** a fire-and-forget `Task { @MainActor [appState] in await appState.wifiMonitor.requestScan() }` fires **immediately after** `popover.show(relativeTo:of:preferredEdge:)` succeeds (FR26, epic AC #5)
   - **And** the `// Story 1.4: scan-on-show hook (FR26)` placeholder comment in `PopoverController.show()` is **removed and replaced** with the actual scan trigger
   - **And** `requestScan()` is **non-throwing** per the Story 1.3 `WiFiMonitorProtocol` — do **not** wrap in `try?` (Story 1.3 Dev Notes carry-forward note)
   - **And** the `Task` does **not** retain `self` (`PopoverController`) — capture only `appState` weakly via `[appState] in ...` or use a strong capture and rely on `Task` finishing in <5 s (the scan timeout); see Dev Notes "Capture discipline in `PopoverController.show()`"

7. **Scanning indicator visible only when list is empty AND `scanStatus == .scanning`**
   - **Given** `appState.scanStatus == .scanning` AND `appState.networkState.wifiNetworks.isEmpty` AND `appState.networkState.connectedWifi == nil`
   - **When** the user observes the panel
   - **Then** a visible scanning indicator is displayed: an `HStack` with `ProgressView()` (system style) + `Text("Searching for networks…")` (`.callout`, `.secondary`), centered horizontally, vertically padded to `PanelLayout.rowHeight` (NFR3, epic AC #6)
   - **And** when the list is non-empty (connected row OR ≥1 other network), the new scan results **merge in without** showing a loading state (UX-DR33, epic AC #6) — the `ForEach` animation from AC #5 is the only visual change
   - **And** the scanning indicator is **suppressed** when the empty-state copy from AC #8 would also apply — i.e., scanning indicator wins over empty-state copy when `scanStatus == .scanning`

8. **Empty-state copy when Wi-Fi is on but no networks were found**
   - **Given** `appState.networkState.isWiFiEnabled == true` AND `wifiNetworks.isEmpty` AND `connectedWifi == nil` AND `appState.scanStatus != .scanning`
   - **When** the panel renders
   - **Then** a `.callout` font, `.secondary` foreground, **horizontally centered** `Text("No networks found")` empty-state appears in the network list area, with **no action button** (UX-DR33, epic AC #7)
   - **And** the empty-state row is vertically padded so the panel does not collapse to an unreadable height — minimum `PanelLayout.rowHeight * 2`
   - **And** when `isWiFiEnabled == false` OR `isWiFiHardwareAvailable == false`, the empty-state copy is **not** shown — that disabled-state UX is **deferred to Epic 2 / PRD 06 Decision #19** (Dev Notes Scope Boundaries); for Story 1.4 the section simply renders an empty list (no "Turn on Wi-Fi…" text yet)

## Tasks / Subtasks

- [ ] **Task 1: Extend `UI/Theme.swift` — add panel/row layout constants** (AC: #1, #2, #4, #7, #8)
  - [ ] Edit `LinkHub/UI/Theme.swift` (currently has `panelWidth: 320`, `outerPadding: 8` only; drop the `// Story 1.4 will add: …` comment)
  - [ ] Add to `enum PanelLayout`:
    ```swift
    static let panelMaxHeight: CGFloat = 520        // PRD 04 D2
    static let interSectionSpacing: CGFloat = 8     // VStack(spacing: 8); UX-DR9
    static let rowHeight: CGFloat = 44              // PRD 04 D13
    static let rowHorizontalPadding: CGFloat = 16   // PRD 04 D13
    static let rowVerticalPadding: CGFloat = 11     // PRD 04 D13
    static let sectionHeaderVerticalPadding: CGFloat = 8
    static let signalBarsSize: CGFloat = 16         // epic AC #3
    static let networkListMaxHeight: CGFloat = 220  // PRD 04 D3 — reserved for Epic 2 ScrollView; OK to add now since constant is read-only
    ```
  - [ ] Keep `import Foundation` + `import CoreGraphics` only (no SwiftUI in `Theme.swift` — `PanelLayout` is a `CGFloat` constants enum; UI types live in their own files)
  - [ ] **Do not** add color tokens to `Theme.swift` — semantic colors are inlined at use site per architecture rule "no hardcoded color values; system semantic only" (NFR31, UX-DR4)

- [ ] **Task 2: `UI/Components/SignalBars.swift` — RSSI → SF Symbol** (AC: #4)
  - [ ] Create `LinkHub/UI/Components/SignalBars.swift`. `import SwiftUI` only
  - [ ] `struct SignalBars: View` with `let rssi: Int`. Body:
    ```swift
    Image(systemName: Self.symbolName(for: rssi))
        .resizable()
        .scaledToFit()
        .frame(width: PanelLayout.signalBarsSize, height: PanelLayout.signalBarsSize)
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
    ```
  - [ ] Static helper `static func symbolName(for rssi: Int) -> String` per the RSSI bucket table in Dev Notes:
    - `>= -60` → `"wifi"` (4-bar; SF Symbol `wifi` is the "full bars" symbol on macOS 13)
    - `-60 ... -70` → `"wifi"` w/ `.symbolVariant(.none)` is not enough on macOS 13 — use the discrete-level SF Symbols: **`wifi`** (4 bars), **`wifi`** with `.opacity(0.75)` is **not** the canonical mapping. **Use the canonical SF Symbols**: `"wifi"` (>=-60), `"wifi"` rendered with `Image(systemName: "wifi")` and a graded variant **only available macOS 14+**. **For macOS 13 baseline, use SF Symbols named `wifi`, `wifi.exclamationmark`, `wifi.slash`** (only these are available pre-14 in the wifi family).
    - **Decision (resolved):** macOS 13 SF Symbol palette for Wi-Fi signal strength is limited. The canonical 4-level set (`wifi.0` … `wifi.3`) is iOS-only / macOS 14+. **For macOS 13, render signal strength with a custom 4-bar `Canvas` view** (PRD 04 D6 explicitly accepts custom signal-strength bars in SwiftUI: "Custom signal-strength bars are straightforward `HStack` + `RoundedRectangle` in SwiftUI. No AppKit sub-view is needed.")
  - [ ] **Replace the SF Symbol approach with PRD 04 D6's canonical 4-bar `RoundedRectangle` `HStack`**:
    ```swift
    struct SignalBars: View {
        let rssi: Int
        var body: some View {
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<4, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(idx < Self.activeBars(for: rssi) ? Color.primary : Color.primary.opacity(0.25))
                        .frame(width: 2.5, height: CGFloat(4 + idx * 3))   // 4, 7, 10, 13 pt
                }
            }
            .frame(width: PanelLayout.signalBarsSize, height: PanelLayout.signalBarsSize, alignment: .bottomLeading)
            .accessibilityHidden(true)
        }
        static func activeBars(for rssi: Int) -> Int {
            switch rssi {
            case let r where r >= -60: return 4
            case let r where r >= -70: return 3
            case let r where r >= -80: return 2
            default: return 1
            }
        }
    }
    ```
    Rationale: epic AC #3 says "16×16 pt SF Symbol" but the canonical 4-level Wi-Fi SF Symbol set is macOS 14+; PRD 04 D6 explicitly authorizes the `RoundedRectangle` fallback. **Document this in story Change Log** ("epic AC #3 'SF Symbol' interpretation diverges to PRD 04 D6 `RoundedRectangle` bars on macOS 13").
  - [ ] Add `#Preview` exercising 4 RSSI levels: -50, -65, -75, -85 (one per bucket) — preview only, no runtime cost (UX § Component Implementation Strategy)
  - [ ] **Pure-function discipline:** `activeBars(for:)` is `static` and `Sendable` — easily unit-testable from `LinkHubTests/UI/Components/SignalBarsTests.swift` without instantiating SwiftUI

- [ ] **Task 3: `UI/Components/WiFiRow.swift` — single network row** (AC: #4)
  - [ ] Create `LinkHub/UI/Components/WiFiRow.swift`. `import SwiftUI` only
  - [ ] `struct WiFiRow: View` with `let network: WiFiNetwork`. Body:
    ```swift
    HStack(spacing: 8) {
        if network.isConnected {
            Image(systemName: "checkmark")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
        }
        Text(displaySSID)
            .font(.body)
            .fontWeight(network.isConnected ? .semibold : .regular)
            .lineLimit(1)
            .truncationMode(.tail)
        Spacer()
        if network.requiresPassword {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        if network.isCaptive {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        SignalBars(rssi: network.rssi)
    }
    .padding(.vertical, PanelLayout.rowVerticalPadding)
    .padding(.horizontal, PanelLayout.rowHorizontalPadding)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Self.accessibilityLabel(for: network))
    ```
  - [ ] Computed `private var displaySSID: String { network.ssid ?? "Hidden Network" }` — FR24
  - [ ] Static helper `static func accessibilityLabel(for network: WiFiNetwork) -> String` per UX-DR22 templates:
    ```swift
    static func accessibilityLabel(for network: WiFiNetwork) -> String {
        let name = network.ssid ?? "Hidden Network"
        let security = network.requiresPassword ? "password required" : "open network"
        let strength = signalStrengthDescription(for: network.rssi)
        if network.isConnected {
            return "\(name), connected, \(security), signal \(strength)"
        }
        return "\(name), \(security), signal \(strength)"
    }
    static func signalStrengthDescription(for rssi: Int) -> String {
        switch rssi {
        case let r where r >= -60: return "excellent"
        case let r where r >= -70: return "good"
        case let r where r >= -80: return "fair"
        default: return "weak"
        }
    }
    ```
    Note: UX-DR22 templates use `securityType` keyword; PRD 04 line 299 example renders this as `"password required" / "open network"` — **adopt that copy** (concise, matches Apple's voice; epic AC #4 says "follows UX-DR22 templates" and UX line 862 example uses `"password-required"` with hyphen; **resolve to `"password required"` without hyphen** to match PRD 04's example which is more recent and copy-edited)
  - [ ] **Captive marker is NOT in the accessibility label** for Story 1.4 — UX-DR22 base template does not include captive marker (Story 2.5 / Epic 2 may extend the label)
  - [ ] Acronym discipline: `WiFi` (not `WIFI` / `Wifi`); `RSSI` in code comments; `SSID` in identifiers
  - [ ] Add 4 `#Preview` cases: connected WPA2; non-connected open; non-connected enterprise; hidden network with password

- [ ] **Task 4: `UI/Panels/WiFiSection.swift` — Wi-Fi list, header, scan/empty states** (AC: #2, #3, #5, #7, #8)
  - [ ] Create `LinkHub/UI/Panels/WiFiSection.swift`. `import SwiftUI` only
  - [ ] `struct WiFiSection: View` with `@EnvironmentObject var appState: AppState` and `@Environment(\.accessibilityReduceMotion) var reduceMotion: Bool` and `@State private var wifiPowerStub: Bool = true` (epic AC #2 — non-functional)
  - [ ] Body composition:
    ```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var header: some View {
        HStack(spacing: 0) {
            Text("WI-FI")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Toggle("", isOn: $wifiPowerStub)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Wi-Fi")
                .controlSize(.small)
        }
        .padding(.horizontal, PanelLayout.rowHorizontalPadding)
        .padding(.vertical, PanelLayout.sectionHeaderVerticalPadding)
    }
    @ViewBuilder
    private var content: some View {
        let connected = appState.networkState.connectedWifi
        let others = appState.networkState.wifiNetworks.filter { $0.id != connected?.id }
        let isEmpty = (connected == nil) && others.isEmpty
        let isScanning = appState.scanStatus == .scanning
        if isEmpty && isScanning {
            scanningIndicator
        } else if isEmpty && appState.networkState.isWiFiEnabled && !isScanning {
            emptyState
        } else {
            VStack(spacing: 0) {
                if let connected { WiFiRow(network: connected) }
                ForEach(others) { network in WiFiRow(network: network) }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: appState.networkState.wifiNetworks)
        }
    }
    private var scanningIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Searching for networks…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, PanelLayout.rowVerticalPadding)
    }
    private var emptyState: some View {
        Text("No networks found")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: PanelLayout.rowHeight * 2, alignment: .center)
    }
    ```
  - [ ] **Note on filter dedupe:** `others = wifiNetworks.filter { $0.id != connected?.id }`. The `id` field on `WiFiNetwork` is the BSSID when present, else `"\(ssid ?? "hidden"):\(security)"` (Story 1.3 Dev Notes). This dedupes the SwiftUI `Identifiable` collision flagged in Story 1.3 review-deferred list
  - [ ] **No `ScrollView` in this story.** PRD 04 D3 specifies a `ScrollView` with `frame(maxHeight: 220)` for the network rows, but for Epic 1 / Story 1.4 the panel is read-only and overflow handling is not under test. Add a Dev-Notes scope boundary; Epic 2 (PRD 06) wires the `ScrollView` when adding `WiFiSectionFooter` (login-item toggle, "Other Networks…", "Open Network Settings…")
  - [ ] **No header decoration animations** beyond AC #5's `ForEach` animation
  - [ ] Add `#Preview` cases driven by `AppState._setNetworkStateForTesting(_:)` Story 1.2 helper:
    1. Empty + scanning
    2. Empty + idle (Wi-Fi on)
    3. Connected + 3 other networks
    4. Hidden-network connected + 2 others (FR24 visual check)

- [ ] **Task 5: Update `LinkHub/UI/PopoverRootView.swift` — wire `WiFiSection`** (AC: #1)
  - [ ] **Modify** `PopoverRootView.swift` (currently renders `Text("LinkHub")` placeholder). Replace body with:
    ```swift
    struct RootPanelView: View {
        @EnvironmentObject var appState: AppState
        var body: some View {
            VStack(spacing: PanelLayout.interSectionSpacing) {
                WiFiSection()
            }
            .frame(width: PanelLayout.panelWidth, alignment: .top)
            .padding(.vertical, PanelLayout.outerPadding)
            .background(PopoverBackground())
        }
    }
    ```
  - [ ] **Drop** the `// WiFiSection placeholder added in Story 1.4` comment and the `Text("LinkHub")` placeholder
  - [ ] **Preserve** `PopoverBackground()` from Story 1.2 — it owns the `.windowBackground` `NSVisualEffectView` + Reduce Transparency fallback. Do not add a `.background(.regularMaterial)` modifier (PRD 04 D9 — "no double-material wash")
  - [ ] Update the existing `#Preview` (if any) — none currently exists in `PopoverRootView.swift`; add one that shows the panel with `MockWiFiMonitor` data via a previews-only `AppState`:
    ```swift
    #if DEBUG
    #Preview {
        let mock = MockWiFiMonitor()
        let state = AppState(wifiMonitor: mock)
        state._setNetworkStateForTesting(NetworkState(
            mode: .wifiOnly,
            ethernetInterfaces: [],
            primaryEthernet: nil,
            wifiNetworks: MockWiFiMonitor.sampleNetworks,
            connectedWifi: MockWiFiMonitor.sampleNetworks.first { $0.isConnected },
            isWiFiEnabled: true,
            isWiFiHardwareAvailable: true
        ))
        return RootPanelView().environmentObject(state)
    }
    #endif
    ```

- [ ] **Task 6: Update `LinkHub/MenuBar/PopoverController.swift` — scan-on-show** (AC: #6)
  - [ ] **Modify** `PopoverController.swift` `show()` body. Replace the `// Story 1.4: scan-on-show hook (FR26)` comment with:
    ```swift
    Task { @MainActor [appState] in
        await appState.wifiMonitor.requestScan()
    }
    ```
  - [ ] **Add `let appState: AppState` stored property** to `PopoverController` (currently the controller has `private weak var button: NSStatusBarButton?` and `hostingController` with `appState` only captured at init — but the show-hook needs `appState` again). Update init: store `appState` as `private let appState: AppState` (strong ref is fine — `PopoverController` is owned by `StatusItemController` which is owned by `AppDelegate` along with `appState`; lifetime is process-scoped per Story 1.2 Dev Notes)
  - [ ] **Capture discipline:** `[appState]` is sufficient — capturing `appState` strongly inside a fire-and-forget `Task` is safe because `appState` is process-scoped. Do **not** capture `self` (avoid retain cycles even though `Task` will finish in <5 s). Do **not** use `[weak self]` because the `Task` does not need `self` — only `appState`
  - [ ] **Order:** the scan-trigger Task fires **after** `popover.show(...)` (which is synchronous AppKit call) and **after** `eventMonitor` registration — preserve the existing line order; only the comment is replaced
  - [ ] **Idempotency:** if `show()` is called twice rapidly while one scan is in flight, Story 1.3's `WiFiMonitor.requestScan()` re-entrancy guard (`inFlightScan`) will no-op the second call — **no additional guard needed in `PopoverController`**
  - [ ] **No throwing:** `requestScan()` is non-throwing per `WiFiMonitorProtocol` (Story 1.3 Task 2). Do not write `try?`. Story 1.3 Dev Notes anticipated this exact change ("Story 1.4 will switch this to `appState.wifiMonitor.requestScan()` (no `try?` since we made it non-throwing in this story)")

- [ ] **Task 7: Test coverage — pure-function helpers, AppState-driven view-model assertions, integration** (AC: all)
  - [ ] **`LinkHubTests/UI/Components/SignalBarsTests.swift`** (NEW):
    - `testActiveBarsBucketBoundaries` — assert `SignalBars.activeBars(for:)` returns `4` at `-60`, `3` at `-61` and `-70`, `2` at `-71` and `-80`, `1` at `-81` and below
    - `testActiveBarsHandlesEdgeCases` — `0`, `-60`, `-1000` all return a valid bar count in `1...4`
  - [ ] **`LinkHubTests/UI/Components/WiFiRowTests.swift`** (NEW):
    - `testAccessibilityLabelConnectedWPA2` — assert `WiFiRow.accessibilityLabel(for: connectedWPA2)` == `"HomeNetwork, connected, password required, signal excellent"`
    - `testAccessibilityLabelOpenNotConnected` — assert label == `"CoffeeWifi, open network, signal fair"`
    - `testAccessibilityLabelHiddenNetwork` — assert hidden-network label starts with `"Hidden Network, "` (FR24)
    - `testSignalStrengthDescriptionAcrossBuckets` — table-driven test on `WiFiRow.signalStrengthDescription(for:)` covering excellent/good/fair/weak boundaries (parallels `SignalBarsTests` but for the string descriptor)
  - [ ] **`LinkHubTests/UI/Panels/WiFiSectionTests.swift`** (NEW): SwiftUI views are awkward to unit-test directly without a snapshot library. **Test the dedupe and ordering logic** by extracting `WiFiSection` helpers into a `static func` API:
    - Add `static func displayedNetworks(from state: NetworkState) -> (connected: WiFiNetwork?, others: [WiFiNetwork])` to `WiFiSection`
    - `testDedupeRemovesConnectedFromOthers` — pass a `NetworkState` with `connectedWifi.id == "X"` and `wifiNetworks` containing both `"X"` and `"Y"`; assert `connected == "X"` and `others == ["Y"]`
    - `testNoConnectedShowsAllAsOthers` — `connectedWifi == nil`; assert `others.count == wifiNetworks.count`
    - `testEmptyStateInputs` — `connectedWifi == nil` and `wifiNetworks == []`; assert `(nil, [])`
    - `testOrderingPreservesMonitorRSSISort` — pass three networks with RSSI -40, -60, -80 in that order; assert `others` preserves order
  - [ ] **Modify** `LinkHubTests/MenuBar/PopoverControllerTests.swift` — add:
    - `testShowTriggersScan` — instantiate `PopoverController(appState: AppState(wifiMonitor: mock), statusItemButton: nil)`. Note: `show()` early-returns when `button.window == nil`, so this test verifies the scan-trigger does **not** fire when there is no window. **Then** add `testShowTriggersScanWithValidWindow` — gated by `try XCTSkipIf(NSStatusBar.system.statusItem(withLength: ...) ...)` only if test hosts can mount a real status item; otherwise refactor the trigger into a testable helper: `func triggerScanOnShow()` and assert that helper calls `appState.wifiMonitor.requestScan()`. **Pick the helper-extraction path** — cleaner than mounting a status item in a test
    - **Refactor `PopoverController.show()`** to call a `private func triggerScanOnShow()` after `popover.show(...)`. The helper is `internal` `#if DEBUG`-gated for testability: `#if DEBUG internal func _triggerScanOnShowForTesting() { triggerScanOnShow() } #endif`
    - `testTriggerScanOnShowFiresRequestScan` — assert mock's scanStatus transitions `idle → scanning → idle` after calling `_triggerScanOnShowForTesting()`; use Combine `.sink` to collect the sequence (mock has 200 ms simulated delay)
  - [ ] **No `WiFiSection` view-tree snapshot tests** — Apple's macOS XCTest does not ship `ViewInspector`/`SnapshotTesting`, and adding an SPM test dep is out of scope for Story 1.4 (PRD 09 owns dep additions). Accessibility-label and dedupe helpers are tested as pure functions; visual fidelity is verified via `#Preview` and manual run with `LINKHUB_MOCK_WIFI=1`
  - [ ] **Modify** `LinkHubTests/State/AppStateTests.swift` (if needed) — no new behavior added to `AppState` in this story; existing tests stand. **Verify** `_setNetworkStateForTesting` still works (it does — preserved from Story 1.3)

- [ ] **Task 8: XcodeGen, build, test, manual verification** (AC: all)
  - [ ] **`project.yml` audit:** new files live in `LinkHub/UI/Panels/`, `LinkHub/UI/Components/` (already covered by Story 1.2's recursive `path: LinkHub` source glob — no edit needed). New test files in `LinkHubTests/UI/Components/`, `LinkHubTests/UI/Panels/` (also covered by recursive `path: LinkHubTests`). Verify post-`xcodegen generate`
  - [ ] Run `DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer xcodegen generate`
  - [ ] Run `xcodebuild -scheme LinkHub -configuration Debug build` → must succeed, **zero warnings** (NFR33)
  - [ ] Run `xcodebuild -scheme LinkHub -configuration Release build` → must succeed, **zero strict-concurrency warnings**. The pre-existing Release sign warning from Story 1.1 (`"LinkHub isn't code signed but requires entitlements"`) is acceptable
  - [ ] Run `xcodebuild -scheme LinkHub -configuration Debug test` → all new tests pass; Story 1.2/1.3's existing tests still pass (no regression)
  - [ ] **Manual verification (AC #1, #2, #3, #4, #5, #6):** with `LINKHUB_MOCK_WIFI=1` set, build & run Debug:
    1. Click status item → popover opens within 200 ms — note clock time on first cold open
    2. Section header shows uppercase "WI-FI" left + Toggle right (toggle visually present, flipping does nothing — confirm non-functional)
    3. Connected row appears first with checkmark in accent color; "HomeNetwork" SSID is semibold
    4. Other 4 networks follow in RSSI-sort order (the canned `MockWiFiMonitor.sampleNetworks` is already sorted in Story 1.3 task 4)
    5. "CoffeeWifi" row shows globe icon (captive); "CorpNetwork" row shows no lock (enterprise per `requiresPassword == false`); "Hidden Network" row renders for the `ssid: nil` entry
    6. Each row's signal bars match the RSSI bucket (HomeNetwork -42 → 4 bars; GuestNetwork -55 → 4 bars; CoffeeWifi -68 → 3 bars; CorpNetwork -72 → 2 bars; Hidden -80 → 2 bars)
    7. Close popover; reopen → scan-on-show triggers (`os_log show --predicate 'subsystem == "com.linkhub.app" AND category == "network.wifi"'` should show no errors; mock's `scanStatus → .scanning → .idle` cycles in <300 ms)
  - [ ] **Manual verification (AC #7 scanning indicator):** in `MockWiFiMonitor`, temporarily increase the simulated scan delay to ~3 s (or set `networks = []` initially in a `#if DEBUG` test variant). Reopen panel → "Searching for networks…" indicator visible. **Revert** the temp change before commit
  - [ ] **Manual verification (AC #8 empty state):** as above with `networks = []` and `connectedWifi = nil` and `scanStatus = .idle` → "No networks found" callout visible. Revert before commit
  - [ ] **VoiceOver verification (AC #4):** open VoiceOver (Cmd+F5); navigate to a WiFiRow; assert label reads e.g. "HomeNetwork, connected, password required, signal excellent". Confirm decorative glyphs (lock, signal bars, captive globe) are not separately announced
  - [ ] **Reduce Motion verification (AC #5):** enable System Settings → Accessibility → Display → Reduce Motion; reopen panel; trigger a scan → list updates **instantly** with no fade. Disable Reduce Motion; verify 0.2 s fade is back

## Dev Notes

### Story foundation

This is the **first story to render Wi-Fi data on screen.** By end of Story 1.4 the user opens the popover and sees a working list of nearby Wi-Fi networks driven by Story 1.3's `WiFiMonitor` push-event pipeline. The story is **read-only** — no connect, no disconnect, no power toggle wiring (those are Epic 2 / PRD 06). The only user-visible interaction in this story is **opening the popover**, which fires `requestScan()` (FR26).

The story closes the gap between "data flows" (Story 1.3) and "users perceive data" (this story). After Story 1.4:

- `RootPanelView` is no longer a placeholder — it composes `WiFiSection`.
- `WiFiSection` reads `appState.networkState` and `appState.scanStatus` and renders three states: scanning-empty, idle-empty, populated.
- `WiFiRow` is the canonical row component; Epic 2 will extend it with the inline-password-expansion and right-click context menu, but the read-only base lives here.
- `PopoverController.show()` triggers the scan, completing the FR26 scan-on-show contract.
- Story 1.5 will hook `LocationDeniedView` into `WiFiSection` to replace the list when authorization is denied — that section swap is a Story 1.5 concern; for now `WiFiSection` always renders the list.

### Previous story intelligence (Story 1.3)

**Carried forward (do not change):**

- `WiFiMonitor` + `MockWiFiMonitor` + `WiFiMonitorProtocol` shape — Story 1.4 only reads `@Published` data through `AppState`, never subscribes to monitors directly (NFR35 hard rule).
- `AppState.networkState`, `connectionMode`, `scanStatus` — already populated by Story 1.3's `Publishers.CombineLatest4` sink + `assign(to: &$scanStatus)` mirror. **Do not** add new sinks in this story.
- `AppState._setNetworkStateForTesting(_:)` — `#if DEBUG` test helper preserved; useful for `WiFiSection` previews and tests.
- `MockWiFiMonitor.sampleNetworks` — 5 canonical networks (HomeNetwork connected WPA2, GuestNetwork WPA2, CoffeeWifi captive open, CorpNetwork enterprise, hidden WPA3). **Use these in `#Preview` blocks** rather than inventing new fixtures (single source of truth for design iteration).
- `WiFiNetwork.id` falls back to `"\(ssid ?? "hidden"):\(security)"` when bssid is nil — Story 1.4's dedupe filter `$0.id != connected?.id` correctly handles both BSSID-keyed and composite-keyed ids.
- `Log.networkWiFi` (`category: "network.wifi"`) — UI layer should not log to this category; if `WiFiSection` ever needs to log (it should not in this story), use `Log.menuBar` or add a `Log.ui` category in a future story.
- `PopoverController` has `// Story 1.4: scan-on-show hook (FR26)` comment in `show()` — replace with the actual trigger.
- `RootPanelView` is a placeholder rendering `Text("LinkHub")` with `PopoverBackground` — the background view stays; the placeholder text is replaced with `WiFiSection()`.

**Story 1.3 review-deferred items inherited by this story:**

- `connectedNetwork.id == bssid` collides with same-BSSID scan-result `id` → SwiftUI `Identifiable` duplicate-id warning when `WiFiSection` merges them. **Resolution:** dedupe via `wifiNetworks.filter { $0.id != connectedWifi?.id }` (Task 4).

**Settings still in force from Stories 1.1/1.2/1.3:**
- `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `MACOSX_DEPLOYMENT_TARGET = 13.0`.
- Debug ad-hoc unsigned, no entitlements; Release has Hardened Runtime + Location entitlement.
- Pre-existing Release sign warning is expected and not a regression.
- `ENABLE_TESTABILITY = YES` Debug-only — preserved.
- `xcodegen generate` is the project-file source of truth.

### Architecture compliance — must-follow guardrails

**Layer-purity rules (architecture.md § Architectural Boundaries):**

- `UI/Panels/WiFiSection.swift` — `import SwiftUI` only. **No** `AppKit`/`Combine`/`CoreWLAN`. Reads state via `@EnvironmentObject var appState: AppState`. **Never** `import CoreWLAN` from any UI file.
- `UI/Components/WiFiRow.swift` — `import SwiftUI` only.
- `UI/Components/SignalBars.swift` — `import SwiftUI` only.
- `UI/PopoverRootView.swift` — `import SwiftUI` only. Already conforms.
- `UI/Theme.swift` — `import Foundation` + `import CoreGraphics` only. No SwiftUI types in `Theme.swift` (constants only).
- `MenuBar/PopoverController.swift` — `import AppKit` + `import SwiftUI` (existing). Reading `appState.wifiMonitor.requestScan()` is allowed — `AppState` is in `State/` and `WiFiMonitorProtocol` is in `Network/`; neither pulls `CoreWLAN` into `MenuBar/`.

**State-subscription rule (NFR35 — hard):**

- UI subscribes to `AppState` only. `WiFiSection` reads `appState.networkState` and `appState.scanStatus`. **Never** import `WiFiMonitor` from a UI file. **Never** instantiate a monitor from UI.
- `@EnvironmentObject var appState: AppState` is the only injection mechanism. The injection happens in `PopoverController.init` via `RootPanelView().environmentObject(appState)` (Story 1.2; preserved).

**Combine pipeline shape (architecture.md § Communication Patterns):**

- Story 1.4 adds **no new Combine sinks**. All state delivery rides Story 1.3's existing `CombineLatest4` sink and `scanStatus` mirror. SwiftUI `@EnvironmentObject` + `@Published` automatically re-renders the view tree on each emission.
- **Do not** add `.sink` calls in `WiFiSection` or `WiFiRow`. SwiftUI handles this implicitly through `@EnvironmentObject`.

**Concurrency:**

- All UI code runs on the SwiftUI actor (`@MainActor` by default for `View` types in macOS 13). No explicit `@MainActor` annotation on view structs.
- `PopoverController.show()` is `@MainActor` (existing). The `Task { @MainActor [appState] in await appState.wifiMonitor.requestScan() }` hop is required per Swift 6 strict concurrency to make the actor isolation explicit at the `Task` boundary — even though `show()` is already on MainActor, the new `Task` would otherwise default to non-isolated context.
- **No `DispatchQueue.main.async` anywhere in this story.** Use `Task { @MainActor in ... }` exclusively (architecture rule).

**Color discipline:**

- Use `Color.primary`, `Color.secondary`, `Color.accentColor`, and `.foregroundStyle(.primary | .secondary)` only. **No hardcoded hex.** The `Color.accentColor` for the connected checkmark and `Color.primary.opacity(0.25)` for inactive signal bars are the **only** non-semantic uses (PRD 04 D10/D11/Decision-#20 — `Color.accentColor` is system-resolved, dark-mode-correct).
- Toggle and ProgressView use system styling — no `.tint()` overrides.

**Reduce Motion:**

- All animations gated on `@Environment(\.accessibilityReduceMotion)` (NFR28, UX-DR16). The `ForEach` row animation in `WiFiSection.content` uses `reduceMotion ? nil : .easeInOut(duration: 0.2)`.
- No other animations are introduced in this story.

**Reduce Transparency:** already handled by `PopoverBackground` (Story 1.2). No change.

**Accessibility hard rules:**

1. Decorative glyphs (`checkmark`, `lock.fill`, `globe`, `SignalBars`) are individually `.accessibilityHidden(true)`. The row container uses `.accessibilityElement(children: .combine)` and exposes a single combined label.
2. The combined label follows UX-DR22 templates exactly. Test the label as a pure function (no SwiftUI introspection needed).
3. The Wi-Fi Toggle has `.accessibilityLabel("Wi-Fi")` explicit.
4. **No `accessibilityValue`** on the row — value is conveyed in the combined label (Apple HIG: "avoid redundant role announcements").
5. The hidden-network row's label starts with the literal `"Hidden Network"` (FR24).

### Library / framework requirements

| Concern | Use | Do NOT use |
|---|---|---|
| Layout container | SwiftUI `VStack`, `HStack`, `ForEach` | `List` (PRD 04 § Constraints — applies own background/separators conflicting with popover material) |
| Network rows scrolling | **None in Story 1.4** — overflow handling deferred to Epic 2 | `ScrollView` with `frame(maxHeight: 220)` is PRD 04 D3 spec; Story 2.x wires it |
| Section header text | `.font(.system(size: 10, weight: .semibold))` + `.textCase(.uppercase)` (UX-DR3, epic AC #2) | `.subheadline` mixed-case (PRD 04 D12 — **conflict with epic AC, see "Spec conflict" below**) |
| Wi-Fi toggle | `Toggle` + `.toggleStyle(.switch)` + `.labelsHidden()` | `NSSwitch` (would cross the AppKit boundary unnecessarily) |
| Signal bars | Custom `RoundedRectangle` `HStack` (PRD 04 D6) | SF Symbols `wifi.0…wifi.3` (macOS 14+ only; our floor is 13.0) |
| Connected glyph | `Image(systemName: "checkmark")` in `Color.accentColor` (PRD 04 D11) | Filled row background (would conflict with hover highlight color) |
| Security marker | `Image(systemName: "lock.fill")` for `requiresPassword == true` | A separate SF Symbol per WiFiSecurity case (over-specified for Story 1.4) |
| Captive marker | `Image(systemName: "globe")` for `isCaptive == true` | A custom shape (Apple HIG: use SF Symbols when available) |
| Hidden network copy | Literal `"Hidden Network"` (FR24) | `"<hidden>"` or empty string |
| List animation | `.animation(.easeInOut(duration: 0.2), value: networks)` (PRD 04 D14) gated on Reduce Motion | `.withAnimation { ... }` blocks (architecture warning: fires on unrelated state changes) |
| Scan trigger | `Task { @MainActor [appState] in await appState.wifiMonitor.requestScan() }` after `popover.show(...)` | `try? await ...` (`requestScan()` is non-throwing per Story 1.3) |
| Empty-state copy | `"No networks found"` `.callout` `.secondary` centered (UX-DR33, epic AC #7) | "No Networks Found" with `wifi.slash` icon (PRD 04 D17 — **conflict with epic AC, see "Spec conflict" below**) |
| Scanning indicator | `ProgressView()` `.controlSize(.small)` + `Text("Searching for networks…")` `.callout` `.secondary` (PRD 04 D18, epic AC #6) | A bespoke `ActivityIndicator` |
| State injection | `@EnvironmentObject var appState: AppState` (existing) | Explicit `@ObservedObject` constructor injection (PRD 07 D3 chose `@EnvironmentObject`) |

### Spec conflicts and resolutions (read carefully)

The PRD 04, UX, and epic specs are mostly aligned, but three normative details diverge. **Epic ACs are the source of truth for this story** (per Story 1.3 Dev Notes precedent: "Epic 1.3 in epics.md is the source of truth for this story's ACs"). Flag each conflict in the story's Change Log so future maintainers can reconcile.

| Conflict | Epic AC says | PRD 04 says | UX says | Resolution |
|---|---|---|---|---|
| Section header style | `.caption` 10 pt **semibold UPPERCASE** "WI-FI" (UX-DR3, UX-DR12) | `.subheadline` semibold + secondary, **mixed-case** "Wi-Fi" (PRD 04 D12) | `.caption` 10 pt semibold uppercase (UX-DR3) | **Follow epic AC + UX → uppercase "WI-FI"** in caption-10pt-semibold. Document in Change Log so future PRD-04 reconciliation is intentional |
| Empty-state visual | `.callout` centered "No networks found", **no icon, no button** (UX-DR33) | `wifi.slash` SF Symbol + "No Networks Found" placeholder row (PRD 04 D17) | `"No networks found"` `.callout` centered, no icon (UX-DR33) | **Follow epic AC + UX → text-only `.callout`**. PRD 04's `wifi.slash` icon is for the disabled-state copy variant, which is Epic 2 / PRD 06 territory |
| Signal bars rendering | "16 × 16 pt **SF Symbol**" (epic AC #3) | Custom 4-bar `RoundedRectangle` `HStack` (PRD 04 D6 — SwiftUI signal-strength bars) | n/a | **Follow PRD 04 D6 → custom 4-bar HStack**. Reason: macOS 13 SF Symbols do not include `wifi.0…wifi.3` (those are macOS 14+ / iOS-only); the only Wi-Fi-related SF Symbols on macOS 13 are `wifi`, `wifi.exclamationmark`, `wifi.slash`. Document in Change Log |

### File-structure requirements (this story creates / modifies these files)

| File | Status | Purpose |
|---|---|---|
| `LinkHub/UI/Theme.swift` | MODIFIED | Add `panelMaxHeight`, `interSectionSpacing`, `rowHeight`, `rowHorizontalPadding`, `rowVerticalPadding`, `sectionHeaderVerticalPadding`, `signalBarsSize`, `networkListMaxHeight` to `enum PanelLayout`. Drop the `// Story 1.4 will add: …` comment |
| `LinkHub/UI/Components/SignalBars.swift` | NEW | `struct SignalBars: View { let rssi: Int; ... }` — 4-bar `RoundedRectangle` HStack per RSSI bucket; 16 × 16 pt; `.accessibilityHidden(true)`. Static `activeBars(for:)` helper for testing |
| `LinkHub/UI/Components/WiFiRow.swift` | NEW | `struct WiFiRow: View { let network: WiFiNetwork; ... }` — single network row per epic AC #3; `.accessibilityElement(children: .combine)` + UX-DR22 label. Static `accessibilityLabel(for:)` and `signalStrengthDescription(for:)` helpers for testing |
| `LinkHub/UI/Panels/WiFiSection.swift` | NEW | `struct WiFiSection: View` — header + content (scanning, empty, list); reads `@EnvironmentObject var appState: AppState`; `@State` toggle stub. Static `displayedNetworks(from:)` helper for dedupe testing |
| `LinkHub/UI/PopoverRootView.swift` | MODIFIED | Replace `Text("LinkHub")` placeholder with `VStack(spacing: PanelLayout.interSectionSpacing) { WiFiSection() }`; preserve `PopoverBackground()`. Add `#Preview` |
| `LinkHub/MenuBar/PopoverController.swift` | MODIFIED | Add `private let appState: AppState`; replace `// Story 1.4: scan-on-show hook (FR26)` comment with actual `Task { @MainActor [appState] in await appState.wifiMonitor.requestScan() }`; add `#if DEBUG` `_triggerScanOnShowForTesting` test hook |
| `LinkHubTests/UI/Components/SignalBarsTests.swift` | NEW | `activeBars(for:)` bucket boundaries, edge cases |
| `LinkHubTests/UI/Components/WiFiRowTests.swift` | NEW | Accessibility-label composition (connected, not-connected, hidden, open) + `signalStrengthDescription(for:)` boundaries |
| `LinkHubTests/UI/Panels/WiFiSectionTests.swift` | NEW | `displayedNetworks(from:)` dedupe + ordering |
| `LinkHubTests/MenuBar/PopoverControllerTests.swift` | MODIFIED | Add `testTriggerScanOnShowFiresRequestScan` exercising the `#if DEBUG` test hook |

### View tree (canonical for this story)

```
RootPanelView (UI/PopoverRootView.swift)
└── VStack(spacing: 8)                    ← PanelLayout.interSectionSpacing
    └── WiFiSection (UI/Panels/WiFiSection.swift)
        ├── header (HStack)
        │   ├── Text("WI-FI")             ← .caption 10pt semibold uppercase secondary
        │   ├── Spacer
        │   └── Toggle($wifiPowerStub)    ← .switch style, labelsHidden, accessibilityLabel "Wi-Fi"
        └── content (@ViewBuilder)
            ├── if isEmpty && isScanning → scanningIndicator (HStack of ProgressView + Text("Searching for networks…"))
            ├── elif isEmpty && !isScanning → emptyState (Text("No networks found"))
            └── else → VStack
                ├── if connected → WiFiRow(network: connected)        ← checkmark + semibold SSID
                └── ForEach(others) { WiFiRow(network: $0) }          ← .animation(.easeInOut(0.2), value: networks)

WiFiRow (UI/Components/WiFiRow.swift)
└── HStack(spacing: 8)                    ← .accessibilityElement(children: .combine), single label
    ├── if isConnected → Image("checkmark")  ← Color.accentColor, .accessibilityHidden(true)
    ├── Text(displaySSID)                  ← .body, .semibold if connected; "Hidden Network" if ssid==nil
    ├── Spacer
    ├── if requiresPassword → Image("lock.fill")     ← .secondary, .accessibilityHidden(true)
    ├── if isCaptive → Image("globe")                ← .secondary, .accessibilityHidden(true)
    └── SignalBars(rssi: network.rssi)               ← .accessibilityHidden(true)
```

### RSSI → signal-strength mapping

| RSSI range (dBm) | active bars | accessibility descriptor (UX § Signal quality descriptor table) |
|---|---|---|
| `>= -60` | 4 | `"excellent"` |
| `-61 ... -70` | 3 | `"good"` |
| `-71 ... -80` | 2 | `"fair"` |
| `< -80` | 1 | `"weak"` |

The descriptor mapping in `WiFiRow.signalStrengthDescription(for:)` and the bar count in `SignalBars.activeBars(for:)` **must agree on bucket boundaries** — both are static testable helpers exercised by `WiFiRowTests` and `SignalBarsTests` respectively.

### VoiceOver label composition (UX-DR22)

| Network state | Template | Example |
|---|---|---|
| Normal (not connected) | `"{SSID}, {securityType}, signal {strength}"` | `"GuestNetwork, password required, signal good"` |
| Connected | `"{SSID}, connected, {securityType}, signal {strength}"` | `"HomeNetwork, connected, password required, signal excellent"` |
| Hidden network normal | `"Hidden Network, {securityType}, signal {strength}"` | `"Hidden Network, password required, signal weak"` |
| Open network | `"{SSID}, open network, signal {strength}"` | `"CoffeeWifi, open network, signal fair"` |

`{securityType}` resolution:
- `requiresPassword == true` → `"password required"`
- `requiresPassword == false` → `"open network"`

`{strength}` resolution: see RSSI mapping table above.

The captive marker (`isCaptive`) is **not** included in the Story 1.4 label (UX-DR22 base templates do not include it; Epic 2 / PRD 06 Story 2.5 may extend the label when the captive-portal handoff lands).

### Capture discipline in `PopoverController.show()`

**Why `[appState]` and not `[weak self]`:**

- `PopoverController` does **not** need to be referenced inside the `Task` — only `appState` does. Capturing `self` strongly is unsafe (could form a retain cycle through `Task → self → popover.delegate=self`); capturing `[weak self]` is unnecessary.
- `appState` is **process-scoped** — owned by `AppDelegate`, lifetime equal to the app. Strong-capture in a fire-and-forget `Task` introduces no leak risk.
- The `Task` is `@MainActor`-isolated so `await appState.wifiMonitor.requestScan()` runs on the same actor as the rest of `appState` access — no actor-hop required at the await.

**Failure modes considered:**

1. User clicks status item rapidly → `show()` called twice while a scan is in flight: Story 1.3's `inFlightScan` guard makes the second `requestScan()` a no-op. ✅
2. User opens popover → close popover → app moves to background mid-scan: the `Task` runs to completion (200 ms mock / 1–3 s real). ✅
3. App terminates mid-scan: `applicationWillTerminate` calls `stopMonitors()` which cancels the in-flight scan task (Story 1.3 patch) and clears the delegate. ✅

### Animation rules (Reduce Motion compliance)

| Trigger | Animation | Duration | Reduce Motion fallback | Source |
|---|---|---|---|---|
| `wifiNetworks` array change → `ForEach` re-render | `.easeInOut` | 0.2 s | Instant (no animation) | PRD 04 D14, NFR28, UX-DR16 |
| Empty → list (first scan completes) | Same as above | 0.2 s | Instant | PRD 04 D14 |
| Scanning indicator → list (scan completes) | Same as above (the scanning indicator branch swaps for the list branch in `@ViewBuilder content`) | 0.2 s | Instant | PRD 04 D14 |

**No other animations** in Story 1.4. The Ethernet-section `.transition(.opacity.combined(with: .move(edge: .top)))` from PRD 04 D15 is **deferred to Epic 3 / PRD 05** — Ethernet section does not exist yet.

### Build-config branching

Story 1.4 uses `#if DEBUG` in two narrow places:

1. `RootPanelView` `#Preview` block — `MockWiFiMonitor` and `_setNetworkStateForTesting` are both `#if DEBUG`-only.
2. `PopoverController._triggerScanOnShowForTesting()` — test-only hook to call the scan trigger from `PopoverControllerTests` without mounting an `NSStatusBar` button.

**Forbidden uses** (architecture rule):
- `#if DEBUG` to change user-visible behavior in the panel.
- `#if RELEASE` (architecture-forbidden).

### Anti-patterns to avoid

- **Do not** subscribe `WiFiSection` or `WiFiRow` to `WiFiMonitor` directly. Read `appState.networkState` only (NFR35). Architecture line "UI subscribes to AppState only" is a hard rule.
- **Do not** add a `Timer` / `DispatchSourceTimer` / `Task.sleep` polling loop for any UI state. Push events + on-demand scan only (FR50, NFR50).
- **Do not** use `List`. PRD 04 § Constraints: "SwiftUI `List` on macOS 13 applies its own background and separator styling that conflicts with the popover material and cannot be fully suppressed without private API. Use `ScrollView` + `ForEach` + `VStack(spacing: 0)` with explicit row backgrounds." Story 1.4 uses just `VStack` + `ForEach` (no `ScrollView` yet — Epic 2 wires it).
- **Do not** use `NavigationStack`. Same constraint section: "Navigation-driven flows (captive portal, hidden network join) must be implemented as sheet presentations from the popover or as separate windows — not `NavigationStack` push, which is unsupported inside `NSPopover` on macOS 13."
- **Do not** add a `.background(.regularMaterial)` modifier on `RootPanelView` or any child. `PopoverBackground` (Story 1.2) already supplies the material; doubling produces a washed-out look (PRD 04 D9).
- **Do not** mutate `appState` from a SwiftUI view. Reads only. The scan trigger in `PopoverController.show()` is the **only** state mutation in this story (and that's via a method call, not a property write).
- **Do not** `try?` the `requestScan()` call — it's non-throwing per Story 1.3.
- **Do not** capture `self` strongly in the `Task { ... }` inside `PopoverController.show()`. Capture `[appState]` only.
- **Do not** add `WiFiSectionFooter`, `"Other Networks…"`, `"Open Network Settings…"`, or `Toggle("Launch at Login", ...)` rows. PRD 04 places these in `WiFiSectionFooter` per Decision #21; **Epic 2 / PRD 06 owns those.**
- **Do not** wire the Wi-Fi power toggle to actually toggle Wi-Fi power. Epic AC #2 explicit: "non-functional in Epic 1; bound to a stub". Wiring is Epic 2 / PRD 06 Story 2.5.
- **Do not** add `LocationDeniedView` or its swap-in logic. **Story 1.5 owns** the auth flow and the `WiFiSection` ↔ `LocationDeniedView` swap.
- **Do not** add SwiftUI `.contextMenu { }` (right-click "Forget" / "Open in Settings"). Epic 2 / PRD 06 Story 2.6 owns Forget + handoffs.
- **Do not** use `.controlAccentColor` overlay for hover highlight in this story. PRD 04 D10 specifies it for hover, but Story 1.4 has no row-action affordances yet (rows are not focusable, not tappable). Hover highlight is a Story 2.x concern when row-tap-to-connect lands.
- **Do not** mark rows `.focusable()`. Same reason as hover — Story 2.x territory when keyboard-driven connect ships.
- **Do not** add `.tint()` to the Toggle. System default tint matches the rest of macOS Control Center.
- **Do not** add `accessibilityValue` on rows. Combined `accessibilityLabel` is the single source of truth (Apple HIG: avoid redundant role announcements).
- **Do not** add `import Combine` to UI files. `@EnvironmentObject` + `@Published` propagation handles re-render automatically.
- **Do not** edit `project.yml` unless `xcodegen generate` produces a project missing one of the new files (verify post-generation).
- **Do not** edit `StatusItemController` icon/label/tooltip mapping. Story 1.6 owns SSID-aware label expansion (UX-DR24 templates).
- **Do not** edit `AppState`. Story 1.4 reads existing state only; no new `@Published` properties, no new sinks.

### Wi-Fi UI data flow (canonical for this story)

```
[ user clicks status item ]
            │
            ▼
StatusItemController.handleStatusItemClick (Story 1.2)
            │
            ▼
PopoverController.show()
  ├── popover.show(relativeTo: ...)
  ├── eventMonitor = NSEvent.addLocalMonitorForEvents(...)
  └── Task { @MainActor [appState] in
           await appState.wifiMonitor.requestScan()    ← Story 1.4 adds this line
       }
            │
            ▼
WiFiMonitor.requestScan() (Story 1.3)
  scanStatus: idle → scanning
  Task.detached → scanForNetworks
  scanStatus: scanning → idle (or .timedOut)
  networks = sortedResults
            │
            ▼
AppState.CombineLatest4.sink (Story 1.3)
  → rebuildState(networks, connected, isEnabled, isHardwareAvailable)
  → AppState.networkState = NetworkState(...)
            │
            ▼
SwiftUI re-renders WiFiSection (Story 1.4)
  ├── compute connected = networkState.connectedWifi
  ├── compute others = networkState.wifiNetworks.filter { $0.id != connected?.id }
  ├── if empty && scanning → scanningIndicator
  ├── elif empty && !scanning → emptyState
  └── else → VStack { WiFiRow(connected) ; ForEach(others) { WiFiRow($0) } }
        with .animation(.easeInOut(0.2), value: networks) gated on Reduce Motion
```

### Library / framework requirements — version notes

- `SwiftUI` `Toggle` / `ProgressView` / `Image(systemName:)` / `ForEach` / `@EnvironmentObject` / `@Environment` / `@State` / `@ViewBuilder` — macOS 10.15+ (our floor 13.0). Available.
- `RoundedRectangle` — SwiftUI since 10.15. Available.
- `.accessibilityHidden(true)` / `.accessibilityElement(children: .combine)` / `.accessibilityLabel(_:)` — SwiftUI since 10.15. Available.
- `.toggleStyle(.switch)` — macOS 11+. Available.
- `.controlSize(.small)` — macOS 11+. Available.
- `.foregroundStyle(_:)` — macOS 12+. Available. (Replaces `.foregroundColor(_:)` for ShapeStyle.)
- `.symbolRenderingMode(_:)` — macOS 12+. Available (not used in this story but available if needed for SF Symbols).
- `Color.accentColor` — SwiftUI since 10.15. Available.
- `.textCase(.uppercase)` — macOS 11+. Available.
- `@Environment(\.accessibilityReduceMotion)` — macOS 11+. Available.

**Not available on macOS 13 (do not attempt):**
- `wifi.0` / `wifi.1` / `wifi.2` / `wifi.3` SF Symbols — these are macOS 14+ / iOS-only. Use `RoundedRectangle` bars (PRD 04 D6).
- `Observation` / `@Observable` macro — macOS 14+. PRD 07 D1 chose `ObservableObject` for this reason.

### Performance notes (NFR2 ≤200 ms cold paint)

- `WiFiSection` is a value-type `View` struct — zero allocation cost beyond what SwiftUI already pays for the view tree.
- `displayedNetworks(from:)` is `O(n)` over `wifiNetworks` (n ≤ ~50 typical). Negligible.
- `WiFiRow.accessibilityLabel(for:)` is `O(1)` per row. The string concatenation is cheap; no `String.format(_:)` overhead.
- `SignalBars` body is 4 `RoundedRectangle` views — SwiftUI memoizes shape rendering. Negligible.
- The `.animation(...)` modifier with `value:` parameter is scoped — only `wifiNetworks` array identity changes trigger it. RSSI updates on existing rows do not (PRD 04 D14 Decision rationale).

**Cold-paint validation:** Instruments Time Profiler trace from app launch to first popover open. Expect ≤200 ms on M-series Macs (NFR2). If the trace shows >200 ms, profile `NSHostingController.viewWillAppear` and `WiFiSection.body` first.

### Testing standards

- Test framework: **XCTest** (Stories 1.1–1.3 carry-forward). No XCUITest.
- New tests live under `LinkHubTests/UI/Components/`, `LinkHubTests/UI/Panels/` mirroring source structure.
- `@testable import LinkHub` in all new test files. `ENABLE_TESTABILITY = YES` Debug-only is from Story 1.1.
- **Pure-function discipline:** test logic — RSSI buckets, accessibility-label composition, dedupe — as `static func` helpers. The view body is exercised via `#Preview` and manual run, **not** unit tests. No SwiftUI snapshot/inspector library is added in Story 1.4.
- **Combine sink testing:** the `PopoverControllerTests` `testTriggerScanOnShowFiresRequestScan` uses an `XCTestExpectation` driven by a `.sink` on `mock.$scanStatus`, collecting the sequence into an array, asserting `[idle, scanning, idle]`. Wait timeout `1.0` s.
- **Test isolation:** any test that reads `UserDefaults.standard.launchAtLogin` cleans up in `tearDown()`. (Carry-forward from Story 1.2; no new UserDefaults usage in this story.)
- **CI flakiness guards:** none required for Story 1.4 — all tests are deterministic pure-function or mock-driven.
- **Mock injection:** prefer constructing `AppState(wifiMonitor: MockWiFiMonitor())` directly in tests; do not depend on env-var detection.
- Run tests via `xcodebuild ... -configuration Debug test` (Story 1.1 scheme).

### Project Structure Notes

- `LinkHub/UI/Panels/` is **first-time occupied**. Story 1.2 created `UI/PopoverRootView.swift`, `UI/Theme.swift`, `UI/Components/PopoverBackground.swift`. Story 1.4 adds the first `Panels/` file (`WiFiSection.swift`).
- The recursive `path: LinkHub` source entry in `project.yml` (Story 1.1) covers `UI/Panels/` automatically via `createIntermediateGroups: true`. Verify post-`xcodegen generate`. If files appear at the wrong group level, add an explicit `path: LinkHub/UI/Panels` group entry to `project.yml` mirroring the existing `LinkHub/UI/Components` pattern.
- `LinkHubTests/UI/Components/` and `LinkHubTests/UI/Panels/` are similarly first-time. Same recursive coverage applies; verify post-generation.
- Architecture canonical tree (architecture.md § Complete Project Directory Structure) places `WiFiRow.swift` directly under `LinkHub/UI/Components/` and `WiFiSection.swift` under `LinkHub/UI/Panels/`. This story matches the canonical tree exactly.
- `SignalBars.swift` is **a Story 1.4 addition explicit in architecture.md line 621** (`SignalBar.swift`). The architecture singular `SignalBar` vs. plural `SignalBars` is a naming nit — **adopt `SignalBars`** to match the epic AC text "SignalBars is a 16 × 16 pt SF Symbol". Document in Change Log.

### References

- [Source: \_bmad-output/planning-artifacts/epics.md#Story 1.4] — story BDD acceptance criteria (epics.md is the source of truth for this story's ACs)
- [Source: docs/04-panel-ui-architecture.md#Decision Log] — D1 (320 pt fixed width), D2 (520 pt max height), D3 (network list ScrollView 220 pt — deferred to Epic 2), D6 (custom RoundedRectangle signal bars), D9 (no double background), D10 (hover highlight — deferred to Epic 2), D11 (connected row checkmark + semibold), D12 (section header style — **conflicts with epic AC #2**, see Spec Conflicts table), D13 (row padding 11/16), D14 (list animation 0.2 s easeInOut on `value: networks`), D15 (Ethernet section animation — Epic 3), D17 (empty state — **conflicts with epic AC #7**), D18 (scanning ProgressView), D20 (system accent only), D21 (Launch at Login footer — Epic 2)
- [Source: docs/04-panel-ui-architecture.md#Layout Structure] — `RootPanelView` component hierarchy; `PanelLayout` constants
- [Source: docs/04-panel-ui-architecture.md#SwiftUI / AppKit Boundary] — 100% SwiftUI inside the `NSHostingController` boundary; no AppKit sub-view needed
- [Source: docs/04-panel-ui-architecture.md#Dark / Light Mode] — semantic color usage; `Color.primary`, `.secondary`, `.accentColor`; no hardcoded hex
- [Source: docs/04-panel-ui-architecture.md#Animation Specification] — list row insert/remove animation 0.2 s easeInOut; RSSI updates do not animate
- [Source: docs/04-panel-ui-architecture.md#Accessibility] — VoiceOver label synthesis per row; signal-quality descriptor mapping; lock icon not separately focusable; signal bar `.accessibilityHidden(true)`; Wi-Fi Toggle `.accessibilityLabel("Wi-Fi")`
- [Source: docs/04-panel-ui-architecture.md#Constraints] — no `List`, no `NavigationStack`, `sizingOptions = .intrinsicContentSize`, no `.background(.regularMaterial)` doubling
- [Source: docs/04-panel-ui-architecture.md#File Ownership] — `RootPanelView` in `UI/PopoverRootView.swift`; `WiFiSection` in `UI/Panels/WiFiSection.swift`; `WiFiRow` + `SignalBars` in `UI/Components/`
- [Source: \_bmad-output/planning-artifacts/ux-design-specification.md#Component Strategy → WiFiSection] — header (`Label("WI-FI") + Toggle($isPowered)`), connected row first, "Other Network…", "Open Network Settings…" footer rows (deferred to Epic 2)
- [Source: \_bmad-output/planning-artifacts/ux-design-specification.md#Component Strategy → WiFiRow] — `HStack { Checkmark?; SSIDText(.body); Spacer; LockIcon?; CaptiveIcon?; SignalBars }`; states `.normal`, `.connected`, `.expanded`, `.connecting` (Story 1.4 covers `.normal` and `.connected` only; `.expanded` and `.connecting` are Epic 2)
- [Source: \_bmad-output/planning-artifacts/ux-design-specification.md#Empty / Loading / Zero States] — Wi-Fi list empty (`.callout` "No networks found"); initial scan / connecting (no loading state — list shows existing data; new results merge in)
- [Source: \_bmad-output/planning-artifacts/ux-design-specification.md#Animation & Motion Patterns] — section reorder 250 ms; row expand/collapse 250 ms (Epic 2); Reduce Motion = instant
- [Source: \_bmad-output/planning-artifacts/ux-design-specification.md#VoiceOver Label Templates] — `WiFiRow` (normal): `"{SSID}, {securityType}, signal {strength}"`; (connected): `"{SSID}, connected, {securityType}, signal {strength}"`
- [Source: \_bmad-output/planning-artifacts/architecture.md#UI Architecture] — `NSHostingController<RootPanelView>` + `sizingOptions = .intrinsicContentSize` + AppState `@EnvironmentObject` (PRD 07 D3); panel-open Wi-Fi scan hook (PRD 02 D16) — `Task { try? await appState.wifiMonitor.requestScan() }` is the canonical scan trigger (Story 1.4 drops the `try?` because `requestScan()` is non-throwing per Story 1.3)
- [Source: \_bmad-output/planning-artifacts/architecture.md#Architectural Boundaries] — UI imports `CoreWLAN` forbidden; UI subscribes to `AppState` only (NFR35); `Network/Models/` Foundation-only; `State/` AppKit/SwiftUI forbidden
- [Source: \_bmad-output/planning-artifacts/architecture.md#Communication Patterns] — `@EnvironmentObject` injection point at NSHostingController creation; SwiftUI auto re-render on `@Published`
- [Source: \_bmad-output/planning-artifacts/architecture.md#Process Patterns] — init order (load-bearing); Reduce Motion gating; build-config branching limited to mock data and test hooks
- [Source: \_bmad-output/planning-artifacts/architecture.md#Pattern Examples] — good Sendable extraction patterns (cross-reference for any future `@Sendable` closure additions)
- [Source: \_bmad-output/planning-artifacts/prd.md#Functional Requirements / Wi-Fi Network Discovery] — FR23–28 referenced; FR24 (Hidden Network literal); FR25 (captive globe); FR26 (scan-on-show); FR27 (push-event-driven list refresh); FR28 (connected-row checkmark)
- [Source: \_bmad-output/planning-artifacts/prd.md#Non-Functional Requirements / Performance] — NFR2 (popover first paint ≤200 ms cold / ≤100 ms warm)
- [Source: \_bmad-output/planning-artifacts/prd.md#Non-Functional Requirements / Reliability] — NFR3 (scanning indicator while empty + scanning); NFR5 (300 ms debounce — already enforced by Story 1.3)
- [Source: \_bmad-output/planning-artifacts/prd.md#Resource Discipline] — FR50, NFR50 (no polling)
- [Source: \_bmad-output/planning-artifacts/prd.md#Non-Functional Requirements / Accessibility] — NFR23 (combined accessibility labels); NFR24 (UX-DR22 row label templates); NFR27 (decorative glyphs `.accessibilityHidden`); NFR28 (Reduce Motion); NFR31 (semantic colors only); NFR35 (UI subscribes to AppState only)
- [Source: \_bmad-output/implementation-artifacts/1-3-wifimonitor-on-demand-scan-push-events-scanstatus-timeout.md] — Story 1.3 carry-forward: `WiFiMonitorProtocol` shape (non-throwing `requestScan()`), `MockWiFiMonitor.sampleNetworks`, `WiFiNetwork.id` BSSID-or-composite fallback, `AppState.scanStatus` mirror, `AppState.networkState` populated via `CombineLatest4`, `_setNetworkStateForTesting` test helper, deferred Identifiable-duplicate-id dedupe (now resolved here)
- [Source: \_bmad-output/implementation-artifacts/1-2-appstate-statusitemcontroller-and-popover-skeleton.md] — Story 1.2 carry-forward: `RootPanelView` placeholder shape, `PanelLayout` constants enum location, `PopoverBackground` material setup, `NSHostingController(rootView: AnyView(RootPanelView().environmentObject(appState)))` injection point, `xcodegen generate` workflow with `DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer`

## Dev Agent Record

### Agent Model Used

Claude (BMad dev-story workflow, Opus 4.x)

### Debug Log References

- No runtime debug logs — implemented on a Linux/web session without Xcode. `xcodebuild` build/test
  and Instruments/VoiceOver/Reduce-Motion manual verification (Task 8) are pending local execution
  on macOS + Xcode 16. All logic is authored to spec; pure-function tests are deterministic.

### Completion Notes List

- Task 1 — `PanelLayout` extended with the 8 documented constants; the `// Story 1.4 will add: …`
  placeholder comment dropped. `Theme.swift` remains `Foundation` + `CoreGraphics` only.
- Task 2 — `SignalBars` implemented as the PRD 04 D6 custom 4-bar `RoundedRectangle` `HStack`
  (not SF Symbols — `wifi.0…3` are macOS 14+). Static `activeBars(for:)` is `Sendable`/testable.
- Task 3 — `WiFiRow` matches the canonical anatomy; decorative glyphs `.accessibilityHidden(true)`,
  combined label via `accessibilityLabel(for:)` per UX-DR22 (`"password required"` copy, no hyphen).
  Hidden networks render the literal `"Hidden Network"` (FR24). Captive marker not in the label.
- Task 4 — `WiFiSection` renders header (uppercase "WI-FI" + non-functional `wifiPowerStub` toggle)
  and the three content states (scanning-empty, idle-empty, populated). `displayedNetworks(from:)`
  dedupes the connected row from "others" (resolves the Story 1.3 Identifiable collision). Animation
  gated on Reduce Motion. No `ScrollView`/`List` (Epic 2 owns overflow).
- Task 5 — `RootPanelView` composes `WiFiSection`; `PopoverBackground()` preserved (no double material).
- Task 6 — `PopoverController` stores `appState`; `// Story 1.4: scan-on-show hook` comment replaced
  with `triggerScanOnShow()` firing `Task { @MainActor [appState] in await …requestScan() }`
  (no `self` capture, no `try?`). `#if DEBUG _triggerScanOnShowForTesting()` test hook added.
- Task 7 — New tests: `SignalBarsTests`, `WiFiRowTests`, `WiFiSectionTests`; extended
  `PopoverControllerTests` with `testTriggerScanOnShowFiresRequestScan` (sink-driven idle→scanning→idle).
- Task 8 — `project.yml` recursive `path: LinkHub`/`LinkHubTests` globs cover the new
  `UI/Panels/`, `UI/Components/`, `LinkHubTests/UI/**` files; no `project.yml` edit needed.
  **`xcodegen generate` + `xcodebuild` build/test + manual (VoiceOver/Reduce-Motion/Instruments)
  verification remain to be run locally on macOS** — cannot run on this Linux session.

### File List

- `LinkHub/UI/Theme.swift` (MODIFIED)
- `LinkHub/UI/Components/SignalBars.swift` (NEW)
- `LinkHub/UI/Components/WiFiRow.swift` (NEW)
- `LinkHub/UI/Panels/WiFiSection.swift` (NEW)
- `LinkHub/UI/PopoverRootView.swift` (MODIFIED)
- `LinkHub/MenuBar/PopoverController.swift` (MODIFIED)
- `LinkHubTests/UI/Components/SignalBarsTests.swift` (NEW)
- `LinkHubTests/UI/Components/WiFiRowTests.swift` (NEW)
- `LinkHubTests/UI/Panels/WiFiSectionTests.swift` (NEW)
- `LinkHubTests/MenuBar/PopoverControllerTests.swift` (MODIFIED)

### Change Log

| Date | Change |
|---|---|
| 2026-05-10 | Story created via bmad-create-story workflow. Status: ready-for-dev. Three spec divergences flagged in Dev Notes "Spec conflicts and resolutions": (1) section header style — epic AC + UX caption-uppercase wins over PRD 04 D12 subheadline-mixed-case; (2) empty-state visual — epic AC + UX text-only `.callout` wins over PRD 04 D17 wifi.slash-icon; (3) signal bars rendering — PRD 04 D6 RoundedRectangle bars wins over epic AC "SF Symbol" (SF Symbols `wifi.0…wifi.3` are macOS 14+ only; floor is 13.0). Each conflict explicitly documented for future PRD reconciliation. |
| 2026-06-08 | dev-story implementation complete (all 8 tasks). 4 source files added/modified, 1 component + 1 section + signal bars; scan-on-show wired in `PopoverController`. 3 new test files + 1 extended. Status → review. All three flagged spec divergences implemented as resolved (uppercase header, text-only empty state, RoundedRectangle signal bars). Build/test + manual a11y/perf verification deferred to local macOS run (web session has no Xcode). |
| 2026-06-08 | code-review (fresh-context static review, Swift 6 concurrency + spec-faithfulness): no BLOCKERs. Verified `[appState]` Task capture safety, `@ViewBuilder` leading-`let` legality, synchronous `@Published` sink emit (the `[.idle,.scanning,.idle]` assertion holds), and macOS 13 API availability. Applied one fix: empty-state guard now also checks `isWiFiHardwareAvailable` (AC #8 — guard was one-sided). Status → done. |
