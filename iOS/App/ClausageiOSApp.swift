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
    @Published var signedIn = SessionStore.load() != nil || SampleMode.isOn
    @Published var account = SessionStore.load()?.orgName
    @Published var message: String?
    @Published var refreshing = false
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

    /// Returns true when fresh numbers arrived. With `apply: false` the new numbers are saved but not shown until `sync()`
    /// (pull to refresh swaps them in with the slash).
    @discardableResult
    func refresh(apply: Bool = true) async -> Bool {
        guard !refreshing else { return false }
        if demo {
            refreshing = true
            try? await Task.sleep(for: .milliseconds(900))
            refreshing = false
            return true
        }
        if SampleMode.isOn {
            refreshing = true
            try? await Task.sleep(for: .milliseconds(600))
            SampleMode.refresh()
            refreshing = false
            message = nil
            if apply { sync() }
            WidgetCenter.shared.reloadAllTimelines()
            return true
        }
        guard SessionStore.load() != nil else { sync(); return false }
        refreshing = true
        defer { refreshing = false }
        let ok: Bool
        switch await UsageSource.refresh() {
        case .ok: message = nil; ok = true
        case .signedOut: message = "Signed out. Sign in again to keep your usage up to date."; ok = false
        case .failed(let text): message = text; ok = false
        }
        if apply { sync() }
        await PhoneNotifier.process()
        WidgetCenter.shared.reloadAllTimelines()
        return ok
    }

    /// Right after sign-in, while the sheet still shows "Connected": the first fetch, so the sheet slides away onto the
    /// Usage screen with numbers in. Waits at most `limit`; a slower fetch carries on and fills them in when it lands.
    func finishSignIn(limit: Duration = .seconds(6)) async {
        let fetch = Task { await refresh() }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await fetch.value }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
        sync()   // signed in either way, even if the fetch is still out
    }

    /// Sample mode, from the welcome screen or Settings: a `SampleData` scenario instead of an account.
    func startSample(_ id: String = SampleData.maxMixed.id) {
        SampleMode.start(id)
        message = nil
        sync()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func stopSample() {
        SampleMode.stop()
        sync()
        WidgetCenter.shared.reloadAllTimelines()
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

    func sync() {
        guard !demo else { return }
        let record = SessionStore.load()
        signedIn = record != nil || SampleMode.isOn
        account = record?.orgName
        snapshot = SharedStore.load()
        history = HistoryStore.load()
    }
}
