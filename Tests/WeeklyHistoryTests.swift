import XCTest

/// Running-total chart states 6a–6f (README → Weekly chart). The window is Tue Sep 29 2026 5:00 AM → Tue Oct 6 5:00 AM, Vancouver.
final class WeeklyHistoryTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Vancouver")!
        return c
    }()

    /// Day 0 is Tuesday Sep 29.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, week: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: 29 + day + 7 * week, hour: hour, minute: minute))!
    }

    private func window(_ pct: Double, week: Int = 0) -> WeeklyWindow {
        WeeklyWindow(start: at(0, 5, week: week), resetsAt: at(7, 5, week: week), percent: pct)
    }

    private func record(_ h: inout WeeklyHistory, _ readings: [(Int, Int, Double)], week: Int = 0) {
        for (d, hr, pct) in readings { h.record(window(pct, week: week), at: at(d, hr, week: week), calendar: cal) }
    }

    private func fullWeek(week: Int = 0) -> [(Int, Int, Double)] {
        [(0, 20, 10), (1, 20, 24), (2, 20, 38), (3, 20, 50), (4, 20, 58), (5, 20, 70), (6, 20, 92)]
    }

    // 6a: installed Friday; the first fetch already returns the week's total.
    func test6aDayOne() throws {
        var h = WeeklyHistory()
        record(&h, [(3, 10, 41), (3, 10, 41)])
        let c = try XCTUnwrap(WeeklyChart.make(history: h, window: window(41), now: at(3, 11), calendar: cal))
        XCTAssertTrue(c.beforeInstall)
        XCTAssertFalse(c.gapFromStart)
        XCTAssertEqual(c.today, 3)
        XCTAssertEqual(c.points, [.init(day: 3, value: 41, kind: .measured)])
        XCTAssertEqual(c.rightLabel, "Counting since today")
        XCTAssertTrue(c.caption.hasPrefix("Fresh tally! You’d already used 41% before Clausage showed up"), c.caption)
    }

    // 6b: before install is one dotted stretch, then a point per day.
    func test6bAFewDaysIn() throws {
        var h = WeeklyHistory()
        record(&h, [(3, 10, 50), (3, 23, 55), (4, 20, 60), (5, 20, 65), (6, 9, 70)])
        let c = try XCTUnwrap(WeeklyChart.make(history: h, window: window(70), now: at(6, 9, 30), calendar: cal))
        XCTAssertTrue(c.beforeInstall)
        XCTAssertEqual(c.points.map(\.day), [3, 4, 5, 6])
        XCTAssertEqual(c.points.map(\.value), [55, 60, 65, 70])      // last reading of each day
        XCTAssertTrue(c.missingDays.isEmpty)
        XCTAssertEqual(c.rightLabel, "Counting since Fri")
        XCTAssertEqual(c.caption, "Tue to Thu are one dotted stretch from before install. A full week of points shows up after the reset on Tuesday.")
    }

    // 6c: no reading on Saturday; Sat gets a hollow interpolated point and the gap is dashed.
    func test6cMissedADay() throws {
        var h = WeeklyHistory()
        record(&h, [(0, 20, 10), (1, 20, 24), (2, 20, 38), (3, 20, 50), (5, 20, 70), (6, 20, 92)])
        let c = try XCTUnwrap(WeeklyChart.make(history: h, window: window(92), now: at(6, 21), calendar: cal))
        XCTAssertFalse(c.beforeInstall)
        XCTAssertEqual(c.missingDays, [4])
        XCTAssertEqual(c.points[4].value, 60, accuracy: 0.001)       // halfway between Fri 50 and Sun 70
        XCTAssertEqual(c.rightLabel, "Running total")
        XCTAssertEqual(c.caption, "No reading on Saturday (the phone napped), so Sat and Sun share one dashed stretch. The total is still exact.")
    }

    // 6d: a point for every day.
    func test6dFullWeek() throws {
        var h = WeeklyHistory()
        record(&h, fullWeek())
        let c = try XCTUnwrap(WeeklyChart.make(history: h, window: window(92), now: at(6, 21), calendar: cal))
        XCTAssertEqual(c.points.count, 7)
        XCTAssertTrue(c.points.allSatisfy { $0.kind == .measured })
        XCTAssertNil(c.ghost)
        XCTAssertEqual(c.current, 92)
        XCTAssertEqual(c.rightLabel, "Running total")
        XCTAssertEqual(c.caption, "The dashed line is an even pace to 100% by Tue 5:00 AM. You’re just under it.")
    }

    // 6e: right after the reset, last week shows as a ghost until Thursday.
    func test6eNewWeek() throws {
        var h = WeeklyHistory()
        record(&h, fullWeek())
        h.record(window(3, week: 1), at: at(0, 8, week: 1), calendar: cal)
        let c = try XCTUnwrap(WeeklyChart.make(history: h, window: window(3, week: 1), now: at(0, 9, week: 1), calendar: cal))
        XCTAssertEqual(c.ghost, [10, 24, 38, 50, 58, 70, 92])
        XCTAssertEqual(c.points, [.init(day: 0, value: 3, kind: .measured)])
        XCTAssertFalse(c.beforeInstall)
        XCTAssertEqual(c.rightLabel, "Week of Oct 6")
        XCTAssertEqual(c.caption, "Clean slate. Last week’s line stays in the background for comparison until Thursday.")

        // From the third day the ghost is gone.
        h.record(window(20, week: 1), at: at(2, 9, week: 1), calendar: cal)
        h.record(window(22, week: 1), at: at(2, 10, week: 1), calendar: cal)
        let later = try XCTUnwrap(WeeklyChart.make(history: h, window: window(22, week: 1), now: at(2, 11, week: 1), calendar: cal))
        XCTAssertNil(later.ghost)
        XCTAssertEqual(later.missingDays, [1])
    }

    // 6f: fewer than two readings and no last week: no chart.
    func test6fNotEnough() {
        var h = WeeklyHistory()
        XCTAssertNil(WeeklyChart.make(history: h, window: window(41), now: at(3, 11), calendar: cal))
        h.record(window(41), at: at(3, 10), calendar: cal)
        XCTAssertNil(WeeklyChart.make(history: h, window: window(41), now: at(3, 11), calendar: cal))
        h.record(window(41), at: at(3, 10, 5), calendar: cal)
        XCTAssertNotNil(WeeklyChart.make(history: h, window: window(41), now: at(3, 11), calendar: cal))
    }

    // Installed in an earlier week: days before the first reading are a gap, not "before install".
    func testGapFromStartWhenInstalledEarlier() throws {
        var h = WeeklyHistory()
        record(&h, fullWeek())
        record(&h, [(2, 10, 30), (2, 12, 32)], week: 1)
        let c = try XCTUnwrap(WeeklyChart.make(history: h, window: window(32, week: 1), now: at(2, 13, week: 1), calendar: cal))
        XCTAssertFalse(c.beforeInstall)
        XCTAssertTrue(c.gapFromStart)
        XCTAssertEqual(c.missingDays, [0, 1])
        XCTAssertEqual(c.points.last?.value, 32)
    }

    func testAbovePaceCaption() throws {
        var h = WeeklyHistory()
        record(&h, [(0, 20, 30), (1, 20, 60)])
        let c = try XCTUnwrap(WeeklyChart.make(history: h, window: window(60), now: at(1, 21), calendar: cal))
        XCTAssertEqual(c.caption, "The dashed line is an even pace to 100% by Tue 5:00 AM. You’re above it, so at this pace you’ll reach the limit before then.")
    }

    func testWellUnderAndLimitCaptions() throws {
        var h = WeeklyHistory()
        record(&h, [(0, 20, 5), (1, 20, 7), (2, 20, 8), (3, 20, 10)])
        let c = try XCTUnwrap(WeeklyChart.make(history: h, window: window(10), now: at(3, 21), calendar: cal))
        XCTAssertTrue(c.caption.hasSuffix("You’re well under it."), c.caption)
        var full = WeeklyHistory()
        record(&full, [(0, 20, 40), (3, 20, 100)])          // the limit message wins over the missed-day one
        let hit = try XCTUnwrap(WeeklyChart.make(history: full, window: window(100), now: at(3, 21), calendar: cal))
        XCTAssertEqual(hit.caption, "You’ve hit this week’s limit. It resets Tue 5:00 AM.")
    }

    func testRecordMergesUnchangedReadingsOnTheSameDay() {
        var h = WeeklyHistory()
        record(&h, [(1, 9, 20), (1, 10, 20), (1, 11, 20), (1, 12, 21), (2, 0, 21)])
        XCTAssertEqual(h.weeks.count, 1)
        XCTAssertEqual(h.weeks[0].samples, 5)
        XCTAssertEqual(h.weeks[0].readings.map(\.pct), [20, 21, 21])     // midnight starts a new day
        XCTAssertEqual(h.weeks[0].readings[0].t, at(1, 11))
    }

    func testKeepsTwoWeeks() {
        var h = WeeklyHistory()
        for w in 0..<3 { h.record(window(10, week: w), at: at(1, 9, week: w), calendar: cal) }
        XCTAssertEqual(h.weeks.map(\.start), [at(0, 5, week: 1), at(0, 5, week: 2)])
    }

    func testResetDayFoldsIntoDaySix() {
        XCTAssertEqual(WeeklyChart.dayIndex(at(7, 3), windowStart: at(0, 5), calendar: cal), 6)
        XCTAssertEqual(WeeklyChart.dayIndex(at(0, 6), windowStart: at(0, 5), calendar: cal), 0)
        XCTAssertEqual(WeeklyChart.dayIndex(at(1, 0), windowStart: at(0, 5), calendar: cal), 1)
    }

    func testPersistenceRoundTrip() {
        let defaults = UserDefaults(suiteName: "WeeklyHistoryTests")!
        defer { defaults.removePersistentDomain(forName: "WeeklyHistoryTests") }
        var h = WeeklyHistory()
        record(&h, fullWeek())
        HistoryStore.save(h, defaults: defaults)
        XCTAssertEqual(HistoryStore.load(defaults: defaults), h)
        HistoryStore.clear(defaults: defaults)
        XCTAssertEqual(HistoryStore.load(defaults: defaults), WeeklyHistory())
    }
}
