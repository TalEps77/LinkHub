import SwiftUI

/// A single Wi-Fi network row (read-only for Epic 1).
///
/// Anatomy (leading → trailing): `Checkmark?` → SSID → `Spacer` → `LockIcon?` →
/// `CaptiveIcon?` → `SignalBars` (UX-DR13). Decorative glyphs are `.accessibilityHidden(true)`;
/// the row exposes one combined label (UX-DR22). Epic 2 / PRD 06 extends this with the
/// inline-password-expansion and context-menu states.
struct WiFiRow: View {
    let network: WiFiNetwork

    var body: some View {
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
    }

    private var displaySSID: String { network.ssid ?? "Hidden Network" }   // FR24

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
        WiFiRow(network: WiFiNetwork(id: "3", ssid: "CorpNetwork", bssid: "3", rssi: -72, isConnected: false, requiresPassword: false, security: .enterprise, isCaptive: false))
        WiFiRow(network: WiFiNetwork(id: "4", ssid: nil, bssid: "4", rssi: -80, isConnected: false, requiresPassword: true, security: .wpa3Personal, isCaptive: false))
    }
    .frame(width: PanelLayout.panelWidth)
    .padding(.vertical)
}
#endif
