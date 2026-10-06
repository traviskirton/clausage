import SwiftUI
import KeyboardShortcuts
import UserNotifications

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General", accounts = "Accounts", notifications = "Notifications", claudeCode = "Claude Code", updates = "Updates", about = "About"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .accounts: "person.fill"
        case .notifications: "bell.fill"
        case .claudeCode: "terminal.fill"
        case .updates: "arrow.down.circle.fill"
        case .about: "info.circle.fill"
        }
    }
}

/// The Settings window: Cream background, an inset Cream 2 sidebar card (About pinned to the bottom), and content
/// panes of section labels above Cream 2 group boxes. Controls stay native, recolored in Ink.
struct SettingsView: View {
    @ObservedObject var model: UsageModel
    @State private var tab: SettingsTab

    init(model: UsageModel, tab: SettingsTab = .general) {
        self.model = model
        _tab = State(initialValue: tab)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(tab.rawValue).font(.system(size: 17, weight: .bold)).foregroundStyle(Color("Ink"))
                        .frame(height: 22).padding(.top, 12).padding(.bottom, 16)
                        .accessibilityAddTraits(.isHeader)
                    pane
                }
                .padding(.leading, 12).padding(.trailing, 20).padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        .background(Color("Cream"))
        .tint(Color("Ink"))
        .frame(width: 760, height: 600)
    }

    @ViewBuilder private var pane: some View {
        switch tab {
        case .general: GeneralTab(model: model)
        case .accounts: AccountsTab(model: model)
        case .notifications: NotificationsTab()
        case .claudeCode: ClaudeCodeTab()
        case .updates: UpdatesTab()
        case .about: AboutTab()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: 40)        // the traffic lights sit here, inside the card
            ForEach(SettingsTab.allCases.filter { $0 != .about }) { item($0) }
            Spacer()
            item(.about)
        }
        .padding(10)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color("Cream2"))
                .shadow(color: Color(red: 38 / 255, green: 35 / 255, blue: 31 / 255).opacity(0.06), radius: 3, y: 1)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(red: 38 / 255, green: 35 / 255, blue: 31 / 255).opacity(0.08), lineWidth: 0.5))
        }
        .padding(8)
    }

    private func item(_ t: SettingsTab) -> some View {
        let selected = tab == t
        return Button { tab = t } label: {
            HStack(spacing: 8) {
                Image(systemName: t.symbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color("Paper"))
                    .frame(width: 22, height: 22)
                    .background(selected ? Color("Ink") : Color("Ink3"), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(t.rawValue).font(.system(size: 13)).foregroundStyle(Color("Ink"))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 34)
            .background(selected ? Color(red: 0.910, green: 0.875, blue: 0.812) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: Building blocks

/// A section: 13pt semibold Ink label above a Cream 2 box (radius 12) whose rows are split by hairlines.
struct SettingsSection<Content: View>: View {
    let title: String?
    var footer: String? = nil
    @ViewBuilder let content: Content

    init(_ title: String?, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color("Ink"))
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .padding(.horizontal, 10)
                .background(Color("Cream2"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundStyle(Color("Ink2"))
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
        }
        .padding(.bottom, 20)
    }
}

/// Hairline between rows inside a section box.
struct RowDivider: View {
    var body: some View { Rectangle().fill(Color("Ink").opacity(0.1)).frame(height: 0.5) }
}

/// One row: title (and optional detail) on the left, a control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let control: Control

    init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(Color("Ink"))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Color("Ink2")).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 9)
        .frame(minHeight: 40)
    }
}

/// A switch in Ink.
struct InkSwitch: View {
    let label: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(label, isOn: $isOn).toggleStyle(.switch).labelsHidden().tint(Color("Ink")).controlSize(.small)
    }
}

/// Native segmented control, recolored: the selected segment is Ink.
struct InkSegmented<T: Hashable>: NSViewRepresentable {
    @Binding var selection: T
    let options: [(T, String)]

    func makeNSView(context: Context) -> NSSegmentedControl {
        let c = NSSegmentedControl(labels: options.map(\.1), trackingMode: .selectOne,
                                   target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        c.segmentStyle = .rounded
        c.selectedSegmentBezelColor = NSColor(named: "Ink")
        c.controlSize = .small
        c.font = .systemFont(ofSize: 12)
        return c
    }

    func updateNSView(_ c: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        for (i, o) in options.enumerated() where c.label(forSegment: i) != o.1 { c.setLabel(o.1, forSegment: i) }
        c.selectedSegment = options.firstIndex { $0.0 == selection } ?? -1
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: InkSegmented
        init(_ p: InkSegmented) { parent = p }
        @MainActor @objc func changed(_ c: NSSegmentedControl) {
            guard c.selectedSegment >= 0, c.selectedSegment < parent.options.count else { return }
            parent.selection = parent.options[c.selectedSegment].0
        }
    }
}

/// Capsule toggle: Ink with Paper text when on, Sand 2 with Ink text when off.
struct ChipToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(configuration.isOn ? Color("Ink") : Color(red: 0.910, green: 0.875, blue: 0.812), in: Capsule())
                .foregroundStyle(configuration.isOn ? Color("Paper") : Color("Ink"))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}

