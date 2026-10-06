import Foundation

/// The weekly (All models) % as this app saw it, per fixed weekly window. claude.ai has no daily series, so each app
/// records its own: on every fetch, `(timestamp, seven_day %)`. Within a window the % only rises, so the last reading of
/// each day is that day's running total.
struct WeeklyHistory: Codable, Equatable {
    struct Reading: Codable, Equatable {
        let t: Date
        let pct: Double
    }

    struct Week: Codable, Equatable {
        let start: Date
        let resetsAt: Date
        var readings: [Reading]
        /// Fetches recorded in this window (thinning merges readings, this doesn't).
        var samples: Int
    }

    /// Oldest first; the current window and the one before it.
    var weeks: [Week] = []
    /// The org these readings belong to; recording for a different one starts over.
    var owner: String? = nil

    /// Records one fetch. Readings with an unchanged % on the same local day are merged (the later time wins).
    mutating func record(_ window: WeeklyWindow, at now: Date, owner: String? = nil, calendar: Calendar = .current) {
        if owner != self.owner {
            weeks = []
            self.owner = owner
        }
        let i: Int
        if let found = weeks.firstIndex(where: { abs($0.resetsAt.timeIntervalSince(window.resetsAt)) < 3600 }) {
            i = found
        } else {
            weeks.append(Week(start: window.start, resetsAt: window.resetsAt, readings: [], samples: 0))
            weeks.sort { $0.resetsAt < $1.resetsAt }
            i = weeks.firstIndex { $0.resetsAt == window.resetsAt }!
        }
        weeks[i].samples += 1
        let reading = Reading(t: now, pct: window.percent)
        if let last = weeks[i].readings.last, last.pct == reading.pct, calendar.isDate(last.t, inSameDayAs: now), last.t <= now {
            weeks[i].readings[weeks[i].readings.count - 1] = reading
        } else {
            weeks[i].readings.append(reading)
            weeks[i].readings.sort { $0.t < $1.t }
        }
        if weeks[i].readings.count > 1_000 { weeks[i].readings.removeFirst(weeks[i].readings.count - 1_000) }
        if weeks.count > 2 { weeks.removeFirst(weeks.count - 2) }
    }

    func week(for window: WeeklyWindow) -> Week? {
        weeks.first { abs($0.resetsAt.timeIntervalSince(window.resetsAt)) < 3600 }
    }

    func week(before w: Week) -> Week? {
        weeks.last { $0.resetsAt <= w.start.addingTimeInterval(3600) }
    }
}

/// Persistence in the App Group, so widgets can draw the chart too.
enum HistoryStore {
    static let key = "weeklyHistory"

    static func load(key: String = key, defaults: UserDefaults = SharedStore.defaults) -> WeeklyHistory {
        guard let data = defaults.data(forKey: key) else { return WeeklyHistory() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return (try? dec.decode(WeeklyHistory.self, from: data)) ?? WeeklyHistory()
    }

    static func save(_ history: WeeklyHistory, key: String = key, defaults: UserDefaults = SharedStore.defaults) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let data = try? enc.encode(history) { defaults.set(data, forKey: key) }
    }

    static func clear(key: String = key, defaults: UserDefaults = SharedStore.defaults) { defaults.removeObject(forKey: key) }
}

// MARK: Chart model (states 6a–6f)

/// What the running-total chart draws. x = the 7 days of the window, y = 0–100%.
struct WeeklyChart: Equatable {
    enum Kind: Equatable {
        /// A reading was taken that day.
        case measured
        /// No reading that day: drawn as a hollow dashed circle, interpolated, with a dashed segment across the gap.
        case missing
    }

    struct Point: Equatable {
        let day: Int
        let value: Double
        let kind: Kind
    }

    /// 0...6, the day of the window that today falls on.
    let today: Int
    /// Today and earlier, in day order. Days before the first reading aren't here.
    let points: [Point]
    /// Draw a dotted "Before Clausage" stretch from (window start, 0) to the first point (6a, 6b).
    let beforeInstall: Bool
    /// The stretch from (window start, 0) to the first point is a missed-day gap (the app was installed earlier).
    let gapFromStart: Bool
    /// Last week's day values, drawn as a faint ghost line (6e, until the third day of the window).
    let ghost: [Double]?
    /// Today's running total.
    let current: Double
    let windowStart: Date
    let resetsAt: Date
    /// Header, right side: "Running total", "Counting since today", "Counting since Fri", "Week of Oct 6".
    let rightLabel: String
    let caption: String

