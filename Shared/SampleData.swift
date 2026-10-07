import Foundation

/// Sample claude.ai responses: the exact JSON shapes `/api/organizations` and `/api/organizations/<id>/usage` return,
/// with made-up values. Sample mode (App Review, screenshots, trying the app without an account) and the unit tests
/// both run them through the same parser as live data.
///
/// Times are written relative to "now" as `{{T+2d6h30m}}` or `{{T-3h}}` and resolved when loaded, so countdowns,
/// pace ticks and forecasts stay live.
enum SampleData {
    struct Scenario: Identifiable, Equatable {
        let id: String
        /// Shown in the sample-mode picker.
        let name: String
        /// One org, as `/api/organizations` returns it.
        let org: String
        /// The `/usage` response template.
        let usage: String
        var credits: UsageCredits? = nil
        var email = "sample@clausage.ai"
        /// Covered by the tests but not offered in the picker (it looks like another scenario).
        var testOnly = false
    }

    static let all: [Scenario] = [maxMixed, proCalm, maxCritical, team, enterprise, free, legacyKeys]
    static var pickable: [Scenario] { all.filter { !$0.testOnly } }
    static func scenario(_ id: String?) -> Scenario? { all.first { $0.id == id } }

    // MARK: Scenarios

    /// Max 5×: one limit near its cap, a product split and usage credits. The default.
    static let maxMixed = Scenario(
        id: "max-mixed", name: "Max · getting full",
        org: #"{"uuid":"sample-max","name":"Sample's Organization","rate_limit_tier":"default_claude_max_5x","capabilities":["chat","claude_max"],"raven_type":null}"#,
        usage: """
        {"five_hour":{"utilization":34.0,"resets_at":"{{T+3h10m}}"},
         "seven_day":{"utilization":64.0,"resets_at":"{{T+2d14h}}"},
         "seven_day_opus":null,
         "limits":[
           {"kind":"session","group":"session","percent":34,"severity":"normal","resets_at":"{{T+3h10m}}","scope":null,"is_active":false},
           {"kind":"weekly_all","group":"weekly","percent":64,"severity":"normal","resets_at":"{{T+2d14h}}","scope":null,"is_active":false},
           {"kind":"weekly_scoped","group":"weekly","percent":88,"severity":"warning","resets_at":"{{T+2d14h}}","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":true}],
         "spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},"enabled":false,"can_toggle":true},
         "seven_day_breakdown":{"as_of":"{{T-15m}}","window_started_at":"{{T-4d10h}}",
           "rows":[{"key":"claude_code","display_name":"Claude Code","percent":57},{"key":"cowork","display_name":"Cowork","percent":30},
                   {"key":"chat","display_name":"Chat","percent":10},{"key":"other","display_name":"Other","percent":3}]}}
        """,
        credits: UsageCredits(enabled: false, spentMinor: 0, limitMinor: 5000, balanceMinor: 0, currency: "USD",
                              autoReload: false, fetched: Date()))

    /// Pro, early in the week: everything calm.
    static let proCalm = Scenario(
        id: "pro-calm", name: "Pro · plenty left",
        org: #"{"uuid":"sample-pro","name":"Sample's Organization","rate_limit_tier":"default_claude_ai","capabilities":["chat","claude_pro"],"raven_type":null}"#,
        usage: """
        {"five_hour":{"utilization":12.0,"resets_at":"{{T+4h05m}}"},
         "seven_day":{"utilization":23.0,"resets_at":"{{T+5d2h}}"},
         "limits":[
           {"kind":"session","group":"session","percent":12,"severity":"normal","resets_at":"{{T+4h05m}}","scope":null,"is_active":false},
           {"kind":"weekly_all","group":"weekly","percent":23,"severity":"normal","resets_at":"{{T+5d2h}}","scope":null,"is_active":false}],
         "spend":null,
         "seven_day_breakdown":{"as_of":"{{T-20m}}","window_started_at":"{{T-1d22h}}",
           "rows":[{"key":"chat","display_name":"Chat","percent":70},{"key":"claude_code","display_name":"Claude Code","percent":25},
                   {"key":"other","display_name":"Other","percent":5}]}}
        """)

    /// Max 20×, late in a heavy session: red bars, "Limiting now" and runout forecasts.
    static let maxCritical = Scenario(
        id: "max-critical", name: "Max · almost out",
        org: #"{"uuid":"sample-max20","name":"Sample's Organization","rate_limit_tier":"default_claude_max_20x","capabilities":["chat","claude_max"],"raven_type":null}"#,
        usage: """
        {"five_hour":{"utilization":96.0,"resets_at":"{{T+48m}}"},
         "seven_day":{"utilization":91.0,"resets_at":"{{T+1d3h}}"},
         "limits":[
           {"kind":"session","group":"session","percent":96,"severity":"critical","resets_at":"{{T+48m}}","scope":null,"is_active":true},
           {"kind":"weekly_all","group":"weekly","percent":91,"severity":"warning","resets_at":"{{T+1d3h}}","scope":null,"is_active":false},
           {"kind":"weekly_scoped","group":"weekly","percent":97,"severity":"critical","resets_at":"{{T+1d3h}}","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}],
         "spend":{"used":{"amount_minor":1240,"currency":"USD","exponent":2},"enabled":true,"can_toggle":true},
         "seven_day_breakdown":{"as_of":"{{T-5m}}","window_started_at":"{{T-5d21h}}",
           "rows":[{"key":"claude_code","display_name":"Claude Code","percent":81},{"key":"chat","display_name":"Chat","percent":12},
                   {"key":"cowork","display_name":"Cowork","percent":7}]}}
        """,
        credits: UsageCredits(enabled: true, spentMinor: 1240, limitMinor: 5000, balanceMinor: 2500, currency: "USD",
                              autoReload: true, fetched: Date()))

