import SwiftUI

struct RootPanelView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    /// In-popover routing flag (UX-DR15/32): when `true`, `OtherNetworkPanel` *replaces* the list
    /// content within the same popover — no sheet / NSWindow / NavigationStack. Routing is plain
    /// view state and is deliberately NOT pushed into `AppState` (which stays network-focused).
    @State private var showingOtherNetwork = false

    var body: some View {
        content
            .frame(width: PanelLayout.panelWidth, alignment: .top)
            .padding(.vertical, PanelLayout.outerPadding)
            .background(PopoverBackground())
            // The "Other Network…" footer button injects this action; we own the flag so the
            // WiFiSection API stays stable (no closure threaded through its init).
            .environment(\.showOtherNetwork) { showingOtherNetwork = true }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showingOtherNetwork)
            // Story 3.5: 250 ms ease-in-out section reorder when the Ethernet section appears /
            // disappears; instant under Reduce Motion (UX-DR9/17/20, NFR28).
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: appState.isEthernetSectionVisible)
    }

    @ViewBuilder
    private var content: some View {
        if showingOtherNetwork {
            OtherNetworkPanel(onClose: { showingOtherNetwork = false })
        } else {
            VStack(spacing: PanelLayout.interSectionSpacing) {
                // Story 3.3: EthernetSection renders above WiFiSection. Story 3.5: visibility is the
                // graced `appState.isEthernetSectionVisible` (true while any interface has link, held
                // for a 1.5 s window after cable-out so transient flutter doesn't flicker, FR13) —
                // not the raw interface list.
                if appState.isEthernetSectionVisible {
                    EthernetSection()
                }
                WiFiSection()
            }
        }
    }
}

/// Environment action that swaps the popover content to `OtherNetworkPanel` (UX-DR15/32).
/// Defaults to a no-op so previews / unit tests render without the routing owner; `RootPanelView`
/// injects the real action (sets `showingOtherNetwork = true`). Mirrors the `\.dismissPopover`
/// idiom (`LocationDeniedView.swift`) so the `WiFiSection` footer stays decoupled from routing.
struct ShowOtherNetworkKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var showOtherNetwork: @MainActor () -> Void {
        get { self[ShowOtherNetworkKey.self] }
        set { self[ShowOtherNetworkKey.self] = newValue }
    }
}

#if DEBUG
#Preview {
    let state = AppState(wifiMonitor: MockWiFiMonitor(), ethernetMonitor: MockEthernetMonitor())
    state._setNetworkStateForTesting(NetworkState(
        mode: .ethernetActive,
        ethernetInterfaces: MockEthernetMonitor.sampleInterfaces,
        primaryEthernet: MockEthernetMonitor.sampleInterfaces.first { $0.isActive },
        wifiNetworks: MockWiFiMonitor.sampleNetworks,
        connectedWifi: MockWiFiMonitor.sampleNetworks.first { $0.isConnected },
        isWiFiEnabled: true,
        isWiFiHardwareAvailable: true
    ))
    return RootPanelView().environmentObject(state)
}
#endif
