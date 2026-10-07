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

/// Settings colors. Every selected or on state is Ember in both appearances; nothing in Settings uses the system
/// accent. Unselected controls sit on a faint fill of the text color. Dark mode has its own warmer surfaces.
enum SettingsColor {
    static let window = dynamic(0xF7EEDD, dark: 0x24211E)
    static let card = dynamic(0xF2E7D3, dark: 0x2D2925)
    static let hairline = dynamic(0x26231F, 0.10, dark: 0xF4EDE2, 0.09)
    static let text = dynamic(0x26231F, dark: 0xF4EDE2)
    static let secondary = dynamic(0x766E64, dark: 0xADA497)
    static let ember = rgb(0xC23B14)
    static let onEmber = Color.white
    /// Unselected segment, chip, picker, shortcut field and button.
    static let control = dynamic(0x26231F, 0.07, dark: 0xF4EDE2, 0.08)
    static let selectedRow = dynamic(0xC23B14, 0.12, dark: 0xE26034, 0.20)
    static let tile = dynamic(0x8A8278, dark: 0x6E665C)
    static let tileGlyph = dynamic(0xFFFCF6, dark: 0xF4EDE2)
    static let switchOff = dynamic(0x26231F, 0.18, dark: 0xF4EDE2, 0.16)
    static let knobOff = dynamic(0xFFFFFF, dark: 0xCFC6B8)
    static let link = dynamic(0xC23B14, dark: 0xFF8A5C)

    static var textNS: NSColor { ns(0x26231F, 1, dark: 0xF4EDE2, 1) }

    private static func rgb(_ hex: Int, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    private static func ns(_ light: Int, _ la: CGFloat, dark: Int, _ da: CGFloat) -> NSColor {
        func c(_ hex: Int, _ a: CGFloat) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: a)
        }
        return NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? c(dark, da) : c(light, la) }
    }

    private static func dynamic(_ light: Int, _ la: CGFloat = 1, dark: Int, _ da: CGFloat = 1) -> Color {
        Color(nsColor: ns(light, la, dark: dark, da))
    }
}

/// Sidebar card geometry. The card is concentric with the window's corners; the traffic lights (placed by macOS for the
/// unified toolbar, 19pt from the corner) sit in its first slot.
enum SettingsSidebar {
    static let windowRadius: CGFloat = 26     // macOS 26, window with a unified toolbar
    static let cardInset: CGFloat = 8         // card from the window edge
    static var cardRadius: CGFloat { windowRadius - cardInset }
    static let cardPadding: CGFloat = 10      // rows from the card edge
    static let rowPadding: CGFloat = 8        // tile from the row edge
    static let rowHeight: CGFloat = 36
    /// Slot for the traffic lights (window y 19–33): General's row starts 14pt below them.
    static let buttonsSlot: CGFloat = 26
}

