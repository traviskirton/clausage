import XCTest

/// The sample-mode scenarios: each one goes through the same parser as live claude.ai data, so they double as
/// parsing tests for every plan and response shape.
final class SampleDataTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    func testEveryScenarioParsesCleanly() throws {
        for s in SampleData.all {
            let org = try XCTUnwrap(SampleData.org(s), s.id)
            XCTAssertNotNil(org.plan, "\(s.id): plan")
            let report = try XCTUnwrap(SampleData.report(s, now: now), "\(s.id): report")
            XCTAssertEqual(report.unparsed, [], "\(s.id): unparsed limits")
            for l in report.limits {
                XCTAssertGreaterThan(l.resetsAt ?? .distantPast, now, "\(s.id): \(l.kind) resets in the future")
            }
        }
        XCTAssertEqual(Set(SampleData.all.map(\.id)).count, SampleData.all.count, "unique ids")
        XCTAssertFalse(SampleData.pickable.contains { $0.testOnly })
    }

    func testRelativeTimes() {
        let out = SampleData.resolve(#"["{{T+1d2h30m}}","{{T-15m}}","{{T+48m}}"]"#, now: now)
        let dates = (try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String])?.compactMap(UsageClient.date)
        XCTAssertEqual(dates?.map { $0.timeIntervalSince(now).rounded() }, [95_400, -900, 2_880])
    }

    func testMaxMixed() throws {
        let snap = SampleData.snapshot(SampleData.maxMixed, now: now)
        XCTAssertEqual(snap.plan?.badge, "Max 5×")
        XCTAssertEqual(snap.limits.map(\.kind), ["session", "weekly_all", "weekly_scoped"])
        XCTAssertEqual(snap.limits[2].title, "Weekly · Fable")
        XCTAssertEqual(snap.limits.first { $0.isActive == true }?.kind, "weekly_scoped")
        XCTAssertEqual(snap.breakdown?.rows.first?.name, "Claude Code")
        XCTAssertEqual(snap.weekly?.percent, 64)
        XCTAssertEqual(snap.credits?.limitMinor, 5000)
        XCTAssertEqual(snap.sample, "max-mixed")
        XCTAssertFalse(SharedStore.isFree(snap))
        XCTAssertEqual(Forecast.level(snap.limits[2]), .warning)
    }

    func testMaxCritical() throws {
        let snap = SampleData.snapshot(SampleData.maxCritical, now: now)
        XCTAssertEqual(snap.plan?.badge, "Max 20×")
        let session = try XCTUnwrap(snap.limits.first { $0.kind == "session" })
        XCTAssertEqual(session.isActive, true)
        XCTAssertEqual(Forecast.level(session), .critical)
        XCTAssertEqual(snap.credits?.enabled, true)
    }

    func testProTeamAndEnterprise() throws {
        let pro = SampleData.snapshot(SampleData.proCalm, now: now)
        XCTAssertEqual(pro.plan?.badge, "Pro")
        XCTAssertTrue(pro.limits.allSatisfy { Forecast.level($0) == .normal })
        XCTAssertNil(pro.credits)

        let team = SampleData.snapshot(SampleData.team, now: now)
        XCTAssertEqual(team.plan?.badge, "Team")
        XCTAssertEqual(team.plan?.orgName, "Sample Studio")
        XCTAssertNil(team.breakdown)

        let ent = SampleData.snapshot(SampleData.enterprise, now: now)
        XCTAssertEqual(ent.plan?.badge, "Enterprise")
        XCTAssertTrue(ent.limits.isEmpty)          // no plan limits: "Nothing to count", not the Free state
        XCTAssertFalse(SharedStore.isFree(ent))
    }

    func testFree() throws {
        let snap = SampleData.snapshot(SampleData.free, now: now)
        XCTAssertEqual(snap.plan?.badge, "Free")
        XCTAssertTrue(SharedStore.isFree(snap))
        XCTAssertTrue(snap.limits.isEmpty)
        XCTAssertNil(snap.weekly)
        XCTAssertNil(snap.credits)
    }

    func testLegacyKeysOnly() throws {
        let r = try XCTUnwrap(SampleData.report(SampleData.legacyKeys, now: now))
        XCTAssertEqual(r.limits.map(\.id), ["five_hour", "seven_day", "seven_day_opus"])
        XCTAssertEqual(r.limits.map(\.title), ["Current session", "Weekly · All models", "Weekly · Opus"])
        XCTAssertEqual(r.weekly?.percent, 47)
        XCTAssertNil(r.breakdown)
    }
}
