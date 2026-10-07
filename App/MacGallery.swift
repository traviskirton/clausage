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
            write(view, to: "\(dir)/popover-\(name).png")
        }
        // Menu bar icon: the same snapshot at a few levels, every display mode, on light and dark bars.
        var row: [NSImage] = []
        for pct in [0.0, 30, 62, 88, 96] {
            let l = model.limits.map { UsageLimit(id: $0.id, kind: $0.kind, title: $0.title, shortTitle: $0.shortTitle,
                                                  percent: $0.kind == "session" ? pct : min($0.percent, pct), resetsAt: $0.resetsAt,
                                                  severity: $0.severity, isActive: $0.isActive) }
            for mode in MenuDisplay.allCases {
                row.append(MenuBarIcon.image(display: mode, limits: l, tint: true, darkMenubar: false, free: model.activeIsFree))
            }
        }
        writeIcons(row, columns: MenuDisplay.allCases.count, to: "\(dir)/menubar.png")

        // Settings: real AppKit + SwiftUI views drawn offscreen, so native controls render too.
        ClaudeCodeLogs.previewAccess = true
        var week = ContributorsScan.Window(requests: 3329, sessions: 1088)
        week.behaviors = [(.highParallel, 50), (.longContext, 50), (.subagentHeavy, 34), (.activeLong, 33), (.cacheMiss, 0)]
        week.skills = [.init(name: "loop", percent: 4), .init(name: "dev-report", percent: 2)]
        week.agents = [.init(name: "Explore", percent: 4)]
        ClaudeCodeLogs.lastResult = ContributorsScan.Result(day: week, week: week, limitHits: ["five_hour": 56, "seven_day": 1])
        for tab in [SettingsTab.general, .notifications, .claudeCode, .accounts, .about] {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                snapshot(SettingsView(model: model, tab: tab), size: NSSize(width: 760, height: 600), appearance: appearance,
                         to: "\(dir)/settings-\(tab.rawValue.replacingOccurrences(of: " ", with: ""))-\(name).png")
            }
        }
    }

    /// Draws a view hierarchy into a PNG through an offscreen window (AppKit controls included).
    private static func snapshot<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to path: String) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }

    private static func write<V: View>(_ view: V, to path: String) {
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    private static func writeIcons(_ icons: [NSImage], columns: Int, to path: String) {
        let cell = NSSize(width: 70, height: 26)
        let rows = (icons.count + columns - 1) / columns
        let size = NSSize(width: cell.width * CGFloat(columns) * 2, height: cell.height * CGFloat(rows) * 2 * 2)
        let img = NSImage(size: size, flipped: true) { _ in
            for (half, dark) in [(0, false), (1, true)] {
                let y0 = CGFloat(half) * cell.height * CGFloat(rows) * 2
                (dark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                NSRect(x: 0, y: y0, width: size.width, height: cell.height * CGFloat(rows) * 2).fill()
                for (i, icon) in icons.enumerated() {
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