/// Row label with a secondary description underneath.
struct DescribedLabel: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(Color("Ink"))
            Text(detail).font(.caption).foregroundStyle(Color("Ink2"))
        }
    }
}

// MARK: General

struct GeneralTab: View {
    @ObservedObject var model: UsageModel
    @AppStorage("menuDisplay") private var display = "off"
    @AppStorage("tintIcon") private var tint = true
    @AppStorage("fillBase") private var fillBase = "auto"
    @AppStorage("thresholds") private var thresholds = "75,80,90"
    @AppStorage("customThresholds") private var custom = ""
    @AppStorage("notifySoon") private var soon = true
    @AppStorage("soonMinutes") private var soonMinutes = 10
    @AppStorage("notifyReset") private var notifyReset = true
    @AppStorage("notifyOutage") private var notifyOutage = false
    @AppStorage("refreshMinutes") private var refresh = 5
    @AppStorage("hotkeyEnabled") private var hotkey = true

    /// The menu bar shows the highest limit.
    private var sessionLabel: String {
        MenuBarIcon.highest(model.limits).map { "\(Int($0.percent.rounded()))%" } ?? "24%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection("Startup") {
                SettingsRow("Launch at login") {
                    InkSwitch(label: "Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                }
            }

            SettingsSection("Menu bar") {
                SettingsRow("Show usage next to icon") {
                    InkSegmented(selection: $display, options: [("off", "Off"), ("percent", sessionLabel), ("ring", "Ring"), ("bars", "Bars"), ("fill", "Fill")])
                        .fixedSize()
                }
                RowDivider()
                SettingsRow("Fill logo base", detail: "White rays on a dark menu bar, dark rays on a light one. Auto follows the menu bar.") {
                    InkSegmented(selection: $fillBase, options: [("auto", "Auto"), ("white", "White"), ("dark", "Dark")]).fixedSize()
                }
                RowDivider()
                SettingsRow("Tint percent by pressure", detail: "Orange at 85%, red at 95% · uses highest limit") {
                    InkSwitch(label: "Tint percent by pressure", isOn: $tint)
                }
            }

            SettingsSection("Notify me when") {
                SettingsRow("Any limit reaches") {
                    HStack(spacing: 6) {
                        ForEach(Prefs.allThresholdChips, id: \.self) { t in
                            Toggle("\(t)%", isOn: chip(t)).toggleStyle(ChipToggleStyle())
                        }
                    }
                }
                RowDivider()
                SettingsRow("Session is about to reset") {
                    HStack {
                        Picker("Minutes before reset", selection: $soonMinutes) {
                            ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min before").tag($0) }
                        }.pickerStyle(.menu).labelsHidden().fixedSize().disabled(!soon)
                        InkSwitch(label: "Session is about to reset", isOn: $soon)
                    }
                }
                RowDivider()
                SettingsRow("A limit resets") { InkSwitch(label: "A limit resets", isOn: $notifyReset) }
                RowDivider()
                SettingsRow("Anthropic reports an outage") {
                    InkSwitch(label: "Anthropic reports an outage", isOn: $notifyOutage)
                        .onChange(of: notifyOutage) { _, on in
                            if on { Task { await Notifier.requestAuthorization(); await StatusMonitor.check() } }
                        }
                }
            }

            SettingsSection("Refresh & shortcuts") {
                SettingsRow("Refresh every") {
                    InkSegmented(selection: $refresh, options: [(1, "1m"), (5, "5m"), (15, "15m"), (30, "30m")]).fixedSize()
                }
                RowDivider()
                SettingsRow("Open popover from anywhere") {
                    HStack {
                        KeyboardShortcuts.Recorder(for: .openPopover)
                        InkSwitch(label: "Open popover from anywhere", isOn: $hotkey)
                    }
                }
                RowDivider()
                SettingsRow("Refresh now (popover open)") { Text("⌘R").foregroundStyle(Color("Ink2")) }
            }
        }
    }

    private func chip(_ t: Int) -> Binding<Bool> {
        Binding(
            get: { Prefs.parse(thresholds).contains(t) },
            set: { on in
                var set = Set(Prefs.parse(thresholds))
                if on { set.insert(t) } else { set.remove(t) }
                thresholds = set.sorted().map(String.init).joined(separator: ",")
            })
    }
}

