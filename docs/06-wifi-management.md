# PRD 06 — Wi-Fi Network Management

**Status:** ✅ Done  
**Depends on:** 03, 04, 08  
**Blocks:** 07

---

## Problem Statement

> How does LinkHub display the Wi-Fi network list, connect to and forget networks, handle
> passwords and Keychain storage, surface hidden networks, detect captive portals, and
> manage Wi-Fi power — all within the constraints of `NSPopover` on macOS 13+?

This PRD decides:

- **`NetworkRow` component** — exact layout, signal bar count, RSSI-to-fill mapping,
  tap action, and accessory icons for connected, secured, enterprise, and captive rows
- **Password connect flow** — where the prompt appears (inline expansion vs. NSPanel)
- **Open network connect flow** — single-tap connection with row-level spinner
- **Enterprise (802.1X) network treatment** — resolves PRD 03 Open Question #3
- **Forget network flow** — trigger mechanism, `CWWiFiClient.removeProfile` authorization
- **Hidden network join ("Other Networks…")** — resolves PRD 04 Open Question #2; NSPanel
  vs. sheet from popover
- **Wi-Fi toggle** — `CWInterface.setPower` authorization and error handling
- **"Open Network Settings…" URL scheme** — macOS 13/14 version-conditional deeplinks
- **Location denial state UI** — view replacing network list when permission denied
- **Captive portal detection** — `CWNetwork.captiveNetwork` read path and UI response
- **Scan trigger and manual refresh** — when scans fire and how refresh is exposed

---

## Decision Log

