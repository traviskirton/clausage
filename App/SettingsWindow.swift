import SwiftUI

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: .shared))
            // Full-size content view + transparent title bar: the split view's sidebar runs to the top of the window with
            // the traffic lights inside it, and the page title (.navigationTitle) renders in the toolbar area.
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.contentViewController = host
            // Transparent title bar, no toolbar: the traffic lights sit inside the sidebar card and each pane draws its own title.
            w.titlebarAppearsTransparent = true
            w.titlebarSeparatorStyle = .none
            w.titleVisibility = .hidden
            w.title = "Clausage Settings"
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(named: "Cream")
            w.isReleasedWhenClosed = false
            w.delegate = self
            // Size the window first: restoring a saved position on a still-tiny window anchors it by its top-left, and
            // SwiftUI then grows it upward from the bottom-left (it jumped to the top of the screen).
            // Reopens where it was last left; centered the first time. All before it is shown.
            w.setContentSize(NSSize(width: 760, height: 600))
            let frameName = "ClaudeUsageSettings"
            if !w.setFrameUsingName(frameName) { w.center() }
            w.setFrameAutosaveName(frameName)
            window = w
            AppActivation.push()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        AppActivation.pop()
    }
}
