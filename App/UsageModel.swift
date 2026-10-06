import SwiftUI
import WebKit
import ServiceManagement
import WidgetKit

struct AccountState {
    var limits: [UsageLimit] = []
    var error: String?
    var updated: Date?
    var signedOut = false
    var breakdown: ProductBreakdown?
    var weekly: WeeklyWindow?
    var plan: Plan?
    /// When the plan was last read from `/api/organizations` (at sign-in, then daily).
    var planFetched: Date?
    var credits: UsageCredits?
}

@MainActor
final class UsageModel: ObservableObject {
    static let shared = UsageModel()

    @Published var accounts: [Account] = []
    @Published var activeID: UUID?
    @Published var states: [UUID: AccountState] = [:]
    @Published var generalError: String?
    @Published var loading = false
    /// Result of the last refresh (drives the footer's "Updated just now" / "Couldn't update" states).
    /// `manual` is false for scheduled refreshes, which skip the success hold.
    @Published var outcome: (id: Int, ok: Bool, manual: Bool)?
    private var outcomeCounter = 0
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var sessions: [UUID: ClaudeSession] = [:]
    private var timer: Timer?
    private var timerMinutes = 0

    // Views read the active account through these.
    var connected: Bool { !accounts.isEmpty }
    var active: Account? { accounts.first { $0.id == activeID } ?? accounts.first }
    var limits: [UsageLimit] { active.flatMap { states[$0.id]?.limits } ?? [] }
    var activeState: AccountState? { active.flatMap { states[$0.id] } }
    var updated: Date? { active.flatMap { states[$0.id]?.updated } }
    var error: String? { active.flatMap { states[$0.id]?.error } ?? generalError }
    var activeSignedOut: Bool { active.flatMap { states[$0.id]?.signedOut } ?? false }

