import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var model = UsageModel.shared

    var body: some Scene {
        MenuBarExtra {
            UsageView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: UsageModel
    @AppStorage("menuDisplay") private var display = "off"
    @AppStorage("tintIcon") private var tint = true
    @AppStorage("fillBase") private var fillBase = "auto"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // When the percent is tinted, or Fill's base is pinned, the image can't be a template: white rays on a dark
        // menubar, dark on a light one (Auto follows the menubar).
        let dark = fillBase == "white" || (fillBase == "auto" && scheme == .dark)
        return Image(nsImage: MenuBarIcon.image(display: MenuDisplay(rawValue: display) ?? .off,
                                                limits: model.limits, tint: tint, darkMenubar: dark,
                                                pinnedBase: fillBase != "auto"))
    }
}

// MARK: Popover

/// 220pt popover: brand header with the plan chip, the limit rows, the product line, and the footer whose timestamp
/// is the refresh button (the tally stands in for the spinner). Warm translucent Paper (Night in dark mode).
struct UsageView: View {
    @ObservedObject var model: UsageModel
    @State private var hold: RefreshHold?       // success / failure text shown after a refresh, before returning to idle
    @State private var hoveringRefresh = false
    @State private var slash = 0.0
    @ObservedObject private var updater = Updater.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var surface: Color {
        scheme == .dark ? Color(red: 36 / 255, green: 33 / 255, blue: 31 / 255).opacity(0.84)
                        : Color(red: 1, green: 252 / 255, blue: 246 / 255).opacity(0.86)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 12)
            if model.connected {
                let limits = Forecast.ordered(model.limits)
                if limits.isEmpty, model.updated != nil, model.error == nil {
                    Text("Nothing to count: your org didn’t set any plan limits.")
                        .font(.system(size: 11)).foregroundStyle(Color("Ink2")).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 10) { ForEach(limits) { UsageBar(limit: $0) } }
                productLine
                if model.activeSignedOut, let a = model.active {
                    Button("Sign in again") { model.reconnect(a) }.padding(.top, 6)
                } else if let e = model.error {
                    Text(e).font(.system(size: 10)).foregroundStyle(Color("CriticalText"))
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                }
                if let v = updater.availableVersion {
                    Button { updater.checkForUpdates() } label: {
                        Text("Update available · \(v)").font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color("EmberDeep")).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                footer.padding(.top, 10)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Not connected. Sign in to your Claude account to see your plan usage.")
                        .font(.system(size: 11)).foregroundStyle(Color("Ink2")).fixedSize(horizontal: false, vertical: true)
                    Button("Connect Claude account") { model.connect() }
                    if let e = model.error {
                        Text(e).font(.system(size: 10)).foregroundStyle(Color("CriticalText")).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack { Spacer(); gear }
                }
            }
        }
        .padding(.top, 12).padding(.horizontal, 12).padding(.bottom, 8)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(surface))
        .background(shortcuts)
        .background(PopoverWindowStyle())
        .onChange(of: model.outcome?.id) { _, _ in
            guard let o = model.outcome else { return }
            let id = o.id
            let announcement: String
            if o.ok {
                // scheduled refreshes just update the time; no success hold
                hold = o.manual ? RefreshHold(id: id, failed: false) : nil
                announcement = "Updated"
            } else {
                hold = RefreshHold(id: id, failed: true)
                announcement = "Couldn't update"
            }
            AccessibilityNotification.Announcement(announcement).post()
            guard let h = hold else { return }
            if !h.failed {
                slash = 0
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.05)) { slash = 1 }
            }
            Task {
                try? await Task.sleep(for: .seconds(h.failed ? 2.5 : 1.5))
                if hold?.id == id { hold = nil }
            }
        }
    }

    // MARK: Header and product line

    private var header: some View {
        HStack(spacing: 5) {
            BrandMark(size: 15)
            Text("clausage").font(.clausageDisplay(13)).brandTracking(-0.035, size: 13).foregroundStyle(Color("Ink"))
            Spacer(minLength: 6)
            if let plan = model.activeState?.plan {
                BrandChip(text: plan.badge, size: 9.5)
                    .accessibilityLabel("Plan: \(plan.badge)")
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "57% of this week came from Claude Code", from claude.ai's weekly split. Hidden when the field is missing.
    @ViewBuilder private var productLine: some View {
        if let top = model.activeState?.breakdown?.rows.first {
            (Text("\(Int(top.percent.rounded()))%").font(.clausagePercent(11.5)).foregroundStyle(Color("Ink"))
             + Text(" of this week came from \(top.name)").foregroundStyle(Color("Ink2")))
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 7) {
            Rectangle().fill(Color("Ink").opacity(0.12)).frame(height: 0.5)
            HStack(spacing: 4) {
                refreshLabel
                Spacer(minLength: 6)
                gear
            }
            .font(.system(size: 11))
            .lineLimit(1)
        }
    }

    private var gear: some View {
        GearMenuButton(model: model)
            .frame(width: 18, height: 18)
            .help("Settings")
    }

    /// ⌘, ⌘R ⌘Q while the popover is focused, without opening the menu.
    private var shortcuts: some View {
        Group {
            Button("") { model.closePopover(); SettingsWindow.shared.show() }.keyboardShortcut(",", modifiers: .command)
            Button("") { model.refresh(userInitiated: true) }.keyboardShortcut("r", modifiers: .command)
            Button("") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)
    }

    // MARK: Refresh label (the timestamp is the refresh button)

    private enum RefreshState { case idle, hover, updating, success, failed }

    private var refreshState: RefreshState {
        if model.loading { return .updating }
        if let h = hold { return h.failed ? .failed : .success }
        return hoveringRefresh ? .hover : .idle
    }

    private var refreshLabel: some View {
        let state = refreshState
        func layer(_ s: RefreshState) -> Double { state == s ? 1 : 0 }
        let time = model.updated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "—"
        return Button {
            guard refreshState == .hover || refreshState == .idle else { return }
            model.refresh(userInitiated: true)
        } label: {
            ZStack(alignment: .leading) {
                Text(time).foregroundStyle(Color("Ink3")).opacity(layer(.idle))
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .medium))
                    Text("Refresh now")
                }
                .foregroundStyle(Color("Ink")).opacity(layer(.hover))
                .background(Capsule().fill(Color("Sand2")).padding(.horizontal, -7).padding(.vertical, -3).opacity(layer(.hover)))
                HStack(spacing: 4) {
                    if state == .updating { TallyLoader(size: 12, interval: 0.12) } else { Tally(size: 12, filled: 0) }
                    Text("Updating…")
                }
                .foregroundStyle(Color("Ink2")).opacity(layer(.updating))
                HStack(spacing: 4) {
                    Tally(size: 12, filled: 4, slash: slash)
                    Text("Updated just now")
                }
                .foregroundStyle(Color("Ink2")).opacity(layer(.success))
                Text("Couldn't update").foregroundStyle(Color("CriticalText")).opacity(layer(.failed))
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: state)
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringRefresh = $0 }
        .modifier(HandCursor())
        .help("Refresh now (⌘R)")
        .accessibilityLabel("Refresh. Last updated \(model.updated?.formatted(date: .omitted, time: .shortened) ?? "never").")
    }
}

