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
    static let selectedRow = dynamic(0xFF4A1C, 0.18, dark: 0xFF4A1C, 0.30)
    /// Secondary (.bordered) button text: Ember Deep in light mode for contrast, a lighter Ember in dark.
    static let buttonText = dynamic(0xC23B14, dark: 0xFF6A40)
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
        .tint(SettingsColor.buttonText)      // .bordered buttons' text; switches and Install Now set Ember themselves
        .onReceive(SettingsWindow.shared.$requestedTab.compactMap { $0 }) { tab = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity)      // the window sets the size (760 × 600); a fixed size here makes SwiftUI add the title bar to it
        .ignoresSafeArea()      // run under the transparent title bar, so the traffic lights land inside the sidebar card
    }

    /// The pane title (SF 20 bold). The plan shows in the popover and on the Accounts row, not here.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(tab.rawValue).font(.system(size: 20, weight: .bold)).tracking(-0.4)
                .foregroundStyle(SettingsColor.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
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
    /// Something under the box, above the footer (e.g. Accounts' "Add Account…").
    var below: AnyView? = nil
    @ViewBuilder let content: Content

    init(_ title: String?, footer: String? = nil, fills: Bool = false, below: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.fills = fills
        self.below = below
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
            if let below { below.padding(.top, 3) }
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
        Toggle(label, isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small).tint(SettingsColor.ember)
    }
}

