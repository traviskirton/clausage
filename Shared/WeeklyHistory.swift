import Foundation

/// The weekly (All models) % as this app saw it, per fixed weekly window. claude.ai has no daily series, so each app
/// records its own: on every fetch, `(timestamp, seven_day %)`, keeping the last reading of each hour. Within a window
/// the % rises, except when claude.ai resets it early; the chart draws that drop as a cliff.
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

    /// Records one fetch. Readings in the same local hour are merged (the later one wins), about 168 a week. Returns the
    /// weeks that just dropped out of the last two, oldest first, for the archive.
    @discardableResult
    mutating func record(_ window: WeeklyWindow, at now: Date, owner: String? = nil, calendar: Calendar = .current) -> [Week] {
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
        if let last = weeks[i].readings.last, calendar.isDate(last.t, equalTo: now, toGranularity: .hour), last.t <= now {
            weeks[i].readings[weeks[i].readings.count - 1] = reading
        } else {
            weeks[i].readings.append(reading)
            weeks[i].readings.sort { $0.t < $1.t }
        }
        if weeks[i].readings.count > 1_000 { weeks[i].readings.removeFirst(weeks[i].readings.count - 1_000) }
        guard weeks.count > 2 else { return [] }
        let older = Array(weeks.prefix(weeks.count - 2))
        weeks.removeFirst(weeks.count - 2)
        return older
    }

    func week(for window: WeeklyWindow) -> Week? {
        weeks.first { abs($0.resetsAt.timeIntervalSince(window.resetsAt)) < 3600 }
    }

    func week(before w: Week) -> Week? {
        weeks.last { $0.resetsAt <= w.start.addingTimeInterval(3600) }
    }
}

/// Persistence in the App Group, so widgets can draw the chart too. Defaults hold the last two weeks; older ones go to
/// `HistoryArchive`.
enum HistoryStore {
    static let key = "weeklyHistory"

    static func load(key: String = key, defaults: UserDefaults = SharedStore.defaults) -> WeeklyHistory {
        guard let data = defaults.data(forKey: key) else { return WeeklyHistory() }
        return decode(data) ?? WeeklyHistory()
    }

    static func save(_ history: WeeklyHistory, key: String = key, defaults: UserDefaults = SharedStore.defaults) {
        if let data = encode(history) { defaults.set(data, forKey: key) }
    }

    /// Records one fetch. Weeks that drop out of the last two go to the archive, if Keep history is longer than that.
    static func record(_ window: WeeklyWindow, at now: Date, owner: String?, key: String = key,
                       defaults: UserDefaults = SharedStore.defaults, archive: URL? = HistoryArchive.directory) {
        var history = load(key: key, defaults: defaults)
        if history.owner != owner { HistoryArchive.clear(key: key, in: archive) }
        let older = history.record(window, at: now, owner: owner)
        save(history, key: key, defaults: defaults)
        if !older.isEmpty {
            HistoryArchive.add(older, owner: owner, keep: HistoryRetention.weeks(defaults), key: key, in: archive)
        }
    }

    /// The history and its archive (sign out, remove account).
    static func clear(key: String = key, defaults: UserDefaults = SharedStore.defaults, archive: URL? = HistoryArchive.directory) {
        defaults.removeObject(forKey: key)
        HistoryArchive.clear(key: key, in: archive)
    }

    static func decode(_ data: Data) -> WeeklyHistory? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(WeeklyHistory.self, from: data)
    }

    static func encode(_ history: WeeklyHistory) -> Data? {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        return try? enc.encode(history)
    }
}

/// Settings → Keep history: how many weeks of readings to keep, the current one included. 0 keeps everything.
/// In the App Group, so an iPhone widget that records a fetch archives by the same rule.
enum HistoryRetention {
    static let key = "historyWeeks"
    static let standard = 2
    static let options: [(weeks: Int, label: String)] = [(2, "2 weeks"), (13, "3 months"), (26, "6 months"), (52, "1 year"), (0, "Forever")]

