import SwiftUI
import AppKit

struct PopoverBackground: NSViewRepresentable {
    @MainActor
    final class Coordinator: NSObject {
        weak var view: NSVisualEffectView?
        private var isRegistered: Bool = false

        func register() {
            guard !isRegistered else { return }
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(handleAccessibilityChange(_:)),
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil
            )
            isRegistered = true
        }

        func unregister() {
            guard isRegistered else { return }
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            isRegistered = false
        }

        @objc nonisolated private func handleAccessibilityChange(_ note: Notification) {
            Task { @MainActor [weak self] in
                guard let self, let view = self.view else { return }
                PopoverBackground.applyReduceTransparencyFallback(to: view)
            }
        }
        // Observer is removed in dismantleNSView (MainActor) rather than deinit — under
        // Swift 6 strict concurrency, deinit is nonisolated and calling NSWorkspace there
        // raises a warning.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .windowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        context.coordinator.view = view
        context.coordinator.register()
        Self.applyReduceTransparencyFallback(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        Self.applyReduceTransparencyFallback(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSVisualEffectView, coordinator: Coordinator) {
        coordinator.unregister()
    }

    fileprivate static func applyReduceTransparencyFallback(to view: NSVisualEffectView) {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        view.material = .windowBackground
        view.isEmphasized = false
        if reduce {
            view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        } else {
            view.layer?.backgroundColor = nil
        }
    }
}
