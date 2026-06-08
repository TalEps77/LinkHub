import AppKit
import Combine

@MainActor
final class StatusItemController {
    let statusItem: NSStatusItem
    private let appState: AppState
    private var cancellables: Set<AnyCancellable> = []
    private let popoverController: PopoverController
    private var previousMode: ConnectionMode? = nil
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
        updateIcon(for: appState.networkState.mode)
        updateLabel(for: appState.networkState)
        updateTooltip(for: appState.networkState)
    }

    private func observeState() {
        appState.$networkState
            .sink { [weak self] state in
                guard let self else { return }
                self.updateIcon(for: state.mode)
                self.updateLabel(for: state)
                self.updateTooltip(for: state)
                self.announceIfDisconnected(newMode: state.mode)
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

    private func updateIcon(for mode: ConnectionMode) {
        let symbolName: String
        let accessibility: String
        switch mode {
        case .ethernetActive:
            symbolName = "cable.connector"
            accessibility = "Ethernet active"
        case .wifiOnly:
            symbolName = "wifi"
            accessibility = "Wi-Fi connected"
        case .disconnected:
            symbolName = "wifi.slash"
            accessibility = "No network connection"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibility)?
            .withSymbolConfiguration(symbolConfig)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func updateLabel(for state: NetworkState) {
        let label: String
        switch state.mode {
        case .ethernetActive:
            // Story 1.3+ will resolve primaryEthernet displayName
            label = "LinkHub: Ethernet"
        case .wifiOnly:
            // Story 1.3+ will resolve connectedWifi SSID
            label = "LinkHub: Wi-Fi"
        case .disconnected:
            label = "LinkHub: No network connection"
        }
        statusItem.button?.setAccessibilityLabel(label)
    }

    private func updateTooltip(for state: NetworkState) {
        let tooltip: String
        switch state.mode {
        case .ethernetActive:
            tooltip = "LinkHub: Ethernet"
        case .wifiOnly:
            tooltip = "LinkHub: Wi-Fi"
        case .disconnected:
            tooltip = "LinkHub: No network connection"
        }
        statusItem.button?.toolTip = tooltip
    }

    private func announceIfDisconnected(newMode: ConnectionMode) {
        let isFirstEmission = (previousMode == nil)
        let transitionedToDisconnected = previousMode != nil
            && previousMode != .disconnected
            && newMode == .disconnected
        // Cold-launch-while-offline: VoiceOver users need a signal that the app started disconnected.
        let coldLaunchOffline = isFirstEmission && newMode == .disconnected
        if transitionedToDisconnected || coldLaunchOffline {
            if let button = statusItem.button {
                NSAccessibility.post(
                    element: button,
                    notification: .announcementRequested,
                    userInfo: [
                        .announcement: "LinkHub: No network connection",
                        .priority: NSAccessibilityPriorityLevel.high.rawValue
                    ]
                )
            }
        }
        previousMode = newMode
    }

    /// UX-DR25: after the user grants Location following a denial, the next scan completion posts
    /// a VoiceOver announcement so assistive-tech users perceive the panel transitioning out of
    /// the denial state. Fires at most once per denied→granted transition.
    private func announceNetworksLoadingIfPending() {
        guard announceNetworksLoadingPending else { return }
        announceNetworksLoadingPending = false
        if let button = statusItem.button {
            NSAccessibility.post(
                element: button,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: "Wi-Fi networks loading",
                    .priority: NSAccessibilityPriorityLevel.high.rawValue
                ]
            )
        }
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
