import SwiftUI

/// In-popover form for joining a hidden Wi-Fi network by typing its SSID + security details
/// (FR32, UX-DR15). This view *replaces* `RootPanelView`'s list content within the same popover
/// — there is no modal sheet, `NSWindow`/`NSPanel`, or `NavigationStack` drill-down (UX-DR15/32,
/// docs/04 hard constraint). `RootPanelView` owns the routing flag; this view only signals "done"
/// via the injected `onClose` closure (covers both Cancel/Esc and a successful Join).
///
/// Architecture boundary: imports **SwiftUI only**. The connect routes through `appState`
/// (NFR35) — this view never touches CoreWLAN or Keychain. Validation is deferred to CoreWLAN
/// (`CWInterface.associate`); there is no client-side SSID/password regex (UX-DR31). The failure
/// copy is mapped by the single source of truth `WiFiRow.errorCaption(for:)`.
struct OtherNetworkPanel: View {
    /// Returns to the main list content (sets `RootPanelView.showingOtherNetwork = false`).
    let onClose: () -> Void

    @EnvironmentObject private var appState: AppState

    @State private var ssid = ""
    @State private var security: SecuritySelection = .wpa
    @State private var password = ""
    /// Last join failure mapped to display copy; `nil` when no error. Field state is preserved
    /// across a failure (UX-DR31) — only this caption changes.
    @State private var errorCaption: String?
    @FocusState private var ssidFieldFocused: Bool

    /// The three security options the Picker offers (FR32, UX-DR15). The 3-way choice is mapped
    /// to the richer `WiFiSecurity` enum by `Self.security(for:)`.
    enum SecuritySelection: CaseIterable, Identifiable {
        case open
        case wpa
        case enterprise

        var id: Self { self }
        var label: String {
            switch self {
            case .open:       return "Open"
            case .wpa:        return "WPA"
            case .enterprise: return "Enterprise"
            }
        }
    }

    /// `true` while this hidden-network join is in flight — drives the busy state and disables the
    /// controls. Sourced from `appState.connectingNetworkID` (single source of truth, UX-DR30/33);
    /// the composite id we build for the typed network is what `connect(to:)` sets.
    private var isJoining: Bool {
        appState.connectingNetworkID == Self.network(ssid: ssid, security: security).id
    }

    /// Join is enabled only when an SSID has been typed (CoreWLAN can't associate to an empty
    /// SSID). Password emptiness is NOT gated client-side — validation is deferred to CoreWLAN
    /// (UX-DR31).
    private var canJoin: Bool {
        !ssid.trimmingCharacters(in: .whitespaces).isEmpty && !isJoining
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Join Other Network")
                .font(.headline)

            TextField("Network Name", text: $ssid)
                .textFieldStyle(.roundedBorder)
                .focused($ssidFieldFocused)
                .accessibilityLabel("Network name")
                .disabled(isJoining)

            Picker("Security", selection: $security) {
                ForEach(SecuritySelection.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .accessibilityLabel("Security")
            .disabled(isJoining)

            if security != .open {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(join)
                    .accessibilityLabel("Password")
                    .disabled(isJoining)
            }

            if let errorCaption {
                Text(errorCaption)
                    .font(.caption)
                    .foregroundStyle(Color.red)   // UX-DR4/30: the one allowed color literal
                    .accessibilityLabel(errorCaption)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(.bordered)        // UX-DR29: no primary action shown
                    .disabled(isJoining)
                Button("Join", action: join)
                    .buttonStyle(.bordered)        // UX-DR29: both .bordered, no .borderedProminent
                    .disabled(!canJoin)
            }
        }
        .padding(.horizontal, PanelLayout.rowHorizontalPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Esc returns to the list without joining and without any Keychain write (UX-DR32).
        .onExitCommand(perform: cancel)
        // UX-DR31: SSID auto-focused on appear.
        .onAppear { ssidFieldFocused = true }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Interaction

    private func cancel() {
        // No Keychain write occurs on cancel/Esc (the join path is the only persistence trigger,
        // and only on success inside AppState.connect). Just hand routing back to RootPanelView.
        onClose()
    }

    private func join() {
        guard canJoin else { return }
        let selection = security
        let typedSSID = ssid
        let typedPassword = password
        Task { await attemptJoin(ssid: typedSSID, selection: selection, password: typedPassword) }
    }

    @MainActor
    private func attemptJoin(ssid: String, selection: SecuritySelection, password: String) async {
        errorCaption = nil
        let network = Self.network(ssid: ssid, security: selection)
        // Open networks pass a nil password; WPA/Enterprise pass the typed value (deferred to
        // CoreWLAN for validation — UX-DR31).
        let result = await appState.connect(to: network, password: Self.password(for: selection, entered: password))
        switch result {
        case .success:
            // The connected-state visual follows from the monitor pipeline updating
            // appState.networkState; return to the list (UX-DR32).
            onClose()
        case .failure(let failure):
            // UX-DR31: show the cause, preserve all field state.
            errorCaption = WiFiRow.errorCaption(for: failure)
        }
    }

    // MARK: - Pure, testable helpers

    /// Maps the 3-way Picker selection to the `WiFiSecurity` enum used by the connect path.
    /// WPA is modeled as `.wpa2Personal` (the password-protected personal case the inline-connect
    /// flow expects); Enterprise → `.enterprise`; Open → `.none`. Pure & static for unit testing.
    static func security(for selection: SecuritySelection) -> WiFiSecurity {
        switch selection {
        case .open:       return .none
        case .wpa:        return .wpa2Personal
        case .enterprise: return .enterprise
        }
    }

    /// Whether the selected security requires a password field. Open networks do not. Pure helper
    /// driving both the conditional `SecureField` and the password the connect path receives.
    static func requiresPassword(for selection: SecuritySelection) -> Bool {
        selection != .open
    }

    /// The password to hand `AppState.connect` for this selection: `nil` for Open (no SecureField
    /// shown), otherwise the entered text verbatim (CoreWLAN validates — UX-DR31).
    static func password(for selection: SecuritySelection, entered: String) -> String? {
        requiresPassword(for: selection) ? entered : nil
    }

    /// Builds the `WiFiNetwork` value for a hidden network from the typed SSID + picked security.
    /// `bssid` is nil (the network isn't broadcasting / wasn't in scan results); Story 2.1's
    /// `WiFiMonitor.performAssociate` does an SSID-directed `scanForNetworks(withSSID:)`, so the
    /// hidden network is located by name. `requiresPassword` derives from the selection;
    /// `isConnected`/`isCaptive` are false. `id` is the composite the model documents for a
    /// nil-bssid network (`"\(ssid):\(security)"`) so `connectingNetworkID` matching is stable.
    /// Pure & static for unit testing.
    static func network(ssid: String, security selection: SecuritySelection) -> WiFiNetwork {
        let sec = security(for: selection)
        return WiFiNetwork(
            id: "\(ssid):\(sec)",
            ssid: ssid,
            bssid: nil,
            rssi: 0,
            isConnected: false,
            requiresPassword: requiresPassword(for: selection),
            security: sec,
            isCaptive: false
        )
    }
}

#if DEBUG
#Preview {
    OtherNetworkPanel(onClose: {})
        .frame(width: PanelLayout.panelWidth)
        .environmentObject(AppState(wifiMonitor: MockWiFiMonitor()))
}
#endif