/// The Settings window: an inset sidebar card (About pinned to the bottom) and content panes of section labels above
/// group boxes. Selected states are Ember; controls are drawn here rather than native so no system blue shows through.
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
            if tab == .about {
                AboutTab().padding(.leading, 12).padding(.trailing, 20).padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tab.rawValue).font(.system(size: 17, weight: .bold)).foregroundStyle(SettingsColor.text)
                            .frame(height: 22).padding(.top, 12).padding(.bottom, 16)
                            .accessibilityAddTraits(.isHeader)
                        pane
                    }
                    .padding(.leading, 12).padding(.trailing, 20).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
            }
        }
        .foregroundStyle(SettingsColor.text)
        .background(SettingsColor.window)
        .tint(SettingsColor.ember)
        .buttonStyle(SoftButtonStyle())
        .focusEffectDisabledCompat()      // the focus ring is the system accent
        .frame(maxWidth: .infinity, maxHeight: .infinity)      // the window sets the size (760 × 600); a fixed size here makes SwiftUI add the title bar to it
        .ignoresSafeArea()      // run under the transparent title bar, so the traffic lights land inside the sidebar card
    }

    @ViewBuilder private var pane: some View {
        switch tab {
        case .general: GeneralTab(model: model)
        case .accounts: AccountsTab(model: model)
        case .notifications: NotificationsTab()
        case .claudeCode: ClaudeCodeTab()
        case .updates: UpdatesTab()
        case .about: EmptyView()
        }
    }

    private var sidebar: some View {
        let m = SettingsSidebar.self
        return VStack(alignment: .leading, spacing: 3) {
            Color.clear.frame(height: m.buttonsSlot)     // the window's traffic lights
            ForEach(SettingsTab.allCases.filter { $0 != .about }) { item($0) }
            Spacer()
            item(.about)
        }
        .padding(m.cardPadding)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: m.cardRadius, style: .continuous)
                .fill(SettingsColor.card)
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                .overlay(RoundedRectangle(cornerRadius: m.cardRadius, style: .continuous)
                    .strokeBorder(SettingsColor.hairline, lineWidth: 0.5))
        }
        .padding(m.cardInset)
    }

    private func item(_ t: SettingsTab) -> some View {
        let selected = tab == t
        return Button { tab = t } label: {
            HStack(spacing: 10) {
                Image(systemName: t.symbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? SettingsColor.onEmber : SettingsColor.tileGlyph)
                    .frame(width: 22, height: 22)
                    .background(selected ? SettingsColor.ember : SettingsColor.tile, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(t.rawValue).font(.system(size: 13, weight: selected ? .medium : .regular)).foregroundStyle(SettingsColor.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SettingsSidebar.rowPadding).padding(.vertical, 7)
            .frame(height: SettingsSidebar.rowHeight)
            .background(selected ? SettingsColor.selectedRow : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: Building blocks

/// A section: 13pt semibold label above a card-colored box (radius 12) whose rows are split by hairlines.
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
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(SettingsColor.text)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .padding(.horizontal, 10)
                .background(SettingsColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundStyle(SettingsColor.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
        }
        .padding(.bottom, 20)
    }
}

/// Hairline between rows inside a section box.
struct RowDivider: View {
    var body: some View { Rectangle().fill(SettingsColor.hairline).frame(height: 0.5) }
}

/// One row: title (and optional detail) on the left, a control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let control: Control
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(SettingsColor.text)
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(SettingsColor.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(enabled ? 1 : 0.45)
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 9)
        .frame(minHeight: 40)
    }
}

/// Switch: Ember track and white knob when on; a faint track (darker in light mode, so it reads on the card) when off.
struct BrandSwitch: View {
    let label: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? SettingsColor.ember : SettingsColor.switchOff)
                Capsule().fill(isOn ? SettingsColor.onEmber : SettingsColor.knobOff)
                    .frame(width: 24, height: 18)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
    }
}

/// Segmented control: a faint track; the selected segment is Ember with white text.
struct BrandSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let on = o.0 == selection
                Button { withAnimation(.easeInOut(duration: 0.2)) { selection = o.0 } } label: {
                    Text(o.1).font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .foregroundStyle(on ? SettingsColor.onEmber : SettingsColor.text)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(on ? SettingsColor.ember : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(SettingsColor.control, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .fixedSize()
    }
}

/// Capsule toggle: Ember with white text when on, the faint control fill when off.
struct ChipToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { Chip(configuration: configuration) }

    private struct Chip: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            Button(action: { configuration.isOn.toggle() }) {
                configuration.label
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(configuration.isOn ? SettingsColor.ember : SettingsColor.control, in: Capsule())
                    .foregroundStyle(configuration.isOn ? SettingsColor.onEmber : SettingsColor.text)
                    .opacity(enabled ? 1 : 0.45)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
        }
    }
}

/// Push buttons in Settings: the faint control fill with text-colored labels.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { SoftButton(configuration: configuration) }

    private struct SoftButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsColor.text)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(SettingsColor.control, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SettingsColor.text.opacity(configuration.isPressed ? 0.08 : 0)))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

