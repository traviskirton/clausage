import SwiftUI

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    /// A pane to switch to in an open window (e.g. Updates when an update is ready).
    @Published private(set) var requestedTab: SettingsTab?

    /// Opens Settings (on Usage the first time), or brings it forward. `tab` picks the pane, even if it's already open.
    func show(tab: SettingsTab? = nil) {
        requestedTab = tab      // nil: a fresh window starts on Usage, an open one stays where it is
        if window == nil {
            let host = NSHostingView(rootView: SettingsView(model: .shared, tab: tab ?? .usage))
            // Don't let SwiftUI size the window: it adds the title bar's safe area (32pt) to the 600pt view.
            host.sizingOptions = []
            // Full-size content view + transparent title bar: the sidebar card runs to the top of the window with the
            // traffic lights inside it, and each pane draws its own title.
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.contentView = host
            w.titlebarAppearsTransparent = true
            w.titlebarSeparatorStyle = .none
            w.titleVisibility = .hidden
            // An empty unified toolbar gives the window macOS's larger corner radius (26pt) and puts the traffic lights
            // 19pt in from the corner. It draws nothing, and the content under it still gets clicks.
            w.toolbar = NSToolbar(identifier: "ClausageSettings")
            w.toolbarStyle = .unified
            w.title = "Clausage Settings"
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(named: "Cream")
            w.isReleasedWhenClosed = false
            w.delegate = self
            // Size the window first: restoring a saved position on a still-tiny window anchors it by its top-left, and
            // SwiftUI then grows it upward from the bottom-left (it jumped to the top of the screen).
            // Reopens where it was last left; centered the first time. All before it is shown.
            w.setFrame(NSRect(x: 0, y: 0, width: 760, height: 600), display: false)   // full-size content: the frame is the content
            let frameName = "ClausageSettings"
            if w.setFrameUsingName(frameName) {
                // A saved frame may carry an older size; keep its top-left and use the current one.
                var f = w.frame
                f.origin.y += f.height - 600
                f.size = NSSize(width: 760, height: 600)
                w.setFrame(f, display: false)
            } else {
                w.center()
            }
            w.setFrameAutosaveName(frameName)
            window = w
            AppActivation.push()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // macOS focuses the first control when a window opens, which rings the Usage row. Start with nothing focused;
        // Tab brings the focus ring in.
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(nil) }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        AppActivation.pop()
    }
}