    static func weeks(_ defaults: UserDefaults = SharedStore.defaults) -> Int {
        defaults.object(forKey: key) as? Int ?? standard
    }
}

/// Weeks older than the last two, one JSON file per history key in the App Group container (kept out of defaults,
/// which every widget reload reads). About 7 KB a week. Trimmed to Keep history each time a week is added, so a
/// shorter setting takes effect at the next reset.
enum HistoryArchive {
    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.groupID)?
            .appendingPathComponent("History", isDirectory: true)
    }

    private static func file(_ key: String, _ dir: URL?) -> URL? { dir?.appendingPathComponent("\(key).json") }

    /// Oldest first.
    static func load(key: String = HistoryStore.key, in dir: URL? = directory) -> WeeklyHistory {
        guard let url = file(key, dir), let data = try? Data(contentsOf: url) else { return WeeklyHistory() }
        return HistoryStore.decode(data) ?? WeeklyHistory()
    }

    /// Adds weeks that left the last two, then keeps the newest `keep - 2` (the last two are in defaults).
    static func add(_ weeks: [WeeklyHistory.Week], owner: String?, keep: Int, key: String = HistoryStore.key,
                    in dir: URL? = directory) {
        guard let url = file(key, dir) else { return }
        guard keep == 0 || keep > 2 else { clear(key: key, in: dir); return }
        var archive = load(key: key, in: dir)
        if archive.owner != owner { archive = WeeklyHistory(weeks: [], owner: owner) }
        for w in weeks {
            archive.weeks.removeAll { abs($0.resetsAt.timeIntervalSince(w.resetsAt)) < 3600 }
            archive.weeks.append(w)
        }
        archive.weeks.sort { $0.resetsAt < $1.resetsAt }
        if keep > 0, archive.weeks.count > keep - 2 { archive.weeks.removeFirst(archive.weeks.count - (keep - 2)) }
        guard let data = HistoryStore.encode(archive) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func clear(key: String = HistoryStore.key, in dir: URL? = directory) {
        if let url = file(key, dir) { try? FileManager.default.removeItem(at: url) }
    }
}

// MARK: Chart model (states 6a–6f)

/// What the running-total chart draws. x = how far through the window (0 at the start, 1 at the reset), so each
/// reading sits at its real hour; y = 0–100%. The history is hourly; the line shows one reading per `lineHours`.
struct WeeklyChart: Equatable {
    /// The line keeps the last reading of each 6-hour block of the local day (12–6 AM, 6 AM–12 PM, …).
    static let lineHours = 6

    enum Kind: Equatable {
        /// A reading was taken that day.
        case measured
        /// No reading that day: drawn as a hollow dashed circle where the dashed stretch crosses the day.
        case missing
    }

    /// A day marker: the day's last reading, or where the line crosses a day with no readings.
    struct Point: Equatable {
        let day: Int
        let value: Double
        let kind: Kind
        /// 0...1 across the window.
        var x: Double = 0
    }

    /// One reading on the line. `dashed`: the stretch leading to it crosses a day with no readings.
    struct Sample: Equatable {
        let x: Double
        let value: Double
        var dashed = false
    }

    /// 0...6, the day of the window that today falls on.
    let today: Int
    /// Day markers, today and earlier, in day order. Days before the first reading aren't here.
    let points: [Point]
    /// The readings, thinned to one per `lineHours`, oldest first. With no reading yet today, it runs on to now, dashed.
    let line: [Sample]
    /// Draw a dotted "Before Clausage" stretch from (window start, 0) to the first point (6a, 6b).
    let beforeInstall: Bool
    /// The stretch from (window start, 0) to the first point is a missed-day gap (the app was installed earlier).
    let gapFromStart: Bool
    /// Last week's readings, drawn as a faint ghost line (6e, until the third day of the window).
    let ghost: [Sample]?
    /// Where each day's letter goes: the middle of that day's part of the window.
    let dayCenters: [Double]
    /// Today's running total.
    let current: Double
    let windowStart: Date
    let resetsAt: Date
    /// Header, right side: "Running total", "Counting since today", "Counting since Fri", "Week of Oct 6".
    let rightLabel: String
    /// The answer, above the caption: "Plate’s clean around Sat 3 PM." / "Leftovers likely." / "Plate’s clean." nil in the
    /// first-week, gap and new-week states, where the caption explains the chart instead.
    var headline: String? = nil
    let caption: String