/// Pop-up menu drawn like an unselected control: value and an up/down chevron on the faint fill.
struct BrandMenuPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                Toggle(o.1, isOn: Binding(get: { selection == o.0 }, set: { if $0 { selection = o.0 } }))
            }
        } label: {
            HStack(spacing: 14) {
                Text(options.first { $0.0 == selection }?.1 ?? "").font(.system(size: 12))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(SettingsColor.text)
            .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 5)
            .background(SettingsColor.control, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// The global-shortcut recorder without its native bezel (whose focus ring and highlight are system blue), on the
/// faint control fill.
struct ShortcutField: View {
    let name: KeyboardShortcuts.Name
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Field(name: name)
            .frame(width: 108, height: 18)
            .padding(.vertical, 2).padding(.leading, 8).padding(.trailing, 6)
            .background(SettingsColor.control, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(enabled ? 1 : 0.45)
    }

    private struct Field: NSViewRepresentable {
        let name: KeyboardShortcuts.Name

        func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
            let r = KeyboardShortcuts.RecorderCocoa(for: name)
            r.isBezeled = false
            r.isBordered = false
            r.drawsBackground = false
            r.backgroundColor = .clear
            r.focusRingType = .none
            r.font = .systemFont(ofSize: 12, weight: .medium)
            r.textColor = SettingsColor.textNS
            return r
        }

        func updateNSView(_ r: KeyboardShortcuts.RecorderCocoa, context: Context) {
            r.shortcutName = name
        }
    }
}

// MARK: General

struct GeneralTab: View {
    @ObservedObject var model: UsageModel
    @AppStorage("menuDisplay") private var display = "off"
    @AppStorage("tintIcon") private var tint = true
    @AppStorage("fillBase") private var fillBase = "auto"
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
                    BrandSwitch(label: "Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                }
            }

            SettingsSection("Menu bar") {
                SettingsRow("Show usage next to icon") {
                    BrandSegmented(selection: $display, options: [("off", "Off"), ("percent", sessionLabel), ("bars", "Bars"), ("fill", "Fill")])
                }
                // Each option's own setting shows only while that option is chosen.
                if display == "fill" {
                    VStack(spacing: 0) {
                        RowDivider()
                        SettingsRow("Fill logo base", detail: "White rays on a dark menu bar, dark rays on a light one. Auto follows the menu bar.") {
                            BrandSegmented(selection: $fillBase, options: [("auto", "Auto"), ("white", "White"), ("dark", "Dark")])
                        }
                    }
                    .transition(.opacity)
                }
                if display == "percent" {
                    VStack(spacing: 0) {
                        RowDivider()
                        SettingsRow("Tint percent by pressure", detail: "Orange at 85%, red at 95% · uses highest limit") {
                            BrandSwitch(label: "Tint percent by pressure", isOn: $tint)
                        }
                    }
                    .transition(.opacity)
                }
            }

            SettingsSection("Refresh & shortcuts") {
                SettingsRow("Refresh every", detail: "Press ⌘R in the popover to refresh now.") {
                    BrandSegmented(selection: $refresh, options: [(1, "1m"), (5, "5m"), (15, "15m"), (30, "30m")])
                }
                RowDivider()
                SettingsRow("Open popover from anywhere") {
                    HStack(spacing: 8) {
                        ShortcutField(name: .openPopover)
                        BrandSwitch(label: "Open popover from anywhere", isOn: $hotkey)
                    }
                }
            }
        }
    }
}

// MARK: Accounts

struct AccountsTab: View {
    @ObservedObject var model: UsageModel
    private var anyFree: Bool { model.accounts.contains { model.states[$0.id]?.plan?.isFree == true } }

    var body: some View {
        SettingsSection("Claude accounts",
                        footer: (anyFree ? "claude.ai doesn’t show usage on the Free plan, so there’s nothing to count. Clausage checks again on every refresh and starts counting as soon as there’s usage. " : "")
                            + (ClaudeSession.supportsMultipleAccounts
                               ? "Each account is kept in its own isolated session on this Mac and only used to read plan usage from claude.ai. Alerts cover all accounts; the menu bar and widget show the selected one."
                               : "Your session stays on this Mac and is only used to read plan usage from claude.ai. On macOS 13 Clausage keeps one account at a time.")) {
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
                            if ClaudeSession.supportsMultipleAccounts, st?.plan?.isFree == true, st?.signedOut != true {
                                Button("Switch…") { model.switchAccount(from: a) }
                                    .help("Use another account: signs this one out, then opens claude.ai sign-in.")
                            }
                            Button("Disconnect", role: .destructive) { model.disconnect(a) }
                        }
                    }
                }
                RowDivider()
                if ClaudeSession.supportsMultipleAccounts {
                    SettingsRow("Add another account") { Button("Add account…") { model.connect() } }
                } else {
                    // macOS 13: one account (one shared cookie store), so another sign-in replaces it.
                    SettingsRow("Use another account", detail: "Signs out, then opens claude.ai sign-in.") {
                        Button("Switch…") { model.connect() }
                    }
                }
            }
        }
    }

    private func accountDetail(_ st: AccountState?) -> String {
        if st?.signedOut == true { return "Signed out" }
        var parts: [String] = []
        if let p = st?.plan?.badge { parts.append(p) }
        let verb = st?.plan?.isFree == true ? "Checked" : "Last updated"
        parts.append(st?.updated.map { "\(verb) \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Fetching usage…")
        return parts.joined(separator: " · ")
    }
}

// MARK: Claude Code (Mac only)

/// What's driving your usage, the way Claude Code's `/usage` computes it, from the transcripts on this Mac.
struct ClaudeCodeTab: View {
    @ObservedObject private var model = UsageModel.shared
    @State private var hasAccess = ClaudeCodeLogs.hasAccess || ClaudeCodeLogs.previewAccess
    @State private var week = true
    @State private var result: ContributorsScan.Result? = ClaudeCodeLogs.lastResult
    @State private var loading = false