    var firstDay: Int { points.first?.day ?? today }
    var missingDays: [Int] { points.filter { $0.kind == .missing }.map(\.day) }

    /// Even pace to 100% by the reset: 1/7 at day 1, 100% at day 7.
    static func pace(day: Int) -> Double { Double(day + 1) / 7 * 100 }

    /// Day of the window (0...6) a date falls on. The window starts mid-day (e.g. Tue 5:00 AM), so its last few hours
    /// on the reset day fold into day 6.
    static func dayIndex(_ date: Date, windowStart: Date, calendar: Calendar) -> Int {
        let a = calendar.startOfDay(for: windowStart), b = calendar.startOfDay(for: date)
        let d = calendar.dateComponents([.day], from: a, to: b).day ?? 0
        return min(6, max(0, d))
    }

    /// `nil` means 6f: fewer than two readings and nothing from last week, so no chart yet.
    static func make(history: WeeklyHistory, window: WeeklyWindow?, now: Date, calendar: Calendar = .current,
                     sleeper: String = "the phone napped") -> WeeklyChart? {
        guard let window, let week = history.week(for: window), !week.readings.isEmpty else { return nil }
        let start = window.start, reset = window.resetsAt
        let today = dayIndex(now, windowStart: start, calendar: calendar)
        let previous = history.week(before: week)

        // Last reading of each day, today included.
        var last: [Int: Double] = [:]
        for r in week.readings where r.t <= now {
            last[dayIndex(r.t, windowStart: start, calendar: calendar)] = r.pct
        }
        guard let firstDay = last.keys.min() else { return nil }
        let current = week.readings.last { $0.t <= now }?.pct ?? window.percent

        // Ghost: last week's line, shown for the first two days of a new window when there's one to compare.
        var ghost: [Double]?
        if today <= 1, let prev = previous, !prev.readings.isEmpty {
            var prevLast: [Int: Double] = [:]
            for r in prev.readings { prevLast[dayIndex(r.t, windowStart: prev.start, calendar: calendar)] = r.pct }
            ghost = fill(prevLast, through: 6)
        }
        if week.samples < 2 && ghost == nil { return nil }       // 6f

        // Installed before this window (or it has last week's data): days without readings are gaps, not "before install".
        let installedEarlier = previous != nil
        let beforeInstall = firstDay > 0 && !installedEarlier

        var points: [Point] = []
        for d in firstDay...max(firstDay, today) {
            if let v = last[d] {
                points.append(Point(day: d, value: v, kind: .measured))
            } else {
                points.append(Point(day: d, value: interpolate(d, last, upTo: today, current: current), kind: .missing))
            }
        }
        let gapFromStart = firstDay > 0 && installedEarlier
        if gapFromStart {
            // Missed days at the start of the window: interpolate from (start, 0).
            let firstValue = last[firstDay] ?? current
            let lead = (0..<firstDay).map { d in Point(day: d, value: firstValue * Double(d + 1) / Double(firstDay + 1), kind: .missing) }
            points = lead + points
        }

        let fmt = Formatters(calendar: calendar)
        let rightLabel: String, caption: String
        if ghost != nil {
            rightLabel = "Week of \(fmt.monthDay(start))"
            caption = "Clean slate. Last week’s line stays in the background for comparison until \(fmt.weekdayLong(calendar.date(byAdding: .day, value: 2, to: start) ?? start))."
        } else if beforeInstall {
            rightLabel = firstDay == today ? "Counting since today" : "Counting since \(fmt.weekdayShort(dayDate(firstDay, start, calendar)))"
            if firstDay == today {
                let first = Int((week.readings.first?.pct ?? current).rounded())
                caption = "Fresh tally! You’d already used \(first)% before Clausage showed up, it just can’t tell which days. From here on, every day gets its own point."
            } else {
                let from = fmt.weekdayShort(dayDate(0, start, calendar)), to = fmt.weekdayShort(dayDate(firstDay - 1, start, calendar))
                let stretch = firstDay == 1 ? "\(from) is one dotted stretch" : "\(from) to \(to) are one dotted stretch"
                caption = "\(stretch) from before install. A full week of points shows up after the reset on \(fmt.weekdayLong(reset))."
            }
        } else if current >= 100 {
            rightLabel = "Running total"
            caption = "You’ve hit this week’s limit. It resets \(fmt.weekdayTime(reset))."
        } else if let gap = firstGap(points) {
            rightLabel = "Running total"
            let names = gap.days.map { fmt.weekdayShort(dayDate($0, start, calendar)) }
            let missed = gap.days.count == 1 ? fmt.weekdayLong(dayDate(gap.days[0], start, calendar)) : names.joined(separator: " and ")
            let span = "\(names.first!) \(gap.days.count == 1 ? "and" : "to") \(fmt.weekdayShort(dayDate(gap.next, start, calendar)))"
            caption = "No reading on \(missed) (\(sleeper)), so \(span) share one dashed stretch. The total is still exact."
        } else {
            rightLabel = "Running total"
            caption = paceCaption(current: current, now: now, start: start, reset: reset, fmt: fmt)
        }

        return WeeklyChart(today: today, points: points, beforeInstall: beforeInstall, gapFromStart: gapFromStart,
                           ghost: ghost, current: current, windowStart: start, resetsAt: reset,
                           rightLabel: rightLabel, caption: caption)
    }

