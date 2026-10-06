import SwiftUI

/// A plain-language summary. Every line here has to be true of this build:
/// - Network: only claude.ai (usage, org list, account email, usage credits). No analytics, ads or tracking SDKs.
/// - The session is in the Keychain as this-device-only (`SessionStore`), never synced.
/// - Usage, weekly history and settings live in the App Group, shared with the widgets.
/// - Feedback leaves only through the user's own Mail app, with diagnostics opt-in and previewable.
struct PrivacyScreen: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var cleared = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your usage stays yours.").font(.clausageDisplay(30)).brandTracking(-0.035, size: 30)
                        .foregroundStyle(Color("Ink"))
                    Text("Clausage has no servers. It talks to claude.ai, and nothing else.")
                        .font(.system(size: 17)).foregroundStyle(Color("Ink2"))
                    HStack(spacing: 8) {
                        ForEach(["No analytics", "No ads", "No tracking"], id: \.self) { tag in
                            Text(tag).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color("Ink"))
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(Color("Cell"), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color("Hairline")))
                        }
                    }
                    .padding(.top, 2)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
            }

            Section {
                item(true, "Limit percentages and reset times")
                item(true, "Plan, usage credits and the weekly split")
                item(true, "Your email", "So you can tell which account is signed in.")
            } header: { SectionTitle("What it reads") }

            Section {
                item(false, "Your chats, prompts or files")
                item(false, "Your password", "You sign in on claude.ai. Clausage only keeps the session it hands back.")
                item(false, "Payment details")
            } header: { SectionTitle("What it never reads") }

            Section {
                kept("Sign-in session", "Keychain", "This iPhone only. Never synced or backed up.")
                kept("Latest usage", "App Group", "Shared with your widgets. Replaced on every refresh.")
                kept("Weekly history", "App Group", "This week’s and last week’s running total, recorded on this iPhone for the chart.")
            } header: { SectionTitle("Where it’s kept") }

            Section {
                item(false, "Nothing, unless you send feedback", "Diagnostics are opt-in, and you can preview them before sending.")
            } header: { SectionTitle("What leaves your phone") }

            Section {
                Button {
                    model.clearCachedUsage()
                    cleared = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cleared ? "Cached Usage Cleared" : "Clear Cached Usage").foregroundStyle(Color("Ink"))
                        Text("Widgets show “No data” until the next refresh.").font(.system(size: 13)).foregroundStyle(Color("Ink2"))
                    }
                }
                .disabled(cleared)
                Button("Sign Out and Delete Everything", role: .destructive) { confirmDelete = true }
                    .foregroundStyle(Color("CriticalText"))
            }
            .listRowBackground(Color("Cell"))

            Section {} footer: {
                Text("Clausage isn’t affiliated with Anthropic. claude.ai is covered by Anthropic’s own privacy policy.")
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color("Grouped").ignoresSafeArea())
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .confirmationDialog("Sign out and delete everything?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Sign Out and Delete Everything", role: .destructive) {
                Task { await model.deleteEverything(); dismiss() }
            }
        } message: {
            Text("Removes your session, cached usage, weekly history and settings from this iPhone.")
        }
    }

    private func item(_ yes: Bool, _ title: String, _ detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: yes ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color("Ink2"))
                .frame(width: 20, height: 20)
                .background(Color("Sand2"), in: Circle())
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17)).foregroundStyle(Color("Ink"))
                if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(Color("Ink2")) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((yes ? "Reads: " : "Never: ") + title + (detail.map { ". \($0)" } ?? ""))
        .listRowBackground(Color("Cell"))
    }

    private func kept(_ title: String, _ tag: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 17)).foregroundStyle(Color("Ink"))
                Spacer()
                BrandChip(text: tag, size: 12)
            }
            Text(detail).font(.system(size: 13)).foregroundStyle(Color("Ink2"))
        }
        .accessibilityElement(children: .combine)
        .listRowBackground(Color("Cell"))
    }
}
