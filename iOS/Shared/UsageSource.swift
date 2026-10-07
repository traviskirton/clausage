import Foundation

/// Where the iOS side gets usage numbers. Only the app and `RefreshUsageIntent` fetch; widgets only read the App Group snapshot.
enum UsageSource {
    enum Outcome {
        case ok
        case signedOut
        case failed(String)
    }

    /// The snapshot in the App Group.
    static func snapshot() -> SharedStore.Snapshot? { SharedStore.load() }

    /// Fetch fresh numbers with the saved session and write them to the App Group.
    /// A network or server error keeps the last snapshot (it just gets older); a real sign-out clears the session.
    @MainActor
    static func refresh() async -> Outcome {
        guard let record = SessionStore.load() else {
            markSignedOut()
            return .signedOut
        }
        let transport = CookieTransport(record: record)
        do {
            var snap = SharedStore.load() ?? .init(limits: [], updated: Date(), connected: true)
            // Free has no usage page, so the plan decides first. It's read after sign-in and then daily, but on every
            // refresh while Free, so an upgrade shows up as soon as it happens.
            if snap.plan == nil || snap.plan?.isFree == true || snap.planUpdated.map({ Date().timeIntervalSince($0) > 86_400 }) ?? true,
               let org = try? await UsageClient.resolveOrg(transport) {
                snap.plan = org.plan
                snap.planUpdated = Date()
                if snap.email == nil { snap.email = await UsageClient.accountEmail(transport) }
            }
            if snap.plan?.isFree == true {
                // Nothing to count. Weekly history already on the device stays as it is.
                snap.limits = []; snap.breakdown = nil; snap.weekly = nil; snap.credits = nil; snap.unparsedLimits = nil
                snap.updated = Date()
                snap.connected = true
                snap.cleared = nil
                SharedStore.save(snap)
                return .ok
            }
            let report = try await UsageClient.fetch(session: transport, orgID: record.orgID)
            snap.limits = report.limits
            snap.updated = Date()
            snap.connected = true
            snap.breakdown = report.breakdown
            snap.weekly = report.weekly
            snap.unparsedLimits = report.unparsed
            snap.cleared = nil
            if let w = report.weekly {
                var history = HistoryStore.load()
                history.record(w, at: Date(), owner: record.orgID)
                HistoryStore.save(history)
            }
            if snap.credits != nil, let on = report.spendEnabled { snap.credits?.enabled = on }
            // Usage credits: two extra read-only requests, at most hourly.
            if snap.credits.map({ Date().timeIntervalSince($0.fetched) > 3600 }) ?? true,
               let credits = await UsageClient.credits(transport, orgID: record.orgID) {
                snap.credits = credits
            }
            SharedStore.save(snap)
            return .ok
        } catch UsageError.unauthorized {
            SessionStore.clear()
            markSignedOut()
            return .signedOut
        } catch {
            return .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    static func markSignedOut() {
        SharedStore.save(.init(limits: [], updated: Date(), connected: false))
    }
}
