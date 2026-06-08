import SwiftUI

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