    private init() {
        Prefs.register()
        #if DEBUG
        if CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--render-gallery") {
            // Fixture mode for screenshots: one fake account, no network, no onboarding.
            let s = UsageFixtures.mixedLive()
            let a = Account(id: UUID(), name: "Demo", orgID: "demo")
            accounts = [a]; activeID = a.id
            var st = AccountState(limits: s.limits, error: nil, updated: s.updated, signedOut: false)
            st.plan = s.plan; st.breakdown = s.breakdown; st.weekly = s.weekly
            states[a.id] = st
            if let i = CommandLine.arguments.firstIndex(of: "--render-gallery"), i + 1 < CommandLine.arguments.count {
                let dir = CommandLine.arguments[i + 1]
                DispatchQueue.main.async { MacGallery.render(into: dir, model: self); exit(0) }
            }
            if let i = CommandLine.arguments.firstIndex(of: "--demo-open"), i + 1 < CommandLine.arguments.count,
               CommandLine.arguments[i + 1] == "settings" {
                DispatchQueue.main.async { SettingsWindow.shared.show() }
            }
            return
        }
        #endif
        // `--reset` behaves like a first launch: forgets accounts, consent and the login item.
        if CommandLine.arguments.contains("--reset") {
            try? SMAppService.mainApp.unregister()
            if let data = UserDefaults.standard.data(forKey: "accounts"),
               let old = try? JSONDecoder().decode([Account].self, from: data) {
                for a in old {
                    Task { try? await WKWebsiteDataStore.remove(forIdentifier: a.id) }
                    HistoryStore.clear(key: Self.historyKey(a.id))
                }
                HistoryStore.clear()
            }
            for k in ["accounts", "activeAccount", "onboarded", "firedThresholds", "thresholdsSeeded",
                      "seenIncidents", "incidentsSeeded"] {
                UserDefaults.standard.removeObject(forKey: k)
            }
            launchAtLogin = false
            Notifier.cancelAll()
            SharedStore.save(.init(limits: [], updated: Date(), connected: false))
        } else if let data = UserDefaults.standard.data(forKey: "accounts"),
                  let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
        }
        activeID = UserDefaults.standard.string(forKey: "activeAccount").flatMap(UUID.init) ?? accounts.first?.id

        Notifier.setup()
        StatusMenu.shared.install()
        Hotkey.install { [weak self] in Task { @MainActor in self?.openPopover() } }
        applyPrefs()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyPrefs() }
        }

        if connected {
            refresh()
            Task { await Notifier.requestAuthorization() }
        } else if !UserDefaults.standard.bool(forKey: "onboarded") {
            DispatchQueue.main.async { self.runOnboarding() }
        }
    }

    // MARK: Prefs

    /// Re-applies settings that need action (refresh interval, hotkey).
    private func applyPrefs() {
        let d = UserDefaults.standard
        let minutes = max(1, d.integer(forKey: "refreshMinutes"))
        if minutes != timerMinutes {
            timerMinutes = minutes
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                    await StatusMonitor.check()
                }
            }
        }
        Hotkey.setEnabled(d.bool(forKey: "hotkeyEnabled"))
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) { UserDefaults.standard.set(data, forKey: "accounts") }
        UserDefaults.standard.set(activeID?.uuidString, forKey: "activeAccount")
    }

    func setActive(_ id: UUID) {
        activeID = id
        saveAccounts()
        publishSnapshot()
    }

    // MARK: Onboarding / accounts

    /// First-run prompt: the user explicitly chooses whether to link their account and launch at login.
    private func runOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Show your Claude usage in the menubar?"
        alert.informativeText = """
            Click Connect to sign in to your Claude account in a window. Your session stays on this Mac and \
            is only used to read your plan usage from claude.ai. Nothing is accessed until you sign in.
            """
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Not Now")
        let box = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
        box.state = .on
        alert.accessoryView = box
        let response = alert.runModal()
        UserDefaults.standard.set(true, forKey: "onboarded")
        if response == .alertFirstButtonReturn {
            connect()
            setLaunchAtLogin(box.state == .on)
        }
    }

    private func session(for id: UUID) -> ClaudeSession {
        if let s = sessions[id] { return s }
        let s = ClaudeSession(accountID: id)
        sessions[id] = s
        return s
    }

    /// Signs in a new account (a fresh, isolated web session).
    func connect() {
        generalError = nil
        let id = UUID()
        let s = session(for: id)
        s.signIn { [weak self] ok in
            guard let self else { return }
            guard ok else { self.sessions[id] = nil; return }
            Task {
                do {
                    let org = try await UsageClient.resolveOrg(s)
                    if let dup = self.accounts.first(where: { $0.orgID == org.id }) {
                        // Same account signed in twice: keep the original, drop the new session.
                        await s.signOut(); self.sessions[id] = nil
                        self.setActive(dup.id); self.refresh(thenOpenPopover: true)
                        return
                    }
                    self.accounts.append(Account(id: id, name: org.name, orgID: org.id))
                    self.activeID = id
                    self.saveAccounts()
                    Task { await Notifier.requestAuthorization() }
                    self.refresh(thenOpenPopover: true)
                } catch {
                    self.generalError = error.localizedDescription
                    await s.signOut(); self.sessions[id] = nil
                }
            }
        }
    }

    /// Re-authenticates an account whose session expired.
    func reconnect(_ account: Account) {
        session(for: account.id).signIn { [weak self] ok in
            guard let self, ok else { return }
            self.states[account.id] = AccountState()
            self.refresh(thenOpenPopover: true)
        }
    }

    func disconnect(_ account: Account) {
        let s = session(for: account.id)
        sessions[account.id] = nil
        states[account.id] = nil
        HistoryStore.clear(key: Self.historyKey(account.id))
        accounts.removeAll { $0.id == account.id }
        if activeID == account.id { activeID = accounts.first?.id }
        saveAccounts()
        Task { await s.signOut() }
        if accounts.isEmpty { Notifier.cancelAll() } else { notify() }
        publishSnapshot()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            generalError = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Refresh

    /// Results are applied together once "Updating…" has been on screen for at least 600 ms, so it never flickers
    /// and the bars animate to their new widths at the same moment the footer shows the result.
    func refresh(thenOpenPopover: Bool = false, userInitiated: Bool = false) {
        guard connected, !loading else { return }
        loading = true
        Task {
            let started = Date()
            var allOK = true
            var results: [(UUID, AccountState)] = []
            for var account in accounts {
                let s = session(for: account.id)
                let previous = states[account.id]
                do {
                    var plan = previous?.plan, planFetched = previous?.planFetched
                    // The org list carries the plan tier: read it at sign-in, then at most daily.
                    if account.orgID == nil || planFetched.map({ Date().timeIntervalSince($0) > 86_400 }) ?? true {
                        let org = try await UsageClient.resolveOrg(s)
                        plan = org.plan; planFetched = Date()
                        if account.orgID == nil {
                            account.orgID = org.id
                            if let i = accounts.firstIndex(where: { $0.id == account.id }) { accounts[i].orgID = org.id }
                            saveAccounts()
                        }
                    }
                    let report = try await UsageClient.fetch(session: s, orgID: account.orgID!)
                    if let w = report.weekly {
                        // Each account keeps its own running total; the active one is copied for the widget in publishSnapshot.
                        var history = HistoryStore.load(key: Self.historyKey(account.id))
                        history.record(w, at: Date(), owner: account.orgID)
                        HistoryStore.save(history, key: Self.historyKey(account.id))
                    }
                    var st = AccountState(limits: report.limits, error: nil, updated: Date(), signedOut: false)
                    st.breakdown = report.breakdown
                    st.weekly = report.weekly
                    st.plan = plan; st.planFetched = planFetched
                    st.credits = previous?.credits
                    results.append((account.id, st))
                } catch {
                    allOK = false
                    var st = states[account.id] ?? AccountState()
                    st.error = error.localizedDescription
                    if case UsageError.unauthorized = error { st.signedOut = true }
                    results.append((account.id, st))
                }
            }
            let remaining = 0.6 - Date().timeIntervalSince(started)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            for (id, st) in results { states[id] = st }
            loading = false
            outcomeCounter += 1
            outcome = (outcomeCounter, allOK, userInitiated)
            publishSnapshot()
            notify()
            if thenOpenPopover { openPopover() }
        }
    }

    private func notify() {
        let all = accounts.compactMap { a -> AccountLimits? in
            guard let st = states[a.id], !st.limits.isEmpty else { return nil }
            return AccountLimits(id: a.id, name: a.name, limits: st.limits)
        }
        if !all.isEmpty { Notifier.process(all) }
    }

    /// Hands the active account's numbers to the widget.
    static func historyKey(_ id: UUID) -> String { "\(HistoryStore.key).\(id.uuidString)" }

    /// The active account's running total.
    var history: WeeklyHistory { active.map { HistoryStore.load(key: Self.historyKey($0.id)) } ?? WeeklyHistory() }

    private func publishSnapshot() {
        HistoryStore.save(history)
        let st = activeState
        SharedStore.save(.init(limits: limits, updated: updated ?? Date(), connected: connected,
                               plan: st?.plan, planUpdated: st?.planFetched, breakdown: st?.breakdown,
                               weekly: st?.weekly, credits: st?.credits))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Closes the menubar popover (e.g. when opening Settings from it).
    func closePopover() {
        let popover = NSApp.windows.first { String(describing: type(of: $0)).contains("MenuBarExtraWindow") } ?? NSApp.keyWindow
        popover?.close()
    }

    /// Clicks the menubar item (used after connecting and by the global hotkey).
    func openPopover() {
        for w in NSApp.windows where String(describing: type(of: w)) == "NSStatusBarWindow" {
            func click(_ v: NSView) -> Bool {
                if let b = v as? NSStatusBarButton { b.performClick(nil); return true }
                return v.subviews.contains(where: click)
            }
            if let c = w.contentView, click(c) { return }
        }
    }
}
