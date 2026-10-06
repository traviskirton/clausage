import AppKit

/// Right-click menu on the menubar item: the same brand menu as the popover's gear.
@MainActor
final class StatusMenu: NSObject {
    static let shared = StatusMenu()
    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            // Only a Bool crosses the isolation boundary; the event itself is returned out here.
            let handled = MainActor.assumeIsolated { self?.showMenu(for: event) ?? false }
            return handled ? nil : event
        }
    }

    /// Pops up the menu if the click landed on our status item. Returns whether it did.
    private func showMenu(for event: NSEvent) -> Bool {
        guard let w = event.window,
              String(describing: type(of: w)) == "NSStatusBarWindow",
              let button = Self.button(in: w.contentView) else { return false }
        let menu = BrandMenu.standard(model: UsageModel.shared)
        NSMenu.popUpContextMenu(menu, with: event, for: button)
        return true
    }

    private static func button(in v: NSView?) -> NSStatusBarButton? {
        guard let v else { return nil }
        if let b = v as? NSStatusBarButton { return b }
        for s in v.subviews { if let b = button(in: s) { return b } }
        return nil
    }
}
