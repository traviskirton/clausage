import Foundation

/// Polls Anthropic's public status page and notifies once per new incident.
@MainActor
enum StatusMonitor {
    private static let url = URL(string: "https://status.claude.com/api/v2/summary.json")!

    static func check() async {
        guard UserDefaults.standard.bool(forKey: "notifyOutage") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let incidents = root["incidents"] as? [[String: Any]] else { return }

        let d = UserDefaults.standard
        var seen = d.stringArray(forKey: "seenIncidents") ?? []
        let firstRun = !d.bool(forKey: "incidentsSeeded")
        for i in incidents {
            guard let id = i["id"] as? String, !seen.contains(id) else { continue }
            seen.append(id)
            if firstRun { continue }   // don't announce incidents that were already open when enabled
            let name = (i["name"] as? String) ?? "Claude incident"
            let update = ((i["incident_updates"] as? [[String: Any]])?.first?["body"] as? String) ?? "Anthropic is investigating."
            Notifier.postOutage(id: id, title: name, body: String(update.prefix(160)))
        }
        d.set(Array(seen.suffix(50)), forKey: "seenIncidents")
        d.set(true, forKey: "incidentsSeeded")
    }
}
