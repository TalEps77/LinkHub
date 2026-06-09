import AppKit
import Combine
import QuartzCore

@MainActor
final class StatusItemController {
    let statusItem: NSStatusItem
    private let appState: AppState
    private var cancellables: Set<AnyCancellable> = []
    private let popoverController: PopoverController
    private var previousMode: ConnectionMode? = nil
    /// Last rendered SF Symbol name — gates the 300 ms crossfade so the icon only animates on an
    /// actual symbol change, never on RSSI-only churn or the initial paint (UX-DR8, UX-DR16).
    private var previousSymbolName: String? = nil
    /// Tracks Wi-Fi power so a true↔false flip posts the "Wi-Fi turned on/off" announcement
    /// (UX-DR25). `nil` until the first emission so cold launch does not announce.
    private var previousWiFiEnabled: Bool? = nil
    /// Tracks the connected Wi-Fi network id to announce "Connected to {SSID}" on a new
    /// association (Story 2.3, UX-DR25). `false` until the first emission so a cold launch that is
    /// already connected does not announce.
    private var sawFirstNetworkState: Bool = false
    private var previousConnectedWifiID: String? = nil
    private var previousLocationDenied: Bool? = nil
    /// Armed on a Location denied→granted transition (Story 1.5, UX-DR25). Consumed on the next
    /// `networkState` emission — i.e. when the auto-retried scan first completes after the grant —
    /// to post the "Wi-Fi networks loading" VoiceOver announcement.
    private var announceNetworksLoadingPending: Bool = false
    private let symbolConfig = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular, scale: .medium)

    #if DEBUG
    var isPopoverShown: Bool { popoverController.isShown }
    #endif

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.popoverController = PopoverController(
            appState: appState,
            statusItemButton: statusItem.button
        )
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick)
    }

    func start() {
        observeState()
        updateIcon(for: appState.networkState)
        updateLabel(for: appState.networkState)
        updateTooltip(for: appState.networkState)
    }

    private func observeState() {
        appState.$networkState
            .sink { [weak self] state in
                guard let self else { return }
                self.updateIcon(for: state)
                self.updateLabel(for: state)
                self.updateTooltip(for: state)
                self.announceIfDisconnected(for: state)
                self.announceWiFiPowerChange(for: state)
                self.announceConnectionIfNew(for: state)
                self.announceNetworksLoadingIfPending()
            }
            .store(in: &cancellables)

        // Detect the Location denied→granted edge (Story 1.5). NSAccessibility lives in AppKit,
        // so the announcement is posted from here (StatusItemController), not from the State or
        // Network layers, which must not import AppKit. The edge arms a pending flag consumed by
        // the next networkState emission (the auto-retried scan's first result).
        appState.$wifiLocationDenied
            .sink { [weak self] denied in
                guard let self else { return }
                if self.previousLocationDenied == true && !denied {
                    self.announceNetworksLoadingPending = true
                }
                self.previousLocationDenied = denied
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for state: NetworkState) {
        let symbolName = Self.symbolName(for: state)
        let label = Self.accessibilityLabel(for: state)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)?
            .withSymbolConfiguration(symbolConfig)
        image?.isTemplate = true
        guard let button = statusItem.button else { return }
        // UX-DR8/UX-DR16: crossfade only on an actual symbol change, and only when Reduce Motion
        // is off. The initial paint (previousSymbolName == nil) and RSSI-only churn never animate.
        let symbolChanged = previousSymbolName != nil && previousSymbolName != symbolName
        if symbolChanged && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            button.wantsLayer = true
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.3
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            button.layer?.add(transition, forKey: "iconCrossfade")
        }
        button.image = image
        previousSymbolName = symbolName
    }

    private func updateLabel(for state: NetworkState) {
        statusItem.button?.setAccessibilityLabel(Self.accessibilityLabel(for: state))
    }

    private func updateTooltip(for state: NetworkState) {
        statusItem.button?.toolTip = Self.accessibilityLabel(for: state)
    }

    /// SF Symbol for the menu-bar icon. Wi-Fi-side mapping only (FR2/FR4); the Ethernet path
    /// (`cable.connector`) is fully wired in Story 3.4. Pure — unit-tested directly.
    static func symbolName(for state: NetworkState) -> String {
        switch state.mode {
        case .ethernetActive: return "cable.connector"
        case .wifiOnly: return "wifi"
        case .disconnected: return "wifi.slash"
        }
    }

    /// VoiceOver label for the menu-bar icon per UX-DR24. Distinguishes "Wi-Fi off" (radio
    /// powered down) from "No network connection" (radio on, nothing joined) — a distinction
    /// `ConnectionMode` alone can't carry, so the label reads `isWiFiEnabled`. The full Ethernet
    /// label (`displayName`, speed) lands in Story 3.4. Pure — unit-tested directly.
    static func accessibilityLabel(for state: NetworkState) -> String {
        switch state.mode {
        case .ethernetActive:
            // UX-DR24: "Ethernet connected, {displayName}, {speed}" (FR8). Story 3.4.
            let name = state.primaryEthernet?.displayName ?? "Ethernet"
            if let mbps = state.primaryEthernet?.linkSpeedMbps {
                return "Ethernet connected, \(name), \(Self.speedDescription(mbps))"
            }
            return "Ethernet connected, \(name)"
        case .wifiOnly:
            let ssid = state.connectedWifi?.ssid ?? "Hidden Network"
            let strength = WiFiNetwork.signalStrengthDescription(for: state.connectedWifi?.rssi ?? -100)
            return "Wi-Fi connected, \(ssid), signal \(strength)"
        case .disconnected:
            return state.isWiFiEnabled ? "No network connection" : "Wi-Fi off"
        }
    }

    /// Negotiated link speed → human string for the UX-DR24 Ethernet icon label (Story 3.4):
    /// ≥1000 Mbps renders as "N.N Gbps", otherwise "N Mbps". (Story 3.3's `EthernetRow` carries a
    /// parallel formatter; consolidate onto the `EthernetInterface` model in a future cleanup —
    /// tracked in the release-gate checklist's spec-divergence section.)
    static func speedDescription(_ mbps: Int) -> String {
        if mbps >= 1000 {
            return String(format: "%.1f Gbps", Double(mbps) / 1000.0)
        }
        return "\(mbps) Mbps"
    }

    private func announceIfDisconnected(for state: NetworkState) {
        let newMode = state.mode
        let isFirstEmission = (previousMode == nil)
        let transitionedToDisconnected = previousMode != nil
            && previousMode != .disconnected
            && newMode == .disconnected
        // Cold-launch-while-offline: VoiceOver users need a signal that the app started disconnected.
        let coldLaunchOffline = isFirstEmission && newMode == .disconnected
        // Suppress when the radio is off — that path is owned by announceWiFiPowerChange
        // ("Wi-Fi turned off"); announcing "No network connection" too would be a misleading
        // double utterance.
        if (transitionedToDisconnected || coldLaunchOffline) && state.isWiFiEnabled {
            postAnnouncement("No network connection")
        }
        previousMode = newMode
    }

    /// UX-DR25 (Story 2.3): announce "Connected to {SSID}" when the connected Wi-Fi network
    /// changes to a new non-nil value. Skips the first emission so a cold launch that is already
    /// connected stays silent; the disconnect utterance is owned by announceIfDisconnected.
    private func announceConnectionIfNew(for state: NetworkState) {
        defer {
            previousConnectedWifiID = state.connectedWifi?.id
            sawFirstNetworkState = true
        }
        guard sawFirstNetworkState else { return }
        guard let connected = state.connectedWifi, connected.id != previousConnectedWifiID else { return }
        postAnnouncement("Connected to \(connected.ssid ?? "Hidden Network")")
    }

    /// UX-DR25: announce Wi-Fi power flips so VoiceOver users perceive the radio state change.
    /// Skips the first emission (cold launch) so startup never announces.
    private func announceWiFiPowerChange(for state: NetworkState) {
        defer { previousWiFiEnabled = state.isWiFiEnabled }
        guard let prev = previousWiFiEnabled, prev != state.isWiFiEnabled else { return }
        postAnnouncement(state.isWiFiEnabled ? "Wi-Fi turned on" : "Wi-Fi turned off")
    }

    /// UX-DR25: after the user grants Location following a denial, the next scan completion posts
    /// a VoiceOver announcement so assistive-tech users perceive the panel transitioning out of
    /// the denial state. Fires at most once per denied→granted transition.
    private func announceNetworksLoadingIfPending() {
        guard announceNetworksLoadingPending else { return }
        announceNetworksLoadingPending = false
        postAnnouncement("Wi-Fi networks loading")
    }

    /// Posts a high-priority VoiceOver announcement on the status-item button (NFR26). The button
    /// is the announcement element so the utterance is associated with the menu-bar control.
    private func postAnnouncement(_ message: String) {
        guard let button = statusItem.button else { return }
        NSAccessibility.post(
            element: button,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    @objc private func handleStatusItemClick() {
        if popoverController.isShown {
            popoverController.close()
        } else {
            popoverController.show()
        }
    }

    func tearDown() {
        cancellables.removeAll()
        popoverController.tearDown()
        // Break the target/action retain edge before the status item is removed.
        statusItem.button?.target = nil
        statusItem.button?.action = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
