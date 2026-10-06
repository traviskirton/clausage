import AppKit
import SwiftUI

/// The popover's gear menu and the status item's right-click menu: a native NSMenu (positioning, dismissal and
/// keyboard handling stay AppKit's), with items drawn in Ink and an Ink-tint highlight instead of the system accent.
@MainActor
enum BrandMenu {
    struct Item {
        let title: String
        var key: String = ""
        let action: () -> Void
    }

    /// `nil` entries are separators.
    static func make(_ items: [Item?]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in items {
            guard let entry else { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: entry.title, action: #selector(Target.fire(_:)), keyEquivalent: entry.key)
            let target = Target(entry.action)
            item.target = target
            item.representedObject = target        // keeps the target alive with the item
            item.view = BrandMenuItemView(title: entry.title, key: entry.key)
            menu.addItem(item)
        }
        return menu
    }

    /// Refresh ⌘R · Open claude.ai Usage · Settings… ⌘, · Quit Clausage ⌘Q.
    static func standard(model: UsageModel) -> NSMenu {
        make([
            Item(title: "Refresh", key: "r") { model.refresh(userInitiated: true) },
            Item(title: "Open claude.ai Usage") { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!) },
            nil,
            Item(title: "Settings…", key: ",") { model.closePopover(); SettingsWindow.shared.show() },
            nil,
            Item(title: "Quit Clausage", key: "q") { NSApplication.shared.terminate(nil) },
        ])
    }

    final class Target: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire(_ sender: Any?) { run() }
    }
}

/// One menu row: title on the left, ⌘-shortcut on the right, an Ink-tint rounded highlight when selected.
final class BrandMenuItemView: NSView {
    private let title: String
    private let key: String

    init(title: String, key: String) {
        self.title = title
        self.key = key
        super.init(frame: NSRect(x: 0, y: 0, width: 210, height: 24))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var ink: NSColor { NSColor(named: "Ink") ?? .labelColor }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = enclosingMenuItem?.isHighlighted ?? false
        if highlighted {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            (dark ? NSColor(red: 244 / 255, green: 238 / 255, blue: 228 / 255, alpha: 0.12)
                  : NSColor(red: 38 / 255, green: 35 / 255, blue: 31 / 255, alpha: 0.09)).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        let font = NSFont.menuFont(ofSize: 13)
        let t = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: ink])
        t.draw(at: NSPoint(x: 14, y: (bounds.height - t.size().height) / 2))
        if !key.isEmpty {
            let s = NSAttributedString(string: "⌘" + key.uppercased(),
                                       attributes: [.font: font, .foregroundColor: NSColor(named: "Ink3") ?? .tertiaryLabelColor])
            s.draw(at: NSPoint(x: bounds.width - 14 - s.size().width, y: (bounds.height - s.size().height) / 2))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, let menu = item.menu else { return }
        menu.cancelTracking()
        if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
    }

    override var acceptsFirstResponder: Bool { false }
}

/// The popover footer's gear: a borderless AppKit button that pops the brand menu below itself.
struct GearMenuButton: NSViewRepresentable {
    let model: UsageModel

    func makeNSView(context: Context) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")!,
                         target: context.coordinator, action: #selector(Coordinator.open(_:)))
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        b.contentTintColor = NSColor(named: "Ink2")
        b.setAccessibilityLabel("Settings menu")
        return b
    }

    func updateNSView(_ b: NSButton, context: Context) { context.coordinator.model = model }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor final class Coordinator: NSObject {
        var model: UsageModel
        init(model: UsageModel) { self.model = model }
        @objc func open(_ sender: NSButton) {
            let menu = BrandMenu.standard(model: model)
            menu.appearance = sender.effectiveAppearance
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        }
    }
}
