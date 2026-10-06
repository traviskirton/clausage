import Foundation

/// "What's contributing to your limits usage?", computed the way Claude Code 2.1.288's `/usage` does it, from the
/// session transcripts on this Mac. Only aggregates are kept: no prompt text,
/// paths or project names leave this file.
enum ContributorsScan {
    // Thresholds, copied from Claude Code 2.1.288.
    static let cacheMissTokens = 100_000          // `input_tokens` above this: a >100k-token cache miss
    static let longContextTokens = 150_000        // cache read + cache write + input above this: >150k context
    static let subagentRequests = 3               // sessions with ≥3 sidechain requests…
    static let subagentShare = 0.5                // …or >50% of their cost from sidechains are subagent-heavy
    static let bucket: TimeInterval = 300         // 5-minute buckets…
    static let parallelSessions = 4               // …with ≥4 distinct sessions: "4+ sessions in parallel"
    static let activeHours = 8                    // sessions with requests in ≥8 distinct clock hours
    static let showAtPercent = 10                 // a behavior line shows at ≥10%
    static let week: TimeInterval = 7 * 86_400
    static let day: TimeInterval = 86_400

    enum Behavior: String, CaseIterable {
        case highParallel = "high_parallel", longContext = "long_context", subagentHeavy = "subagent_heavy",
             activeLong = "cron", cacheMiss = "cache_miss"
    }

    struct Share: Equatable, Identifiable {
        let name: String
        let percent: Int
        var id: String { name }
    }

    struct Window: Equatable {
        var requests = 0
        var sessions = 0
        /// Each behavior's share of weighted cost (0–100), all of them, biggest first.
        var behaviors: [(Behavior, Int)] = []
        var skills: [Share] = []
        var agents: [Share] = []
        var plugins: [Share] = []
        var mcpServers: [Share] = []

        /// The lines `/usage` would show: ≥10%.
        var shown: [(Behavior, Int)] { behaviors.filter { $0.1 >= ContributorsScan.showAtPercent } }

        static func == (a: Window, b: Window) -> Bool {
            a.requests == b.requests && a.sessions == b.sessions && a.skills == b.skills && a.agents == b.agents
                && a.plugins == b.plugins && a.mcpServers == b.mcpServers
                && a.behaviors.map(\.0) == b.behaviors.map(\.0) && a.behaviors.map(\.1) == b.behaviors.map(\.1)
        }
    }

    struct Result: Equatable {
        var day = Window()
        var week = Window()
        /// Rejected requests (`quotaLimits`) in the last 7 days, by `rateLimitType` ("five_hour", "seven_day", …).
        var limitHits: [String: Int] = [:]
        var scanned: Date = Date()
    }

    struct Record {
        let ts: Date
        let session: String
        let cached, cacheCreate, uncached, output: Double
        let isSubagent: Bool
        let tier: Double
        let agent, skill, plugin, mcp: String?

        /// Claude Code's relative cost: cache reads 1, input 10, cache writes 12.5, output 50, times the model tier.
        var cost: Double { (cached + uncached * 10 + cacheCreate * 12.5 + output * 50) * tier }
    }

    /// Fable 10, Opus 5, Haiku 1, anything else (Sonnet) 3.
    static func tier(_ model: String?) -> Double {
        guard let m = model?.lowercased() else { return 3 }
        if m.contains("fable") { return 10 }
        if m.contains("opus") { return 5 }
        if m.contains("haiku") { return 1 }
        return 3
    }

    // MARK: Scan

    /// Scans `projects/*/*.jsonl` and `projects/*/<session>/subagents/**/*.jsonl` under `claudeDir` (files touched in the last 7 days).
    static func scan(claudeDir: URL, now: Date = Date()) -> Result {
        let since = now.addingTimeInterval(-week)
        var records: [Record] = []
        var seen = Set<String>()
        var hits: [String: Int] = [:]
        for file in files(in: claudeDir.appendingPathComponent("projects"), since: since) {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            forEachLine(data) { line in
                if line.range(of: quotaMarker) != nil, let hit = limitHit(line, since: since) { hits[hit, default: 0] += 1 }
                guard line.range(of: assistantMarker) != nil, line.range(of: usageMarker) != nil,
                      let (r, key) = record(line, since: since) else { return }
                if !key.isEmpty { guard seen.insert(key).inserted else { return } }
                records.append(r)
            }
        }
        var result = Result(scanned: now)
        result.week = fold(records)
        result.day = fold(records.filter { $0.ts >= now.addingTimeInterval(-day) })
        result.limitHits = hits
        return result
    }

    private static let assistantMarker = Data(#""type":"assistant""#.utf8)
    private static let usageMarker = Data(#""usage":{"#.utf8)
    private static let quotaMarker = Data(#""quotaLimits":{"#.utf8)

    static func files(in projects: URL, since: Date) -> [URL] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else { return [] }
        var out: [URL] = []
        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for e in entries {
                if e.pathExtension == "jsonl" { out.append(e); continue }
                let sub = e.appendingPathComponent("subagents")
                guard let walker = fm.enumerator(at: sub, includingPropertiesForKeys: nil) else { continue }
                for case let f as URL in walker where f.pathExtension == "jsonl" { out.append(f) }
            }
        }
        return out.filter {
            let mod = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (mod ?? .distantFuture) >= since
        }
    }

    private static func forEachLine(_ data: Data, _ body: (Data) -> Void) {
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            if end > start { body(data[start..<end]) }
            start = end + 1
        }
    }

