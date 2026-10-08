import SwiftUI
import KeyboardShortcuts
import UserNotifications

enum SettingsTab: String, CaseIterable, Identifiable {
    case usage = "Usage", claudeCode = "Claude Code"
    case general = "General", accounts = "Accounts", notifications = "Notifications", updates = "Updates", about = "About"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .usage: "chart.xyaxis.line"
        case .claudeCode: "terminal"
        case .general: "gearshape"
        case .accounts: "person.crop.circle"
        case .notifications: "bell"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
}

/// Settings colors. Ember is the app's AccentColor, so native switches and the focus ring pick it up; the tokens here
/// are for what Settings draws itself. Dark mode has its own warmer surfaces.
enum SettingsColor {
    static let window = dynamic(0xF7EEDD, dark: 0x24211E)
    static let card = dynamic(0xF2E7D3, dark: 0x2D2925)
    static let hairline = dynamic(0x26231F, 0.10, dark: 0xF4EDE2, 0.09)
    static let text = dynamic(0x26231F, dark: 0xF4EDE2)
    static let secondary = dynamic(0x766E64, dark: 0xADA497)
    static let tertiary = dynamic(0x8A8278, dark: 0x8F867A)
    static let ember = rgb(0xFF4A1C)
    static let onEmber = Color.white
    /// Plan chip in pane headers.
    static let chip = dynamic(0xE8DFCF, dark: 0xF4EDE2, 0.08)
    /// Unselected threshold chip.
    static let control = dynamic(0x26231F, 0.07, dark: 0xF4EDE2, 0.08)
    static var textNS: NSColor { ns(0x26231F, 1, dark: 0xF4EDE2, 1) }
    static let selectedRow = dynamic(0xFF4A1C, 0.12, dark: 0xFF4A1C, 0.20)
    static let tile = dynamic(0x8A8278, dark: 0x8F867A)
    static let link = dynamic(0xC23B14, dark: 0xFF8A63)
    /// The running-total chart's Paper card and its 1pt inset edge.
    static let chartCard = dynamic(0xFFFCF6, dark: 0x24211E)
    static let chartEdge = dynamic(0xEAE1D2, dark: 0xF4EDE2, 0.10)

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

    /// A color with light and dark values, resolved by the view's appearance (no color-scheme branching in views).
    static func dynamic(_ light: Int, _ la: CGFloat = 1, dark: Int, _ da: CGFloat = 1) -> Color {
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
    /// Slot for the traffic lights (window y 19–33): the first row starts 14pt below them.
    static let buttonsSlot: CGFloat = 26
}

/// The Settings window: an inset sidebar card (Usage and Claude Code, a divider, the preferences, About pinned to the
/// bottom) and content panes with a shared header (title and plan chip) above labeled group boxes. Controls are native,
/// tinted Ember through the app's AccentColor.
struct SettingsView: View {
    @ObservedObject var model: UsageModel
    @State private var tab: SettingsTab

