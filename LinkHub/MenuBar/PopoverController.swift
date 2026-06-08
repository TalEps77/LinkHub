import AppKit
import SwiftUI

@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private weak var button: NSStatusBarButton?
    private let appState: AppState
    private let hostingController: NSHostingController<AnyView>
    private var eventMonitor: Any? = nil

    var isShown: Bool { popover.isShown }

    #if DEBUG
    var hasEventMonitor: Bool { eventMonitor != nil }
    #endif

    init(appState: AppState, statusItemButton: NSStatusBarButton?) {
        self.button = statusItemButton
        self.appState = appState
        self.hostingController = NSHostingController(
            rootView: AnyView(RootPanelView().environmentObject(appState))
        )
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        hostingController.sizingOptions = [.intrinsicContentSize]
        popover.contentViewController = hostingController
        popover.contentSize = CGSize(width: 320, height: 480)
    }

    func show() {
        guard let button = self.button, button.window != nil else {
            Log.menuBar.error("StatusItem button has no window — skipping show")
            return
        }
        removeEventMonitor()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.popover.isShown && event.keyCode == 53 {
                self.popover.performClose(nil)
                return nil
            }
            return event
        }
        triggerScanOnShow()
    }

    /// Fire-and-forget on-demand scan when the panel becomes visible (FR26). Captures only
    /// `appState` (process-scoped, owned by AppDelegate) — never `self` — to avoid a retain
    /// cycle through the popover delegate. `requestScan()` is non-throwing (Story 1.3), and
    /// its `inFlightScan` guard no-ops rapid re-entrant shows.
    private func triggerScanOnShow() {
        Task { @MainActor [appState] in
            await appState.wifiMonitor.requestScan()
        }
    }

    #if DEBUG
    /// Test hook: exercises the scan-on-show trigger without mounting an `NSStatusBar` button.
    func _triggerScanOnShowForTesting() {
        triggerScanOnShow()
    }
    #endif

    func close() {
        popover.performClose(nil)
        removeEventMonitor()
    }

    func tearDown() {
        removeEventMonitor()
        if popover.isShown {
            popover.close()
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removeEventMonitor()
    }
}
