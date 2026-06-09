import SwiftUI

/// The Wi-Fi section of the panel: section header (label + power toggle) plus the network list
/// with its content states (off / location-denied / scanning / empty / populated).
///
/// Story 2.5 wires the header `Toggle` to `AppState.setWiFiPower(_:)` (FR35); when the radio is
/// off the list is replaced by a "Wi-Fi: Off" label. Reads state via `@EnvironmentObject` only —
/// never subscribes to a monitor directly (NFR35).
struct WiFiSection: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    /// Swaps the popover content to `OtherNetworkPanel` (UX-DR15/32). Injected by `RootPanelView`;
    /// defaults to a no-op so the section renders standalone in previews/tests. Using the
    /// environment action (not a closure through `init`) keeps `WiFiSection`'s API stable.
    @Environment(\.showOtherNetwork) private var showOtherNetwork
    /// Dismisses the popover before the System Settings handoff (Story 2.6). Injected by
    /// `PopoverController`; defaults to a no-op in previews/tests.
    @Environment(\.dismissPopover) private var dismissPopover

    /// Drives the header power `Toggle` (Story 2.5). Reads the live power state from the monitor's
    /// `isWiFiEnabled` (no local `@State` to drift from reality); the setter routes through
    /// `AppState` (NFR35). The flip resolves asynchronously and re-renders via `networkState`.
    private var wifiPowerBinding: Binding<Bool> {
        Binding(
            get: { appState.networkState.isWiFiEnabled },
            set: { newValue in Task { await appState.setWiFiPower(newValue) } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
            // Footers (Story 2.4 "Other Network…", Story 2.6 "Open Network Settings…"). Hidden
            // when the list itself is hidden — i.e. location-denied (LocationDeniedView) or Wi-Fi off.
            if !appState.wifiLocationDenied && appState.networkState.isWiFiEnabled {
                otherNetworkFooter
                openSettingsFooter
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A `.plain` footer button below the network list that opens the hidden-network join form
    /// in-place (UX-DR34 ellipsis copy). Routes via the `\.showOtherNetwork` environment action.
    private var otherNetworkFooter: some View {
        Button("Other Network…", action: showOtherNetwork)
            .buttonStyle(.plain)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, PanelLayout.rowHorizontalPadding)
            .padding(.vertical, PanelLayout.rowVerticalPadding)
            .accessibilityLabel("Other Network")
    }

    /// A `.plain` footer link (UX-DR34 ellipsis copy) that hands off to the system Wi-Fi settings
    /// pane (FR38). Dismisses the popover first so the settings window comes forward (UX-DR32).
    private var openSettingsFooter: some View {
        Button("Open Network Settings…") {
            dismissPopover()
            SystemSettingsService.openWiFiSettings()
        }
        .buttonStyle(.plain)
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, PanelLayout.rowHorizontalPadding)
        .padding(.vertical, PanelLayout.rowVerticalPadding)
        .accessibilityLabel("Open Network Settings")
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("WI-FI")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Toggle("", isOn: wifiPowerBinding)
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
        let displayed = Self.displayedNetworks(from: appState.networkState)
        let isEmpty = (displayed.connected == nil) && displayed.others.isEmpty
        let isScanning = appState.scanStatus == .scanning
        switch Self.contentMode(
            locationDenied: appState.wifiLocationDenied,
            isEmpty: isEmpty,
            isScanning: isScanning,
            isWiFiEnabled: appState.networkState.isWiFiEnabled,
            isWiFiHardwareAvailable: appState.networkState.isWiFiHardwareAvailable
        ) {
        case .wifiOff:
            // FR34 / UX-DR12 / UX-DR33: radio off — list hidden, plain "Wi-Fi: Off" label remains.
            wifiOffState
        case .locationDenied:
            // UX-DR12 / UX-DR14: Location denial replaces the list entirely.
            LocationDeniedView()
        case .scanning:
            scanningIndicator
        case .empty:
            emptyState
        case .list:
            VStack(spacing: 0) {
                if let connected = displayed.connected { WiFiRow(network: connected) }
                ForEach(displayed.others) { network in WiFiRow(network: network) }
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

    private var wifiOffState: some View {
        Text("Wi-Fi: Off")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: PanelLayout.rowHeight, alignment: .center)
    }

    /// The mutually-exclusive content states the section can display, in priority order.
    enum ContentMode: Equatable {
        case wifiOff
        case locationDenied
        case scanning
        case empty
        case list
    }

    /// Pure branch selector for `content` — decides which view the section renders. Power-off wins
    /// over everything (FR34: nothing to scan or show when the radio is off). Then Location denial
    /// (UX-DR12: without Location access the list can never populate). Unit-tested directly without
    /// instantiating SwiftUI (mirrors `displayedNetworks`).
    static func contentMode(
        locationDenied: Bool,
        isEmpty: Bool,
        isScanning: Bool,
        isWiFiEnabled: Bool,
        isWiFiHardwareAvailable: Bool
    ) -> ContentMode {
        if !isWiFiEnabled { return .wifiOff }
        if locationDenied { return .locationDenied }
        if isEmpty && isScanning { return .scanning }
        if isEmpty && isWiFiHardwareAvailable && !isScanning { return .empty }
        return .list
    }

    /// Splits `NetworkState` into the connected row and the de-duplicated "other networks"
    /// list (drops any scan-result entry whose `id` matches the connected network — resolves
    /// the SwiftUI `Identifiable` duplicate-id collision deferred from Story 1.3). Pure
    /// function — unit-tested directly without instantiating SwiftUI.
    static func displayedNetworks(from state: NetworkState) -> (connected: WiFiNetwork?, others: [WiFiNetwork]) {
        let connected = state.connectedWifi
        let others = state.wifiNetworks.filter { $0.id != connected?.id }
        return (connected, others)
    }
}

#if DEBUG
@MainActor
private func previewState(_ networks: [WiFiNetwork]) -> AppState {
    let state = AppState(wifiMonitor: MockWiFiMonitor())
    state._setNetworkStateForTesting(NetworkState(
        mode: networks.contains(where: \.isConnected) ? .wifiOnly : .disconnected,
        ethernetInterfaces: [],
        primaryEthernet: nil,
        wifiNetworks: networks,
        connectedWifi: networks.first { $0.isConnected },
        isWiFiEnabled: true,
        isWiFiHardwareAvailable: true
    ))
    return state
}

#Preview("Connected + others") {
    WiFiSection()
        .environmentObject(previewState(MockWiFiMonitor.sampleNetworks))
        .frame(width: PanelLayout.panelWidth)
}

#Preview("Empty (idle)") {
    WiFiSection()
        .environmentObject(previewState([]))
        .frame(width: PanelLayout.panelWidth)
}
#endif
