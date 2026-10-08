import Carbon
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global "open popover" shortcut. Default ⌥⌘U, user-recordable in Settings; clearing it turns it off.
    static let openPopover = Self("openPopover", default: .init(.u, modifiers: [.option, .command]))
}

enum Hotkey {
    static func install(action: @escaping () -> Void) {
        migrateLegacy()
        migrateSwitch()
        KeyboardShortcuts.onKeyDown(for: .openPopover, action: action)
    }

    /// The on/off switch is gone (the recorder alone decides): a shortcut that was switched off starts out cleared.
    private static func migrateSwitch() {
        let d = UserDefaults.standard
        guard let on = d.object(forKey: "hotkeyEnabled") as? Bool else { return }
        if !on { KeyboardShortcuts.setShortcut(nil, for: .openPopover) }
        d.removeObject(forKey: "hotkeyEnabled")
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