    var firstDay: Int { points.first?.day ?? today }
    var missingDays: [Int] { points.filter { $0.kind == .missing }.map(\.day) }

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
        func position(_ t: Date, _ start: Date, _ reset: Date) -> Double {
            min(max(t.timeIntervalSince(start) / max(reset.timeIntervalSince(start), 1), 0), 1)
        }
        func x(_ t: Date) -> Double { position(t, start, reset) }

        // First and last reading of each day, today included.
        let readings = thinned(week.readings.filter { $0.t <= now }, calendar: calendar)
        var firstOf: [Int: WeeklyHistory.Reading] = [:], lastOf: [Int: WeeklyHistory.Reading] = [:]
        for r in readings {
            let d = dayIndex(r.t, windowStart: start, calendar: calendar)
            if firstOf[d] == nil { firstOf[d] = r }
            lastOf[d] = r
        }
        guard let firstDay = lastOf.keys.min() else { return nil }
        let current = readings.last?.pct ?? window.percent

        // Ghost: last week's line, shown for the first two days of a new window when there's one to compare.
        var ghost: [Sample]?
        if today <= 1, let prev = previous, !prev.readings.isEmpty {
            ghost = thinned(prev.readings, calendar: calendar).map { Sample(x: position($0.t, prev.start, prev.resetsAt), value: $0.pct) }
        }
        if week.samples < 2 && ghost == nil { return nil }       // 6f

        // Installed before this window (or it has last week's data): days without readings are gaps, not "before install".
        let installedEarlier = previous != nil
        let beforeInstall = firstDay > 0 && !installedEarlier
        let gapFromStart = firstDay > 0 && installedEarlier

        // The line: every reading at its time, dashed across days without readings; on to now if today has none yet.
        var line: [Sample] = []
        var lineDay: Int?
        for r in readings {
            let d = dayIndex(r.t, windowStart: start, calendar: calendar)
            line.append(Sample(x: x(r.t), value: r.pct, dashed: lineDay.map { d - $0 > 1 } ?? false))
            lineDay = d
        }
        if let d = lineDay, d < today { line.append(Sample(x: x(now), value: current, dashed: true)) }

        // A day without readings: as far along the stretch that crosses it as the day is between the stretch's ends
        // (the window start at 0% before the first reading; now at the current total after the last).
        func across(_ d: Int) -> (x: Double, value: Double) {
            let a = lastOf.keys.filter { $0 < d }.max(), b = firstOf.keys.filter { $0 > d }.min()
            let dayA = Double(a ?? -1), xA = a.map { x(lastOf[$0]!.t) } ?? 0, vA = a.map { lastOf[$0]!.pct } ?? 0
            let dayB = Double(b ?? today), xB = b.map { x(firstOf[$0]!.t) } ?? x(now), vB = b.map { firstOf[$0]!.pct } ?? current
            guard dayB > dayA else { return (xA, vA) }
            let f = (Double(d) - dayA) / (dayB - dayA)
            return (xA + (xB - xA) * f, vA + (vB - vA) * f)
        }
        var points: [Point] = []
        for d in (gapFromStart ? 0 : firstDay)...max(firstDay, today) {
            if let r = lastOf[d] {
                points.append(Point(day: d, value: r.pct, kind: .measured, x: x(r.t)))
            } else {
                let c = across(d)
                points.append(Point(day: d, value: c.value, kind: .missing, x: c.x))
            }
        }

