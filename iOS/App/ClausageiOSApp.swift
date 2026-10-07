import SwiftUI
import WidgetKit
import BackgroundTasks
import UIKit

@main
struct ClausageiOSApp: App {
    nonisolated static let refreshID = "com.postfl.clausage-ios.refresh"
    @Environment(\.scenePhase) private var phase

    init() {
        // Pull to refresh draws its own tally; hide the system spinner it would otherwise show.
        UIRefreshControl.appearance().tintColor = .clear
    }

    var body: some Scene {
        WindowGroup { UsageScreen() }
            .onChange(of: phase) { _, p in if p == .background { Self.scheduleRefresh() } }
            // iOS decides when this actually runs; it is a best effort between the times you open the app.
            .backgroundTask(.appRefresh(Self.refreshID)) {
                _ = await UsageSource.refresh()
                await PhoneNotifier.process()
                WidgetCenter.shared.reloadAllTimelines()
                Self.scheduleRefresh()
            }
    }

    /// Asks iOS for the next background refresh, unless "Refresh in background" is off.
    nonisolated static func scheduleRefresh() {
        guard PhonePrefs.backgroundRefresh else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

@MainActor
final class PhoneModel: ObservableObject {
    @Published var snapshot: SharedStore.Snapshot? = SharedStore.load()
    @Published var history = HistoryStore.load()
    @Published var signedIn = SessionStore.load() != nil
    @Published var account = SessionStore.load()?.orgName
    @Published var message: String?
    @Published var refreshing = false
    /// Result of the last refresh, for diagnostics in Send Feedback.
    @Published var lastResult: String?
    /// Debug-only fixture mode for screenshots (`--demo`): no network.
    let demo: Bool

    init() {
        SessionStore.migrateToThisDeviceOnly()
        #if DEBUG
        demo = CommandLine.arguments.contains("--demo")
        if demo {
            let s = CommandLine.arguments.contains("--demo-free") ? UsageFixtures.free : UsageFixtures.screen
            snapshot = s
            history = UsageFixtures.history(for: s, values: [10, 24, 38, 50, 58, 70])
            signedIn = true
            account = "Travis"
        }
        #else
        demo = false
        #endif
    }

    /// "Now" for drawing: the fixture time in demo mode, so pace ticks and the chart match the design.
    var now: Date { demo ? UsageFixtures.screenNow : Date() }

    /// The email to show, or the org name when claude.ai didn't return one.
    var who: String? { snapshot?.email ?? account }

    /// Returns true when fresh numbers arrived.
    @discardableResult
    func refresh() async -> Bool {
        guard !refreshing else { return false }
        if demo {
            refreshing = true
            try? await Task.sleep(for: .milliseconds(900))
            refreshing = false
            return true
        }
        guard SessionStore.load() != nil else { sync(); return false }
        refreshing = true
        defer { refreshing = false }
        let ok: Bool
        switch await UsageSource.refresh() {
        case .ok: message = nil; ok = true; lastResult = "ok"
        case .signedOut: message = "Signed out. Sign in again to keep your usage up to date."; ok = false; lastResult = "signed out"
        case .failed(let text): message = text; ok = false; lastResult = "failed: \(text)"
        }
        sync()
        await PhoneNotifier.process()
        WidgetCenter.shared.reloadAllTimelines()
        return ok
    }

    func signOut() async {
        SessionStore.clear()
        await ClaudeWebView.clearCookies()
        HistoryStore.clear()
        UsageSource.markSignedOut()
        PhoneNotifier.cancelAll()
        message = nil
        sync()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Privacy → Clear Cached Usage: widgets show "No data" until the next refresh.
    func clearCachedUsage() {
        var s = SharedStore.load() ?? .init(limits: [], updated: Date(), connected: signedIn)
        s.limits = []; s.breakdown = nil; s.weekly = nil; s.credits = nil; s.plan = nil; s.planUpdated = nil
        s.cleared = true
        SharedStore.save(s)
        HistoryStore.clear()
        sync()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Privacy → Sign Out and Delete Everything.
    func deleteEverything() async {
        await signOut()
        SharedStore.defaults.removeObject(forKey: "snapshot")
        for key in SharedStore.defaults.dictionaryRepresentation().keys { SharedStore.defaults.removeObject(forKey: key) }
        sync()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func sync() {
        guard !demo else { return }
        let record = SessionStore.load()
        signedIn = record != nil
        account = record?.orgName
        snapshot = SharedStore.load()
        history = HistoryStore.load()
    }
}
