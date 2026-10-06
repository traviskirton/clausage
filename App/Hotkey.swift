import Carbon
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global "open popover" shortcut. Default ⌥⌘U, user-recordable in Settings.
    static let openPopover = Self("openPopover", default: .init(.u, modifiers: [.option, .command]))
}

enum Hotkey {
    private static var enabled: Bool?

    static func install(action: @escaping () -> Void) {
        migrateLegacy()
        KeyboardShortcuts.onKeyDown(for: .openPopover, action: action)
    }

    static func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on { KeyboardShortcuts.enable(.openPopover) } else { KeyboardShortcuts.disable(.openPopover) }
    }

    /// Carries a shortcut recorded with the old Carbon recorder over to KeyboardShortcuts, once.
    private static func migrateLegacy() {
        let d = UserDefaults.standard
        guard let code = d.object(forKey: "hotkeyCode") as? Int, let mods = d.object(forKey: "hotkeyMods") as? Int else { return }
        if code != 32 || mods != cmdKey | optionKey {
            KeyboardShortcuts.setShortcut(.init(carbonKeyCode: code, carbonModifiers: mods), for: .openPopover)
        }
        for k in ["hotkeyCode", "hotkeyMods", "hotkeyLabel"] { d.removeObject(forKey: k) }
    }
}
