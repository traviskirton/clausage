import Foundation

/// Sample mode: the app runs on a `SampleData` scenario instead of a claude.ai account, so anyone (App Review included)
/// can see every screen and widget without signing in. No network: a refresh just rebuilds the scenario around "now".
/// The snapshot carries the scenario id (`Snapshot.sample`), which is what keeps sample mode on across launches.
enum SampleMode {
    static var scenarioID: String? { SharedStore.load()?.sample }
    static var isOn: Bool { scenarioID != nil }

    /// Starts sample mode, or switches scenario: writes the scenario's snapshot and a week of running-total history.
    static func start(_ id: String = SampleData.maxMixed.id) { write(id) }

    /// Rebuilds the current scenario around now (pull to refresh, background refresh, the widget's ↻).
    static func refresh() { if let id = scenarioID { write(id) } }

    /// Back to signed out. The sample history goes with it.
    static func stop() {
        HistoryStore.clear()
        UsageSource.markSignedOut()
    }

    private static func write(_ id: String) {
        guard let s = SampleData.scenario(id) else { return }
        let snap = SampleData.snapshot(s, now: Date())
        SharedStore.save(snap)
        if snap.weekly != nil { HistoryStore.save(UsageFixtures.history(for: snap)) } else { HistoryStore.clear() }
    }
}