/// Native segmented control (SwiftUI's segmented picker), label hidden.
struct SettingsSegmented<T: Hashable>: View {
    let label: String
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in Text(o.1).tag(o.0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .tint(SettingsColor.ember)      // same Ember as the switches, not the deeper button-text tint
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

/// The native shortcut recorder as it ships (shape, clear button, focus ring), except for its fill: macOS 26 draws the
/// field's bezel in a small SwiftUI host whose fill is a plain full-size layer in a cool system gray, with a layer that
/// tints it from the wallpaper. `RecorderHost` recolors that layer warm and hides the tint, after every layout and
/// appearance change, since the system may redraw it.
struct ShortcutField: View {
    let name: KeyboardShortcuts.Name
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Field(name: name)
            .frame(width: 130)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(enabled ? 1 : 0.45)
    }

    private struct Field: NSViewRepresentable {
        let name: KeyboardShortcuts.Name

        func makeNSView(context: Context) -> RecorderHost { RecorderHost(name: name) }

        func updateNSView(_ host: RecorderHost, context: Context) {
            host.recorder.shortcutName = name
            host.recolor()
        }
    }

    final class RecorderHost: NSView {
        let recorder: KeyboardShortcuts.RecorderCocoa
        /// Warm white in light mode, a faint warm tint over the group box in dark.
        private static let fill = NSColor(name: nil) {
            $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0xF4 / 255, green: 0xED / 255, blue: 0xE2 / 255, alpha: 0.08)
                : NSColor(srgbRed: 0xFF / 255, green: 0xFC / 255, blue: 0xF6 / 255, alpha: 1)
        }
        private var observers: [NSObjectProtocol] = []

        init(name: KeyboardShortcuts.Name) {
            recorder = KeyboardShortcuts.RecorderCocoa(for: name)
            super.init(frame: .zero)
            recorder.translatesAutoresizingMaskIntoConstraints = false
            addSubview(recorder)
            NSLayoutConstraint.activate([
                recorder.leadingAnchor.constraint(equalTo: leadingAnchor), recorder.trailingAnchor.constraint(equalTo: trailingAnchor),
                recorder.topAnchor.constraint(equalTo: topAnchor), recorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            // Focus, recording and key-window changes can redraw the bezel.
            for n in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                      Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange")] {
                observers.append(NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                    DispatchQueue.main.async { self?.recolor() }
                })
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        override var intrinsicContentSize: NSSize { recorder.intrinsicContentSize }

        override func layout() {
            super.layout()
            recolor()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            DispatchQueue.main.async { [weak self] in self?.recolor() }
        }

        func recolor() {
            guard let root = recorder.layer else { return }
            let size = recorder.bounds.size
            var fill: CGColor?
            effectiveAppearance.performAsCurrentDrawingAppearance { fill = Self.fill.cgColor }
            func walk(_ l: CALayer) {
                if type(of: l) == CALayer.self, l.backgroundColor != nil, l.bounds.size == size {
                    if l.backgroundColor != fill { l.backgroundColor = fill }
                } else if String(describing: type(of: l)) == "CAChameleonLayer" {
                    l.isHidden = true
                }
                l.sublayers?.forEach(walk)
            }
            walk(root)
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
                    RunningTotalChart(chart: chart, level: level, labelBackground: SettingsColor.chartCard)
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
    @AppStorage("fillAccent") private var fillAccent = false
    @AppStorage("refreshMinutes") private var refresh = 5

    /// The menu bar shows All models.
    private var sessionLabel: String {
        MenuBarIcon.shown(model.limits).map { "\(Int($0.percent.rounded()))%" } ?? "24%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection("Startup") {
                SettingsRow("Launch at login") {
                    SettingsSwitch(label: "Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                }
            }

            SettingsSection("Menu bar") {
                SettingsRow("Show usage") {
                    SettingsSegmented(label: "Show usage", selection: $display, options: [("off", "Icon only"), ("percent", sessionLabel), ("bars", "Bars"), ("fill", "Fill")])
                }
                // Each option's own setting shows only while that option is chosen.
                if display == "fill" {
                    VStack(spacing: 0) {
                        RowDivider()
                        SettingsRow("Icon color", detail: "Auto matches the menu bar.") {
                            SettingsSegmented(label: "Icon color", selection: $fillBase, options: [("auto", "Auto"), ("white", "Light"), ("dark", "Dark")])
                        }
                        RowDivider()
                        SettingsRow("Fill with accent color", detail: "Uses your accent color from System Settings.") {
                            SettingsSwitch(label: "Fill with accent color", isOn: $fillAccent)
                        }
                    }
                    .transition(.opacity)
                }
                if display == "percent" {
                    VStack(spacing: 0) {
                        RowDivider()
                        SettingsRow("Tint percent by pressure", detail: "Orange at 85%, red at 95% · uses All models") {
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
                // The recorder is the only control: clearing it (×) turns the shortcut off.
                SettingsRow("Open popover from anywhere") {
                    ShortcutField(name: .openPopover)
                }
            }
        }
    }
}

// MARK: Accounts

struct AccountsTab: View {
    @ObservedObject var model: UsageModel
    /// The account a Disconnect click is asking about.
    @State private var confirming: Account?
    private var anyFree: Bool { model.accounts.contains { model.states[$0.id]?.plan?.isFree == true } }

    private var footnote: String {
        (anyFree ? "claude.ai doesn’t show usage on the Free plan, so there’s nothing to count. Clausage checks again on every refresh and starts counting as soon as there’s usage. " : "")
            + (ClaudeSession.supportsMultipleAccounts
               ? "Each account is kept in its own isolated session on this Mac and only used to read plan usage from claude.ai. Alerts cover all accounts; the menu bar and widget show the selected one."
               : "Your session stays on this Mac and is only used to read plan usage from claude.ai. On macOS 13 Clausage keeps one account at a time.")
    }

    var body: some View {
        SettingsSection("Claude accounts", footer: footnote, below: model.accounts.isEmpty ? nil : AnyView(addButton)) {
            if model.accounts.isEmpty {
                SettingsRow("Not connected", detail: "Sign in to see your plan usage.") {
                    Button("Connect…") { model.connect() }
                }
            } else {
                ForEach(Array(model.accounts.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { RowDivider() }
                    row(a)
                }
            }
        }
        .confirmationDialog("Disconnect \(confirming?.name ?? "this account")?",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            presenting: confirming) { a in
            Button("Disconnect", role: .destructive) { model.disconnect(a) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Clausage signs it out on this Mac and forgets its usage history.")
        }
    }

    /// With two or more accounts, a radio picks the one the menu bar shows.
    private func row(_ a: Account) -> some View {
        let st = model.states[a.id]
        return HStack(spacing: 8) {
            if model.accounts.count > 1 {
                Picker("Show in menu bar", selection: Binding(get: { model.active?.id }, set: { if let id = $0 { model.setActive(id) } })) {
                    Text("").tag(Optional(a.id))
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Show \(a.name) in the menu bar")
            }
            SettingsRow(a.name, detail: accountDetail(st)) {
                HStack {
                    if st?.signedOut == true { Button("Sign In…") { model.reconnect(a) } }
                    if ClaudeSession.supportsMultipleAccounts, st?.plan?.isFree == true, st?.signedOut != true {
                        Button("Switch…") { model.switchAccount(from: a) }
                            .help("Use another account: signs this one out, then opens claude.ai sign-in.")
                    }
                    Button(role: .destructive) { confirming = a } label: {
                        Text("Disconnect").foregroundStyle(Color("CriticalText"))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    /// Under the card, trailing. On macOS 13 there's one account (one shared cookie store), so another sign-in replaces it.
    private var addButton: some View {
        HStack {
            Spacer()
            if ClaudeSession.supportsMultipleAccounts {
                Button("Add Account…") { model.connect() }
            } else {
                Button("Use Another Account…") { model.connect() }
                    .help("Signs out, then opens claude.ai sign-in.")
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
    /// Free: just why it's empty, and the same way forward as the Usage pane. The scan switch comes back on Pro or Max.
    private var freeBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                EmptyTally(size: 36)
                Text("Nothing to break down yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(SettingsColor.text)
                Text("This shows what’s driving your Claude Code limit. It needs a Pro or Max plan, since Free doesn’t include Claude Code.")
                    .font(.system(size: 12)).foregroundStyle(SettingsColor.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 340).fixedSize(horizontal: false, vertical: true)
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
    @AppStorage("thresholds") private var thresholds = "85,95"
    @AppStorage("notifySoon") private var soon = true
    @AppStorage("soonMinutes") private var soonMinutes = 10
    @AppStorage("notifyReset") private var notifyReset = true
    @AppStorage("notifyOutage") private var notifyOutage = false

    private var allowed: Bool { status == .authorized || status == .provisional }

    private var statusText: String {
        if allowed { return "Allowed" }
        return status == .denied ? "Off in System Settings" : "Not requested yet"
    }

    /// Under the card: what to expect from the one action this state offers.
    private var permissionFootnote: String? {
        if allowed { return nil }
        return status == .denied ? "The alerts above won’t appear until notifications are turned on."
                                 : "macOS asks only once. After that, you change it in System Settings."
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

            // One action per state: Allow… before macOS has asked, Open System Settings… once it's off, none when allowed.
            SettingsSection("Permission", footer: permissionFootnote) {
                SettingsRow("Notifications", detail: statusText) {
                    if status == .denied {
                        Button("Open System Settings…") { openSystemSettings() }
                    } else if !allowed {
                        Button("Allow…") { Task { await Notifier.requestAuthorization(); await load() } }
                    }
                }
                RowDivider()
                SettingsRow("Send a test notification") {
                    Button("Send test") { Notifier.sendTest() }
                }
                .disabled(!allowed)
            }
        }
        .task { await load() }
        // Re-read when coming back from System Settings, or when the Settings window becomes key again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
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
            version
            RowDivider()
            SettingsRow("Check automatically", detail: "Looks for new versions in the background.") {
                SettingsSwitch(label: "Check automatically", isOn: Binding(get: { updater.automaticChecks }, set: { updater.automaticChecks = $0 }))
            }
        }
    }

    /// Up to date: this version and "Check for Updates…". An update ready: "Clausage 0.0.9 (9) is available", what
    /// you have, release notes when the appcast has them, and Install Now.
    @ViewBuilder private var version: some View {
        switch updater.status {
        case .available, .installing:
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clausage \(updater.availableVersion ?? "")\(updater.availableBuild.map { " (\($0))" } ?? "") is available")
                        .font(.system(size: 13)).foregroundStyle(SettingsColor.text)
                    HStack(spacing: 4) {
                        Text("You have \(AppVersion.short) (\(AppVersion.build))")
                        if let notes = updater.releaseNotes {
                            Text("·")
                            Link(destination: notes) {
                                HStack(spacing: 2) {
                                    Text("Release notes")
                                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundStyle(SettingsColor.link)
                            }
                        }
                    }
                    .font(.system(size: 11)).foregroundStyle(SettingsColor.secondary)
                }
                Spacer(minLength: 8)
                InstallNowButton()
            }
            .padding(.vertical, 9)
            .frame(minHeight: 40)
        default:
            SettingsRow("Clausage \(AppVersion.short) (\(AppVersion.build))",
                        detail: { if case .failed(let m) = updater.status { return m } else { return nil } }()) {
                Button { updater.check() } label: {
                    BusyLabel(title: "Check for Updates…", busyTitle: "Checking…", busy: updater.status == .checking)
                }
            }
        }
    }
}

/// The primary action: quits, installs the ready update and relaunches. Native prominent button: Ember, white text.
struct InstallNowButton: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Button { updater.installNow() } label: {
            Text("Install Now")
        }
        .buttonStyle(.borderedProminent)
        .tint(SettingsColor.ember)
    }
}

/// A button label that, while busy, shows a native spinner and `busyTitle` in place of its title. It keeps at least
/// the title's width, so the button doesn't shrink.
struct BusyLabel: View {
    let title: String
    let busyTitle: String
    let busy: Bool

    var body: some View {
        ZStack {
            Text(title).opacity(busy ? 0 : 1)
            if busy {
                HStack(spacing: 5) {
                    // The native spinner draws in gray and ignores tint: lift it to white, then multiply by the button's
                    // text color.
                    ProgressView().controlSize(.small).scaleEffect(0.8)
                        .brightness(1).colorMultiply(SettingsColor.buttonText)
                    Text(busyTitle)
                }
            }
        }
        .accessibilityLabel(busy ? busyTitle : title)
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
                    Text("Clausage")
                        .font(.clausageDisplay(34)).brandTracking(-0.045, size: 34)
                        .foregroundStyle(SettingsColor.text)
                    Text("Your Claude plan limits, at a glance.")
                        .font(.system(size: 13)).foregroundStyle(SettingsColor.secondary)
                    versionLine
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SettingsSection(nil) {
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

    /// "Version 0.0.11 (10) · Up to date · Updates…": the last known update result, and a way to the Updates pane,
    /// where checking and installing live.
    private var versionLine: some View {
        HStack(spacing: 0) {
            Text("Version \(AppVersion.short) (\(AppVersion.build))")
                .font(.system(size: 12, weight: .medium, design: .monospaced)).monospacedDigit()
                .textSelection(.enabled)
            if let status = lastKnownStatus {
                Text(" · \(status)").font(.system(size: 12))
            }
            Text(" · ").font(.system(size: 12))
            Button("Updates…") { SettingsWindow.shared.show(tab: .updates) }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .foregroundStyle(SettingsColor.link)
        }
        .foregroundStyle(SettingsColor.secondary)
    }

    private var lastKnownStatus: String? {
        switch updater.status {
        case .available, .installing: return "Update available"
        default: return updater.lastChecked == nil ? nil : "Up to date"
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
