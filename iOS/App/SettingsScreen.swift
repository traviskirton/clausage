import SwiftUI
import StoreKit
import WidgetKit
import UserNotifications

/// Opened from the gear: brand header, then a native grouped list on the warm background with Ink switches.
struct SettingsScreen: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.requestReview) private var requestReview
    @Environment(\.dismiss) private var dismiss

    @State private var near = PhonePrefs.notifyNear
    @State private var critical = PhonePrefs.notifyCritical
    @State private var runout = PhonePrefs.notifyRunout
    @State private var resets = PhonePrefs.notifyResets
    @State private var paceTick = DisplayPrefs.showPaceTick
    @State private var background = PhonePrefs.backgroundRefresh
    @State private var notificationsDenied = false

    private var limits: [UsageLimit] { Forecast.ordered(model.snapshot?.limits ?? []) }
    private var shownCount: Int { DisplayPrefs.visible(model.snapshot?.limits ?? []).count }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    AppIconView(size: 76)
                    Wordmark(size: 30)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.who ?? "Signed in").font(.system(size: 17)).foregroundStyle(Color("Ink"))
                        Text("Signed in through claude.ai").font(.system(size: 13)).foregroundStyle(Color("Ink2"))
                    }
                    Spacer()
                    if let plan = model.snapshot?.plan {
                        Text(plan.badge).font(.system(size: 17)).foregroundStyle(Color("Ink2"))
                    }
                }
                Button("Sign Out", role: .destructive) {
                    Task { await model.signOut(); dismiss() }
                }
                .foregroundStyle(Color("CriticalText"))
            } header: { SectionTitle("Account") }

            Section {
                toggle("Near limit", "When a limit reaches 85%", $near) { PhonePrefs.notifyNear = $0 }
                toggle("Critical", "When a limit reaches 95%", $critical) { PhonePrefs.notifyCritical = $0 }
                toggle("Runout forecast", "Only if you’ll run out before it resets", $runout) { PhonePrefs.notifyRunout = $0 }
                toggle("Limit resets", nil, $resets) { PhonePrefs.notifyResets = $0 }
            } header: {
                SectionTitle("Notifications")
            } footer: {
                if notificationsDenied {
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
                toggle("Pace tick", "Marks how much of the window has passed", $paceTick) {
                    DisplayPrefs.showPaceTick = $0
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } header: { SectionTitle("Limits") }

            Section {
                toggle("Refresh in background", nil, $background) {
                    PhonePrefs.backgroundRefresh = $0
                    ClaudeUsageiOSApp.scheduleRefresh()
                }
            } header: {
                SectionTitle("Widgets")
            } footer: {
                Text("iOS decides when widgets update, usually every 15–30 minutes. Tap a widget’s ↻ to update now.")
            }

            Section {
                NavigationLink("Send Feedback") { FeedbackScreen(model: model) }
                NavigationLink("Privacy") { PrivacyScreen(model: model) }
                Button { requestReview() } label: {
                    HStack {
                        Text("Rate Clausage").foregroundStyle(Color("Ink"))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                }
            }

            Section {
                VStack(spacing: 10) {
                    Tally(size: 28, filled: 4, slash: 1)
                    Text("Clausage \(AppInfo.version) · An independent app, not made by or affiliated with Anthropic.")
                        .font(.system(size: 12)).foregroundStyle(Color("Ink3"))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color("Grouped").ignoresSafeArea())
        .tint(Color("Ink"))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .task { await checkPermission() }
    }

    private func toggle(_ title: String, _ detail: String?, _ value: Binding<Bool>, _ apply: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
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

    private func checkPermission() async {
        notificationsDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
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
    /// "0.0.4 (3)".
    static var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "?") (\(i?["CFBundleVersion"] as? String ?? "?"))"
    }
}
