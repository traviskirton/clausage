import Foundation

enum UsageError: LocalizedError {
    case unauthorized, http(Int), badResponse, unexpected(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Signed out. Connect your Claude account again."
        case .http(let c): return "Server returned HTTP \(c)."
        case .badResponse: return "Unexpected response."
        case .unexpected(let s): return "Couldn't read usage data: \(s)"
        }
    }
}

/// Something that can GET a path on claude.ai with a signed-in session: the Mac's hidden web view, or the iPhone's cookie-based URLSession.
protocol UsageTransport {
    @MainActor func get(_ path: String) async throws -> (status: Int, body: String)
}

/// Read-only claude.ai calls. Every request here is a GET; nothing changes account state.
enum UsageClient {
    struct Org {
        let id: String
        let name: String
        let plan: Plan?
    }

    @MainActor
    static func resolveOrg(_ session: UsageTransport) async throws -> Org {
        let (status, body) = try await session.get("/api/organizations")
        if status == 401 || status == 403 { throw UsageError.unauthorized }
        guard status == 200,
              let orgs = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [[String: Any]],
              let org = orgs.first(where: { ($0["capabilities"] as? [String])?.contains("chat") == true }) ?? orgs.first,
              let id = org["uuid"] as? String
        else { throw UsageError.unexpected(String(body.prefix(120))) }
        var name = (org["name"] as? String) ?? "Claude"
        for suffix in ["'s Organization", "’s Organization"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        let plan = Plan.from(tier: org["rate_limit_tier"] as? String,
                             capabilities: org["capabilities"] as? [String] ?? [],
                             ravenType: org["raven_type"] as? String,
                             orgName: name)
        return Org(id: id, name: name, plan: plan)
    }

    /// The signed-in account's email, if claude.ai returns it. Best effort: nil on any failure.
    @MainActor
    static func accountEmail(_ session: UsageTransport) async -> String? {
        guard let (status, body) = try? await session.get("/api/account"), status == 200,
              let root = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        else { return nil }
        return (root["email_address"] as? String) ?? (root["email"] as? String)
    }

    /// Usage credits: `overage_spend_limit` (on/off, monthly limit, spent) and `prepaid/credits` (balance, auto-reload).
    /// Both are read-only GETs. nil when neither answers.
    @MainActor
    static func credits(_ session: UsageTransport, orgID: String, now: Date = Date()) async -> UsageCredits? {
        func object(_ path: String) async -> [String: Any]? {
            guard let (status, body) = try? await session.get(path), status == 200 else { return nil }
            return try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        }
        let limit = await object("/api/organizations/\(orgID)/overage_spend_limit")
        let prepaid = await object("/api/organizations/\(orgID)/prepaid/credits")
        guard limit != nil || prepaid != nil else { return nil }

        let cap = (limit?["cap"] as? [String: Any])?["money"] as? [String: Any]
        let balance = (prepaid?["balance"] as? [String: Any])?["money"] as? [String: Any]
        // The org's currency comes from the spend limit (the /usage `spend` block can say USD for a CAD org).
        let currency = (limit?["currency"] as? String) ?? (cap?["currency"] as? String)
            ?? (balance?["currency"] as? String) ?? (prepaid?["currency"] as? String) ?? "USD"
        let exponent = (cap?["exponent"] as? Int) ?? (balance?["exponent"] as? Int) ?? 2
        let limitMinor = (cap?["amount_minor"] as? Int) ?? (limit?["monthly_credit_limit"] as? Int)
        let balanceMinor = (balance?["amount_minor"] as? Int) ?? (prepaid?["amount"] as? Int)
        let autoReload = ((prepaid?["auto_reload_settings"] as? [String: Any])?["enabled"] as? Bool)
            ?? (prepaid.map { _ in false })
        return UsageCredits(enabled: limit?["is_enabled"] as? Bool ?? false,
                            spentMinor: limit?["used_credits"] as? Int,
                            limitMinor: limitMinor, balanceMinor: balanceMinor,
                            currency: currency, exponent: exponent, autoReload: autoReload, fetched: now)
    }

    @MainActor
    static func fetch(session: UsageTransport, orgID: String) async throws -> UsageReport {
        let (status, body) = try await session.get("/api/organizations/\(orgID)/usage")
        if status == 401 || status == 403 { throw UsageError.unauthorized }
        guard status == 200 else { throw UsageError.http(status) }
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)),
              let report = report(json)
        else { throw UsageError.unexpected(String(body.prefix(200))) }
        return report
    }

    /// The whole response. nil only if it isn't a usage response at all; an org with no plan limits (Enterprise) parses
    /// to an empty `limits` list.
    static func report(_ json: Any) -> UsageReport? {
        guard let root = json as? [String: Any],
              root["limits"] != nil || root.keys.contains("five_hour") || root.keys.contains("seven_day")
        else { return nil }
        let limits = parse(json)
        var weekly: WeeklyWindow?
        if let w = root["seven_day"] as? [String: Any], let pct = number(w["utilization"]), let reset = date(w["resets_at"]) {
            weekly = WeeklyWindow(start: reset.addingTimeInterval(-7 * 86400), resetsAt: reset, percent: pct)
        } else if let all = limits.first(where: { $0.kind == "weekly_all" }), let reset = all.resetsAt {
            weekly = WeeklyWindow(start: reset.addingTimeInterval(-7 * 86400), resetsAt: reset, percent: all.percent)
        }
        let breakdown = productBreakdown(root["seven_day_breakdown"])
        if let start = breakdown?.windowStart, let w = weekly, abs(start.timeIntervalSince(w.start)) < 3600 {
            weekly = WeeklyWindow(start: start, resetsAt: w.resetsAt, percent: w.percent)
        }
        let spend = (root["spend"] as? [String: Any])?["enabled"] as? Bool
        var unparsed: [String] = []
        if let raw = root["limits"] as? [[String: Any]] {
            for (i, l) in raw.enumerated() where (l["kind"] as? String) == nil || number(l["percent"]) == nil {
                unparsed.append((l["kind"] as? String) ?? "limits[\(i)]")
            }
        }
        return UsageReport(limits: limits, breakdown: breakdown, weekly: weekly, spendEnabled: spend, unparsed: unparsed)
    }

    static func productBreakdown(_ v: Any?) -> ProductBreakdown? {
        guard let b = v as? [String: Any], let rows = b["rows"] as? [[String: Any]] else { return nil }
        let parsed = rows.compactMap { r -> ProductBreakdown.Row? in
            guard let key = r["key"] as? String, let pct = number(r["percent"]) else { return nil }
            return .init(key: key, name: ProductBreakdown.displayName(key, fallback: r["display_name"] as? String), percent: pct)
        }
        guard !parsed.isEmpty else { return nil }
        return ProductBreakdown(asOf: date(b["as_of"]), windowStart: date(b["window_started_at"]),
                                rows: parsed.sorted { $0.percent > $1.percent })
    }

    /// Accepts either a `limits` array or the `five_hour` / `seven_day*` keys.
    static func parse(_ json: Any) -> [UsageLimit] {
        guard let root = json as? [String: Any] else { return [] }
        if let limits = root["limits"] as? [[String: Any]] {
            return limits.enumerated().compactMap { i, l in
                guard let kind = l["kind"] as? String, let pct = number(l["percent"]) else { return nil }
                let model = ((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                let title: String, short: String
                switch kind {
                case "session": (title, short) = ("Current session", "Session")
                case "weekly_all": (title, short) = ("Weekly · All models", "Weekly · All")
                case "weekly_scoped": (title, short) = ("Weekly · \(model ?? "Scoped")", "Weekly · \(model ?? "Scoped")")
                default:
                    title = kind.replacingOccurrences(of: "_", with: " ").capitalized
                    short = title
                }
                return UsageLimit(id: "\(kind)-\(i)", kind: kind, title: title, shortTitle: short, percent: pct,
                                  resetsAt: date(l["resets_at"]), severity: l["severity"] as? String ?? "normal",
                                  isActive: l["is_active"] as? Bool)
            }
        }
        let keys: [(String, String, String, String)] = [
            ("five_hour", "session", "Current session", "Session"),
            ("seven_day", "weekly_all", "Weekly · All models", "Weekly · All"),
            ("seven_day_opus", "weekly_scoped", "Weekly · Opus", "Weekly · Opus"),
            ("seven_day_sonnet", "weekly_scoped", "Weekly · Sonnet", "Weekly · Sonnet")]
        return keys.compactMap { key, kind, title, short in
            guard let d = root[key] as? [String: Any], let pct = number(d["utilization"]) else { return nil }
            return UsageLimit(id: key, kind: kind, title: title, shortTitle: short, percent: pct,
                              resetsAt: date(d["resets_at"]), severity: "normal")
        }
    }

    static func number(_ v: Any?) -> Double? {
        (v as? Double) ?? (v as? Int).map(Double.init) ?? (v as? NSNumber)?.doubleValue
    }

    static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        // Microsecond fractions ("…00.874305+00:00"): drop the fraction and retry.
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) {
            return f.date(from: s.replacingCharacters(in: r, with: ""))
        }
        return nil
    }
}
