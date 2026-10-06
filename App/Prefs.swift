import Foundation

enum Prefs {
    static let presetThresholds = [50, 75, 80, 90]

    static func register() {
        UserDefaults.standard.register(defaults: [
            "menuDisplay": "fill",
            "fillBase": "auto",
            "tintIcon": true,
            "thresholds": "75,80,90",
            "customThresholds": "",
            "notifySoon": true,
            "soonMinutes": 10,
            "notifyReset": true,
            "refreshMinutes": 5,
            "hotkeyEnabled": true,
            "notifyOutage": false,
        ])
    }

    static func parse(_ s: String) -> [Int] {
        s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    static var thresholds: [Int] { parse(UserDefaults.standard.string(forKey: "thresholds") ?? "") }
    static var allThresholdChips: [Int] {
        Set(presetThresholds + parse(UserDefaults.standard.string(forKey: "customThresholds") ?? "")).sorted()
    }
}
