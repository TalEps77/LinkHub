import SwiftUI

/// The Ethernet section of the panel (Story 3.3, FR12).
///
/// Rendered ABOVE `WiFiSection` by `RootPanelView` whenever at least one interface has link
/// (UX-DR9/10). Header mirrors `WiFiSection`'s: `.caption` UPPERCASE 10 pt semibold "ETHERNET"
/// (UX-DR3). Renders the top 2 active interfaces inline as `EthernetRow`s.
///
/// Scope boundary: multi-interface sort + "+N more" overflow is Story 3.6 — this section renders
/// at most 2 rows and does not collapse/overflow. The 250 ms section-reorder animation and
/// cable-out grace timer are Story 3.5. Reads state via `@EnvironmentObject` only (NFR35);
/// imports `SwiftUI` only.
struct EthernetSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(spacing: 0) {
                ForEach(Self.displayedInterfaces(from: appState.networkState)) { interface in
                    EthernetRow(interface: interface)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("ETHERNET")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, PanelLayout.rowHorizontalPadding)
        .padding(.vertical, PanelLayout.sectionHeaderVerticalPadding)
    }

    /// The interfaces rendered inline, in priority order: active interfaces first (healthiest at
    /// the top, UX-DR10), then everything else preserving the monitor's order, capped at the top 2.
    /// Pure function — unit-tested directly without instantiating SwiftUI (mirrors
    /// `WiFiSection.displayedNetworks`). Full multi-interface sort + "+N more" overflow is Story 3.6.
    static func displayedInterfaces(from state: NetworkState) -> [EthernetInterface] {
        let active = state.ethernetInterfaces.filter { $0.isActive }
        let inactive = state.ethernetInterfaces.filter { !$0.isActive }
        return Array((active + inactive).prefix(2))
    }
}

#if DEBUG
@MainActor
private func previewState(_ interfaces: [EthernetInterface]) -> AppState {
    let state = AppState(
        wifiMonitor: MockWiFiMonitor(),
        ethernetMonitor: MockEthernetMonitor(interfaces: interfaces)
    )
    state._setNetworkStateForTesting(NetworkState(
        mode: interfaces.contains(where: \.isActive) ? .ethernetActive : .disconnected,
        ethernetInterfaces: interfaces,
        primaryEthernet: interfaces.first { $0.isActive },
        wifiNetworks: [],
        connectedWifi: nil,
        isWiFiEnabled: true,
        isWiFiHardwareAvailable: true
    ))
    return state
}

#Preview("Active + obtaining") {
    EthernetSection()
        .environmentObject(previewState(MockEthernetMonitor.sampleInterfaces))
        .frame(width: PanelLayout.panelWidth)
}

#Preview("Timeout + no link") {
    EthernetSection()
        .environmentObject(previewState([
            EthernetInterface(id: "en6", bsdName: "en6", displayName: "USB-C LAN", linkSpeedMbps: 100, ipv4: nil, state: .dhcpTimeout),
            EthernetInterface(id: "en7", bsdName: "en7", displayName: "USB-C Ethernet", linkSpeedMbps: nil, ipv4: nil, state: .noLink)
        ]))
        .frame(width: PanelLayout.panelWidth)
}
#endif