    init(model: UsageModel, tab: SettingsTab = .usage) {
        self.model = model
        _tab = State(initialValue: tab)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Group {
                if tab == .about {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        AboutTab()
                    }
                    .padding(.leading, 12).padding(.trailing, 20).padding(.bottom, 20)
                } else {
                    // The margins are inside the scroll view, so it runs to the window edge and its scroller sits in the
                    // right-hand gutter rather than over the group boxes.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            pane
                        }
                        .padding(.leading, 12).padding(.trailing, 20).padding(.bottom, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.automatic)
                }
            }
        }
        .foregroundStyle(SettingsColor.text)
        .background(SettingsColor.window)
        .tint(SettingsColor.ember)
        .frame(maxWidth: .infinity, maxHeight: .infinity)      // the window sets the size (760 × 600); a fixed size here makes SwiftUI add the title bar to it
        .ignoresSafeArea()      // run under the transparent title bar, so the traffic lights land inside the sidebar card
    }

    /// The pane title (SF 20 bold) and, on the trailing side, the plan chip.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(tab.rawValue).font(.system(size: 20, weight: .bold)).tracking(-0.2)
                .foregroundStyle(SettingsColor.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let plan = model.activeState?.plan {
                Text(plan.badge)
                    .font(.clausageDisplay(12))
                    .foregroundStyle(SettingsColor.text)
                    .padding(.top, 3).padding(.bottom, 4).padding(.horizontal, 9)
                    .background(SettingsColor.chip, in: Capsule())
                    .lineLimit(1).fixedSize()
                    .accessibilityLabel("Plan: \(plan.badge)")
            }
        }
        .frame(height: 26)
        .padding(.top, 14).padding(.bottom, 14)
    }

    @ViewBuilder private var pane: some View {
        switch tab {
        case .usage: UsageTab(model: model)
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
            item(.usage)
            item(.claudeCode)
            Divider().overlay(SettingsColor.hairline).padding(.horizontal, m.rowPadding).padding(.vertical, 6)
            ForEach([SettingsTab.general, .accounts, .notifications, .updates]) { item($0) }
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

    /// A sidebar row: the white glyph on a rounded tile (Ink 3, Ember when selected) and the name, on a 12% Ember wash
    /// when selected (20% in dark mode).
    private func item(_ t: SettingsTab) -> some View {
        let selected = tab == t
        return Button { tab = t } label: {
            HStack(spacing: 10) {
                Image(systemName: t.symbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
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

/// A group: a 13pt semibold label 7pt above a card-colored box (radius 12) whose rows are split by hairlines.
/// Groups are 16pt apart.
struct SettingsSection<Content: View>: View {
    let title: String?
    var footer: String? = nil
    /// Stretch the box to the height it's offered (side-by-side groups of equal height).
    var fills = false
    @ViewBuilder let content: Content

    init(_ title: String?, footer: String? = nil, fills: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.fills = fills
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(SettingsColor.text)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .topLeading)
                .background(SettingsColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundStyle(SettingsColor.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
        }
        .padding(.bottom, 16)
    }
}

/// Hairline between rows inside a group box.
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

/// Native switch, label hidden (the row shows it). Ember when on, from the AccentColor.
struct SettingsSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
    }
}

/// Native segmented control with the selected segment in Ember (`selectedSegmentBezelColor`; SwiftUI's segmented
/// picker always draws a neutral selection on macOS).
struct SettingsSegmented<T: Hashable>: View {
    let label: String
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        Segments(label: label, labels: options.map(\.1),
                 selected: options.firstIndex { $0.0 == selection } ?? -1,
                 onSelect: { i in if options.indices.contains(i) { selection = options[i].0 } })
            .fixedSize()
    }

    private struct Segments: NSViewRepresentable {
        let label: String
        let labels: [String]
        let selected: Int
        let onSelect: (Int) -> Void

        func makeCoordinator() -> Target { Target() }

        func makeNSView(context: Context) -> NSSegmentedControl {
            let c = NSSegmentedControl(labels: labels, trackingMode: .selectOne,
                                       target: context.coordinator, action: #selector(Target.changed(_:)))
            c.selectedSegmentBezelColor = NSColor(SettingsColor.ember)
            c.setAccessibilityLabel(label)
            return c
        }

        func updateNSView(_ c: NSSegmentedControl, context: Context) {
            context.coordinator.onSelect = onSelect
            if c.segmentCount != labels.count { c.segmentCount = labels.count }
            for (i, l) in labels.enumerated() where c.label(forSegment: i) != l { c.setLabel(l, forSegment: i) }
            if c.selectedSegment != selected { c.selectedSegment = selected }
            c.isEnabled = context.environment.isEnabled
        }

        final class Target: NSObject {
            var onSelect: (Int) -> Void = { _ in }
            @objc func changed(_ c: NSSegmentedControl) { onSelect(c.selectedSegment) }
        }
    }
}

/// Native pop-up button, label hidden.
struct SettingsMenuPicker<T: Hashable>: View {
    let label: String
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in Text(o.1).tag(o.0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

/// The native shortcut recorder (with its own clear button) without its bezel, whose fill is a cool system gray, on
/// the warm control fill instead.
struct ShortcutField: View {
    let name: KeyboardShortcuts.Name
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Field(name: name)
            .frame(width: 108, height: 18)
            .padding(.vertical, 3).padding(.leading, 10).padding(.trailing, 14)
            .background(SettingsColor.control, in: Capsule())
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
            r.font = .systemFont(ofSize: 12, weight: .medium)
            r.textColor = SettingsColor.textNS
            return r
        }

        func updateNSView(_ r: KeyboardShortcuts.RecorderCocoa, context: Context) {
            r.shortcutName = name
        }
    }
}

/// Threshold chip (no native control does several-of-a-set as capsules): Ember with white text when on, a faint fill
/// of the text color when off.
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

// MARK: Usage (the landing pane)

/// Everything Clausage knows on one page, in the iPhone's order: limits, the week's running total with its forecast,
/// then this week by product and usage credits side by side.
struct UsageTab: View {
    @ObservedObject var model: UsageModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        if !model.connected {
            SettingsSection(nil) {
                SettingsRow("Not connected", detail: "Sign in to see your plan usage.") {
                    Button("Connect…") { model.connect() }
                }
            }
        } else if model.activeIsFree {
            freeBody
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        let st = model.activeState
        let limits = Forecast.ordered(model.limits)
        VStack(alignment: .leading, spacing: 0) {
            if model.activeSignedOut, let a = model.active {
                SettingsSection(nil) {
                    SettingsRow("Signed out", detail: "Sign in again to keep your usage up to date.") {
                        Button("Sign In…") { model.reconnect(a) }
                    }
                }
            } else if let e = model.error {
                Text(e).font(.system(size: 11)).foregroundStyle(Color("CriticalText"))
                    .fixedSize(horizontal: false, vertical: true).padding(.bottom, 12)
            }

            SettingsSection("Limits") {
                if limits.isEmpty {
                    SettingsRow(st?.updated == nil ? "Counting your usage…" : "Nothing to count",
                                detail: st?.updated == nil ? nil : "Your org didn’t set any plan limits.") { EmptyView() }
                }
                ForEach(Array(limits.enumerated()), id: \.element.id) { i, l in
                    if i > 0 { RowDivider() }
                    PaneLimitRow(limit: l)
                }
            }

            if let w = st?.weekly {
                let level = limits.first { $0.kind == "weekly_all" }.map(Forecast.level) ?? .normal
                week(WeeklyChart.make(history: model.history, window: w, now: Date()), level: level)
            }

            let breakdown = st?.breakdown.flatMap { $0.rows.isEmpty ? nil : $0 }
            let credits = st?.credits
            if breakdown != nil || credits != nil {
                HStack(alignment: .top, spacing: 14) {
                    if let breakdown { product(breakdown) }
                    if let credits { creditsBox(credits) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The running total on a Paper card, then the forecast in the house voice.
    private func week(_ chart: WeeklyChart?, level: Forecast.Level) -> some View {
        SettingsSection("All models this week") {
            VStack(alignment: .leading, spacing: 12) {
                if let chart {
                    RunningTotalChart(chart: chart, level: level)
                        .frame(height: 150)
                        .padding(.horizontal, 4).padding(.vertical, 6)
                        .background(SettingsColor.chartCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(SettingsColor.chartEdge, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 3) {
                        if let headline = chart.headline {
                            Text(headline).font(.system(size: 13, weight: .semibold)).foregroundStyle(SettingsColor.text)
                        }
                        Text(chart.caption).font(.system(size: 12)).foregroundStyle(SettingsColor.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                } else {
                    NotEnoughYet()
                }
            }
            .padding(.vertical, 12)
        }
    }

    /// The biggest share large, then the rest, high to low.
    private func product(_ b: ProductBreakdown) -> some View {
        SettingsSection("This week by product", fills: true) {
            if let top = b.rows.first {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(top.percent.rounded()))%")
                        .font(.clausagePercent(34)).brandTracking(-0.04, size: 34).foregroundStyle(SettingsColor.text)
                    Text("came from \(top.name)").font(.system(size: 12, weight: .medium)).foregroundStyle(SettingsColor.text)
                        .padding(.top, 2)
                    if b.rows.count > 1 {
                        RowDivider().padding(.top, 10).padding(.bottom, 8)
                        HStack(spacing: 0) {
                            ForEach(Array(b.rows.dropFirst().enumerated()), id: \.element.id) { i, row in
                                if i > 0 { Spacer(minLength: 8) }
                                (Text(row.name + " ").font(.system(size: 11)).foregroundColor(SettingsColor.secondary)
                                 + Text("\(Int(row.percent.rounded()))%").font(.clausagePercent(12)).foregroundColor(SettingsColor.text))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(b.rows.map { "\($0.name) \(Int($0.percent.rounded())) percent" }.joined(separator: ", "))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Read-only: on or off, the amounts, and a link to claude.ai to change them.
    private func creditsBox(_ c: UsageCredits) -> some View {
        SettingsSection("Usage credits", fills: true) {
            VStack(alignment: .leading, spacing: 3) {
                Text(c.stateText).font(.system(size: 13, weight: .semibold)).foregroundStyle(SettingsColor.text)
                if !c.detailText.isEmpty {
                    Text(c.detailText).font(.system(size: 11)).foregroundStyle(SettingsColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Link(destination: URL(string: "https://claude.ai/settings/usage")!) {
                    HStack(spacing: 3) {
                        Text("Manage")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsColor.link)
                }
                .accessibilityHint("Opens claude.ai usage settings")
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
    }

    /// claude.ai has no usage page on Free: the empty tally, why, and one way forward.
    private var freeBody: some View {
        VStack(spacing: 8) {
            EmptyTally(size: 40)
            Text(FreePlanCopy.headline).font(.system(size: 13, weight: .semibold)).foregroundStyle(SettingsColor.text)
            Text(FreePlanCopy.bodyScreen)
                .font(.system(size: 12)).foregroundStyle(SettingsColor.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360).fixedSize(horizontal: false, vertical: true)
            if ClaudeSession.supportsMultipleAccounts, let a = model.active {
                Button(FreePlanCopy.switchAccount) { model.switchAccount(from: a) }.padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, 20)
        .background(SettingsColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A limit on the Usage pane: name and percent, an 8pt bar with a 2×12pt tick, then "Resets …" and, when the forecast
/// runs out before the reset, "Out ~…" on the trailing side.
struct PaneLimitRow: View {
    let limit: UsageLimit

    private var level: Forecast.Level { Forecast.level(limit) }
    private var runout: String? {
        Forecast.hitDate(limit).map { "Out ~\(Forecast.timeText($0, window: limit.windowLength))" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(Forecast.fullName(limit)).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Text("\(Int(limit.percent.rounded()))%").font(.clausagePercent(18)).brandTracking(-0.03, size: 18)
            }
            .foregroundStyle(SettingsColor.text)
            .frame(height: 18)
            LimitBar(limit: limit, height: 8, tick: 12)
            HStack {
                if let r = Forecast.screenResetText(limit) {
                    Text(r).foregroundStyle(SettingsColor.secondary)
                }
                Spacer(minLength: 8)
                if let runout {
                    Text(runout).fontWeight(.medium)
                        .foregroundStyle(level == .critical ? Color("CriticalText") : Color("NearText"))
                }
            }
            .font(.system(size: 11))
            .lineLimit(1)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var s = "\(Forecast.fullName(limit)), \(Int(limit.percent.rounded())) percent used"
        if let r = Forecast.screenResetText(limit) { s += ", " + r.lowercased() }
        if let hit = Forecast.hitDate(limit) {
            let when = limit.windowLength > 86_400
                ? hit.formatted(.dateTime.weekday(.wide).hour().minute())
                : hit.formatted(.dateTime.hour().minute())
            s += ", runs out around \(when)"
        }
        return s
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
                    SettingsSwitch(label: "Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                }
            }

            SettingsSection("Menu bar") {
                SettingsRow("Show usage next to icon") {
                    SettingsSegmented(label: "Show usage next to icon", selection: $display, options: [("off", "Off"), ("percent", sessionLabel), ("bars", "Bars"), ("fill", "Fill")])
                }
                // Each option's own setting shows only while that option is chosen.
                if display == "fill" {
                    VStack(spacing: 0) {
                        RowDivider()
                        SettingsRow("Fill logo base", detail: "White rays on a dark menu bar, dark rays on a light one. Auto follows the menu bar.") {
                            SettingsSegmented(label: "Fill logo base", selection: $fillBase, options: [("auto", "Auto"), ("white", "White"), ("dark", "Dark")])
                        }
                    }
                    .transition(.opacity)
                }
                if display == "percent" {
                    VStack(spacing: 0) {
                        RowDivider()
                        SettingsRow("Tint percent by pressure", detail: "Orange at 85%, red at 95% · uses highest limit") {
                            SettingsSwitch(label: "Tint percent by pressure", isOn: $tint)
                        }
                    }
                    .transition(.opacity)
                }
            }

            SettingsSection("Refresh & shortcuts") {
                SettingsRow("Refresh every", detail: "Press ⌘R in the popover to refresh now.") {
                    SettingsSegmented(label: "Refresh every", selection: $refresh, options: [(1, "1m"), (5, "5m"), (15, "15m"), (30, "30m")])
                }
                RowDivider()
                SettingsRow("Open popover from anywhere") {
                    HStack(spacing: 8) {
                        ShortcutField(name: .openPopover)
                        SettingsSwitch(label: "Open popover from anywhere", isOn: $hotkey)
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
            .background(SettingsColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var scanSwitch: some View {
        SettingsSection(nil) {
            SettingsRow("Scan Claude Code sessions",
                        detail: "Reads ~/.claude on this Mac. Only totals are kept, never prompts or code, and nothing leaves this Mac.") {
                SettingsSwitch(label: "Scan Claude Code sessions", isOn: Binding(get: { hasAccess }, set: setScanning))
            }
        }
    }

    private var scanBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(week ? "Last 7 days" : "Last 24 hours") of Claude Code on this Mac. Shares overlap, so they don’t add up to 100%.")
                    .font(.system(size: 11)).foregroundStyle(SettingsColor.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                SettingsSegmented(label: "Period", selection: $week, options: [(false, "Day"), (true, "Week")])
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
                        SettingsMenuPicker(label: "Minutes before", selection: $soonMinutes, options: [5, 10, 15, 30].map { ($0, "\($0) min before") })
                            .disabled(!soon)
                        SettingsSwitch(label: "Session is about to reset", isOn: $soon)
                    }
                }
                RowDivider()
                SettingsRow("A limit resets") { SettingsSwitch(label: "A limit resets", isOn: $notifyReset) }
                }
                .disabled(model.activeIsFree)
                RowDivider()
                SettingsRow("Anthropic reports an outage") {
                    SettingsSwitch(label: "Anthropic reports an outage", isOn: $notifyOutage)
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
                SettingsSwitch(label: "Check automatically", isOn: Binding(get: { updater.automaticChecks }, set: { updater.automaticChecks = $0 }))
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