| # | Decision | Options Considered | Choice | Rationale |
|---|----------|--------------------|--------|-----------|
| 1 | **Signal bar count in `SignalBarsView`** | 3 bars; 4 bars | **4 bars** | macOS system Wi-Fi menu and Control Center use 4-bar signal display. 4 bars aligns with the 4 signal quality tiers already defined in PRD 04 (excellent/good/fair/weak), yielding a 1:1 RSSI tier → fill-level mapping with no lossy rounding. |
| 2 | **RSSI → fill-level mapping** | Linear dBm scaling; tier-based fill | **Tier-based: rssi ≥ −60 → 4, −61…−70 → 3, −71…−80 → 2, < −80 → 1** | Matches the `signalQuality` tiers defined normatively in PRD 04. Linear dBm scaling produces unintuitive sub-pixel fills and does not reflect the perceptual steps in actual signal quality. |
| 3 | **`NetworkRow` tap action — connected row** | No action; show detail sheet; toggle disconnect | **No action on tap; secondary action (right-click) exposes context menu** | The connected row is informational. Disconnecting Wi-Fi is rare; burying it behind right-click prevents accidental disconnects. Matches macOS system Wi-Fi menu behaviour where the connected row is not tappable. |
| 4 | **`NetworkRow` tap action — unconnected row** | Connect immediately; open detail; show inline expansion | **Connect immediately — open/enterprise networks; inline expansion for password-required PSK networks** | Direct connect for open networks is instant and frictionless (matches system menu). Password networks need a field to type the passphrase; inline expansion keeps context without spawning a window. |
| 5 | **Password prompt location** | Inline expansion below row (Option A); sheet from popover (Option B — unsupported macOS 13); NSPanel (Option C) | **Option A: inline expansion below the tapped `NetworkRow`** | Sheet from `NSPopover` is unsupported on macOS 13 (PRD 04 constraint). NSPanel adds window lifecycle complexity for a single-field form. Inline expansion is fully SwiftUI, auto-resizes the popover via `sizingOptions = .intrinsicContentSize`, and keeps focus inside the popover. **Resolves PRD 04 Open Question #2 for PSK networks.** |
| 6 | **`CWWiFiClient.associate` thread** | Main thread (blocks UI); `Task.detached` on cooperative pool; dedicated serial `DispatchQueue` | **`Task.detached(priority: .userInitiated)`** | `associate(to:password:rememberCredentials:)` is synchronous and can take 3–8 seconds. Calling it on the main actor would freeze the UI. `Task.detached` places it on the cooperative thread pool; its return crosses back to `@MainActor` via `await`. Consistent with the `requestScan()` pattern from PRD 03. |
| 7 | **Enterprise (802.1X) `requiresPassword` value** | `true` (requires credential); `false` (no PSK) | **`requiresPassword = false` for `WiFiSecurity.enterprise`** | Enterprise networks authenticate via EAP/certificate negotiated by the supplicant (system-managed), not a user-typed passphrase. Showing the inline password expansion for 802.1X is incorrect. A distinct "802.1X" badge communicates the security type without prompting for a password. **Resolves PRD 03 Open Question #3.** |
| 8 | **Enterprise connect attempt** | Block connection in-app; attempt `associate(to:password:nil, rememberCredentials:false)`; deeplink only | **Attempt `associate(to:password:nil, rememberCredentials:false)`; on `CWError.notPermitted` show inline deeplink to Network Settings** | If the user has already configured 802.1X credentials in System Settings, the `associate` call succeeds. If not, `CWError.notPermitted` is thrown and the inline message guides the user to configure credentials. This avoids blocking users who have already set up 802.1X. |
| 9 | **Forget network authorization** | In-app `AuthorizationServices` admin prompt; open System Settings deeplink; disable feature | **Open System Settings deeplink: `x-apple.systempreferences:com.apple.wifi-settings-extension`** | `CWWiFiClient.removeProfile(_:authorization:)` requires an `AuthorizationRef` with admin rights. `AuthorizationServices` is deprecated since macOS 14. Forget is an infrequent, destructive action — leaving the popover to complete it in System Settings is acceptable and avoids any deprecated API surface. |
| 10 | **Forget network trigger** | Right-click context menu; long-press; dedicated "×" button on hover | **Right-click (secondary click) context menu with "Forget This Network" item** | Context menus are the established macOS pattern for destructive row actions (Finder, Safari bookmarks). A hover "×" button risks accidental taps. Long-press has no standard macOS affordance on cursor-based input. |
| 11 | **"Other Networks…" hidden network UI** | Sheet from popover (unsupported macOS 13); `NavigationStack` push (unsupported in `NSPopover`); `NSPanel` | **`NSPanel` (standalone floating window)** | Neither sheet nor `NavigationStack` is viable inside `NSPopover` on macOS 13. `NSPanel` with `NSHostingController<OtherNetworkView>` is the correct macOS pattern for accessory floating windows. Non-activating (`becomesKeyOnlyIfNeeded = true`) so the menu bar app does not steal activation. **Fully resolves PRD 04 Open Question #2.** |
| 12 | **Wi-Fi toggle authorization** | Require admin auth before `setPower`; attempt without auth; disable toggle | **Attempt `CWInterface.setPower(_:error:)` without admin auth; handle error gracefully** | On macOS 13+ the system allows non-admin users to toggle Wi-Fi via Control Center. `setPower` succeeds for the current user in the same context. If it throws, revert the toggle and show a transient error label — no in-app auth required. |
| 13 | **"Open Network Settings…" URL scheme** | `x-apple.systempreferences:com.apple.preference.network` (legacy); `x-apple.systempreferences:com.apple.wifi-settings-extension` (Ventura+) | **`wifi-settings-extension` with `preference.network` fallback** | `wifi-settings-extension` is available on macOS 13 (Ventura) and later and opens directly to the Wi-Fi pane. `NSWorkspace.open` returns `false` if the URL is unhandled — the fallback catches any edge case. |
| 14 | **Captive portal open mechanism** | Open `http://captive.apple.com` in browser; open Safari with portal URL; do nothing | **`NSWorkspace.shared.open(URL(string: "http://captive.apple.com")!)` — opens in default browser** | macOS redirects `http://captive.apple.com` to the captive portal login page. Opening in the default browser is less intrusive than forcing Safari. The system captive network assistant may already have opened a sheet — LinkHub's button is a fallback for users who dismissed it. |
| 15 | **Scan after connect/disconnect** | No auto-rescan; immediate rescan; delayed rescan | **1.5 s delayed `requestScan()` after `associate()` completes; immediate rescan after disconnect** | After `associate()` the association state takes ~1 s to settle (DHCP, RSSI update). An immediate rescan may catch a transient state. 1.5 s avoids the race. After disconnect the interface drops immediately, so an immediate rescan is correct. |
| 16 | **Manual refresh affordance** | No button; pull-to-refresh; icon button in header | **`Image(systemName: "arrow.clockwise")` button in `WiFiSectionHeader` trailing area** | Matches the "refresh" idiom in macOS status bar panels. Disabled and rotating during an active scan. Avoids the pull-to-refresh gesture (non-standard on macOS). |
| 17 | **`isCaptive` field in `WiFiNetwork`** | Read `CWNetwork.captiveNetwork` during scan and store; check at display time | **Add `isCaptive: Bool` to `WiFiNetwork`; read `CWNetwork.captiveNetwork` during scan extraction in `WiFiMonitor.requestScan()`** | `captiveNetwork` is a read-only `CWNetwork` property — it must be read on the scan thread before `CWNetwork` is discarded (per PRD 03 Decision #12 on `Sendable` extraction). Storing it in the value type makes it available at render time without extra CoreWLAN calls. |

---

## Data Model Addition

`WiFiNetwork.swift` gains one field not present in the PRD 03 definition (PRD 03 explicitly deferred captive portal to PRD 06):

```swift
struct WiFiNetwork: Identifiable, Equatable, Sendable {
    let id: String          // BSSID
    let ssid: String?
    let bssid: String
    let rssi: Int
    let isConnected: Bool
    let requiresPassword: Bool   // false for .enterprise and .none
    let security: WiFiSecurity
    let isCaptive: Bool          // NEW — CWNetwork.captiveNetwork
}
```

Extraction in `WiFiMonitor.requestScan()` (on `Task.detached` thread, before actor crossing):

```swift
// Inside Task.detached — CWNetwork is not Sendable; extract all fields here
WiFiNetwork(
    id:               cwNetwork.bssid ?? "",
    ssid:             cwNetwork.ssid,
    bssid:            cwNetwork.bssid ?? "",
    rssi:             cwNetwork.rssiValue,
    isConnected:      cwNetwork.bssid == connectedBSSID,
    requiresPassword: cwNetwork.security() != .none && cwNetwork.security() != .enterprise,
    security:         WiFiSecurity(from: cwNetwork.security()),
    isCaptive:        cwNetwork.captiveNetwork
)
```

---

## `NetworkRow` Component Spec

**File:** `UI/Components/NetworkRow.swift`

### Layout (row height: 44 pt, H padding: 16 pt, V padding: 11 pt)

```
HStack(spacing: 8) {
    SignalBarsView(rssi: network.rssi)          // 16 × 12 pt bounding box
    if network.requiresPassword
    || network.security == .enterprise {
        Image(systemName: "lock.fill")          // 11 pt, .secondary
    }
    VStack(alignment: .leading, spacing: 1) {
        Text(network.ssid ?? "Hidden Network")  // .body; .semibold if isConnected
            .lineLimit(1)
        if network.security == .enterprise {
            Text("802.1X")                      // .caption2, .secondary
        }
        if network.isConnected && network.isCaptive {
            Text("Sign in required")            // .caption2, .secondary
        }
    }
    Spacer()
    trailingAccessory                           // see table below
}
.padding(.horizontal, 16)
.padding(.vertical, 11)
.frame(minHeight: 44)
```

### Trailing Accessory Logic

| State | Accessory |
|-------|-----------|
| `isConnected && !isCaptive` | `Image(systemName: "checkmark")`, `.accentColor` |
| `isConnected && isCaptive` | `Image(systemName: "network.badge.shield.half.filled")`, `.orange` |
| `isConnecting` | `ProgressView()`, 16 pt control size `.small` |
| none of the above | _(empty)_ |

### `SignalBarsView` Spec

Four `RoundedRectangle(cornerRadius: 1.5)` bars in `HStack(spacing: 2)`, ascending heights (5, 8, 11, 14 pt), fixed width 3.5 pt each.

Fill count = `network.rssi.signalQuality.barCount`:

| RSSI (dBm) | `signalQuality` | `barCount` |
|------------|-----------------|------------|
| ≥ −60 | `.excellent` | 4 |
| −61 … −70 | `.good` | 3 |
| −71 … −80 | `.fair` | 2 |
| < −80 | `.weak` | 1 |

Filled bars: `.foregroundStyle(.primary)`.  
Unfilled bars: `.foregroundStyle(.primary.opacity(0.25))`.  
`SignalBarsView` carries `.accessibilityHidden(true)` — signal strength is expressed in the row's `accessibilityLabel`.

### Swift Pseudocode

```swift
// UI/Components/NetworkRow.swift

struct NetworkRow: View {
    let network: WiFiNetwork
    var onConnect: (WiFiNetwork, String?, Bool) async throws -> Void  // (network, password, remember)
    var onDisconnect: () -> Void
    var onCaptiveSignIn: (WiFiNetwork) -> Void

    @State private var isHovered = false
    @State private var isExpanded = false   // password prompt visible
    @State private var isConnecting = false
    @State private var connectError: String?

    var body: some View {
        VStack(spacing: 0) {
            // ── Main row ──────────────────────────────────────
            HStack(spacing: 8) {
                SignalBarsView(rssi: network.rssi)
                    .frame(width: 16, height: 12)
                    .accessibilityHidden(true)

                if network.requiresPassword || network.security == .enterprise {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(network.ssid ?? "Hidden Network")
                        .font(.body)
                        .fontWeight(network.isConnected ? .semibold : .regular)
                        .lineLimit(1)
                    if network.security == .enterprise {
                        Text("802.1X")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if network.isConnected && network.isCaptive {
                        Text("Sign in required")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isConnecting {
                    ProgressView().controlSize(.small)
                } else if let err = connectError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if network.isConnected && network.isCaptive {
                    Image(systemName: "network.badge.shield.half.filled")
                        .foregroundStyle(.orange)
                } else if network.isConnected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.accentColor)
                }
            }
            .padding(.horizontal, PanelLayout.rowHPad)
            .padding(.vertical, PanelLayout.rowVPad)
            .frame(minHeight: PanelLayout.rowHeight)
            .contentShape(Rectangle())
            .onTapGesture { handleTap() }
            .onHover { isHovered = $0 }
            .background(
                isHovered
                    ? Color(nsColor: .controlAccentColor).opacity(0.12)
                    : Color.clear
            )

            // ── Inline password expansion ─────────────────────
            if isExpanded {
                PasswordPromptView(
                    network: network,
                    onJoin: { password, remember in
                        Task { await connectWithPassword(password, remember: remember) }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .contextMenu { contextMenuItems }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(network.isConnected ? .isSelected : [])
    }

    private func handleTap() {
        if network.isConnected && network.isCaptive {
            onCaptiveSignIn(network)
            return
        }
        guard !network.isConnected else { return }
        if network.requiresPassword {
            connectError = nil
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        } else {
            // Open network or enterprise — connect directly
            Task { await connectDirectly() }
        }
    }

    @MainActor
    private func connectDirectly() async {
        isConnecting = true
        connectError = nil
        defer { isConnecting = false }
        do {
            try await onConnect(network, nil, true)
        } catch let cwe as CWError {
            connectError = NetworkRow.message(for: cwe, isEnterprise: network.security == .enterprise)
        } catch {
            connectError = "Connection failed."
        }
    }

    @MainActor
    private func connectWithPassword(_ password: String, remember: Bool) async {
        isConnecting = true
        withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false }
        defer { isConnecting = false }
        do {
            try await onConnect(network, password, remember)
        } catch {
            // Re-open expansion with error — PasswordPromptView handles error display
            // via its own onJoin async throws path; this catch handles unexpected throws
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true }
        }
    }

    private static func message(for error: CWError, isEnterprise: Bool) -> String {
        switch error.code {
        case .notPermitted where isEnterprise:
            return "Configure 802.1X in Network Settings."
        case .notPermitted:
            return "Incorrect password. Please try again."
        case .timeout:
            return "Connection timed out."
        default:
            return "Connection failed."
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if network.isConnected {
            Button("Disconnect") { onDisconnect() }
            Divider()
        }
        Button("Forget This Network") { forgetNetwork() }
    }

    private func forgetNetwork() {
        // CWWiFiClient.removeProfile requires admin auth — open System Settings
        let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!
        NSWorkspace.shared.open(url)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [network.ssid ?? "Hidden Network"]
        parts.append(network.rssi.signalQuality.accessibilityDescription)
        if network.security == .enterprise {
            parts.append("802.1X enterprise network")
        } else {
            parts.append(network.requiresPassword ? "password required" : "open network")
        }
        if network.isConnected && network.isCaptive { parts.append("sign in required") }
        else if network.isConnected { parts.append("connected") }
        return parts.joined(separator: ", ")
    }
}
```

---

## Password Prompt Component Spec

Embedded inside `NetworkRow.swift` as `PasswordPromptView` (not a separate file — collocated with its only consumer).

```swift
// Inside UI/Components/NetworkRow.swift

struct PasswordPromptView: View {
    let network: WiFiNetwork
    var onJoin: (String, Bool) async throws -> Void  // throws CWError
    var onCancel: () -> Void

    @State private var password = ""
    @State private var showPassword = false
    @State private var rememberNetwork = true
    @State private var isJoining = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Password field + show/hide toggle
            HStack {
                Group {
                    if showPassword {
                        TextField("Password", text: $password)
                            .onSubmit { attemptJoin() }
                    } else {
                        SecureField("Password", text: $password)
                            .onSubmit { attemptJoin() }
                    }
                }
                .textFieldStyle(.roundedBorder)
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Remember toggle
            Toggle("Remember this network", isOn: $rememberNetwork)
                .toggleStyle(.checkbox)
                .font(.caption)

            // Action buttons
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    attemptJoin()
                } label: {
                    if isJoining {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Join")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || isJoining)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PanelLayout.rowHPad)
        .padding(.bottom, 12)
        .onAppear {
            // Pre-fill with saved passphrase if available
            if let saved = KeychainService.loadPassword(forSSID: network.ssid ?? "") {
                password = saved
            }
        }
    }

    private func attemptJoin() {
        guard !password.isEmpty else { return }
        isJoining = true
        errorMessage = nil
        Task {
            defer { isJoining = false }
            do {
                try await onJoin(password, rememberNetwork)
            } catch let cwe as CWError {
                errorMessage = Self.message(for: cwe)
            } catch {
                errorMessage = "Connection failed."
            }
        }
    }

    private static func message(for error: CWError) -> String {
        switch error.code {
        case .notPermitted: return "Incorrect password. Please try again."
        case .timeout:      return "Connection timed out. Move closer to the network."
        default:            return "Connection failed."
        }
    }
}
```

---

## `WiFiSection` & `WiFiSectionHeader` Spec

**File:** `UI/Panels/WiFiSection.swift`

### `WiFiSectionHeader`

```swift
HStack {
    Text("Wi-Fi")
        .font(.subheadline).fontWeight(.semibold)
        .foregroundStyle(.secondary)
    Spacer()
    // Manual refresh
    Button {
        Task { try? await wifiMonitor.requestScan() }
    } label: {
        Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(isScanning ? 360 : 0))
            .animation(
                isScanning
                    ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                    : .default,
                value: isScanning
            )
    }
    .buttonStyle(.plain)
    .disabled(isScanning || !wifiEnabled)
    .accessibilityLabel("Refresh Wi-Fi networks")
    // Power toggle
    Toggle("", isOn: $wifiEnabled)
        .toggleStyle(.switch)
        .accessibilityLabel("Wi-Fi")
        .onChange(of: wifiEnabled) { _, newValue in
            Task { await setWiFiPower(newValue) }
        }
}
.padding(.horizontal, PanelLayout.rowHPad)
.padding(.vertical, PanelLayout.sectionHeaderVPad)
```

### `WiFiSection` State Machine

| Condition | Content in `ScrollView` |
|-----------|-------------------------|
| `wifiLocationDenied` | `LocationDenialView` (replaces scroll region) |
| `!wifiEnabled` | `EmptyStateRow("Turn on Wi-Fi to see nearby networks.")` |
| `isScanning && networks.isEmpty` | `ProgressView()` row + label "Searching for networks…" |
| `networks.isEmpty && !isScanning` | SF Symbol `wifi.slash` + `"No Networks Found"` |
| otherwise | Connected row (pinned top) + `ForEach(otherNetworks)` + `WiFiSectionFooter` |

`otherNetworks` = `networks.filter { !$0.isConnected }.sorted { $0.rssi > $1.rssi }` (strongest signal first).

### `WiFiSection` Closure Implementations

```swift
// onConnect: (WiFiNetwork, String?, Bool) async throws -> Void
onConnect: { network, password, remember in
    try await wifiMonitor.connect(to: network, password: password, remember: remember)
}

// onDisconnect: () -> Void
onDisconnect: {
    Task { await wifiMonitor.disconnect() }
}

// onCaptiveSignIn: (WiFiNetwork) -> Void
onCaptiveSignIn: { _ in
    NSWorkspace.shared.open(URL(string: "http://captive.apple.com")!)
}
```

### `WiFiSectionFooter` Spec

Two plain button rows at the bottom of the network list. Both buttons are always visible when the Wi-Fi section is shown (including when Wi-Fi is disabled — per PRD 04 State C wireframe which shows "Open Network Settings…" in the disabled state). Tapping "Other Networks…" opens `OtherNetworkPanel`.

```swift
// Embedded in UI/Panels/WiFiSection.swift

struct WiFiSectionFooter: View {
    var onOtherNetworks: () -> Void   // shows OtherNetworkPanel

    var body: some View {
        VStack(spacing: 0) {
            Button("Other Networks…", action: onOtherNetworks)
                .buttonStyle(.plain)
                .font(.body)
                .foregroundStyle(.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PanelLayout.rowHPad)
                .padding(.vertical, PanelLayout.rowVPad)
                .frame(minHeight: PanelLayout.rowHeight)
                .contentShape(Rectangle())
                .accessibilityLabel("Join other network")

            Button("Open Network Settings…") {
                SystemSettingsService.openNetworkSettings()
            }
            .buttonStyle(.plain)
            .font(.body)
            .foregroundStyle(.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PanelLayout.rowHPad)
            .padding(.vertical, PanelLayout.rowVPad)
            .frame(minHeight: PanelLayout.rowHeight)
            .contentShape(Rectangle())
            .accessibilityLabel("Open Network Settings")
        }
    }
}
```

### Wi-Fi Power Toggle Error Handling

`setPower` is a synchronous blocking CoreWLAN call — it must not run on `@MainActor`. Dispatch to a detached task and revert the toggle on the main actor if it fails.

```swift
@MainActor
private func setWiFiPower(_ on: Bool) async {
    do {
        try await Task.detached(priority: .userInitiated) {
            var nsError: NSError?
            let iface = CWWiFiClient.shared().interface()
            guard iface?.setPower(on, error: &nsError) == true else {
                throw nsError ?? NSError(domain: NSOSStatusErrorDomain, code: -1)
            }
        }.value
    } catch {
        wifiEnabled = !on
        powerErrorMessage = "Could not change Wi-Fi power"
        try? await Task.sleep(for: .seconds(3))
        powerErrorMessage = nil
    }
}
```

---

## Location Denial View Spec

Shown in `WiFiSection` when `AppState.wifiLocationDenied == true`. Replaces the `ScrollView` content entirely.

```swift
// Embedded in UI/Panels/WiFiSection.swift

struct LocationDenialView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Wi-Fi scanning requires Location access.")
                .font(.body)
                .multilineTextAlignment(.center)
            Text("LinkHub needs Location permission to show nearby networks.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Privacy Settings") {
                SystemSettingsService.openLocationPrivacySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, PanelLayout.rowHPad)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }
}
```

---

## "Other Networks…" Panel Spec

**File:** `UI/Windows/OtherNetworkPanel.swift`

### `OtherNetworkPanel` (NSPanel subclass)

### `OtherNetworkPanel` Lifecycle

The panel is created lazily in `WiFiSection` and stored strongly so it isn't deallocated:

```swift
// In WiFiSection
@State private var otherNetworkPanel: OtherNetworkPanel?

// In WiFiSectionFooter button action:
if otherNetworkPanel == nil {
    otherNetworkPanel = OtherNetworkPanel(
        positioningWindow: NSApp.keyWindow,
        wifiMonitor: wifiMonitor
    )
}
otherNetworkPanel?.makeKeyAndOrderFront(nil)

// In WiFiSection.body:
.onDisappear { otherNetworkPanel?.close() }
```

```swift
// UI/Windows/OtherNetworkPanel.swift

final class OtherNetworkPanel: NSPanel {

    init(positioningWindow: NSWindow?, wifiMonitor: WiFiMonitor) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),  // intrinsic sizing takes over
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Other Network"
        becomesKeyOnlyIfNeeded = true
        isFloatingPanel = true
        hidesOnDeactivate = false

        let hostingController = NSHostingController(
            rootView: OtherNetworkView(
                onJoin: { [weak self] ssid, security, password, remember in
                    Task { try? await wifiMonitor.connect(
                        ssid: ssid,
                        security: security,
                        password: password,
                        remember: remember
                    )}
                    self?.close()
                },
                onCancel: { [weak self] in self?.close() }
            )
        )
        hostingController.sizingOptions = .intrinsicContentSize  // panel resizes with content
        contentViewController = hostingController

        // Position below the status item — use the screen containing the parent window
        if let parentWindow = positioningWindow,
           let screen = parentWindow.screen ?? NSScreen.main {
            let parentFrame = parentWindow.frame
            let panelWidth: CGFloat = 400
            var origin = NSPoint(
                x: parentFrame.minX,
                y: parentFrame.minY - 280
            )
            // Clamp to screen visible area
            let visibleArea = screen.visibleFrame
            origin.x = max(visibleArea.minX, min(origin.x, visibleArea.maxX - panelWidth))
            origin.y = max(visibleArea.minY + 10, origin.y)
            setFrameOrigin(origin)
        } else {
            center()
        }
    }
}

struct OtherNetworkView: View {
    var onJoin: (String, WiFiSecurity, String?, Bool) -> Void
    var onCancel: () -> Void

    @State private var ssid = ""
    @State private var securityChoice: SecurityChoice = .wpa2wpa3
    @State private var password = ""
    @State private var showPassword = false
    @State private var rememberNetwork = true
    @State private var isJoining = false
    @State private var errorMessage: String?

    enum SecurityChoice: String, CaseIterable, Identifiable {
        case none       = "None"
        case wpa2wpa3   = "WPA2/WPA3 Personal"
        case wpa3       = "WPA3 Personal"
        case enterprise = "WPA2/WPA3 Enterprise"
        var id: String { rawValue }
        var requiresPassword: Bool { self != .none }
        var wifiSecurity: WiFiSecurity {
            switch self {
            case .none:       return .none
            case .wpa2wpa3:   return .wpa2Personal
            case .wpa3:       return .wpa3Personal
            case .enterprise: return .enterprise
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Other Network")
                .font(.headline)
            Form {
                TextField("Network Name", text: $ssid)
                Picker("Security:", selection: $securityChoice) {
                    ForEach(SecurityChoice.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                if securityChoice.requiresPassword {
                    HStack {
                        Group {
                            if showPassword { TextField("Password", text: $password) }
                            else            { SecureField("Password", text: $password) }
                        }
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                    }
                    Toggle("Remember this network", isOn: $rememberNetwork)
                }
            }
            if let error = errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Join") {
                    let pw = securityChoice.requiresPassword ? password : nil
                    onJoin(ssid, securityChoice.wifiSecurity, pw, rememberNetwork)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    ssid.isEmpty
                    || (securityChoice.requiresPassword && password.isEmpty)
                    || isJoining
                )
            }
        }
        .padding(20)
        // No fixed .frame — NSHostingController.sizingOptions = .intrinsicContentSize
        // drives the panel height. Minimum width is enforced by the NSPanel content rect width.
    }
}
```

---

## `WiFiMonitor` API Additions

PRD 03 defined `requestScan()`. This PRD adds write-path methods to `Network/WiFiMonitor.swift`:

```swift
// Network/WiFiMonitor.swift — additions for PRD 06
// WiFiMonitor is @MainActor (PRD 03 Decision #9); all methods inherit that isolation.

/// Associates with a network. Dispatches synchronous CoreWLAN call off main actor.
/// CWNetwork is non-Sendable (PRD 03 Decision #12) — it is never passed across
/// isolation boundaries. The Task.detached body fetches CWNetwork from the cache
/// on the background thread using only the Sendable `bssid: String`.
/// Stores password in LinkHub Keychain for pre-fill on next expansion.
/// Throws CWError on failure.
func connect(to network: WiFiNetwork, password: String?, remember: Bool) async throws {
    guard let iface = CWWiFiClient.shared().interface() else {
        throw CWError(.operationNotPermitted)
    }
    let bssid = network.bssid  // String — Sendable; safe to capture across actor boundary
    try await Task.detached(priority: .userInitiated) {
        // CWNetwork fetched here on the background thread — never crosses actor boundary
        guard let cwNet = iface.cachedScanResults()?.first(where: { $0.bssid == bssid })
        else { throw CWError(.operationNotPermitted) }
        try iface.associate(to: cwNet, password: password, rememberCredentials: remember)
    }.value
    // Pre-fill store: saves password in LinkHub Keychain for next-time inline expansion
    if remember, let pw = password, let ssid = network.ssid {
        try? KeychainService.savePassword(pw, forSSID: ssid)
    }
    await refreshConnectedNetwork()
    try await Task.sleep(for: .milliseconds(1500))
    try? await requestScan()
}

/// Associates with a hidden network by SSID. Used by OtherNetworkPanel.
/// Scans for the network by SSID name on the background thread.
/// If not found in scan results, attempts associate with a nil BSSID (CoreWLAN resolves it).
func connect(ssid: String, security: WiFiSecurity, password: String?, remember: Bool) async throws {
    guard let iface = CWWiFiClient.shared().interface() else {
        throw CWError(.operationNotPermitted)
    }
    let ssidData = ssid.data(using: .utf8)
    try await Task.detached(priority: .userInitiated) {
        // Scan specifically for this SSID to locate its CWNetwork
        let results = try iface.scanForNetworks(withSSID: ssidData) 
        // Use first match; if none found (hidden network not broadcasting), try associating by SSID
        if let cwNet = results.first {
            try iface.associate(to: cwNet, password: password, rememberCredentials: remember)
        } else {
            // Network not found in scan — surface error to caller
            throw CWError(.operationNotPermitted)
        }
    }.value
    if remember, let pw = password {
        try? KeychainService.savePassword(pw, forSSID: ssid)
    }
    await refreshConnectedNetwork()
    try await Task.sleep(for: .milliseconds(1500))
    try? await requestScan()
}

/// Disassociates from the current network and triggers an immediate rescan.
/// `disassociate()` is synchronous and blocking — runs in a detached task.
func disconnect() async {
    await Task.detached(priority: .userInitiated) {
        CWWiFiClient.shared().interface()?.disassociate()
    }.value
    connectedNetwork = nil
    Task { try? await requestScan() }
}

/// Re-reads association state from CWInterface on the main actor.
/// isCaptive is set to false; it is re-populated on the next scan.
@MainActor
private func refreshConnectedNetwork() async {
    guard let iface = CWWiFiClient.shared().interface() else { return }
    // Extract Sendable values before publishing (PRD 03 Decision #12)
    if let bssid = iface.bssid() {
        connectedNetwork = WiFiNetwork(
            id: bssid, ssid: iface.ssid(), bssid: bssid,
            rssi: iface.rssiValue(), isConnected: true,
            requiresPassword: false,
            security: WiFiSecurity(from: iface.security()),
            isCaptive: false
        )
    } else {
        connectedNetwork = nil
    }
}
```

---

## `KeychainService` API

**File:** `Services/KeychainService.swift`

```swift
// Services/KeychainService.swift

enum KeychainService {

    private static let service = Bundle.main.bundleIdentifier ?? "com.linkhub"

    /// Stores a Wi-Fi passphrase for the given SSID.
    /// kSecAttrAccessibleAfterFirstUnlock per PRD 08 Decision #7.
    static func savePassword(_ password: String, forSSID ssid: String) throws {
        let data = Data(password.utf8)
        let query: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrService:    service,
            kSecAttrAccount:    ssid,
            kSecValueData:      data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)   // remove stale entry if any
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    /// Returns the stored passphrase for an SSID, or nil if not found.
    static func loadPassword(forSSID ssid: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: ssid,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let pw = String(data: data, encoding: .utf8) else { return nil }
        return pw
    }
}
```

---

## `SystemSettingsService` Additions

`SystemSettingsService` is defined in full in `Services/SystemSettingsService.swift` (see PRD 05 for the canonical definition). PRD 06 contributes `openWiFiSettings()` and `openLocationPrivacySettings()` — both are included in the merged definition in PRD 05.

All calls in this PRD use:
- `SystemSettingsService.openWiFiSettings()` — for the "Forget This Network" deeplink and Wi-Fi section header
- `SystemSettingsService.openLocationPrivacySettings()` — for the `LocationDenialView` button
- `SystemSettingsService.openNetworkSettings()` — for the `WiFiSectionFooter` "Open Network Settings…" button

---

## Error Message Catalogue

| Error | Condition | UI copy |
|-------|-----------|---------|
| Wrong password | `CWError.notPermitted` after PSK `associate` | "Incorrect password. Please try again." |
| Connection timeout | `CWError.timeout` | "Connection timed out. Move closer to the network." |
| 802.1X not configured | `CWError.notPermitted` after enterprise `associate` | "Configure 802.1X credentials in Network Settings." (with deeplink button) |
| Wi-Fi power toggle failed | `setPower` error ≠ nil | "Could not change Wi-Fi power." (auto-dismisses after 3 s) |
| Scan failed (generic) | `CWError` other than location | "Scan failed. Tap ↻ to try again." |
| Location denied | `CWError.operationNotPermitted` from scan | `LocationDenialView` replaces list |

---

## Captive Portal Flow

```
WiFiMonitor.requestScan()
    └── reads CWNetwork.captiveNetwork → WiFiNetwork.isCaptive = true

WiFiSection renders NetworkRow(network.isConnected && network.isCaptive):
    ├── trailing: network.badge.shield.half.filled (.orange)
    ├── subtitle: "Sign in required"
    └── onTap → NSWorkspace.shared.open("http://captive.apple.com")
                  macOS redirects to actual portal login URL
```

The system captive network assistant may have already shown a sheet. The `NetworkRow` tap provides a manual re-entry point if the user dismissed it.

---

## Scan Trigger Summary

| Event | Scan action |
|-------|-------------|
| Panel opens | `requestScan()` immediately |
| User taps ↻ refresh button | `requestScan()` immediately |
| `associate()` completes (any result) | `requestScan()` after 1.5 s delay |
| `disconnect()` called | `requestScan()` immediately |
| `CWEventDelegate.ssidDidChange` fires | No extra scan — `connectedNetwork` updated from `CWInterface` |
| App in background, panel closed | No scan — `scanCacheUpdated` not registered (PRD 03 Decision #6) |

---

## File Ownership

| File | Responsibility |
|------|----------------|
| `UI/Components/NetworkRow.swift` | `NetworkRow`, `SignalBarsView`, `PasswordPromptView` |
| `UI/Panels/WiFiSection.swift` | `WiFiSection`, `WiFiSectionHeader` (with refresh button), `WiFiSectionFooter`, `LocationDenialView` |
| `UI/Windows/OtherNetworkPanel.swift` | `OtherNetworkPanel` (`NSPanel` subclass), `OtherNetworkView` (SwiftUI) |
| `Network/WiFiMonitor.swift` | Adds `connect(to:password:remember:)`, `disconnect()`, `refreshConnectedNetwork()` |
| `Network/Models/WiFiNetwork.swift` | Adds `isCaptive: Bool` field |
| `Services/KeychainService.swift` | `savePassword(_:forSSID:)`, `loadPassword(forSSID:)` |
| `Services/SystemSettingsService.swift` | `openWiFiSettings()`, `openLocationPrivacySettings()` |

---

## Constraints

- **`CWWiFiClient.associate` is synchronous and must not run on the main thread.** All connect calls go through `Task.detached(priority: .userInitiated)`. Result is awaited back on `@MainActor` to update `connectedNetwork` and UI state. See PRD 03 threading summary.
- **`NSPopover` sheet is unsupported on macOS 13.** SwiftUI `.sheet` requires a `Window`-backed `Scene`. `OtherNetworkPanel` must be an `NSPanel`, not a `.sheet` modifier. This is the normative resolution of PRD 04 Open Question #2.
- **Inline password expansion auto-resizes the popover.** `NSHostingController.sizingOptions = .intrinsicContentSize` (PRD 04 Decision #8) propagates the new intrinsic height to `NSPopover.contentSize` automatically. No manual `contentSize` mutation needed.
- **`CWWiFiClient.removeProfile(_:authorization:)` requires admin rights.** `AuthorizationServices` is deprecated in macOS 14. LinkHub does not implement a privileged helper. The forget action opens System Settings rather than performing in-app elevation.
- **`isCaptive` must be read on the scan thread.** `CWNetwork.captiveNetwork` is an Obj-C property of a non-`Sendable` type. It must be accessed before the `Task.detached` body returns, during `WiFiNetwork` construction, per PRD 03 Decision #12.
- **Enterprise networks set `requiresPassword = false`.** The inline password expansion must not appear for `WiFiSecurity.enterprise`. The flag is derived at extraction time: `requiresPassword = security != .none && security != .enterprise`.
- **Swift 6 strict concurrency.** `WiFiNetwork` with `isCaptive: Bool` remains a plain value type with all `Sendable` stored properties — conformance is automatic. `OtherNetworkPanel` is `@MainActor`-confined (accessed only from `StatusItemController` on main actor). `OtherNetworkView` is a SwiftUI `View` struct — implicitly `Sendable`.
- **`NSPanel.becomesKeyOnlyIfNeeded = true`.** The Other Networks panel must not steal key status from the system or the popover. `isFloatingPanel = true` keeps it above standard windows without stealing activation.
- **`KeychainService` uses `kSecAttrAccessibleAfterFirstUnlock`.** Per PRD 08 Decision #7. Credentials must survive reboot without requiring a user unlock before LinkHub can reconnect.
- **`CWNetwork` must never cross actor boundaries.** `connect(to:password:remember:)` passes only the Sendable `bssid: String` into the `Task.detached` body, which re-fetches `CWNetwork` from `cachedScanResults()` on the background thread. If the cache is stale and no match is found, `connect` throws `CWError.operationNotPermitted` — user can tap the refresh button and retry. `findCWNetwork(bssid:)` is not implemented; it would create an unsafe Sendable crossing.
- **`CWInterface.disassociate()` and `setPower(_:error:)` are synchronous blocking calls.** Both must be dispatched via `Task.detached(priority: .userInitiated)` to avoid blocking `@MainActor`. `disconnect()` is async for this reason.

---

## Out of Scope

- **Disconnecting from Ethernet** — `EthernetMonitor` has no disconnect concept; physical link state is hardware-controlled.
- **Per-network traffic statistics** (bytes sent/received) — not exposed by `CWInterface`.
- **Wi-Fi 6 / 6E / 7 protocol badges** — `CWInterface` does not expose the PHY generation reliably on macOS 13.
- **VPN state interaction** — LinkHub shows physical Wi-Fi association state. Which packets traverse the Wi-Fi interface when a VPN is active is not tracked.
- **WEP network connection** — `WiFiSecurity.other` networks are displayed but may fail with `CWError.notPermitted`; the error surface handles this gracefully. Active WEP support is not a goal.
- **Passpoint / Hotspot 2.0 networks** — not a use case for this version.
- **Configuring 802.1X certificates in-app** — users configure enterprise credentials in System Settings. LinkHub connects to already-configured profiles only.
- **iCloud Keychain sync for Wi-Fi passwords** — LinkHub stores passwords in the local keychain only (`kSecAttrSynchronizable` is not set). System-level Wi-Fi Keychain syncing is handled by macOS independently.
- **Captive portal URL extraction** — LinkHub opens `http://captive.apple.com` as a universal redirect. Extracting the actual portal URL from the network response or `NEHotspotHelper` is deferred.

---

## Open Questions

| # | Question | Impact | To resolve before |
|---|----------|--------|-------------------|
| 1 | **Resolved — default assumption: ssid() is NOT synchronous post-associate. Immediate read is best-effort; delegate ssidDidChange is authoritative.** `CWInterface.ssid()` is NOT updated synchronously on `associate()` return. The `refreshConnectedNetwork()` call inside `connect(to:)` immediately after `associate()` is an optimistic best-effort read that may return stale data. The authoritative update arrives via `CWEventDelegate.ssidDidChange` → `refreshConnectedNetwork()`. This is why both code paths exist: the immediate read for snappy UI, plus the delegate callback as the corrective source of truth. | — | Resolved. |
| 2 | **Resolved — default assumption: setPower succeeds without admin for active user. Error path (revert + surface error) handles the failure case if assumption is wrong.** `CWInterface.setPower(_:error:)` succeeds for the currently logged-in user from an `LSUIElement` process without admin rights, consistent with macOS Control Center behavior. If the call returns a non-nil error, the toggle is reverted and the error is surfaced. The existing pseudo-code already handles this; the assumption merely confirms the expected happy path. | — | Resolved. |
| 3 | ~~Should `OtherNetworkPanel` position itself relative to the status item frame?~~ **Resolved:** `OtherNetworkPanel` receives the popover's `NSWindow` as `positioningWindow` and uses `positioningWindow.screen ?? NSScreen.main` to clamp within the correct screen's visible frame. The bounding is done in the init — no PRD 07 dependency. | — | Resolved in this PRD. |

---

## References

- [Apple Developer: CWWiFiClient](https://developer.apple.com/documentation/corewlan/cwwificlient) — `associate(to:password:rememberCredentials:)`, `removeProfile(_:authorization:)`.
- [Apple Developer: CWInterface](https://developer.apple.com/documentation/corewlan/cwinterface) — `scanForNetworks(withSSID:)`, `setPower(_:error:)`, `ssid()`, `bssid()`, `rssiValue()`, `disassociate()`, `cachedScanResults()`.
- [Apple Developer: CWNetwork](https://developer.apple.com/documentation/corewlan/cwnetwork) — `captiveNetwork`, `security()`, `ssid`, `bssid`, `rssiValue`.
- [Apple Developer: CWError](https://developer.apple.com/documentation/corewlan/cwerror) — `notPermitted`, `timeout`, `operationNotPermitted` error codes used in connect-flow error handling.
- [Apple Developer: Keychain Services — SecItemAdd](https://developer.apple.com/documentation/security/secitemadd(_:_:)) — `kSecClass`, `kSecAttrService`, `kSecAttrAccount`, `kSecAttrAccessible`.
- [Apple Developer: kSecAttrAccessibleAfterFirstUnlock](https://developer.apple.com/documentation/security/ksecattracaessibleafterfirstunlock) — Accessibility attribute allowing background read after boot.
- [Apple Developer: NSPanel](https://developer.apple.com/documentation/appkit/nspanel) — `becomesKeyOnlyIfNeeded`, `isFloatingPanel`, `nonactivatingPanel` style mask.
- [Apple Developer: NSWorkspace.open(_:)](https://developer.apple.com/documentation/appkit/nsworkspace/1526091-open) — URL-scheme-based deep linking into System Settings.
- [Apple HIG: Popovers — Limitations](https://developer.apple.com/design/human-interface-guidelines/popovers) — Sheets inside popovers are not supported; use separate windows for secondary tasks.
- [Apple HIG: Alerts — Destructive actions](https://developer.apple.com/design/human-interface-guidelines/alerts) — Guidance on placing destructive actions in context menus rather than primary row taps.
- [WWDC 2022: Protect mutable state with Swift actors (session 110351)](https://developer.apple.com/videos/play/wwdc2022/110351/) — `Task.detached` for synchronous blocking work; bridging back to `@MainActor`.
- [Swift.org: Swift 6 Concurrency Migration Guide — Task.detached](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/) — Correct usage of `Task.detached` for CPU-bound or blocking work.
