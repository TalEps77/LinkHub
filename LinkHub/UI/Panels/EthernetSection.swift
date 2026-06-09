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
    /// Dismisses the popover before the Network Settings overflow handoff (Story 3.6).
    @Environment(\.dismissPopover) private var dismissPopover

    /// Max interfaces rendered inline before the rest collapse into the overflow row (UX-DR10).
    static let inlineLimit = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(spacing: 0) {
                ForEach(Self.displayedInterfaces(from: appState.networkState)) { interface in
                    EthernetRow(interface: interface)
                }
                let overflow = Self.overflowCount(from: appState.networkState)
                if overflow > 0 {
                    overflowRow(count: overflow)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "+ N more in Settings…" row (FR21/FR22, UX-DR10). Dismisses the popover, then opens the
    /// macOS Network settings pane (UX-DR32). `.plain` button styled like the Wi-Fi footers.
    private func overflowRow(count: Int) -> some View {
        Button("+ \(count) more in Settings…") {
            dismissPopover()
            SystemSettingsService.openNetworkSettings()
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, PanelLayout.rowHorizontalPadding)
        .padding(.vertical, PanelLayout.rowVerticalPadding)
        .accessibilityLabel("\(count) more interfaces in Settings")
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

    /// All interfaces that have link (cable in), sorted active-first then by BSD name (FR20 —
    /// stable identifier tie-break). Cable-out `.noLink` interfaces are excluded: the section only
    /// represents interfaces with a cable. Pure function.
    static func linkedSorted(from state: NetworkState) -> [EthernetInterface] {
        state.ethernetInterfaces
            .filter { $0.state != .noLink }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive }   // active first
                return lhs.bsdName < rhs.bsdName                          // tie-break: BSD name
            }
    }

    /// The interfaces rendered inline — the top `inlineLimit` (2) of `linkedSorted` (UX-DR10).
    /// Unit-tested directly without instantiating SwiftUI (mirrors `WiFiSection.displayedNetworks`).
    static func displayedInterfaces(from state: NetworkState) -> [EthernetInterface] {
        Array(linkedSorted(from: state).prefix(inlineLimit))
    }

    /// How many linked interfaces are hidden behind the "+N more" overflow row (FR21).
    static func overflowCount(from state: NetworkState) -> Int {
        max(0, linkedSorted(from: state).count - inlineLimit)
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