        let day0 = calendar.startOfDay(for: start)
        let dayCenters = (0..<7).map { d -> Double in
            let a = d == 0 ? start : calendar.date(byAdding: .day, value: d, to: day0) ?? start
            let b = d == 6 ? reset : calendar.date(byAdding: .day, value: d + 1, to: day0) ?? reset
            return (x(a) + x(b)) / 2
        }

        let fmt = Formatters(calendar: calendar)
        let rightLabel: String, caption: String
        var headline: String?
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
            (headline, caption) = paceCaption(current: current, now: now, start: start, reset: reset, fmt: fmt)
        } else if let gap = firstGap(points) {
            rightLabel = "Running total"
            let names = gap.days.map { fmt.weekdayShort(dayDate($0, start, calendar)) }
            let missed = gap.days.count == 1 ? fmt.weekdayLong(dayDate(gap.days[0], start, calendar)) : names.joined(separator: " and ")
            let span = "\(names.first!) \(gap.days.count == 1 ? "and" : "to") \(fmt.weekdayShort(dayDate(gap.next, start, calendar)))"
            caption = "No reading on \(missed) (\(sleeper)), so \(span) share one dashed stretch. The total is still exact."
        } else {
            rightLabel = "Running total"
            (headline, caption) = paceCaption(current: current, now: now, start: start, reset: reset, fmt: fmt)
        }

        return WeeklyChart(today: today, points: points, line: line, beforeInstall: beforeInstall, gapFromStart: gapFromStart,
                           ghost: ghost, dayCenters: dayCenters, current: current, windowStart: start, resetsAt: reset,
                           rightLabel: rightLabel, headline: headline, caption: caption)
    }

    /// The answer and the reason, compared with the even-pace line:
    /// above it, "Plate’s clean around Sat 3 PM." / "You’re eating faster than the dashed line, and seconds aren’t served until Tue 5:00 AM.";
    /// at or under it, "Leftovers likely." / "You’re at or under the dashed line, so you should make it to Tue 5:00 AM.";
    /// full, "Plate’s clean." / "Seconds are served Tue 5:00 AM."
    static func paceCaption(current: Double, now: Date, start: Date, reset: Date, fmt: Formatters) -> (String, String) {
        let resetText = fmt.weekdayTime(reset)
        if current >= 100 { return ("Plate’s clean.", "Seconds are served \(resetText).") }
        let seconds = now.timeIntervalSince(start)
        let pace = min(max(seconds / reset.timeIntervalSince(start), 0), 1) * 100
        if current > pace + 0.5, seconds > 0, current > 0 {
            let hit = now.addingTimeInterval((100 - current) / (current / seconds))
            return ("Plate’s clean around \(fmt.weekdayHour(min(hit, reset))).",
                    "You’re eating faster than the dashed line, and seconds aren’t served until \(resetText).")
        }
        return ("Leftovers likely.", "You’re at or under the dashed line, so you should make it to \(resetText).")
    }

    /// The last reading of each `lineHours` block, plus the readings either side of a drop, so an early reset stays a
    /// cliff at its hour. A day's last reading always stays, so the day markers sit on the line.
    static func thinned(_ readings: [WeeklyHistory.Reading], calendar: Calendar) -> [WeeklyHistory.Reading] {
        func block(_ t: Date) -> (Date, Int) { (calendar.startOfDay(for: t), calendar.component(.hour, from: t) / lineHours) }
        return readings.indices.filter { i in
            guard i + 1 < readings.count else { return true }
            let r = readings[i], next = readings[i + 1]
            return block(next.t) != block(r.t) || next.pct < r.pct || (i > 0 && readings[i - 1].pct > r.pct)
        }.map { readings[$0] }
    }

    private static func dayDate(_ d: Int, _ start: Date, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: d, to: start) ?? start
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
        /// "Sat 3 PM", to the nearest hour (forecasts are approximate).
        func weekdayHour(_ d: Date) -> String {
            string(calendar.dateInterval(of: .hour, for: d.addingTimeInterval(1800))?.start ?? d, "EEE h a")
        }
        func letter(_ d: Date) -> String { String(string(d, "EEEEE")) }
    }
}
