import XCTest

/// Parsing of the claude.ai responses, using captured response shapes (values made up or rounded).
final class UsageParsingTests: XCTestCase {
    private let usage = """
    {"five_hour":{"utilization":15.0,"resets_at":"2026-10-06T10:20:00.879324+00:00","limit_dollars":null},
     "seven_day":{"utilization":95.0,"resets_at":"2026-10-06T12:00:00.879348+00:00"},
     "seven_day_opus":null,"iguana_necktie":{"utilization":0.0,"limit_dollars":250},"cedar_ember":null,
     "extra_usage":{"is_enabled":false,"monthly_limit":null},
     "limits":[
       {"kind":"session","group":"session","percent":15,"severity":"normal","resets_at":"2026-10-06T10:20:00.879324+00:00","scope":null,"is_active":false},
       {"kind":"weekly_all","group":"weekly","percent":95,"severity":"critical","resets_at":"2026-10-06T12:00:00.879348+00:00","scope":null,"is_active":true},
       {"kind":"weekly_scoped","group":"weekly","percent":74,"severity":"normal","resets_at":"2026-10-06T11:59:59.879579+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}],
     "spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},"enabled":false,"can_toggle":true},
     "seven_day_breakdown":{"as_of":"2026-10-06T05:45:15.895251+00:00","window_started_at":"2026-09-29T12:00:00.879348+00:00",
       "rows":[{"key":"claude_code","display_name":"Claude Code","percent":57},{"key":"chat","display_name":"Chat","percent":10},
               {"key":"cowork","display_name":"Cowork","percent":30},{"key":"other","display_name":"Other","percent":3}]}}
    """

    private func json(_ s: String) -> Any { try! JSONSerialization.jsonObject(with: Data(s.utf8)) }

    func testReport() throws {
        let r = try XCTUnwrap(UsageClient.report(json(usage)))
        XCTAssertEqual(r.limits.map(\.kind), ["session", "weekly_all", "weekly_scoped"])
        XCTAssertEqual(r.limits.map(\.isActive), [false, true, false])
        XCTAssertEqual(r.limits[2].title, "Weekly · Fable")
        XCTAssertEqual(r.breakdown?.rows.map(\.key), ["claude_code", "cowork", "chat", "other"])
        XCTAssertEqual(r.breakdown?.rows.first?.name, "Claude Code")
        XCTAssertEqual(r.weekly?.percent, 95)
        XCTAssertEqual(r.weekly?.start, UsageClient.date("2026-09-29T12:00:00.879348+00:00"))
        XCTAssertEqual(r.spendEnabled, false)
    }

    func testMissingBreakdownAndEmptyLimits() throws {
        let r = try XCTUnwrap(UsageClient.report(json(#"{"five_hour":null,"seven_day":null,"limits":[]}"#)))
        XCTAssertTrue(r.limits.isEmpty)          // Enterprise: nothing to count, but not an error
        XCTAssertNil(r.breakdown)
        XCTAssertNil(r.weekly)
        XCTAssertNil(UsageClient.report(json(#"{"error":"nope"}"#)))
    }

    func testMicrosecondDates() {
        XCTAssertNotNil(UsageClient.date("2026-10-06T10:20:00.879324+00:00"))
        XCTAssertNotNil(UsageClient.date("2026-11-05T07:59:00+00:00"))
        XCTAssertNotNil(UsageClient.date("2026-11-12T08:15:00Z"))
    }

    func testMoneyAndCreditsRow() {
        XCTAssertEqual(Money.format(minor: 7000, currency: "CAD"), "CA$70")
        XCTAssertEqual(Money.format(minor: 1240, currency: "CAD"), "CA$12.40")
        XCTAssertEqual(Money.format(minor: 0, currency: "USD"), "$0")
        let off = UsageCredits(enabled: false, spentMinor: 0, limitMinor: 7000, balanceMinor: 0, currency: "CAD",
                               autoReload: false, fetched: Date())
        XCTAssertEqual(off.stateText, "Off")
        XCTAssertEqual(off.detailText, "Limit CA$70 · Balance CA$0")
        var on = off
        on.enabled = true; on.spentMinor = 1240; on.autoReload = true
        XCTAssertEqual(on.stateText, "CA$12.40 of CA$70 this month")
        XCTAssertEqual(on.detailText, "Balance CA$0 · Auto-reload on")
        on.limitMinor = nil
        XCTAssertEqual(on.stateText, "CA$12.40 this month")
    }

    func testPlanBadges() {
        func badge(_ tier: String?, _ caps: [String], raven: String? = nil) -> String? {
            Plan.from(tier: tier, capabilities: caps, ravenType: raven, orgName: "Postfl")?.badge
        }
        XCTAssertEqual(badge("default_claude_max_5x", ["chat", "claude_max"]), "Max 5×")
        XCTAssertEqual(badge("default_claude_max_20x", ["chat", "claude_max"]), "Max 20×")
        XCTAssertEqual(badge("default_claude_ai", ["chat", "claude_pro"]), "Pro")
        XCTAssertEqual(badge("default_claude_ai", ["chat"]), "Free")
        XCTAssertEqual(badge("default_raven", ["chat", "raven"], raven: "team"), "Team")
        XCTAssertEqual(badge("default_claude_max_5x", ["chat"], raven: "team"), "Team Premium")
        XCTAssertEqual(badge("default_raven_enterprise", ["chat"], raven: "enterprise"), "Enterprise")
        XCTAssertEqual(Plan.from(tier: "default_raven", capabilities: ["chat"], ravenType: "team", orgName: "Postfl")?.orgName, "Postfl")
        XCTAssertNil(Plan.from(tier: "default_claude_max_5x", capabilities: ["chat", "claude_max"], ravenType: nil, orgName: "Travis")?.orgName)
        XCTAssertNil(badge(nil, ["api"]))
    }
}