private struct RefreshHold: Equatable {
    let id: Int
    let failed: Bool
}

/// Pointing-hand cursor over the refresh label (macOS 15+; earlier systems keep the arrow).
private struct HandCursor: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) { content.pointerStyle(.link) } else { content }
    }
}

/// Makes the popover window look like the system menu-bar panels (Sound, Wi-Fi): the menu material,
/// blending behind the window, always active, with the window's own border, shadow and corners.
/// It reuses the window's existing background effect view when there is one, and adds one if not.
/// Also gives the window the system utility-window animation so it fades in and out like menus.
private struct PopoverWindowStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowStyleView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class WindowStyleView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.animationBehavior = .utilityWindow
            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                Self.applyMenuMaterial(to: window)
            }
        }

        private static func effectViews(in view: NSView) -> [NSVisualEffectView] {
            var found = view.subviews.flatMap(effectViews)
            if let v = view as? NSVisualEffectView { found.append(v) }
            return found
        }

        private static func applyMenuMaterial(to window: NSWindow) {
            guard let content = window.contentView else { return }
            let root = content.superview ?? content
            let existing = effectViews(in: root)
            if !existing.isEmpty {
                for v in existing { v.material = .menu; v.blendingMode = .behindWindow; v.state = .active }
                return
            }
            // No native effect view: add one behind the SwiftUI content and let it show through. It goes in the content
            // view's superview, below it; adding it inside NSHostingController.view is unsupported.
            guard let parent = content.superview else { return }
            let v = NSVisualEffectView(frame: content.frame)
            v.material = .menu; v.blendingMode = .behindWindow; v.state = .active
            v.autoresizingMask = [.width, .height]
            v.wantsLayer = true
            v.layer?.cornerRadius = 12; v.layer?.masksToBounds = true
            parent.addSubview(v, positioned: .below, relativeTo: content)
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}
