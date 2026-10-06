import Foundation

/// Linear "at this pace" projection for a usage window.
enum Forecast {
    struct Summary {
        let text: String
        /// true when the limit would be hit before the window resets
        let warning: Bool
    }

    /// Fraction (0...1) of the window that has elapsed, or nil if unknown / already reset.
    static func elapsed(_ l: UsageLimit, now: Date = Date()) -> Double? {
        guard let r = l.resetsAt else { return nil }
        let remaining = r.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        return min(max(1 - remaining / l.windowLength, 0), 1)
    }

    /// When usage would reach 100% at the current pace, if that happens before the reset.
    static func hitDate(_ l: UsageLimit, now: Date = Date()) -> Date? {
        guard let e = elapsed(l, now: now), e > 0.05, l.percent > 0, l.percent < 100, let r = l.resetsAt else { return nil }
        let ratePerSecond = l.percent / (e * l.windowLength)
        let hit = now.addingTimeInterval((100 - l.percent) / ratePerSecond)
        return hit < r ? hit : nil
    }

    static func projectedEnd(_ l: UsageLimit, now: Date = Date()) -> Double? {
        guard let e = elapsed(l, now: now), e > 0.05 else { return nil }
        return min(l.percent / e, 100)
    }

    static func timeText(_ d: Date, window: TimeInterval) -> String {
        window > 86_400
            ? d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            : d.formatted(.dateTime.hour().minute())
    }

    enum Level { case normal, warning, critical }

    /// Popover row state, from the percent used (not the forecast): under 85% normal,
    /// 85% to under 95% warning (near critical), 95% and up critical.
    static func level(_ l: UsageLimit) -> Level {
        l.percent >= 95 ? .critical : (l.percent >= 85 ? .warning : .normal)
    }

    static func summary(_ l: UsageLimit, now: Date = Date()) -> Summary? {
        if let hit = hitDate(l, now: now) {
            let name = l.kind == "session" ? "Session" : "Weekly"
            return Summary(text: "\(name) limit by \(timeText(hit, window: l.windowLength)) at this pace", warning: true)
        }
        if let end = projectedEnd(l, now: now) {
            return Summary(text: "On pace to finish near \(Int(end.rounded()))%", warning: false)
        }
        return nil
    }
}

// MARK: Shared display rules (iOS widgets and anywhere else that needs the same state, copy and order)

extension Forecast {
    /// Data older than this is shown dimmed.
    static let staleAfter: TimeInterval = 3 * 3600
    static let levelThresholds: [Double] = [85, 95]

    static func isStale(updated: Date, now: Date = Date()) -> Bool { now.timeIntervalSince(updated) > staleAfter }

    /// Display order: session, all models, then per-model limits (original order within a group).
    static func ordered(_ limits: [UsageLimit]) -> [UsageLimit] {
        func rank(_ l: UsageLimit) -> Int { l.kind == "session" ? 0 : (l.kind == "weekly_all" ? 1 : 2) }
        return limits.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    private static func modelOrAll(_ l: UsageLimit) -> String {
        l.kind == "weekly_all" ? "All models" : l.title.replacingOccurrences(of: "Weekly · ", with: "")
    }
    /// "Current session", "All models", or the model name.
    static func fullName(_ l: UsageLimit) -> String { l.kind == "session" ? "Current session" : modelOrAll(l) }
    /// "Session", "All models", or the model name.
    static func shortName(_ l: UsageLimit) -> String { l.kind == "session" ? "Session" : modelOrAll(l) }
    /// Circular gauge label: "Session", "All", or the model name.
    static func gaugeName(_ l: UsageLimit) -> String {
        l.kind == "session" ? "Session" : (l.kind == "weekly_all" ? "All" : modelOrAll(l))
    }

    /// "Out ~9:32 AM" / "Out ~Mon 9:40 PM". Only when the row is near critical or critical and the run-out lands before the reset.
    static func forecastText(_ l: UsageLimit, now: Date = Date()) -> String? {
        guard level(l) != .normal, let hit = hitDate(l, now: now) else { return nil }
        return "Out ~\(timeText(hit, window: l.windowLength))"
    }

    /// "Resets 12:00 PM" / "Resets Tue 5:00 AM".
    static func resetText(_ l: UsageLimit) -> String? {
        l.resetsAt.map { "Resets \(timeText($0, window: l.windowLength))" }
    }

    /// Most pressing limit: critical > near critical > normal, then highest percent.
    static func mostPressing(_ limits: [UsageLimit]) -> UsageLimit? {
        func key(_ l: UsageLimit) -> (Int, Double) {
            switch level(l) { case .critical: return (2, l.percent); case .warning: return (1, l.percent); case .normal: return (0, l.percent) }
        }
        return limits.max { key($0) < key($1) }
    }

    /// Times at which, at the current pace, the percent will cross 85% and 95% before the window resets.
    static func crossings(_ l: UsageLimit, now: Date = Date()) -> [Date] {
        guard let e = elapsed(l, now: now), e > 0.05, l.percent > 0, let r = l.resetsAt else { return [] }
        let rate = l.percent / (e * l.windowLength)
        return levelThresholds.compactMap { t in
            guard l.percent < t else { return nil }
            let d = now.addingTimeInterval((t - l.percent) / rate)
            return d < r ? d : nil
        }
    }
}
