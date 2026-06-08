import SwiftUI

struct RootPanelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // WiFiSection placeholder added in Story 1.4
            Text("LinkHub")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(width: PanelLayout.panelWidth)
        .padding(.vertical, PanelLayout.outerPadding)
        .background(PopoverBackground())
    }
}
