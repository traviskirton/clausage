import SwiftUI
import StoreKit
import WidgetKit
import UserNotifications

/// Opened from the gear: the current app icon and wordmark, then a native grouped list on the warm background with Ink
/// switches (design handoff: iOS Settings v2).
struct SettingsScreen: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var near = PhonePrefs.notifyNear
    @State private var critical = PhonePrefs.notifyCritical
    @State private var runout = PhonePrefs.notifyRunout
    @State private var resets = PhonePrefs.notifyResets
    @State private var paceTick = DisplayPrefs.showPaceTick
    @State private var background = PhonePrefs.backgroundRefresh
    @State private var notificationsDenied = false
    @State private var icon = AppIcon.current
    @State private var confirmSignOut = false
    @AppStorage(HistoryRetention.key, store: SharedStore.defaults) private var keepWeeks = HistoryRetention.standard
    @State private var composingFeedback = false

    private var limits: [UsageLimit] { Forecast.ordered(model.snapshot?.limits ?? []) }
    private var free: Bool { SharedStore.isFree(model.snapshot) }
    private var shownCount: Int { DisplayPrefs.visible(model.snapshot?.limits ?? []).count }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section {
            } header: {
                VStack(spacing: 10) {
                    Image(icon.preview).resizable().frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .accessibilityHidden(true)
                    Wordmark(size: 26)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .textCase(nil)
            }

            if let sample = model.snapshot?.sample {
                Section {
                    Picker("Scenario", selection: Binding(get: { sample }, set: { model.startSample($0) })) {
                        ForEach(SampleData.pickable) { Text($0.name).tag($0.id) }
                    }
                    .listRowBackground(Color("Cell"))
                    Button("Exit Sample Mode", role: .destructive) { model.stopSample(); dismiss() }
                        .foregroundStyle(Color("CriticalText"))
                        .listRowBackground(Color("Cell"))
                } header: {
                    SectionTitle("Sample data")
                } footer: {
                    Text("Made-up numbers that show how Clausage works, with nothing from a real account. Exit to sign in with yours.")
                }
            } else {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.who ?? "Signed in").font(.system(size: 17)).foregroundStyle(Color("Ink"))
                            Text("Signed in through claude.ai").font(.system(size: 13)).foregroundStyle(Color("Ink2"))
                        }
                        Spacer()
                        if let plan = model.snapshot?.plan {
                            Text(plan.badge).font(.system(size: 17)).foregroundStyle(Color("Ink2"))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    Button("Sign Out", role: .destructive) { confirmSignOut = true }
                        .foregroundStyle(Color("CriticalText"))
                        .confirmationDialog("Sign out of claude.ai?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                            Button("Sign Out", role: .destructive) { Task { await model.signOut(); dismiss() } }
                        } message: {
                            Text("Clausage stops counting until you sign in again.")
                        }
                } header: { SectionTitle("Account") }
            }

            Section {
                // Free: nothing to alert on. Disabled (not just faded); saved choices are kept for later.
                // Runout forecast is last, so the example below sits right under it.
                Group {
                    toggle("Getting full", "When a limit reaches 85%", $near) { PhonePrefs.notifyNear = $0 }
                    toggle("Last bites", "When a limit reaches 95%", $critical) { PhonePrefs.notifyCritical = $0 }
                    toggle("Seconds are served", "When a limit resets", $resets) { PhonePrefs.notifyResets = $0 }
                    toggle("Runout forecast", "Only if you’ll run out before it resets", $runout) { PhonePrefs.notifyRunout = $0 }
                }
                .disabled(free)
                .opacity(free ? 0.45 : 1)
            } header: {
                SectionTitle("Notifications")
            } footer: {
                if free {
                    Text("Limit alerts come back on Pro or Max.")
                } else if notificationsDenied {
                    Text("Notifications are off for Clausage in iOS Settings, so these won’t arrive.")
                } else {
                    Text("Example: “At this pace you’ll reach the All models limit Mon 9:40 PM.”")
                }
            }

            Section {
                NavigationLink {
                    LimitsScreen(limits: limits)
                } label: {
                    LabeledContent("Shown in app and widgets") {
                        Text("\(shownCount) of \(limits.count)")
                    }
                }
                .disabled(limits.isEmpty)
                .listRowBackground(Color("Cell"))
                toggle("Pace tick", "Shows if you’re ahead of an even pace", $paceTick) {
                    DisplayPrefs.showPaceTick = $0
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } header: { SectionTitle("Limits") }

            Section {
                Picker("Keep history", selection: $keepWeeks) {
                    ForEach(HistoryRetention.options, id: \.weeks) { Text($0.label).tag($0.weeks) }
                }
                .foregroundStyle(Color("Ink"))
                .listRowBackground(Color("Cell"))
            } header: {
                SectionTitle("History")
            } footer: {
                Text("Hourly All models readings. They stay on this iPhone, and signing out deletes them.")
            }

            Section {
                IconPicker(selection: $icon)
                    .listRowBackground(Color("Cell"))
                    .id("icons")
            } header: { SectionTitle("App icon") }

            Section {
                toggle("Refresh in background", nil, $background) {
                    PhonePrefs.backgroundRefresh = $0
                    ClausageiOSApp.scheduleRefresh()
                }
            } header: {
                SectionTitle("Widgets")
            } footer: {
                Text("iOS decides when widgets update, usually every 15–30 minutes. Tap a widget’s ↻ to update now.")
            }

            Section {
                OutsideRow(title: "Send Feedback") { sendFeedback() }
                OutsideRow(title: "Rate Clausage") { rate() }
                OutsideRow(title: "Privacy") { openURL(AppInfo.privacyURL) }
                NavigationLink("Acknowledgements") { AcknowledgementsScreen() }
                    .foregroundStyle(Color("Ink"))
                    .listRowBackground(Color("Cell"))
                    .id("support")
            } header: { SectionTitle("Support") }

            Section {
            } footer: {
                VStack(spacing: 10) {
                    Tally(size: 36, filled: 4, slash: 1)
                    Text("An independent app, not made by or affiliated with Anthropic.")
                        .frame(maxWidth: 300)
                    Text("Clausage \(AppInfo.version)").monospacedDigit()
                }
                .font(.system(size: 13)).foregroundStyle(Color("Ink3"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            }
        }
        #if DEBUG
        .onAppear {
            // `--demo-scroll icons|support`: screenshots of the lower groups.
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--demo-scroll"), i + 1 < args.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo(args[i + 1], anchor: .center) }
            }
        }
        #endif
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color("Grouped").ignoresSafeArea())
        .tint(Color("Ink"))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.navigationStack)
        .task { await checkPermission() }
        .sheet(isPresented: $composingFeedback) {
            MailComposer(to: Feedback.address, subject: "Clausage feedback", body: feedbackBody, attachments: []) { _ in
                composingFeedback = false
            }
            .ignoresSafeArea()
        }
    }

    private func toggle(_ title: String, _ detail: String?, _ value: Binding<Bool>, _ apply: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17)).foregroundStyle(Color("Ink"))
                if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(Color("Ink2")) }
            }
        }
        .onChange(of: value.wrappedValue) { _, on in
            apply(on)
            if on { Task { await PhoneNotifier.requestAuthorization(); await checkPermission() } }
        }
        .listRowBackground(Color("Cell"))
    }

    /// Room to write, then the version and device so a bug report has its context.
    private var feedbackBody: String {
        let device = UIDevice.current
        return "\n\n—\nClausage \(AppInfo.version), \(device.systemName) \(device.systemVersion)"
    }

    private func sendFeedback() {
        if MailComposer.canSend { composingFeedback = true; return }
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = Feedback.address
        c.queryItems = [URLQueryItem(name: "subject", value: "Clausage feedback"), URLQueryItem(name: "body", value: feedbackBody)]
        if let url = c.url { openURL(url) }
    }

    /// The App Store's write-a-review page once the app has a store ID; until then, the in-app review prompt.
    private func rate() {
        if let url = AppInfo.writeReviewURL { openURL(url) } else { requestReview() }
    }

    private func checkPermission() async {
        notificationsDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}

