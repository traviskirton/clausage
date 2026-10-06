import XCTest

/// The Claude Code breakdown port (ContributorsScan) against hand-computed transcripts.
final class ContributorsScanTests: XCTestCase {
    private var dir: URL!
    private let now = Date(timeIntervalSince1970: 1_791_300_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("cc-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("projects/p1/s-main/subagents"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.string(from: d)
    }

    /// One assistant line. Cost = (read + input*10 + write*12.5 + out*50) * tier.
    private func line(session: String, ago: TimeInterval, model: String = "claude-sonnet-5-5", read: Int = 0, input: Int = 0,
                      write: Int = 0, out: Int = 0, sidechain: Bool = false, request: String = UUID().uuidString,
                      extra: String = "") -> String {
        #"{"type":"assistant","sessionId":"\#(session)","isSidechain":\#(sidechain),"timestamp":"\#(iso(now.addingTimeInterval(-ago)))","requestId":"\#(request)"\#(extra),"message":{"id":"msg_\#(request)","model":"\#(model)","usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(write),"cache_read_input_tokens":\#(read),"output_tokens":\#(out)}}}"#
    }

    private func write(_ lines: [String], _ path: String) throws {
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    func testWeightsTiersAndDedupe() throws {
        try write([
            line(session: "a", ago: 600, model: "claude-opus-5-5", out: 1, request: "r1"),          // 50 * 5 = 250
            line(session: "a", ago: 600, model: "claude-opus-5-5", out: 1, request: "r1"),          // duplicate: ignored
            line(session: "a", ago: 500, model: "claude-haiku-4-5", input: 25, request: "r2"),       // 250 * 1 = 250
            line(session: "a", ago: 400, model: "<synthetic>", request: "r3"),                       // zero tokens: dropped
        ], "projects/p1/a.jsonl")
        let r = ContributorsScan.scan(claudeDir: dir, now: now)
        XCTAssertEqual(r.week.requests, 2)
        XCTAssertEqual(r.week.sessions, 1)
        XCTAssertEqual(ContributorsScan.tier("claude-fable-5-1"), 10)
        XCTAssertEqual(ContributorsScan.tier("claude-sonnet-5-5"), 3)
    }

    func testBehaviorsAndAttribution() throws {
        let big = #","attributionSkill":"loop""#
        try write([
            // Long context (>150k), skill /loop: cost 160_000 * 3 = 480_000
            line(session: "s1", ago: 3600, read: 160_000, extra: big),
            // Cache miss (>100k input): 120_000*10*3 = 3_600_000
            line(session: "s2", ago: 3600, input: 120_000),
            // Small request: 1000*3 = 3000
            line(session: "s3", ago: 3600, read: 1000),
        ], "projects/p1/main.jsonl")
        // Subagent lines carry the parent's sessionId; 3 sidechain requests make s4 subagent-heavy.
        let agent = #","attributionAgent":"Explore""#
        try write((0..<3).map { _ in line(session: "s4", ago: 7200, read: 100_000, sidechain: true, extra: agent) },
                  "projects/p1/s-main/subagents/agent-1.jsonl")
        let r = ContributorsScan.scan(claudeDir: dir, now: now)
        let total = 480_000.0 + 3_600_000 + 3000 + 900_000
        let pct: (Double) -> Int = { Int(($0 / total * 100).rounded()) }
        let b = Dictionary(uniqueKeysWithValues: r.week.behaviors.map { ($0.0, $0.1) })
        XCTAssertEqual(b[.cacheMiss], pct(3_600_000))
        XCTAssertEqual(b[.longContext], pct(480_000))          // the 120k-input request stays under 150k
        XCTAssertEqual(b[.subagentHeavy], pct(900_000))
        XCTAssertEqual(r.week.skills, [.init(name: "loop", percent: pct(480_000))])
        XCTAssertEqual(r.week.agents, [.init(name: "Explore", percent: pct(900_000))])
        XCTAssertEqual(r.week.requests, 6)
    }

    func testParallelAndLongSessions() throws {
        // Four sessions inside one 5-minute bucket: all their cost counts as parallel.
        let t0 = (floor(now.timeIntervalSince1970 / 300) - 2) * 300 + 10
        let ago = now.timeIntervalSince1970 - t0
        var lines = (1...4).map { line(session: "p\($0)", ago: ago, read: 1000) }
        // One session active in 8 distinct hours.
        lines += (0..<8).map { line(session: "long", ago: Double($0) * 3600 + 10_000, read: 1000) }
        try write(lines, "projects/p1/x.jsonl")
        let r = ContributorsScan.scan(claudeDir: dir, now: now)
        let b = Dictionary(uniqueKeysWithValues: r.week.behaviors.map { ($0.0, $0.1) })
        XCTAssertEqual(b[.highParallel], Int((4.0 / 12 * 100).rounded()))
        XCTAssertEqual(b[.activeLong], Int((8.0 / 12 * 100).rounded()))
        XCTAssertEqual(r.day.sessions, 5)
    }

    func testDayWindowAndLimitHits() throws {
        try write([
            line(session: "old", ago: 2 * 86_400, read: 1000),
            line(session: "new", ago: 3600, read: 1000),
            #"{"type":"assistant","timestamp":"\#(iso(now.addingTimeInterval(-100)))","quotaLimits":{"status":"rejected","rateLimitType":"five_hour"}}"#,
            #"{"type":"assistant","timestamp":"\#(iso(now.addingTimeInterval(-200)))","quotaLimits":{"status":"rejected","rateLimitType":"seven_day"}}"#,
            #"{"type":"assistant","timestamp":"\#(iso(now.addingTimeInterval(-9 * 86_400)))","quotaLimits":{"status":"rejected","rateLimitType":"five_hour"}}"#,
        ], "projects/p1/y.jsonl")
        let r = ContributorsScan.scan(claudeDir: dir, now: now)
        XCTAssertEqual(r.week.requests, 2)
        XCTAssertEqual(r.day.requests, 1)
        XCTAssertEqual(r.limitHits, ["five_hour": 1, "seven_day": 1])
    }

    /// Set CLAUSAGE_REAL_SCAN=1 to print this Mac's numbers (compare with `claude /usage`).
    func testRealTranscripts() throws {
        guard ProcessInfo.processInfo.environment["CLAUSAGE_REAL_SCAN"] == "1" else { throw XCTSkip("set CLAUSAGE_REAL_SCAN=1") }
        let home = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
        let start = Date()
        let r = ContributorsScan.scan(claudeDir: home)
        for (name, w) in [("day", r.day), ("week", r.week)] {
            print("SCAN \(name): \(w.requests) requests, \(w.sessions) sessions, behaviors \(w.behaviors.map { "\($0.0.rawValue)=\($0.1)" }), skills \(w.skills.prefix(8).map { "\($0.name) \($0.percent)" }), agents \(w.agents.prefix(8).map { "\($0.name) \($0.percent)" })")
        }
        print("SCAN hits \(r.limitHits) in \(Date().timeIntervalSince(start))s")
    }
}
