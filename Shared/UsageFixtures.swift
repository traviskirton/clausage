import Foundation

/// Sample snapshots for previews and the in-app gallery. Monday 5 Oct 2026, 11:30 AM.
/// Pace (how much of the window has elapsed) is set per limit; reset times follow from it, rounded to 5 minutes.
enum UsageFixtures {
    static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 11, minute: 30))!

    private static func limit(_ kind: String, _ title: String, _ short: String, pct: Double, pace: Double,
                              at now: Date = now, active: Bool? = nil) -> UsageLimit {
        let window: TimeInterval = kind == "session" ? 5 * 3600 : 7 * 86400
        let raw = now.addingTimeInterval((1 - pace) * window).timeIntervalSinceReferenceDate
        let reset = Date(timeIntervalSinceReferenceDate: (raw / 300).rounded() * 300)
        return UsageLimit(id: "\(kind)-\(title)", kind: kind, title: title, shortTitle: short,
                          percent: pct, resetsAt: reset, severity: "normal", isActive: active)
    }

    private static func snapshot(_ s: (Double, Double), _ a: (Double, Double), _ f: (Double, Double),
                                 days: [Double], updated: Date) -> SharedStore.Snapshot {
        var snap = SharedStore.Snapshot(limits: [
            limit("session", "Current session", "Session", pct: s.0, pace: s.1),
            limit("weekly_all", "Weekly · All models", "Weekly · All", pct: a.0, pace: a.1),
            limit("weekly_scoped", "Weekly · Fable", "Weekly · Fable", pct: f.0, pace: f.1),
        ], updated: updated, connected: true, days: days)
        snap.plan = Plan(badge: "Max 5×", orgName: nil)
        if let all = snap.limits.first(where: { $0.kind == "weekly_all" }), let r = all.resetsAt {
            snap.weekly = WeeklyWindow(start: r.addingTimeInterval(-7 * 86400), resetsAt: r, percent: all.percent)
        }
        snap.breakdown = breakdown
        return snap
    }

    private static let recent = now.addingTimeInterval(-46 * 60)

    /// The Mixed scenario relative to the real clock (for views that read `Date()` themselves, like the Mac popover).
    static func mixedLive(_ at: Date = Date()) -> SharedStore.Snapshot {
        var s = SharedStore.Snapshot(limits: [
            limit("session", "Current session", "Session", pct: 96, pace: 0.90, at: at, active: false),
            limit("weekly_all", "Weekly · All models", "Weekly · All", pct: 88, pace: 0.70, at: at, active: true),
            limit("weekly_scoped", "Weekly · Fable", "Weekly · Fable", pct: 62, pace: 0.93, at: at, active: false),
        ], updated: at.addingTimeInterval(-60), connected: true)
        s.plan = Plan(badge: "Max 5×", orgName: nil)
        s.breakdown = breakdown
        if let all = s.limits.first(where: { $0.kind == "weekly_all" }), let r = all.resetsAt {
            s.weekly = WeeklyWindow(start: r.addingTimeInterval(-7 * 86400), resetsAt: r, percent: all.percent)
        }
        return s
    }

    static let mixed = snapshot((96, 0.90), (88, 0.70), (87, 0.93), days: [8, 15, 17, 10, 6, 14, 18], updated: recent)
    static let calm = snapshot((22, 0.30), (62, 0.55), (40, 0.50), days: [8, 15, 17, 10, 6, 14, 18], updated: recent)
    static let allCritical = snapshot((97, 0.90), (96, 0.70), (95, 0.96), days: [8, 15, 17, 10, 6, 14, 18], updated: recent)
    static var stale: SharedStore.Snapshot {
        var s = mixed
        s.updated = now.addingTimeInterval(-4 * 3600)
        return s
    }

    static let breakdown = ProductBreakdown(asOf: now, windowStart: nil, rows: [
        .init(key: "claude_code", name: "Claude Code", percent: 57), .init(key: "cowork", name: "Cowork", percent: 30),
        .init(key: "chat", name: "Chat", percent: 10), .init(key: "other", name: "Other", percent: 3)])

    /// A running total for the weekly window of `snapshot`: one reading per day at 8 PM up to the snapshot's time,
    /// rising to its weekly % (a point for every day so far, state 6d). `values` overrides the earlier days.
    static func history(for snapshot: SharedStore.Snapshot, values: [Double]? = nil) -> WeeklyHistory {
        guard let w = snapshot.weekly else { return WeeklyHistory() }
        let cal = Calendar.current
        let today = WeeklyChart.dayIndex(snapshot.updated, windowStart: w.start, calendar: cal)
        var h = WeeklyHistory()
        func add(_ v: Double, _ t: Date) {
            h.record(WeeklyWindow(start: w.start, resetsAt: w.resetsAt, percent: v), at: t, calendar: cal)
        }
        for d in 0..<today {
            let day = cal.startOfDay(for: cal.date(byAdding: .day, value: d, to: w.start)!)
            let v = values.flatMap { d < $0.count ? $0[d] : nil } ?? (w.percent * Double(d + 1) / Double(today + 1)).rounded()
            add(v, cal.date(byAdding: .hour, value: 20, to: day)!)
        }
        add(w.percent, snapshot.updated.addingTimeInterval(-60))
        add(w.percent, snapshot.updated)
        return h
    }

    // MARK: The Usage screen, as drawn in the design (Mon 9:23 PM)

    static let screenNow = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 21, minute: 23))!

    static var screen: SharedStore.Snapshot {
        let resets = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 5))!
        let session = UsageLimit(id: "session-0", kind: "session", title: "Current session", shortTitle: "Session", percent: 10,
                                 resetsAt: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 22, minute: 20)),
                                 severity: "normal", isActive: false)
        let all = UsageLimit(id: "weekly_all-1", kind: "weekly_all", title: "Weekly · All models", shortTitle: "Weekly · All",
                             percent: 92, resetsAt: resets, severity: "critical", isActive: true)
        let fable = UsageLimit(id: "weekly_scoped-2", kind: "weekly_scoped", title: "Weekly · Fable", shortTitle: "Weekly · Fable",
                               percent: 74, resetsAt: resets, severity: "normal", isActive: false)
        var s = SharedStore.Snapshot(limits: [session, all, fable], updated: screenNow, connected: true)
        s.plan = Plan(badge: "Max 5×", orgName: nil)
        s.weekly = WeeklyWindow(start: resets.addingTimeInterval(-7 * 86400), resetsAt: resets, percent: 92)
        s.breakdown = breakdown
        s.credits = UsageCredits(enabled: false, spentMinor: 0, limitMinor: 7000, balanceMinor: 0, currency: "CAD",
                                 autoReload: false, fetched: screenNow)
        s.email = "you@example.com"
        return s
    }

    /// Signed in on Free: claude.ai has no usage page, so no limits at all.
    static var free: SharedStore.Snapshot {
        var s = SharedStore.Snapshot(limits: [], updated: screenNow, connected: true)
        s.plan = Plan(badge: "Free", orgName: nil)
        s.email = "travis@postfl.com"
        return s
    }
}