    private var window: ContributorsScan.Window? { result.map { week ? $0.week : $0.day } }

    var body: some View {
        if model.activeIsFree { freeBody } else { scanBody }
    }

    /// Free: the switch still works; the breakdown is replaced by why it's empty.
    private var freeBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            scanSwitch
            VStack(spacing: 8) {
                EmptyTally(size: 36)
                Text("Nothing to break down yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(SettingsColor.text)
                Text("This shows what’s driving your Claude Code limit. It needs a Pro or Max plan, since Free doesn’t include Claude Code.")
                    .font(.system(size: 12)).foregroundStyle(SettingsColor.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 340).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28).padding(.horizontal, 20)
            .background(Color("Cream2"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var scanSwitch: some View {
        SettingsSection(nil) {
            SettingsRow("Scan Claude Code sessions",
                        detail: "Reads ~/.claude on this Mac. Only totals are kept, never prompts or code, and nothing leaves this Mac.") {
                BrandSwitch(label: "Scan Claude Code sessions", isOn: Binding(get: { hasAccess }, set: setScanning))
            }
        }
    }

    private var scanBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(week ? "Last 7 days" : "Last 24 hours") of Claude Code on this Mac. Shares overlap, so they don’t add up to 100%.")
                    .font(.system(size: 11)).foregroundStyle(SettingsColor.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                BrandSegmented(selection: $week, options: [(false, "Day"), (true, "Week")])
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
                        TallyLoader(size: 16, ink: SettingsColor.text)
                        Text("Reading this Mac’s Claude Code sessions…").font(.system(size: 12)).foregroundStyle(SettingsColor.secondary)
                    }
                    .padding(.bottom, 20)
                }
            }

            scanSwitch
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
                    Text("\(b.1)%").font(.clausagePercent(20)).foregroundStyle(SettingsColor.text)
                        .frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.copy(b.0).title).font(.system(size: 13, weight: .medium)).foregroundStyle(SettingsColor.text)
                        Text(Self.copy(b.0).tip).font(.system(size: 11)).foregroundStyle(SettingsColor.secondary)
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
                    Text(prefix + s.name).font(.system(size: 12, design: .monospaced)).foregroundStyle(SettingsColor.text).lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(s.percent)%").font(.system(size: 12)).foregroundStyle(SettingsColor.secondary)
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
                    Text("\(r.limitHits[k] ?? 0)").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(SettingsColor.text)
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

/// Which alerts you get and the macOS permission, all in one place.
struct NotificationsTab: View {
    @ObservedObject private var model = UsageModel.shared
    @State private var status: UNAuthorizationStatus = .notDetermined
    @AppStorage("thresholds") private var thresholds = "75,80,90"
    @AppStorage("notifySoon") private var soon = true
    @AppStorage("soonMinutes") private var soonMinutes = 10
    @AppStorage("notifyReset") private var notifyReset = true
    @AppStorage("notifyOutage") private var notifyOutage = false

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Blocked in System Settings"
        default: return "Not requested yet"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection("Notify me when",
                            footer: model.activeIsFree ? "Limit alerts need a Pro or Max plan. Your choices are kept for when they do." : nil) {
                Group {
                SettingsRow("Any limit reaches") {
                    HStack(spacing: 5) {
                        ForEach(Prefs.allThresholdChips, id: \.self) { t in
                            Toggle("\(t)%", isOn: chip(t)).toggleStyle(ChipToggleStyle())
                        }
                    }
                }
                RowDivider()
                SettingsRow("Session is about to reset") {
                    HStack(spacing: 8) {
                        BrandMenuPicker(selection: $soonMinutes, options: [5, 10, 15, 30].map { ($0, "\($0) min before") })
                            .disabled(!soon)
                        BrandSwitch(label: "Session is about to reset", isOn: $soon)
                    }
                }
                RowDivider()
                SettingsRow("A limit resets") { BrandSwitch(label: "A limit resets", isOn: $notifyReset) }
                }
                .disabled(model.activeIsFree)
                RowDivider()
                SettingsRow("Anthropic reports an outage") {
                    BrandSwitch(label: "Anthropic reports an outage", isOn: $notifyOutage)
                        .onChangeCompat(of: notifyOutage) { on in
                            if on { Task { await Notifier.requestAuthorization(); await StatusMonitor.check() } }
                        }
                }
            }

