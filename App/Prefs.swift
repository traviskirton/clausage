import Foundation

enum Prefs {
    /// The chips in Notifications. The defaults (85%, 95%) match where bars turn orange and red.
    static let presetThresholds = [50, 75, 85, 95]

    static func register() {
        UserDefaults.standard.register(defaults: [
            "menuDisplay": "fill",
            "fillBase": "auto",
            "tintIcon": true,
            "thresholds": "85,95",
            "customThresholds": "",
            "notifySoon": true,
            "soonMinutes": 10,
            "notifyReset": true,
            "refreshMinutes": 5,
            "hotkeyEnabled": true,
            "notifyOutage": false,
        ])
        // Ring was dropped from the menu bar options; its closest replacement is Bars.
        if UserDefaults.standard.string(forKey: "menuDisplay") == "ring" {
            UserDefaults.standard.set("bars", forKey: "menuDisplay")
        }
    }

    static func parse(_ s: String) -> [Int] {
        s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    static var thresholds: [Int] { parse(UserDefaults.standard.string(forKey: "thresholds") ?? "") }
    static var allThresholdChips: [Int] {
        // Thresholds already on (e.g. 80% or 90% from the old presets) keep their chip, so they can still be turned off.
        Set(presetThresholds + parse(UserDefaults.standard.string(forKey: "customThresholds") ?? "") + thresholds).sorted()
    }
}
