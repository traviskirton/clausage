import Foundation

struct UsageLimit: Identifiable, Codable, Equatable {
    let id: String
    /// "session", "weekly_all" or "weekly_scoped"
    let kind: String
    let title: String
    let shortTitle: String
    let percent: Double
    let resetsAt: Date?
    let severity: String
    /// `limits[].is_active`: the limit that's binding right now ("Limiting now"). nil when the response doesn't say.
    var isActive: Bool? = nil

    var windowLength: TimeInterval { kind == "session" ? 5 * 3600 : 7 * 86400 }
}

/// The plan badge, mapped from the org's `rate_limit_tier` and `capabilities`.
struct Plan: Codable, Equatable {
    /// "Free", "Pro", "Max 5×", "Max 20×", "Team", "Team Premium", "Enterprise".
    let badge: String
    /// Shown under the badge on Team and Enterprise, so you know which org you're in.
    let orgName: String?

    static func from(tier: String?, capabilities: [String], ravenType: String?, orgName: String) -> Plan? {
        let tier = tier?.lowercased() ?? ""
        let caps = Set(capabilities.map { $0.lowercased() })
        let raven = ravenType?.lowercased() ?? ""
        if raven.contains("enterprise") || caps.contains("claude_enterprise") || tier.contains("enterprise") {
            return Plan(badge: "Enterprise", orgName: orgName)
        }
        if !raven.isEmpty || caps.contains("raven") || caps.contains("claude_team") || tier.hasPrefix("default_raven") {
            // A Max tier on a team org is Team Premium (Claude Code detects it the same way).
            return Plan(badge: tier.contains("max") ? "Team Premium" : "Team", orgName: orgName)
        }
        if tier.contains("max_20x") { return Plan(badge: "Max 20×", orgName: nil) }
        if tier.contains("max_5x") { return Plan(badge: "Max 5×", orgName: nil) }
        if caps.contains("claude_max") { return Plan(badge: "Max", orgName: nil) }
        if caps.contains("claude_pro") { return Plan(badge: "Pro", orgName: nil) }
        if tier == "default_claude_ai" || caps == ["chat"] { return Plan(badge: "Free", orgName: nil) }
        return nil
    }
}

/// `seven_day_breakdown`: the weekly window's share by product, computed by claude.ai across all devices.
struct ProductBreakdown: Codable, Equatable {
    struct Row: Codable, Equatable, Identifiable {
        let key: String
        let name: String
        let percent: Double
        var id: String { key }
    }
    let asOf: Date?
    let windowStart: Date?
    /// Biggest share first.
    let rows: [Row]

    static func displayName(_ key: String, fallback: String?) -> String {
        switch key {
        case "claude_code": return "Claude Code"
        case "cowork": return "Cowork"
        case "chat": return "Chat"
        case "other": return "Other"
        default: return fallback ?? key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// The weekly (All models) window: fixed, `start` + 7 days = `resetsAt`.
struct WeeklyWindow: Codable, Equatable {
    let start: Date
    let resetsAt: Date
    let percent: Double
}

/// Usage credits: one read-only row. Amounts are minor units in `currency`.
struct UsageCredits: Codable, Equatable {
    var enabled: Bool
    var spentMinor: Int?
    var limitMinor: Int?
    var balanceMinor: Int?
    var currency: String
    var exponent: Int = 2
    var autoReload: Bool?
    var fetched: Date
}

extension UsageCredits {
    /// "CA$70", "CA$12.40": the currency's symbol, cents only when there are any.
    func money(_ minor: Int) -> String { Money.format(minor: minor, currency: currency, exponent: exponent) }

    /// Off: "Off". On: "CA$12.40 of CA$70 this month" (or "CA$12.40 this month" with no cap).
    var stateText: String {
        guard enabled else { return "Off" }
        let spent = money(spentMinor ?? 0)
        if let l = limitMinor { return "\(spent) of \(money(l)) this month" }
        return "\(spent) this month"
    }

    /// Off: "Limit CA$70 · Balance CA$0". On: "Balance CA$0 · Auto-reload on".
    var detailText: String {
        var parts: [String] = []
        if !enabled, let l = limitMinor { parts.append("Limit \(money(l))") }
        if let b = balanceMinor { parts.append("Balance \(money(b))") }
        if enabled, autoReload == true { parts.append("Auto-reload on") }
        return parts.joined(separator: " · ")
    }
}

enum Money {
    static func format(minor: Int, currency: String, exponent: Int = 2) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        // en_US spells other dollars out ("CA$", "A$"), so the currency is never ambiguous.
        f.locale = Locale(identifier: "en_US")
        let value = Double(minor) / pow(10, Double(exponent))
        let whole = minor % Int(pow(10, Double(exponent))) == 0
        f.minimumFractionDigits = whole ? 0 : exponent
        f.maximumFractionDigits = whole ? 0 : exponent
        return f.string(from: NSNumber(value: value)) ?? "\(currency) \(value)"
    }
}

/// Everything one `/usage` call returns that the app shows.
struct UsageReport: Equatable {
    var limits: [UsageLimit]
    var breakdown: ProductBreakdown?
    var weekly: WeeklyWindow?
    /// `spend.enabled` and `spend.used`, used when the hourly credits fetch hasn't run yet.
    var spendEnabled: Bool?
    /// Limit entries the response had but we couldn't read (for diagnostics).
    var unparsed: [String] = []
}

struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var orgID: String?
}

/// App → widget hand-off, stored in the shared App Group.
enum SharedStore {
    #if os(iOS)
    static let groupID = "group.com.postfl.clausage"
    #else
    static let groupID = "G3GED29J33.com.postfl.clausage"
    #endif

    struct Snapshot: Codable {
        var limits: [UsageLimit]
        var updated: Date
        var connected: Bool
        /// Share of the weekly "All models" usage per day, oldest first, today last (7 values). Superseded by `WeeklyHistory`.
        var days: [Double]? = nil
        var plan: Plan? = nil
        var planUpdated: Date? = nil
        var breakdown: ProductBreakdown? = nil
        var weekly: WeeklyWindow? = nil
        var credits: UsageCredits? = nil
        /// The signed-in account's email, when claude.ai returns it.
        var email: String? = nil
        /// Limit entries the last response had but the app couldn't read (diagnostics only).
        var unparsedLimits: [String]? = nil
        /// Privacy → Clear Cached Usage: widgets show "No data" until the next refresh.
        var cleared: Bool? = nil
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    static func save(_ snapshot: Snapshot) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(snapshot) { defaults.set(data, forKey: "snapshot") }
    }

    static func load() -> Snapshot? {
        guard let data = defaults.data(forKey: "snapshot") else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Snapshot.self, from: data)
    }
}
