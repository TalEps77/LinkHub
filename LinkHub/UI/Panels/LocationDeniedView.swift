import SwiftUI
import AppKit

/// Replaces the Wi-Fi network list when CoreLocation authorization is `.denied` / `.restricted`
/// (UX-DR12, UX-DR14). macOS 10.15+ requires granted Location access for `CWWiFiClient`
/// scanning to return any results (docs/08), so without it the Wi-Fi list can never populate.
///
/// Architecture boundary: this view imports **SwiftUI + AppKit only** — never CoreLocation.
/// It reads the denial state via `appState.wifiLocationDenied` (a plain `Bool` driven by
/// `WiFiMonitor`'s `CLLocationManager`) and hands off to System Settings through `NSWorkspace`.
/// The popover dismissal goes through the `\.dismissPopover` environment action injected by
/// `PopoverController` (AppKit), so this view stays decoupled from the popover machinery.
struct LocationDeniedView: View {
    @Environment(\.dismissPopover) private var dismissPopover

    /// Deep-link to System Settings → Privacy & Security → Location Services (FR40). Exposed as
    /// a `static` constant so the URL is unit-testable without driving SwiftUI / AppKit.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Location access required")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Apple requires Location access to scan for nearby Wi-Fi networks on macOS 10.15 and later. LinkHub uses it only to read network names.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Privacy Settings") {
                // FR40: dismiss the popover, then open the Privacy → Location Services pane.
                dismissPopover()
                NSWorkspace.shared.open(Self.settingsURL)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, PanelLayout.rowHorizontalPadding)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Environment action that dismisses the enclosing popover. Defaults to a no-op so SwiftUI
/// previews and unit tests render without an `NSPopover`; `PopoverController` injects the real
/// close action. Boundary-clean handoff from the SwiftUI layer to the AppKit popover owner.
struct DismissPopoverKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var dismissPopover: @MainActor () -> Void {
        get { self[DismissPopoverKey.self] }
        set { self[DismissPopoverKey.self] = newValue }
    }
}

#if DEBUG
#Preview {
    LocationDeniedView()
        .frame(width: PanelLayout.panelWidth)
}
#endif
