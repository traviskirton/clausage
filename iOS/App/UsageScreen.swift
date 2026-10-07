import SwiftUI
import UIKit

/// The main screen: header with the plan badge, limit rows, the weekly running total, this week by product,
/// usage credits and the footer. Pull to refresh counts the tally up; the gear opens Settings.
struct UsageScreen: View {
    @StateObject private var model = PhoneModel()
    @State private var showSignIn = false
    @State private var showSettings = false
    @State private var pull: CGFloat = 0
    @State private var restY: CGFloat?
    @State private var slash: Double = 0
    @State private var justUpdated = false
    @State private var debugScreen: String?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScreenBackground()
                if model.signedIn, SharedStore.isFree(model.snapshot) {
                    freeScreen
                } else if model.signedIn {
                    main
                } else {
                    WelcomeScreen(message: model.message) { showSignIn = true }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSettings) { SettingsScreen(model: model) }
            .navigationDestination(isPresented: Binding(get: { debugScreen != nil }, set: { if !$0 { debugScreen = nil } })) {
                switch debugScreen {
                case "privacy": PrivacyScreen(model: model)
                case "feedback": FeedbackScreen(model: model)
                default: SettingsScreen(model: model)
                }
            }
        }
        .tint(Color("Ink"))
        .sheet(isPresented: $showSignIn) {
            SignInSheet { Task { await model.refresh() } }
        }
        .task {
            #if DEBUG
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--demo-open"), i + 1 < args.count { debugScreen = args[i + 1] }
            if args.contains("--demo-welcome") { model.signedIn = false }
            #endif
            GalleryLauncher.runIfRequested()
            await model.refresh()
        }
        .onChange(of: phase) { _, p in if p == .active { Task { await model.refresh() } } }
    }

    // MARK: Main

    private var main: some View {
        let now = model.now
        let snap = model.snapshot
        return ScrollViewReader { proxy in ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { g in
                    Color.clear.preference(key: PullKey.self, value: g.frame(in: .named("usage")).minY)
                }
                .frame(height: 0)

                Color.clear.frame(height: 58)        // room for the gear, which stays put
                UsageHeader(plan: snap?.plan)
                    .padding(.bottom, 26)

                if let s = snap, s.connected, s.cleared != true {
                    content(s, now: now)
                } else {
                    loading
                }
                footer(snap)
                    .padding(.top, 26)
                    .padding(.bottom, 32)
                    .id("footer")
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            #if DEBUG
            if CommandLine.arguments.contains("--demo-bottom") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("footer", anchor: .bottom) }
            }
            #endif
        }
        }
        .coordinateSpace(name: "usage")
        .scrollIndicators(.hidden)
        .refreshable { await pullRefresh() }
        .onPreferenceChange(PullKey.self) { y in
            if restY == nil { restY = y }
            pull = max(0, y - (restY ?? y))
        }
        .overlay(alignment: .top) { statusScrim }
        .overlay(alignment: .top) { pullIndicator }
        .overlay(alignment: .topTrailing) { gear }
    }

    // MARK: Free plan

    /// Free plan: claude.ai has no usage page, so the empty tally, one sentence of why and one way forward.
    /// Pull to refresh rechecks the plan; an upgrade switches straight to the Usage screen.
    private var freeScreen: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 72)
                    VStack(spacing: 0) {
                        EmptyTally(size: 120)
                        VStack(spacing: 12) {
                            Text(FreePlanCopy.headline + ".")
                                .font(.clausageDisplay(32)).brandTracking(-0.035, size: 32)
                                .foregroundStyle(Color("Ink"))
                            Text(FreePlanCopy.bodyScreen)
                                .font(.system(size: 16)).lineSpacing(4)
                                .foregroundStyle(Color("Ink2"))
                                .frame(maxWidth: 300)
                        }
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .padding(.top, 28)
                        if let who = model.who {
                            (Text(who) + Text("  Free").fontWeight(.semibold))
                                .font(.system(size: 13)).foregroundStyle(Color("Ink"))
                                .lineLimit(1).truncationMode(.middle)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color("Sand2"), in: Capsule())
                                .padding(.top, 18)
                                .accessibilityLabel("\(who), Free plan")
                        }
                    }
                    Spacer(minLength: 40)
                    VStack(spacing: 14) {
                        Button {
                            Task { await model.signOut(); showSignIn = true }
                        } label: {
                            Text(FreePlanCopy.switchAccount)
                                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Color("Paper"))
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(Color("Ink"), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Text("Upgraded? Pull down to check again.")
                            .font(.system(size: 13)).foregroundStyle(Color("Ink3"))
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
                .frame(minHeight: geo.size.height)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.refresh() }
        }
        .overlay(alignment: .top) {
            if model.refreshing {
                VStack(spacing: 4) {
                    TallyLoader(size: 30)
                    Text("Checking…").font(.system(size: 13)).foregroundStyle(Color("Ink2"))
                }
                .padding(.top, 50)
                .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) { gear }
    }

    @ViewBuilder private func content(_ s: SharedStore.Snapshot, now: Date) -> some View {
        let limits = DisplayPrefs.visible(s.limits)
        let activeID = limits.first { $0.isActive == true }?.id
        VStack(alignment: .leading, spacing: 30) {
            if s.limits.isEmpty {
                NothingToCount().brandCard()
            } else {
                VStack(spacing: UsageSize.screen.rowGap) {
                    ForEach(limits) { l in
                        UsageRow(limit: l, now: now, size: .screen, stale: Forecast.isStale(updated: s.updated, now: now),
                                 showActiveChip: l.id == activeID, ring: Color("Paper"))
                    }
                }
                if let w = s.weekly {
                    let level = s.limits.first { $0.kind == "weekly_all" }.map(Forecast.level) ?? (w.percent >= 95 ? .critical : w.percent >= 85 ? .warning : .normal)
                    RunningTotalCard(chart: WeeklyChart.make(history: model.history, window: w, now: now), level: level, now: now)
                }
            }
            if let b = s.breakdown { ProductCard(breakdown: b) }
            if let c = s.credits { CreditsCard(credits: c) }
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            if model.refreshing || model.snapshot == nil { TallyLoader(size: 40) } else { Tally(size: 40, filled: 0) }
            Text(model.message ?? (model.refreshing || model.snapshot == nil ? "Counting your usage…" : "No data yet. Pull down to refresh."))
                .font(.system(size: 15)).foregroundStyle(model.message == nil ? Color("Ink2") : Color("CriticalText"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }

    @ViewBuilder private func footer(_ s: SharedStore.Snapshot?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s, s.connected {
                let time = justUpdated ? "Updated just now" : "Updated \(s.updated.formatted(date: .omitted, time: .shortened))"
                Text(time + (model.who.map { " · \($0)" } ?? ""))
                    .font(.system(size: 13)).foregroundStyle(Color("Ink3"))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: justUpdated)
            }
            if let m = model.message, model.snapshot?.connected == true {
                Text(m).font(.system(size: 13)).foregroundStyle(Color("CriticalText"))
            }
        }
    }

    /// Content fades out under the status bar instead of colliding with the clock.
    private var statusScrim: some View {
        GeometryReader { g in
            LinearGradient(colors: [Color("Paper"), Color("Paper").opacity(0.9), Color("Paper").opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: g.safeAreaInsets.top + 16)
                .offset(y: -g.safeAreaInsets.top)
        }
        .allowsHitTesting(false)
    }

    // MARK: Gear and pull to refresh

    private var gear: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Color("Ink"))
                .frame(width: 44, height: 44)
                .modifier(GlassCircle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.top, 6)
        .accessibilityLabel("Settings")
    }

    /// Below the gear: the tally counts up a stroke at a time as you pull; while refreshing it keeps counting;
    /// on success the Ember slash lands.
    private var pullIndicator: some View {
        let strokes = min(4, Int(pull / 22))
        let release = pull > 92
        return VStack(spacing: 4) {
            if model.refreshing {
                TallyLoader(size: 30)
            } else {
                Tally(size: 30, filled: slash > 0 ? 4 : strokes, slash: slash)
            }
            Text(model.refreshing ? "Counting…" : (slash > 0 ? "Updated" : (release ? "Release to refresh" : "Pull to refresh")))
                .font(.system(size: 13)).foregroundStyle(Color("Ink2"))
        }
        .padding(.top, 50)
        .opacity(model.refreshing || slash > 0 ? 1 : min(1, Double(pull) / 50))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func pullRefresh() async {
        let ok = await model.refresh()
        guard ok else { return }
        withAnimation(.easeOut(duration: 0.35)) { slash = 1 }
        UIAccessibility.post(notification: .announcement, argument: "Updated")
        justUpdated = true
        try? await Task.sleep(for: .milliseconds(650))
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            slash = 0
            try? await Task.sleep(for: .seconds(2))
            justUpdated = false
        }
    }
}

private struct PullKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Paper → Paper 2, top to bottom.
struct ScreenBackground: View {
    var body: some View {
        LinearGradient(colors: [Color("Paper"), Color("Paper2")], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// A 44pt glass circle on iOS 26, a material circle before that.
struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}