    /// Team: the org name shows under the badge.
    static let team = Scenario(
        id: "team", name: "Team",
        org: #"{"uuid":"sample-team","name":"Sample Studio","rate_limit_tier":"default_raven","capabilities":["chat","raven"],"raven_type":"team"}"#,
        usage: """
        {"five_hour":{"utilization":41.0,"resets_at":"{{T+2h15m}}"},
         "seven_day":{"utilization":55.0,"resets_at":"{{T+3d8h}}"},
         "limits":[
           {"kind":"session","group":"session","percent":41,"severity":"normal","resets_at":"{{T+2h15m}}","scope":null,"is_active":false},
           {"kind":"weekly_all","group":"weekly","percent":55,"severity":"normal","resets_at":"{{T+3d8h}}","scope":null,"is_active":false}],
         "spend":null,"seven_day_breakdown":null}
        """,
        email: "sample@studio.example")

    /// Enterprise with no plan limits: nothing to count, but not an error.
    static let enterprise = Scenario(
        id: "enterprise", name: "Enterprise · no limits",
        org: #"{"uuid":"sample-ent","name":"Sample Corp","rate_limit_tier":"default_raven_enterprise","capabilities":["chat"],"raven_type":"enterprise"}"#,
        usage: #"{"five_hour":null,"seven_day":null,"limits":[],"spend":null,"seven_day_breakdown":null}"#,
        email: "sample@corp.example")

    /// Free: claude.ai has no usage page, and `/usage` returns all nulls (shape captured from a real Free account).
    static let free = Scenario(
        id: "free", name: "Free",
        org: #"{"uuid":"sample-free","name":"Sample's Organization","rate_limit_tier":"default_claude_ai","capabilities":["chat"],"raven_type":null}"#,
        usage: """
        {"five_hour":null,"seven_day":null,"seven_day_oauth_apps":null,"seven_day_opus":null,"seven_day_sonnet":null,
         "seven_day_cowork":null,"extra_usage":null,"limits":[],"spend":null,"member_dashboard_available":false,
         "seven_day_breakdown":null}
        """)

    /// The older shape with only `five_hour` / `seven_day*` keys and no `limits` array.
    static let legacyKeys = Scenario(
        id: "legacy-keys", name: "Pro · older response",
        org: #"{"uuid":"sample-legacy","name":"Sample's Organization","rate_limit_tier":"default_claude_ai","capabilities":["chat","claude_pro"],"raven_type":null}"#,
        usage: """
        {"five_hour":{"utilization":58.0,"resets_at":"{{T+1h30m}}"},
         "seven_day":{"utilization":47.0,"resets_at":"{{T+4d}}"},
         "seven_day_opus":{"utilization":20.0,"resets_at":"{{T+4d}}"}}
        """,
        testOnly: true)

    // MARK: Loading

    /// The usage template with every `{{T±…}}` replaced by an ISO 8601 time (microseconds, like claude.ai) relative to `now`.
    static func resolve(_ template: String, now: Date) -> String {
        let pattern = #"\{\{T([+-])(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?\}\}"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return template }
        let ns = template as NSString
        var out = template
        for m in re.matches(in: template, range: NSRange(location: 0, length: ns.length)).reversed() {
            func part(_ i: Int) -> Double {
                let r = m.range(at: i)
                return r.location == NSNotFound ? 0 : Double(ns.substring(with: r)) ?? 0
            }
            let sign: Double = ns.substring(with: m.range(at: 1)) == "-" ? -1 : 1
            let seconds = sign * (part(2) * 86_400 + part(3) * 3_600 + part(4) * 60)
            let text = timestamp(now.addingTimeInterval(seconds))
            out = (out as NSString).replacingCharacters(in: m.range, with: text)
        }
        return out
    }

    private static func timestamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'+00:00'"
        return f.string(from: d)
    }

    /// The org (and so the plan) the scenario's `/api/organizations` response resolves to.
    static func org(_ s: Scenario) -> UsageClient.Org? {
        guard let o = try? JSONSerialization.jsonObject(with: Data(s.org.utf8)) as? [String: Any] else { return nil }
        return UsageClient.org(from: [o])
    }

    /// The scenario's `/usage` response, parsed exactly like a live one.
    static func report(_ s: Scenario, now: Date = Date()) -> UsageReport? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(resolve(s.usage, now: now).utf8)) else { return nil }
        return UsageClient.report(json)
    }

    /// What a refresh would save to the App Group for this scenario. `sample` marks it, so the UI can say so.
    static func snapshot(_ s: Scenario, now: Date = Date()) -> SharedStore.Snapshot {
        let org = org(s)
        var snap = SharedStore.Snapshot(limits: [], updated: now, connected: true)
        snap.plan = org?.plan
        snap.planUpdated = now
        snap.email = s.email
        snap.sample = s.id
        if org?.plan?.isFree != true, let r = report(s, now: now) {
            snap.limits = r.limits
            snap.breakdown = r.breakdown
            snap.weekly = r.weekly
            snap.unparsedLimits = r.unparsed
            snap.credits = s.credits.map { var c = $0; c.fetched = now; return c }
        }
        return snap
    }
}
