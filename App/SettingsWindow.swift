import SwiftUI

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingView(rootView: SettingsView(model: .shared))
            // Don't let SwiftUI size the window: it adds the title bar's safe area (32pt) to the 600pt view.
            host.sizingOptions = []
            // Full-size content view + transparent title bar: the split view's sidebar runs to the top of the window with
            // the traffic lights inside it, and the page title (.navigationTitle) renders in the toolbar area.
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.contentView = host
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
            w.setFrame(NSRect(x: 0, y: 0, width: 760, height: 600), display: false)   // full-size content: the frame is the content
            let frameName = "ClaudeUsageSettings"
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
        placeWindowButtons()
    }

    /// The traffic lights are the sidebar card's first row: centered in a row-height slot inset like the About row at
    /// the bottom, left-aligned with the row tiles. The title bar container is resized to end where that slot ends, so
    /// it never covers the General row. AppKit lays the buttons out again on some window events, hence the re-runs.
    private func placeWindowButtons() {
        guard let w = window else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { w.standardWindowButton($0) }
        guard buttons.count == 3, let container = buttons[0].superview?.superview else { return }
        let spacing = buttons[1].frame.minX - buttons[0].frame.minX
        let m = SettingsSidebar.self
        var f = container.frame
        f.size.height = m.buttonsRowTop + m.rowHeight
        f.origin.y = w.frame.height - f.height
        container.frame = f
        for (i, b) in buttons.enumerated() {
            let top = m.buttonsRowTop + (m.rowHeight - b.frame.height) / 2
            b.setFrameOrigin(NSPoint(x: m.tileLeading + CGFloat(i) * spacing, y: f.height - top - b.frame.height))
        }
    }

    func windowDidResize(_ notification: Notification) { placeWindowButtons() }
    func windowDidBecomeKey(_ notification: Notification) { placeWindowButtons() }
    func windowDidResignKey(_ notification: Notification) { placeWindowButtons() }
    func windowDidChangeEffectiveAppearance(_ notification: Notification) { placeWindowButtons() }

    func windowWillClose(_ notification: Notification) {
        window = nil
        AppActivation.pop()
    }
}
