import Foundation

/// Display choices the app and its widgets share, kept in the App Group.
enum DisplayPrefs {
    private static var d: UserDefaults { SharedStore.defaults }

    /// "Pace tick: marks how much of the window has passed." On by default.
    static var showPaceTick: Bool {
        get { d.object(forKey: "showPaceTick") as? Bool ?? true }
        set { d.set(newValue, forKey: "showPaceTick") }
    }

    /// Limits hidden from the app and widgets, by short name ("Session", "All models", "Fable").
    static var hiddenLimits: Set<String> {
        get { Set(d.stringArray(forKey: "hiddenLimits") ?? []) }
        set { d.set(Array(newValue).sorted(), forKey: "hiddenLimits") }
    }

    /// Display order, minus anything hidden.
    static func visible(_ limits: [UsageLimit]) -> [UsageLimit] {
        let hidden = hiddenLimits
        return Forecast.ordered(limits).filter { !hidden.contains(Forecast.shortName($0)) }
    }
}