/// A Support row that leaves the app: the title, then ↗ in the tertiary label color.
private struct OutsideRow: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Color("Ink"))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens outside Clausage")
        .listRowBackground(Color("Cell"))
    }
}

// MARK: App icon

/// Fresh is the primary icon; Smoked and Grilled are alternates (`AppIcon-Smoked.icon`, `AppIcon-Grilled.icon`).
enum AppIcon: String, CaseIterable, Identifiable {
    case fresh, smoked, grilled
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    /// `nil` is the primary icon.
    var alternateName: String? { self == .fresh ? nil : "AppIcon-\(name)" }
    /// Light render of the `.icon` (`tools/make-icon-previews.sh`); `UIImage(named:)` can't load app icons.
    var preview: String { "IconPreview-\(name)" }

    @MainActor static var current: AppIcon {
        allCases.first { $0.alternateName == UIApplication.shared.alternateIconName } ?? .fresh
    }
}

/// Three tiles in one standard row: 64pt icons, the selected one ringed in Ink.
struct IconPicker: View {
    @Binding var selection: AppIcon

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(AppIcon.allCases) { icon in
                let selected = icon == selection
                Button { choose(icon) } label: {
                    VStack(spacing: 8) {
                        Image(icon.preview).resizable().frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .padding(5.5)       // 3pt gap + the 2.5pt ring
                            .overlay(RoundedRectangle(cornerRadius: 20.5, style: .continuous)
                                .strokeBorder(selected ? Color("Ink") : .clear, lineWidth: 2.5))
                        Text(icon.name).font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color("Ink") : Color("Ink2"))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(icon.name) app icon")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func choose(_ icon: AppIcon) {
        guard icon != selection, UIApplication.shared.supportsAlternateIcons else { return }
        let previous = selection
        selection = icon
        UIApplication.shared.setAlternateIconName(icon.alternateName) { error in
            if error != nil { Task { @MainActor in selection = previous } }
        }
    }
}

// MARK: Acknowledgements

/// Open-source work bundled in the app. On iPhone that's the typeface.
struct AcknowledgementsScreen: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    LicenseScreen(title: "Bricolage Grotesque", text: Self.ofl)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Bricolage Grotesque").font(.system(size: 17)).foregroundStyle(Color("Ink"))
                        Text("By Mathieu Triay · SIL Open Font License 1.1").font(.system(size: 13)).foregroundStyle(Color("Ink2"))
                    }
                }
                .listRowBackground(Color("Cell"))
            } header: {
                SectionTitle("Type")
            } footer: {
                Text("The clausage wordmark, every headline and every percentage.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color("Grouped").ignoresSafeArea())
        .tint(Color("Ink"))
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
    }

    /// The license file bundled with the font.
    static var ofl: String {
        Bundle.main.url(forResource: "BricolageGrotesque-OFL", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "SIL Open Font License 1.1, https://openfontlicense.org"
    }
}

struct LicenseScreen: View {
    let title: String
    let text: String
    var body: some View {
        ScrollView {
            Text(text).font(.system(size: 13, design: .monospaced)).foregroundStyle(Color("Ink"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .textSelection(.enabled)
        }
        .background(Color("Grouped").ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
    }
}

/// Which limits show in the app and widgets. At least one stays on.
struct LimitsScreen: View {
    let limits: [UsageLimit]
    @State private var hidden = DisplayPrefs.hiddenLimits

    var body: some View {
        List {
            Section {
                ForEach(limits) { l in
                    let name = Forecast.shortName(l)
                    let shown = !hidden.contains(name)
                    Toggle(Forecast.fullName(l), isOn: Binding(
                        get: { shown },
                        set: { on in
                            if on { hidden.remove(name) } else { hidden.insert(name) }
                            DisplayPrefs.hiddenLimits = hidden
                            WidgetCenter.shared.reloadAllTimelines()
                        }))
                    .disabled(shown && limits.count - hidden.count <= 1)
                    .listRowBackground(Color("Cell"))
                }
            } footer: {
                Text("Hidden limits stay off the Usage screen and the Home Screen widgets. Lock Screen gauges still show the limit you pick.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color("Grouped").ignoresSafeArea())
        .tint(Color("Ink"))
        .navigationTitle("Limits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
    }
}

/// Grouped-list section header: sentence case, 13 semibold, Ink 2.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).textCase(nil).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color("Ink2"))
    }
}

enum AppInfo {
    static let privacyURL = URL(string: "https://clausage.ai/privacy/")!
    /// The iOS app's Apple ID in App Store Connect (App Information).
    static let appStoreID: String? = "6819942596"
    static var writeReviewURL: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)?action=write-review") }
    }

    /// "0.0.4 (3)".
    static var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "?") (\(i?["CFBundleVersion"] as? String ?? "?"))"
    }
}
