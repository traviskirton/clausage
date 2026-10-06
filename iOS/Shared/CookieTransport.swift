import Foundation

/// Talks to claude.ai with the saved `sessionKey`, no web view. The spike showed this passes Cloudflare from a Mac;
/// a Cloudflare challenge is reported as its own error so it never looks like a sign-out.
@MainActor
struct CookieTransport: UsageTransport {
    let record: ClaudeSessionRecord

    func get(_ path: String) async throws -> (status: Int, body: String) {
        guard let url = URL(string: "https://claude.ai" + path) else { throw UsageError.badResponse }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(record.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("sessionKey=\(record.sessionKey)", forHTTPHeaderField: "Cookie")

        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        cfg.httpCookieStorage = nil
        let (data, resp) = try await URLSession(configuration: cfg).data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw UsageError.badResponse }
        let body = String(decoding: data, as: UTF8.self)

        if (http.statusCode == 403 || http.statusCode == 503),
           http.value(forHTTPHeaderField: "cf-mitigated") != nil || body.contains("Just a moment") {
            throw UsageError.unexpected("Cloudflare is challenging this device (HTTP \(http.statusCode)).")
        }
        keepSessionFresh(http, url: url)
        return (http.statusCode, body)
    }

    /// The server may roll the session cookie forward; keep the newest value.
    private func keepSessionFresh(_ http: HTTPURLResponse, url: URL) {
        guard let headers = http.allHeaderFields as? [String: String] else { return }
        let fresh = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        guard let key = fresh.first(where: { $0.name == "sessionKey" })?.value, key != record.sessionKey else { return }
        var updated = record
        updated.sessionKey = key
        SessionStore.save(updated)
    }
}
