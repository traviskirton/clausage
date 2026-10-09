import Foundation

enum UsageTimeline {
    /// Entries at: now, each limit's reset, the stale cutoff, and the projected 85% / 95% crossings, so states flip without the app running.
    static func dates(_ s: SharedStore.Snapshot?, now: Date) -> [Date] {
        var dates: Set<Date> = [now]
        if let s {
            dates.insert(s.updated.addingTimeInterval(Forecast.staleAfter + 1))
            for l in s.limits {
                if let r = l.resetsAt { dates.insert(r) }
                dates.formUnion(Forecast.crossings(l, now: now))
            }
        }
        return Array(dates.filter { $0 >= now }.sorted().prefix(24))
    }

    /// When to ask for the next timeline (iOS fetches fresh numbers then). iOS treats it as a request and spaces reloads
    /// out by its own budget, so this is the soonest, not a promise.
    static func refreshDate(_ now: Date) -> Date { now.addingTimeInterval(5 * 60) }
}
