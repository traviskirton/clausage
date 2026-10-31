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
        XCTAssertEqual(c.points.map(\.day), [3])
        XCTAssertEqual(c.points.map(\.value), [41])
        XCTAssertEqual(c.points.map(\.kind), [.measured])
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
        XCTAssertNil(c.headline)
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
        XCTAssertEqual(c.headline, "Leftovers likely.")
        XCTAssertEqual(c.caption, "You’re at or under the dashed line, so you should make it to Tue 5:00 AM.")
    }

    // 6e: right after the reset, last week shows as a ghost until Thursday.
    func test6eNewWeek() throws {
        var h = WeeklyHistory()
        record(&h, fullWeek())
        h.record(window(3, week: 1), at: at(0, 8, week: 1), calendar: cal)
        let c = try XCTUnwrap(WeeklyChart.make(history: h, window: window(3, week: 1), now: at(0, 9, week: 1), calendar: cal))
        XCTAssertEqual(c.ghost?.map(\.value), [10, 24, 38, 50, 58, 70, 92])
        XCTAssertEqual(c.points.map(\.day), [0])
        XCTAssertEqual(c.points.map(\.value), [3])
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
        // 60% after 40 of 168 hours: 1.5%/h, so 100% in another 26h40m, Thu 11:40 PM → the nearest hour.
        XCTAssertEqual(c.headline, "Plate’s clean around Fri 12 AM.")
        XCTAssertEqual(c.caption, "You’re eating faster than the dashed line, and seconds aren’t served until Tue 5:00 AM.")
    }

    func testUnderPaceAndFullCaptions() throws {
        var h = WeeklyHistory()
        record(&h, [(0, 20, 5), (1, 20, 7), (2, 20, 8), (3, 20, 10)])
        let c = try XCTUnwrap(WeeklyChart.make(history: h, window: window(10), now: at(3, 21), calendar: cal))
        XCTAssertEqual(c.headline, "Leftovers likely.")
        var full = WeeklyHistory()
        record(&full, [(0, 20, 40), (3, 20, 100)])          // the limit message wins over the missed-day one
        let hit = try XCTUnwrap(WeeklyChart.make(history: full, window: window(100), now: at(3, 21), calendar: cal))
        XCTAssertEqual(hit.headline, "Plate’s clean.")
        XCTAssertEqual(hit.caption, "Seconds are served Tue 5:00 AM.")
    }

    func testRecordKeepsTheLastReadingOfEachHour() {
        var h = WeeklyHistory()
        h.record(window(20), at: at(1, 9), calendar: cal)
        h.record(window(21), at: at(1, 9, 30), calendar: cal)
        h.record(window(22), at: at(1, 9, 55), calendar: cal)
        h.record(window(22), at: at(1, 10, 5), calendar: cal)
        h.record(window(22), at: at(1, 11), calendar: cal)
        XCTAssertEqual(h.weeks.count, 1)
        XCTAssertEqual(h.weeks[0].samples, 5)
        XCTAssertEqual(h.weeks[0].readings.map(\.pct), [22, 22, 22])     // one per hour, even when unchanged
        XCTAssertEqual(h.weeks[0].readings.map(\.t), [at(1, 9, 55), at(1, 10, 5), at(1, 11)])
    }

    // The history is hourly; the line keeps the last reading of each 6-hour block, at its own time.
    func testLineKeepsOneReadingPerSixHours() throws {
        var h = WeeklyHistory()
        record(&h, [(0, 9, 2), (0, 10, 5), (0, 14, 9), (1, 9, 10), (1, 11, 16)])
        XCTAssertEqual(h.weeks[0].readings.count, 5)
        let c = try XCTUnwrap(WeeklyChart.make(history: h, window: window(16), now: at(1, 12), calendar: cal))
        XCTAssertEqual(c.line.map(\.value), [5, 9, 16])
        XCTAssertTrue(c.line.allSatisfy { !$0.dashed })
        // Tue 10 AM is 5 of the window's 168 hours in.
        XCTAssertEqual(c.line[0].x, 5.0 / 168, accuracy: 1e-9)
        XCTAssertEqual(c.points.map(\.value), [9, 16])                 // day markers: each day's last reading
        XCTAssertEqual(c.points[0].x, 9.0 / 168, accuracy: 1e-9)
    }

    // An early (free) reset: the total drops mid-window. The line keeps the drop where it was seen, a cliff, not a
    // day-long slope.
    func testEarlyResetIsACliffAtItsHour() throws {
        var h = WeeklyHistory()
        record(&h, [(2, 20, 60), (2, 23, 62), (3, 9, 62), (3, 10, 1), (3, 11, 3), (3, 12, 4)])
        let c = try XCTUnwrap(WeeklyChart.make(history: h, window: window(4), now: at(3, 13), calendar: cal))
        XCTAssertEqual(c.line.map(\.value), [62, 62, 1, 3, 4])                // both sides of the drop survive thinning
        XCTAssertEqual(c.line[2].x - c.line[1].x, 1.0 / 168, accuracy: 1e-9)   // within the hour
        XCTAssertEqual(c.current, 4)
    }

    // A missed day: the stretch across it is dashed, and its ring sits on that stretch.
    func testMissedDayStretchIsDashed() throws {
        var h = WeeklyHistory()
        record(&h, [(0, 20, 10), (1, 20, 24), (3, 20, 50)])
        let c = try XCTUnwrap(WeeklyChart.make(history: h, window: window(50), now: at(3, 21), calendar: cal))
        XCTAssertEqual(c.line.map(\.dashed), [false, false, true])
        let ring = try XCTUnwrap(c.points.first { $0.kind == .missing })
        XCTAssertEqual(ring.day, 2)
        XCTAssertEqual(ring.value, 37, accuracy: 0.001)
        XCTAssertEqual(ring.x, (c.line[1].x + c.line[2].x) / 2, accuracy: 1e-9)
    }

    func testKeepsTwoWeeks() {
        var h = WeeklyHistory()
        for w in 0..<3 { h.record(window(10, week: w), at: at(1, 9, week: w), calendar: cal) }
        XCTAssertEqual(h.weeks.map(\.start), [at(0, 5, week: 1), at(0, 5, week: 2)])
    }

    // Keep history: weeks past the last two move to the archive, trimmed to the setting at each reset.
    func testArchiveKeepsOlderWeeksUpToTheSetting() {
        let suite = "WeeklyHistoryArchiveTests"
        let defaults = UserDefaults(suiteName: suite)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        func record(_ w: Int, owner: String = "org") {
            HistoryStore.record(window(10, week: w), at: at(1, 9, week: w), owner: owner, defaults: defaults, archive: dir)
        }
        func starts(_ h: WeeklyHistory) -> [Date] { h.weeks.map(\.start) }

        // The default (2 weeks) archives nothing.
        for w in 0..<3 { record(w) }
        XCTAssertEqual(starts(HistoryArchive.load(in: dir)), [])

        defaults.set(13, forKey: HistoryRetention.key)
        for w in 3..<6 { record(w) }
        XCTAssertEqual(starts(HistoryStore.load(defaults: defaults)), [at(0, 5, week: 4), at(0, 5, week: 5)])
        XCTAssertEqual(starts(HistoryArchive.load(in: dir)), [at(0, 5, week: 1), at(0, 5, week: 2), at(0, 5, week: 3)])

        // Shorter: 3 weeks in all keeps one archived week, from the next reset.
        defaults.set(3, forKey: HistoryRetention.key)
        record(6)
        XCTAssertEqual(starts(HistoryArchive.load(in: dir)), [at(0, 5, week: 4)])

        // Forever, then another org: its history starts over, archive included.
        defaults.set(0, forKey: HistoryRetention.key)
        record(7)
        XCTAssertEqual(HistoryArchive.load(in: dir).weeks.count, 2)
        record(8, owner: "other")
        XCTAssertEqual(starts(HistoryArchive.load(in: dir)), [])
        XCTAssertEqual(starts(HistoryStore.load(defaults: defaults)), [at(0, 5, week: 8)])

        // Signing out clears both.
        record(9, owner: "other"); record(10, owner: "other")
        XCTAssertEqual(HistoryArchive.load(in: dir).weeks.count, 1)
        HistoryStore.clear(defaults: defaults, archive: dir)
        XCTAssertEqual(HistoryArchive.load(in: dir), WeeklyHistory())
        XCTAssertEqual(HistoryStore.load(defaults: defaults), WeeklyHistory())
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