    private static func date(_ s: Any?) -> Date? {
        guard let s = s as? String else { return nil }
        return iso.date(from: s) ?? isoPlain.date(from: s)
    }
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    /// One assistant line → a record and its dedupe key (`requestId` → `message.id` → `uuid`).
    static func record(_ line: Data, since: Date) -> (Record, String)? {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              (o["type"] as? String) == "assistant",
              let msg = o["message"] as? [String: Any], let u = msg["usage"] as? [String: Any],
              let ts = date(o["timestamp"]), ts >= since,
              let session = o["sessionId"] as? String
        else { return nil }
        func n(_ k: String) -> Double { (u[k] as? NSNumber)?.doubleValue ?? 0 }
        let r = Record(ts: ts, session: session,
                       cached: n("cache_read_input_tokens"), cacheCreate: n("cache_creation_input_tokens"),
                       uncached: n("input_tokens"), output: n("output_tokens"),
                       isSubagent: (o["isSidechain"] as? Bool) == true, tier: tier(msg["model"] as? String),
                       agent: o["attributionAgent"] as? String, skill: o["attributionSkill"] as? String,
                       plugin: o["attributionPlugin"] as? String, mcp: o["attributionMcpServer"] as? String)
        guard r.cached + r.cacheCreate + r.uncached + r.output > 0 else { return nil }
        let key = (o["requestId"] as? String) ?? (msg["id"] as? String) ?? (o["uuid"] as? String) ?? ""
        return (r, key)
    }

    /// A rejected request's `quotaLimits.rateLimitType`, if the line is in the window.
    static func limitHit(_ line: Data, since: Date) -> String? {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let q = o["quotaLimits"] as? [String: Any], (q["status"] as? String) == "rejected",
              let ts = date(o["timestamp"]), ts >= since
        else { return nil }
        return (q["rateLimitType"] as? String) ?? "other"
    }

    // MARK: Fold

    static func fold(_ records: [Record]) -> Window {
        var total = 0.0, cacheMiss = 0.0, longCtx = 0.0
        struct Session { var cost = 0.0, sub = 0.0, subCount = 0, hours = Set<Int>() }
        var sessions: [String: Session] = [:]
        var buckets: [Int: (sids: Set<String>, cost: Double)] = [:]
        var bySkill: [String: Double] = [:], byAgent: [String: Double] = [:], byPlugin: [String: Double] = [:], byMcp: [String: Double] = [:]

        for r in records {
            let c = r.cost
            total += c
            if let a = r.agent { byAgent[r.skill ?? a, default: 0] += c } else if let s = r.skill { bySkill[s, default: 0] += c }
            if let p = r.plugin { byPlugin[p, default: 0] += c }
            if let m = r.mcp { byMcp[m, default: 0] += c }
            if r.uncached > Double(cacheMissTokens) { cacheMiss += c }
            if r.cached + r.cacheCreate + r.uncached > Double(longContextTokens) { longCtx += c }
            var s = sessions[r.session] ?? Session()
            s.cost += c
            if r.isSubagent { s.sub += c; s.subCount += 1 }
            s.hours.insert(Int(floor(r.ts.timeIntervalSince1970 / 3600)))
            sessions[r.session] = s
            let b = Int(floor(r.ts.timeIntervalSince1970 / bucket))
            var bk = buckets[b] ?? (Set(), 0)
            bk.sids.insert(r.session); bk.cost += c
            buckets[b] = bk
        }

        let parallel = buckets.values.filter { $0.sids.count >= parallelSessions }.reduce(0) { $0 + $1.cost }
        let subHeavy = sessions.values.filter { $0.subCount >= subagentRequests || ($0.cost > 0 && $0.sub / $0.cost > subagentShare) }
            .reduce(0) { $0 + $1.cost }
        let longActive = sessions.values.filter { $0.hours.count >= activeHours }.reduce(0) { $0 + $1.cost }
        func pct(_ x: Double) -> Int { total > 0 ? Int((x / total * 100).rounded()) : 0 }
        func top(_ m: [String: Double]) -> [Share] {
            m.sorted { $0.value > $1.value }.map { Share(name: $0.key, percent: pct($0.value)) }.filter { $0.percent > 0 }
        }
        let behaviors: [(Behavior, Double)] = [(.cacheMiss, cacheMiss), (.longContext, longCtx), (.subagentHeavy, subHeavy),
                                               (.highParallel, parallel), (.activeLong, longActive)]
        return Window(requests: records.count, sessions: sessions.count,
                      // Stable by cost, like Claude Code's sort (ties keep the order above).
                      behaviors: behaviors.enumerated().sorted { ($0.element.1, -$0.offset) > ($1.element.1, -$1.offset) }
                        .map { ($0.element.0, pct($0.element.1)) },
                      skills: top(bySkill), agents: top(byAgent), plugins: top(byPlugin), mcpServers: top(byMcp))
    }
}