            SettingsSection("Permission",
                            footer: "macOS only lets an app ask for permission once. After that, turn notifications on or off in System Settings.") {
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
        }
        .task { await load() }
        // Refresh when returning from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await load() }
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

enum AppVersion {
    static var short: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }
}

struct UpdatesTab: View {
    @ObservedObject private var updater = Updater.shared
    var body: some View {
        SettingsSection("Version") {
            SettingsRow("Clausage \(AppVersion.short) (\(AppVersion.build))") {
                Button("Check for Updates…") { updater.checkForUpdates() }.disabled(!updater.canCheck)
            }
            RowDivider()
            SettingsRow("Check automatically", detail: "Looks for new versions in the background.") {
                BrandSwitch(label: "Check automatically", isOn: Binding(get: { updater.automaticChecks }, set: { updater.automaticChecks = $0 }))
            }
        }
    }
}

/// Identity in the middle, then what people come here for: is it up to date, and how to report something.
/// Quitting is ⌘Q and the gear menu.
struct AboutTab: View {
    @ObservedObject private var updater = Updater.shared
    @Environment(\.colorScheme) private var scheme

    enum Links {
        static let website = URL(string: "https://clausage.ai")!
        static let privacy = URL(string: "https://clausage.ai/privacy")!
        static let acknowledgements = URL(string: "https://clausage.ai/acknowledgements")!
        static let feedbackAddress = "counter@clausage.ai"
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                icon
                VStack(spacing: 6) {
                    Text("clausage")
                        .font(.clausageDisplay(34)).brandTracking(-0.045, size: 34)
                        .foregroundStyle(SettingsColor.text)
                        .accessibilityLabel("Clausage")
                    Text("Your Claude plan limits, at a glance.")
                        .font(.system(size: 13)).foregroundStyle(SettingsColor.secondary)
                    Text("Version \(AppVersion.short) (\(AppVersion.build))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(SettingsColor.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SettingsSection(nil) {
                SettingsRow(updateTitle, detail: updateDetail) { updateControl }
                RowDivider()
                Button(action: sendFeedback) {
                    SettingsRow("Send Feedback", detail: "Bugs, ideas, or numbers that look wrong. Goes to the developer.") {
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SettingsColor.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, -16)

            VStack(spacing: 10) {
                HStack(spacing: 18) {
                    link("Website", Links.website)
                    link("Privacy", Links.privacy)
                    link("Acknowledgements", Links.acknowledgements)
                }
                Text("An independent app, not made by or affiliated with Anthropic. Claude is a trademark of Anthropic.")
                    .font(.system(size: 11)).foregroundStyle(SettingsColor.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4).padding(.bottom, 2)
        }
    }

    /// The app icon as a tile: it stays light in dark mode (it's the icon, not the UI).
    private var icon: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 1, green: 252 / 255, blue: 246 / 255), Color(red: 239 / 255, green: 230 / 255, blue: 216 / 255)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(red: 38 / 255, green: 35 / 255, blue: 31 / 255).opacity(0.18), lineWidth: 0.5))
            .overlay(BrandMark(size: 46, ink: Color(red: 38 / 255, green: 35 / 255, blue: 31 / 255),
                               ember: Color(red: 1, green: 74 / 255, blue: 28 / 255)))
            .frame(width: 96, height: 96)
            .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.14), radius: 11, y: 8)
            .accessibilityHidden(true)
    }

    private var updateTitle: String {
        switch updater.status {
        case .idle: "Not checked yet"
        case .checking: "Checking for updates…"
        case .upToDate: "Up to date"
        case .available(let v): "Version \(v) is available"
        case .failed: "Couldn’t check for updates"
        }
    }

    private var updateDetail: String? {
        if case .failed(let message) = updater.status { return message }
        guard let d = updater.lastChecked else { return nil }
        let time = d.formatted(date: .omitted, time: .shortened)
        let day = Calendar.current.isDateInToday(d) ? "today" : Calendar.current.isDateInYesterday(d) ? "yesterday"
            : d.formatted(.dateTime.month(.abbreviated).day())
        return "Checked \(day) at \(time)"
    }

    @ViewBuilder private var updateControl: some View {
        switch updater.status {
        case .checking: TallyLoader(size: 18, ink: SettingsColor.text)
        case .available: Button("Install") { updater.checkForUpdates() }.disabled(!updater.canCheck)
        default: Button("Check Now") { updater.probe() }.disabled(!updater.canCheck)
        }
    }

    private func link(_ title: String, _ url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(SettingsColor.link)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
    }

    /// Feedback goes to the developer through the user's own Mail app, with the version and macOS prefilled.
    private func sendFeedback() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = Links.feedbackAddress
        c.queryItems = [URLQueryItem(name: "subject", value: "Clausage feedback"),
                        URLQueryItem(name: "body", value: "\n\n— Clausage \(AppVersion.short) (\(AppVersion.build)), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }
}