// MARK: Accounts

struct AccountsTab: View {
    @ObservedObject var model: UsageModel
    var body: some View {
        SettingsSection("Claude accounts",
                        footer: "Each account is kept in its own isolated session on this Mac and only used to read plan usage from claude.ai. Alerts cover all accounts; the menu bar and widget show the selected one.") {
            if model.accounts.isEmpty {
                SettingsRow("Not connected", detail: "Sign in to see your plan usage.") {
                    Button("Connect…") { model.connect() }
                }
            } else {
                ForEach(Array(model.accounts.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { RowDivider() }
                    let st = model.states[a.id]
                    SettingsRow(a.name + (a.id == model.active?.id ? "  ·  shown in menu bar" : ""),
                                detail: accountDetail(st)) {
                        HStack {
                            if st?.signedOut == true { Button("Sign in…") { model.reconnect(a) } }
                            else if a.id != model.active?.id { Button("Show") { model.setActive(a.id) } }
                            Button("Disconnect", role: .destructive) { model.disconnect(a) }
                        }
                    }
                }
                RowDivider()
                SettingsRow("Add another account") { Button("Add account…") { model.connect() } }
            }
        }
    }

    private func accountDetail(_ st: AccountState?) -> String {
        if st?.signedOut == true { return "Signed out" }
        var parts: [String] = []
        if let p = st?.plan?.badge { parts.append(p) }
        parts.append(st?.updated.map { "Last updated \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Fetching usage…")
        return parts.joined(separator: " · ")
    }
}

// MARK: Claude Code (Mac only)

/// What's driving your usage, the way Claude Code's `/usage` computes it, from the transcripts on this Mac.
struct ClaudeCodeTab: View {
    @State private var hasAccess = ClaudeCodeLogs.hasAccess || ClaudeCodeLogs.previewAccess
    @State private var week = true
    @State private var result: ContributorsScan.Result? = ClaudeCodeLogs.lastResult
    @State private var loading = false

    private var window: ContributorsScan.Window? { result.map { week ? $0.week : $0.day } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(week ? "Last 7 days" : "Last 24 hours") of Claude Code on this Mac. Shares overlap, so they don’t add up to 100%.")
                    .font(.system(size: 11)).foregroundStyle(Color("Ink2")).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                InkSegmented(selection: $week, options: [(false, "Day"), (true, "Week")]).fixedSize()
            }
            .padding(.bottom, 16)

            if hasAccess {
                if let w = window {
                    driving(w)
                    HStack(alignment: .top, spacing: 12) {
                        shares("Top skills", w.skills, prefix: "/")
                        shares("Top subagents", w.agents)
                    }
                    if let r = result { hits(r) }
                } else {
                    HStack(spacing: 8) {
                        TallyLoader(size: 16)
                        Text("Reading this Mac’s Claude Code sessions…").font(.system(size: 12)).foregroundStyle(Color("Ink2"))
                    }
                    .padding(.bottom, 20)
                }
            }

            SettingsSection(nil) {
                SettingsRow("Scan Claude Code sessions",
                            detail: "Reads ~/.claude on this Mac. Only totals are kept, never prompts or code, and nothing leaves this Mac.") {
                    InkSwitch(label: "Scan Claude Code sessions", isOn: Binding(get: { hasAccess }, set: setScanning))
                }
            }
        }
        .task { if hasAccess { await load(force: false) } }
    }