    /// "The dashed line is an even pace to 100% by Tue 5:00 AM. You're just under it."
    static func paceCaption(current: Double, now: Date, start: Date, reset: Date, fmt: Formatters) -> String {
        let head = "The dashed line is an even pace to 100% by \(fmt.weekdayTime(reset))."
        if current >= 100 { return "You’ve hit this week’s limit. It resets \(fmt.weekdayTime(reset))." }
        let elapsed = min(max(now.timeIntervalSince(start) / reset.timeIntervalSince(start), 0), 1)
        let pace = elapsed * 100
        if current > pace + 0.5 { return "\(head) You’re above it, so at this pace you’ll reach the limit before then." }
        return "\(head) " + (pace - current < 10 ? "You’re just under it." : "You’re well under it.")
    }

    private static func dayDate(_ d: Int, _ start: Date, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: d, to: start) ?? start
    }

    /// Day values 0...through, interpolating days without readings.
    private static func fill(_ values: [Int: Double], through end: Int) -> [Double] {
        (0...end).map { d in values[d] ?? interpolate(d, values, upTo: end, current: values.values.max() ?? 0) }
    }

    /// Linear between the nearest measured days around `d` (0 at the window start; `current` if nothing later).
    private static func interpolate(_ d: Int, _ values: [Int: Double], upTo today: Int, current: Double) -> Double {
        let before = values.keys.filter { $0 < d }.max()
        let after = values.keys.filter { $0 > d && $0 <= today }.min()
        let x0 = Double(before ?? -1), y0 = before.flatMap { values[$0] } ?? 0
        let x1 = Double(after ?? today), y1 = after.flatMap { values[$0] } ?? current
        guard x1 > x0 else { return y0 }
        return y0 + (y1 - y0) * (Double(d) - x0) / (x1 - x0)
    }

    private static func firstGap(_ points: [Point]) -> (days: [Int], next: Int)? {
        guard let i = points.firstIndex(where: { $0.kind == .missing }) else { return nil }
        var days: [Int] = []
        var j = i
        while j < points.count, points[j].kind == .missing { days.append(points[j].day); j += 1 }
        let next = j < points.count ? points[j].day : min(days.last! + 1, 6)
        return (days, next)
    }

    struct Formatters {
        let calendar: Calendar
        private func string(_ d: Date, _ format: String) -> String {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            return f.string(from: d)
        }
        func weekdayShort(_ d: Date) -> String { string(d, "EEE") }
        func weekdayLong(_ d: Date) -> String { string(d, "EEEE") }
        func monthDay(_ d: Date) -> String { string(d, "MMM d") }
        func weekdayTime(_ d: Date) -> String { string(d, "EEE h:mm a") }
        func letter(_ d: Date) -> String { String(string(d, "EEEEE")) }
    }
}
