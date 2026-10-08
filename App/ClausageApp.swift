import SwiftUI

@main
struct ClausageApp: App {
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
                                                pinnedBase: fillBase != "auto", free: model.activeIsFree))
    }
}

// MARK: Popover

/// Popover colors: the warm translucent Paper gradient over the menu material. The plan chip's quiet tint is
/// `PopoverChip` / `PopoverChipText` in the asset catalog.
enum PopoverColor {
    static let top = SettingsColor.dynamic(0xFFFCF6, 0.95, dark: 0x2A2624, 0.92)
    static let bottom = SettingsColor.dynamic(0xF6EFE3, 0.95, dark: 0x1F1D1B, 0.92)
}

/// 220pt popover: the title row with the plan chip, the limit rows, and the footer whose timestamp is the refresh
/// button (the tally stands in for the spinner). The product split lives in Settings → Usage.
struct UsageView: View {
    @ObservedObject var model: UsageModel
    @State private var hold: RefreshHold?       // success / failure text shown after a refresh, before returning to idle
    @State private var hoveringRefresh = false
    @State private var slash = 0.0
    @ObservedObject private var updater = Updater.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 12)
            if model.connected, model.activeIsFree {
                freeBody
                footer.padding(.top, 12)
            } else if model.connected {
                let limits = Forecast.ordered(model.limits)
                if limits.isEmpty, model.updated != nil, model.error == nil {
                    Text("Nothing to count: your org didn’t set any plan limits.")
                        .font(.system(size: 11)).foregroundStyle(Color("Ink2")).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 12) { ForEach(limits) { UsageBar(limit: $0) } }
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
                footer.padding(.top, 12)
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
        .padding(.top, 12).padding(.horizontal, 12).padding(.bottom, 9)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [PopoverColor.top, PopoverColor.bottom], startPoint: .top, endPoint: .bottom)))
        .background(shortcuts)
        .background(PopoverWindowStyle())
        .onChangeCompat(of: model.outcome?.id) { _ in
            guard let o = model.outcome else { return }
            let id = o.id
            let announcement: String
            if o.ok {
                // scheduled refreshes just update the time; no success hold. On Free it goes straight back to "Checked".
                hold = o.manual && !model.activeIsFree ? RefreshHold(id: id, failed: false) : nil
                announcement = model.activeIsFree ? "Checked" : "Updated"
            } else {
                hold = RefreshHold(id: id, failed: true)
                announcement = "Couldn't update"
            }
            announce(announcement)
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

    // MARK: Free plan

    /// claude.ai has no usage page on Free: the empty tally, one line of why, and one way forward.
    private var freeBody: some View {
        VStack(spacing: 6) {
            EmptyTally(size: 40)
            VStack(spacing: 6) {
                Text(FreePlanCopy.headline).font(.clausageDisplay(15)).brandTracking(-0.03, size: 15).foregroundStyle(Color("Ink"))
                Text(FreePlanCopy.bodyShort).font(.system(size: 11)).lineSpacing(2).foregroundStyle(Color("Ink2"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            if let a = model.active {
                Button { model.closePopover(); model.switchAccount(from: a) } label: {
                    Text(FreePlanCopy.switchAccount).font(.system(size: 11, weight: .medium)).foregroundStyle(Color("EmberDeep"))
                }
                .buttonStyle(.plain)
                .modifier(HandCursor())
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.horizontal, 4).padding(.bottom, 4)
    }

    // MARK: Title row

    /// The rays-and-halo mark, "Clausage" in Bricolage, and the plan chip.
    private var header: some View {
        HStack(spacing: 5) {
            BrandMark(size: 18)
            Text("Clausage").font(.clausageDisplay(15)).brandTracking(-0.035, size: 15).foregroundStyle(Color("Ink"))
            Spacer(minLength: 6)
            if let plan = model.activeState?.plan {
                Text(plan.badge)
                    .font(.clausageDisplay(10.5))
                    .foregroundStyle(Color("PopoverChipText"))
                    .padding(.top, 3).padding(.bottom, 4).padding(.horizontal, 7)
                    .background(Color("PopoverChip"), in: Capsule())
                    .lineLimit(1).fixedSize()
                    .accessibilityLabel("Plan: \(plan.badge)")
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 7) {
            Rectangle().fill(Color("Hairline")).frame(height: 0.5)
            HStack(spacing: 4) {
                refreshLabel
                Spacer(minLength: 6)
                gear
            }
            .font(.system(size: 10.5))
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
        let verb = model.activeIsFree ? "Checked" : "Updated"
        let time = model.updated.map { "\(verb) \($0.formatted(date: .omitted, time: .shortened))" } ?? "—"
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
        .accessibilityLabel(model.activeIsFree
            ? "Check again. Last checked \(model.updated?.formatted(date: .omitted, time: .shortened) ?? "never")."
            : "Refresh. Last updated \(model.updated?.formatted(date: .omitted, time: .shortened) ?? "never").")
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
