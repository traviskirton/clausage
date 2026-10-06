import AppKit

/// Menubar-only apps have no Dock icon or Cmd-Tab entry. Show them while any window is open.
@MainActor
enum AppActivation {
    private static var count = 0

    static func push() {
        count += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func pop() {
        count = max(0, count - 1)
        if count == 0 { NSApp.setActivationPolicy(.accessory) }
    }
}
