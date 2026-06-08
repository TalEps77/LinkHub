import SwiftUI

/// A single Wi-Fi network row.
///
/// Anatomy (leading → trailing): `Checkmark?` → SSID → `Spacer` → `LockIcon?` →
/// `CaptiveIcon?` → `SignalBars` (UX-DR13). Decorative glyphs are `.accessibilityHidden(true)`;
/// the row exposes one combined label (UX-DR22).
///
/// Story 2.3 adds the inline-connect flow:
/// - Open networks (`requiresPassword == false`) connect on a single tap, no expansion.
/// - Password-protected networks expand below the row into a `SecureField` (auto-focused; Return
///   submits, Esc collapses). On expansion the field is pre-filled from any stored passphrase so a
///   returning user just presses Return. On failure an inline `.caption` `Color.red` caption shows
///   the cause, the field is cleared, focus is retained, and the row stays expanded (UX-DR31).
///
/// Expansion / password / error / focus are **local** view state. Which network is currently
/// connecting comes from `appState.connectingNetworkID` (single source of truth; no separate
/// spinner — UX-DR30/33). The connect call routes through `AppState` (NFR35); this file imports
/// `SwiftUI` only — never CoreWLAN or Keychain.
struct WiFiRow: View {
    let network: WiFiNetwork

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    /// Whether the inline password field is shown. Local — see type doc.
    @State private var isExpanded = false
    @State private var password = ""
    /// Last connection failure for this row, mapped to display copy. `nil` when no error.
    @State private var errorCaption: String?
    @FocusState private var passwordFieldFocused: Bool

    /// `true` while this row's connection attempt is in flight (drives the `.connecting` visual).
    private var isConnecting: Bool { appState.connectingNetworkID == network.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            if isExpanded {
                expansion
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isExpanded)
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
    }

    // MARK: - Main row

    private var mainRow: some View {
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
            if isConnecting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
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
    }

    // MARK: - Inline password expansion

    private var expansion: some View {
        VStack(alignment: .leading, spacing: 4) {
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($passwordFieldFocused)
                .onSubmit(submit)
                .accessibilityLabel("Password for \(displaySSID)")   // UX-DR22 field-level label
                .disabled(isConnecting)
            if let errorCaption {
                Text(errorCaption)
                    .font(.caption)
                    .foregroundStyle(Color.red)   // UX-DR4/30: the one allowed color literal
                    .accessibilityLabel(errorCaption)
            }
        }
        .padding(.horizontal, PanelLayout.rowHorizontalPadding)
        .padding(.bottom, PanelLayout.rowVerticalPadding)
        // Esc collapses without submitting (UX-DR31).
        .onExitCommand(perform: collapse)
    }

    private var displaySSID: String { network.ssid ?? "Hidden Network" }   // FR24

    // MARK: - Interaction

    private func handleTap() {
        // Connecting rows ignore taps; the connected row is informational (PRD 06 D3).
        guard !isConnecting, !network.isConnected else { return }

        if network.requiresPassword {
            if isExpanded {
                collapse()
            } else {
                expand()
            }
        } else {
            // Open network — single-tap connect, no expansion (PRD 06 D4).
            Task { await connect(password: nil) }
        }
    }

    private func expand() {
        errorCaption = nil
        // Pre-fill from any remembered passphrase so the user can just press Return (UX-DR31).
        if let ssid = network.ssid, !ssid.isEmpty {
            password = appState.storedPassword(forSSID: ssid) ?? ""
        }
        isExpanded = true
        // Auto-focus the field once it is in the tree.
        passwordFieldFocused = true
    }

    private func collapse() {
        isExpanded = false
        passwordFieldFocused = false
        password = ""
        errorCaption = nil
    }

    private func submit() {
        guard !password.isEmpty, !isConnecting else { return }
        let entered = password
        Task { await connect(password: entered) }
    }

    @MainActor
    private func connect(password: String?) async {
        errorCaption = nil
        let result = await appState.connect(to: network, password: password)
        switch result {
        case .success:
            // Success: collapse. The connected-state visual follows from the monitor pipeline
            // updating `appState.networkState` (re-renders this row as `.connected`). The
            // "Connected to {SSID}" VoiceOver announcement (UX-DR25) is posted by
            // StatusItemController on the connectedWifi state edge, keeping NSAccessibility in the
            // AppKit layer and WiFiRow SwiftUI-only (NFR35, Story 1.4 layer rule).
            collapse()
        case .failure(let failure):
            // UX-DR31: clear the field, keep focus, stay expanded, show the cause.
            errorCaption = Self.errorCaption(for: failure)
            self.password = ""
            if network.requiresPassword {
                isExpanded = true
                passwordFieldFocused = true
            }
        }
    }

    // MARK: - Pure, testable helpers

    /// Cause-typed failure → user-facing caption (UX-DR30/34). Pure & static for unit testing.
    static func errorCaption(for failure: WiFiConnectionFailure) -> String {
        switch failure {
        case .wrongPassword:       return "Incorrect password"
        case .outOfRange:          return "Network out of range"
        case .associationTimeout:  return "Connection timed out"
        case .authenticationError: return "Authentication failed"
        case .unknown:             return "Couldn't connect"
        }
    }

    /// Combined VoiceOver label per UX-DR22 templates. Pure function — unit-tested directly.
    static func accessibilityLabel(for network: WiFiNetwork) -> String {
        let name = network.ssid ?? "Hidden Network"
        let security = network.requiresPassword ? "password required" : "open network"
        let strength = signalStrengthDescription(for: network.rssi)
        if network.isConnected {
            return "\(name), connected, \(security), signal \(strength)"
        }
        return "\(name), \(security), signal \(strength)"
    }

    /// RSSI (dBm) → human descriptor. Delegates to the canonical model helper so the panel row
    /// and the menu-bar icon label never diverge. Buckets must agree with `SignalBars.activeBars(for:)`.
    static func signalStrengthDescription(for rssi: Int) -> String {
        WiFiNetwork.signalStrengthDescription(for: rssi)
    }

}

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        WiFiRow(network: WiFiNetwork(id: "1", ssid: "HomeNetwork", bssid: "1", rssi: -42, isConnected: true, requiresPassword: true, security: .wpa2Personal, isCaptive: false))
        WiFiRow(network: WiFiNetwork(id: "2", ssid: "CoffeeWifi", bssid: "2", rssi: -68, isConnected: false, requiresPassword: false, security: .none, isCaptive: true))
        WiFiRow(network: WiFiNetwork(id: "3", ssid: "GuestNetwork", bssid: "3", rssi: -55, isConnected: false, requiresPassword: true, security: .wpa2Personal, isCaptive: false))
        WiFiRow(network: WiFiNetwork(id: "4", ssid: nil, bssid: "4", rssi: -80, isConnected: false, requiresPassword: true, security: .wpa3Personal, isCaptive: false))
    }
    .frame(width: PanelLayout.panelWidth)
    .padding(.vertical)
    .environmentObject(AppState(wifiMonitor: MockWiFiMonitor()))
}
#endif
