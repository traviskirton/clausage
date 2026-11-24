import XCTest

/// The clausage MCP (`mcp/server.py`) reads this app's App Group data directly: the snapshot (`src_app`) and the weekly
/// history (`get_history`). These tests encode both with the app's real encoders and compare them with the golden files in
/// `mcp/tests/fixtures/`, which the MCP's own tests read. Rename a field or key here and this fails; regenerate the goldens
/// with `TEST_RUNNER_CLAUSAGE_UPDATE_FIXTURES=1 xcodebuild … test` and the MCP tests then show what broke on the Python side.
final class MCPContractTests: XCTestCase {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("mcp/tests/fixtures", isDirectory: true)

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)  // fixed, so the goldens are stable

    func testSnapshotMatchesGolden() throws {
        let snap = SharedStore.Snapshot(limits: [
            UsageLimit(id: "s", kind: "session", title: "Current session", shortTitle: "Session",
                       percent: 10, resetsAt: t0.addingTimeInterval(7200), severity: "normal", isActive: true),
            UsageLimit(id: "w", kind: "weekly_all", title: "Weekly · All models", shortTitle: "Weekly · All",
                       percent: 93, resetsAt: t0.addingTimeInterval(86_400), severity: "warning"),
            UsageLimit(id: "f", kind: "weekly_scoped", title: "Weekly · Fable", shortTitle: "Weekly · Fable",
                       percent: 76, resetsAt: t0.addingTimeInterval(86_400), severity: "normal")],
            updated: t0, connected: true)
        try check(XCTUnwrap(SharedStore.encode(snap)), golden: "app-snapshot.json")
    }

    func testWeeklyHistoryMatchesGolden() throws {
        let start = t0.addingTimeInterval(-7 * 86_400)
        let readings = [10.0, 30, 55, 95].enumerated().map { i, p in
            WeeklyHistory.Reading(t: start.addingTimeInterval(60 + Double(i) * 86_400), pct: p)
        }
        let history = WeeklyHistory(weeks: [.init(start: start, resetsAt: t0, readings: readings, samples: 4)], owner: "org")
        try check(XCTUnwrap(HistoryStore.encode(history)), golden: "app-weekly-history.json")
    }

    /// Keys and locations the MCP hard-codes.
    func testKeysMatchGolden() throws {
        let keys: [String: String] = [
            "macGroupID": SharedStore.groupID,
            "snapshotKey": SharedStore.snapshotKey,
            "historyKey": HistoryStore.key,
            "retentionKey": HistoryRetention.key,
            "archiveDir": HistoryArchive.folder,
            "archiveFile": "\(HistoryStore.key).json"]
        let data = try JSONSerialization.data(withJSONObject: keys, options: [.sortedKeys])
        try check(data, golden: "app-keys.json")
    }

    private func check(_ data: Data, golden name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = Self.fixtures.appendingPathComponent(name)
        if ProcessInfo.processInfo.environment["CLAUSAGE_UPDATE_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: Self.fixtures, withIntermediateDirectories: true)
            let pretty = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data),
                                                    options: [.prettyPrinted, .sortedKeys])
            try pretty.write(to: url)
            return
        }
        let golden = try Data(contentsOf: url)
        let a = try JSONSerialization.jsonObject(with: data) as? NSDictionary
        let b = try JSONSerialization.jsonObject(with: golden) as? NSDictionary
        XCTAssertEqual(a, b, "\(name) changed: the clausage MCP reads this. Update mcp/server.py, then regenerate with "
                       + "TEST_RUNNER_CLAUSAGE_UPDATE_FIXTURES=1 and run the MCP tests.", file: file, line: line)
    }
}