    private func driving(_ w: ContributorsScan.Window) -> some View {
        SettingsSection("What’s driving your usage") {
            let shown = w.shown
            if shown.isEmpty {
                SettingsRow(w.requests == 0 ? "No Claude Code requests in this period" : "Nothing stands out",
                            detail: w.requests == 0 ? nil : "No pattern reached 10% of your Claude Code usage.") { EmptyView() }
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { i, b in
                if i > 0 { RowDivider() }
                HStack(alignment: .top, spacing: 12) {
                    Text("\(b.1)%").font(.clausagePercent(20)).foregroundStyle(Color("Ink"))
                        .frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.copy(b.0).title).font(.system(size: 13, weight: .medium)).foregroundStyle(Color("Ink"))
                        Text(Self.copy(b.0).tip).font(.system(size: 11)).foregroundStyle(Color("Ink2"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func shares(_ title: String, _ items: [ContributorsScan.Share], prefix: String = "") -> some View {
        SettingsSection(title) {
            if items.isEmpty {
                SettingsRow("None in this period") { EmptyView() }
            }
            ForEach(Array(items.prefix(8).enumerated()), id: \.element.id) { i, s in
                if i > 0 { RowDivider() }
                HStack {
                    Text(prefix + s.name).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color("Ink")).lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(s.percent)%").font(.system(size: 12)).foregroundStyle(Color("Ink2"))
                }
                .frame(minHeight: 38)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func hits(_ r: ContributorsScan.Result) -> some View {
        SettingsSection("Limit hits this week") {
            let order = ["five_hour", "seven_day"] + r.limitHits.keys.filter { $0 != "five_hour" && $0 != "seven_day" }.sorted()
            ForEach(Array(order.enumerated()), id: \.element) { i, k in
                if i > 0 { RowDivider() }
                SettingsRow(Self.limitName(k)) {
                    Text("\(r.limitHits[k] ?? 0)").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Color("Ink"))
                }
            }
        }
    }

    static func limitName(_ key: String) -> String {
        switch key {
        case "five_hour": return "5-hour limit"
        case "seven_day": return "Weekly limit"
        case "seven_day_opus": return "Weekly Opus limit"
        case "seven_day_sonnet": return "Weekly Sonnet limit"
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func copy(_ b: ContributorsScan.Behavior) -> (title: String, tip: String) {
        switch b {
        case .highParallel: return ("While 4+ sessions ran in parallel", "All sessions share one limit. Queue the ones you don’t need at the same time.")
        case .longContext: return ("At more than 150k context", "Long sessions cost more, even when cached. /compact mid-task, /clear between tasks.")
        case .subagentHeavy: return ("From subagent-heavy sessions", "Each subagent makes its own requests. Point simple ones at a cheaper model.")
        case .activeLong: return ("From sessions active 8+ hours", "Usually background or loop sessions. Make sure they’re intentional.")
        case .cacheMiss: return ("At a >100k-token cache miss", "Going idle lets the cache expire, so the next request re-sends the whole context.")
        }
    }

    private func setScanning(_ on: Bool) {
        if on {
            if ClaudeCodeLogs.chooseFolder() { hasAccess = true; Task { await load(force: true) } }
        } else {
            ClaudeCodeLogs.forget()
            hasAccess = false
            result = nil
        }
    }

    private func load(force: Bool) async {
        if !force, let r = result, Date().timeIntervalSince(r.scanned) < 300 { return }
        loading = true
        result = await ClaudeCodeLogs.contributors()
        loading = false
    }
}

// MARK: Notifications

struct NotificationsTab: View {
    @State private var status: UNAuthorizationStatus = .notDetermined

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Blocked in System Settings"
        default: return "Not requested yet"
        }
    }

    var body: some View {
        SettingsSection("Permission",
                        footer: "macOS only lets an app ask for permission once. After that, turn notifications on or off in System Settings. Choose which alerts you get under General → Notify me when.") {
            SettingsRow("Notifications", detail: statusText) {
                HStack {
                    if status == .notDetermined {
                        Button("Allow…") { Task { await Notifier.requestAuthorization(); await load() } }
                    }
                    Button("Open System Settings…") { openSystemSettings() }
                }
            }
            RowDivider()
            SettingsRow("Send a test notification") {
                Button("Send test") { Notifier.sendTest() }.disabled(status == .denied)
            }
        }
        .task { await load() }
        // Refresh when returning from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await load() }
        }
    }

    /// Opens this app's page in Notifications settings (falls back to the Notifications pane).
    private func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        let base = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        for u in ["\(base)?id=\(id)", base] {
            if let url = URL(string: u), NSWorkspace.shared.open(url) { return }
        }
    }

    private func load() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

// MARK: Updates / About

struct UpdatesTab: View {
    @ObservedObject private var updater = Updater.shared
    private var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "?") (\(i?["CFBundleVersion"] as? String ?? "?"))"
    }
    var body: some View {
        SettingsSection("Version") {
            SettingsRow("Clausage \(version)") {
                Button("Check for Updates…") { updater.checkForUpdates() }.disabled(!updater.canCheck)
            }
            RowDivider()
            SettingsRow("Check automatically", detail: "Looks for new versions in the background.") {
                InkSwitch(label: "Check automatically", isOn: Binding(get: { updater.automaticChecks }, set: { updater.automaticChecks = $0 }))
            }
        }
    }
}

struct AboutTab: View {
    var body: some View {
        SettingsSection(nil) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Wordmark(size: 26)
                    Text("Your Claude plan limits in the menu bar.").foregroundStyle(Color("Ink2"))
                    Text("An independent app, not made by or affiliated with Anthropic.").font(.caption).foregroundStyle(Color("Ink2"))
                }
                Spacer()
            }
            .padding(.vertical, 12)
            RowDivider()
            SettingsRow("Quit Clausage") { Button("Quit") { NSApplication.shared.terminate(nil) } }
        }
    }
}
