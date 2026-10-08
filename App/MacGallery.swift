#if DEBUG
import SwiftUI

/// Debug aid: renders the popover (light and dark) and the menu bar icon states to PNGs.
/// Run the app binary with `--render-gallery <folder>`.
@MainActor
enum MacGallery {
    static func render(into dir: String, model: UsageModel) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let backdrop = scheme == .dark ? Color(red: 0.16, green: 0.13, blue: 0.11) : Color(red: 0.78, green: 0.55, blue: 0.40)
            let view = UsageView(model: model)
                .environment(\.colorScheme, scheme)
                .padding(30)
                .background(backdrop)
            // Through an offscreen window, so the AppKit parts (the gear button) draw too.
            let fitting = NSHostingView(rootView: view).fittingSize
            snapshot(view, size: fitting, appearance: scheme == .dark ? .darkAqua : .aqua, to: "\(dir)/popover-\(name).png")
        }
        // Menu bar icon: the same snapshot at a few levels, every display mode, on light and dark bars (each half drawn
        // for its bar, as the menu bar does).
        writeIcons(columns: MenuDisplay.allCases.count, to: "\(dir)/menubar.png") { dark in
            [0.0, 30, 62, 88, 96].flatMap { pct in
                let l = model.limits.map { UsageLimit(id: $0.id, kind: $0.kind, title: $0.title, shortTitle: $0.shortTitle,
                                                      percent: $0.kind == "session" ? pct : min($0.percent, pct), resetsAt: $0.resetsAt,
                                                      severity: $0.severity, isActive: $0.isActive) }
                return MenuDisplay.allCases.map {
                    MenuBarIcon.image(display: $0, limits: l, tint: true, darkMenubar: dark, free: model.activeIsFree)
                }
            }
        }
        // Fill with accent color, at the same levels.
        writeIcons(columns: 5, to: "\(dir)/menubar-accent.png") { dark in
            [0.0, 30, 62, 88, 96].map { pct in
                MenuBarIcon.image(display: .fill, limits: [UsageLimit(id: "s", kind: "session", title: "Current session", shortTitle: "Session",
                                                                      percent: pct, resetsAt: nil, severity: "normal", isActive: nil)],
                                  tint: true, darkMenubar: dark, accentFill: true)
            }
        }

        // Settings: real AppKit + SwiftUI views drawn offscreen, so native controls render too.
        ClaudeCodeLogs.previewAccess = true
        var week = ContributorsScan.Window(requests: 3329, sessions: 1088)
        week.behaviors = [(.highParallel, 50), (.longContext, 50), (.subagentHeavy, 34), (.activeLong, 33), (.cacheMiss, 0)]
        week.skills = [.init(name: "loop", percent: 4), .init(name: "dev-report", percent: 2)]
        week.agents = [.init(name: "Explore", percent: 4)]
        ClaudeCodeLogs.lastResult = ContributorsScan.Result(day: week, week: week, limitHits: ["five_hour": 56, "seven_day": 1])
        for tab in SettingsTab.allCases {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                snapshot(SettingsView(model: model, tab: tab), size: NSSize(width: 760, height: 600), appearance: appearance,
                         to: "\(dir)/settings-\(tab.rawValue.replacingOccurrences(of: " ", with: ""))-\(name).png")
            }
        }
        // Accounts with two accounts: a radio per row picks the one the menu bar shows.
        let second = Account(id: UUID(), name: "work@example.com", orgID: "demo-2")
        model.accounts.append(second)
        model.states[second.id] = model.activeState
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            snapshot(SettingsView(model: model, tab: .accounts), size: NSSize(width: 760, height: 600), appearance: appearance,
                     to: "\(dir)/settings-Accounts-two-\(name).png")
        }
        model.accounts.removeAll { $0.id == second.id }
        model.states[second.id] = nil

        // Updates while a check runs.
        Updater.shared.previewChecking()
        for tab in [SettingsTab.updates] {
            snapshot(SettingsView(model: model, tab: tab), size: NSSize(width: 760, height: 600), appearance: .darkAqua,
                     to: "\(dir)/settings-\(tab.rawValue)-checking-dark.png")
        }
        // Updates with an update ready (3g).
        // The version after this one, so the preview never reads as a downgrade.
        let next = AppVersion.short.split(separator: ".").map(String.init).enumerated()
            .map { i, p in i == 2 ? String((Int(p) ?? 0) + 1) : p }.joined(separator: ".")
        Updater.shared.previewAvailable(next, build: String((Int(AppVersion.build) ?? 0) + 1))
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            snapshot(SettingsView(model: model, tab: .updates), size: NSSize(width: 760, height: 600), appearance: appearance,
                     to: "\(dir)/settings-Updates-available-\(name).png")
        }
        // The whole Usage pane, below the fold too.
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            snapshot(SettingsView(model: model, tab: .usage), size: NSSize(width: 760, height: 980), appearance: appearance,
                     to: "\(dir)/settings-Usage-full-\(name).png")
        }
    }

    /// Draws a view hierarchy into a PNG through an offscreen window (AppKit controls included). The window is key in an
    /// active app, so native controls draw in their active colors (accent-tinted switches), not the inactive gray.
    private static func snapshot<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to path: String) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = KeyWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        // The window server's copy shows controls as they are on screen; drawing the view (cacheDisplay) gives AppKit
        // controls their inactive look. Falls back to that when the capture isn't allowed.
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.bestResolution, .boundsIgnoreFraming]),
           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        } else if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
        }
        window.orderOut(nil)
    }

    private final class KeyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private static func write<V: View>(_ view: V, to path: String) {
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    private static func writeIcons(columns: Int, to path: String, icons make: (_ dark: Bool) -> [NSImage]) {
        let cell = NSSize(width: 70, height: 26)
        let sets = [false: make(false), true: make(true)]
        let rows = ((sets[false]?.count ?? 0) + columns - 1) / columns
        let size = NSSize(width: cell.width * CGFloat(columns) * 2, height: cell.height * CGFloat(rows) * 2 * 2)
        let img = NSImage(size: size, flipped: true) { _ in
            for (half, dark) in [(0, false), (1, true)] {
                let y0 = CGFloat(half) * cell.height * CGFloat(rows) * 2
                (dark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                NSRect(x: 0, y: y0, width: size.width, height: cell.height * CGFloat(rows) * 2).fill()
                for (i, icon) in (sets[dark] ?? []).enumerated() {
                    let x = CGFloat(i % columns) * cell.width * 2 + 16, y = y0 + CGFloat(i / columns) * cell.height * 2 + 8
                    let drawn = icon.isTemplate ? tinted(icon, dark ? .white : .black) : icon
                    drawn.draw(in: NSRect(x: x, y: y, width: icon.size.width * 2, height: icon.size.height * 2))
                }
            }
            return true
        }
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    /// What the menu bar does with a template image: paint its alpha in the bar's text color.
    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { r in
            image.draw(in: r)
            color.setFill()
            r.fill(using: .sourceIn)
            return true
        }
    }
}
#endif
