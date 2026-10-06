import SwiftUI
import MessageUI
import PhotosUI
import UIKit

enum Feedback {
    /// Where feedback goes: the developer. Sent from the user's own Mail app; Clausage has no server.
    static let address = "travis@postfl.com"
    static let maxLength = 2000

    enum Kind: String, CaseIterable, Identifiable {
        case bug = "Bug", idea = "Idea", wrongNumbers = "Wrong numbers"
        var id: String { rawValue }
    }
}

/// Bug / Idea / Wrong numbers, a message, the current Usage screen attached (removable), opt-in diagnostics and usage
/// snapshot (with a preview), and an optional reply-to address. Sent with Mail; after it's sent the slash lands.
struct FeedbackScreen: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss

    @State private var kind: Feedback.Kind = .bug
    @State private var text = ""
    /// Opt-in, as the Privacy screen promises.
    @State private var diagnostics = false
    /// On for "Wrong numbers" (that's what it's for), off otherwise; always the user's choice.
    @State private var usageSnapshot = false
    @State private var replyTo = true
    @State private var screenshot: UIImage?
    @State private var extraImages: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var composing = false
    @State private var thanks = false
    @State private var slash = 0.0
    @State private var mailUnavailable = false
    @FocusState private var editing: Bool

    private var email: String? { model.snapshot?.email }

    var body: some View {
        ZStack {
            form
            if thanks { thanksView.transition(.opacity) }
        }
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { send() } label: {
                    Text("Send").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color("Paper"))
                        .padding(.horizontal, 16).frame(height: 36)
                        .background(Color("Ink"), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
        }
        .sheet(isPresented: $composing) {
            MailComposer(to: Feedback.address, subject: "Clausage feedback: \(kind.rawValue)", body: composedBody,
                         attachments: attachments) { sent in
                composing = false
                if sent { showThanks() }
            }
            .ignoresSafeArea()
        }
        .alert("Mail isn’t set up", isPresented: $mailUnavailable) {
            Button("Open Mail Draft") { openMailto() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clausage sends feedback with Mail. You can open a plain draft instead; screenshots aren’t included.")
        }
        .task { if screenshot == nil { screenshot = UsageScreenshot.render(model: model) } }
        .onChange(of: kind) { _, k in usageSnapshot = (k == .wrongNumbers) }
        .onChange(of: pickerItems) { _, items in
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { images.append(img) }
                }
                extraImages = images
            }
        }
    }

    private var form: some View {
        List {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(Feedback.Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                if kind == .wrongNumbers {
                    Text("If claude.ai shows the same numbers, that’s Claude’s limit, not a Clausage bug.")
                }
            }

            Section {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder).foregroundStyle(Color("Ink3")).padding(.top, 8).padding(.leading, 5)
                    }
                    TextEditor(text: $text)
                        .focused($editing)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .onChange(of: text) { _, t in if t.count > Feedback.maxLength { text = String(t.prefix(Feedback.maxLength)) } }
                }
                HStack { Spacer(); Text(verbatim: "\(text.count) / \(Feedback.maxLength)").font(.system(size: 12)).foregroundStyle(Color("Ink3")) }
            }
            .listRowBackground(Color("Cell"))

            Section {
                HStack(spacing: 12) {
                    if let screenshot {
                        thumbnail(screenshot) { self.screenshot = nil }
                    }
                    ForEach(Array(extraImages.enumerated()), id: \.offset) { i, img in
                        thumbnail(img) { extraImages.remove(at: i); if i < pickerItems.count { pickerItems.remove(at: i) } }
                    }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 3, matching: .images) {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Color("Ink3").opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: 64, height: 88)
                            .overlay(Image(systemName: "plus").foregroundStyle(Color("Ink3")))
                    }
                    .accessibilityLabel("Add a screenshot")
                    Spacer()
                }
                .padding(.vertical, 4)
            } header: {
                SectionTitle("Screenshot")
            } footer: {
                Text("Your current Usage screen is attached by default. Remove it if you’d rather not.")
            }
            .listRowBackground(Color("Cell"))

            Section {
                Toggle(isOn: $diagnostics) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostics")
                        Text("App and iOS version, last refresh time and result, and which limits failed to parse.")
                            .font(.system(size: 13)).foregroundStyle(Color("Ink2"))
                    }
                }
                NavigationLink("Preview What’s Sent") { FeedbackPreview(text: composedBody) }
                Toggle(isOn: $usageSnapshot) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usage snapshot")
                        Text("The percentages and reset times on screen right now. Helps check “wrong numbers”.")
                            .font(.system(size: 13)).foregroundStyle(Color("Ink2"))
                    }
                }
            } header: { SectionTitle("Include") }
            .listRowBackground(Color("Cell"))

            if let email {
                Section {
                    Toggle("Reply to \(email)", isOn: $replyTo)
                } footer: {
                    Text("Goes to the developer, not to Anthropic. No account details or chats are ever included.")
                }
                .listRowBackground(Color("Cell"))
            } else {
                Section {} footer: {
                    Text("Goes to the developer, not to Anthropic. No account details or chats are ever included.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color("Grouped").ignoresSafeArea())
        .tint(Color("Ink"))
        .scrollDismissesKeyboard(.interactively)
    }

    private var placeholder: String {
        switch kind {
        case .bug: return "What happened, and what did you expect?"
        case .idea: return "What would make Clausage better?"
        case .wrongNumbers: return "Which number looks wrong, and what does claude.ai show?"
        }
    }

    private func thumbnail(_ img: UIImage, remove: @escaping () -> Void) -> some View {
        Image(uiImage: img).resizable().scaledToFill()
            .frame(width: 64, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color("Hairline")))
            .overlay(alignment: .topTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color("Ink"))
                }
                .offset(x: 8, y: -8)
                .accessibilityLabel("Remove screenshot")
            }
    }

    // MARK: What's sent

    private var composedBody: String {
        var parts = [text.trimmingCharacters(in: .whitespacesAndNewlines)]
        parts.append("— Type: \(kind.rawValue)")
        if replyTo, let email { parts.append("— Reply to: \(email)") }
        if diagnostics { parts.append("— Diagnostics\n" + FeedbackDiagnostics.text(model: model)) }
        if usageSnapshot { parts.append("— Usage snapshot\n" + FeedbackDiagnostics.usage(model.snapshot)) }
        return parts.joined(separator: "\n\n")
    }

    private var attachments: [UIImage] { (screenshot.map { [$0] } ?? []) + extraImages }

    private func send() {
        editing = false
        if MailComposer.canSend { composing = true } else { mailUnavailable = true }
    }

    private func openMailto() {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = Feedback.address
        c.queryItems = [URLQueryItem(name: "subject", value: "Clausage feedback: \(kind.rawValue)"),
                        URLQueryItem(name: "body", value: composedBody)]
        if let url = c.url { UIApplication.shared.open(url) { ok in if ok { showThanks() } } }
    }

    private func showThanks() {
        withAnimation(.easeInOut(duration: 0.2)) { thanks = true }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.35)) { slash = 1 }
            try? await Task.sleep(for: .milliseconds(1400))
            dismiss()
        }
    }

    private var thanksView: some View {
        VStack(spacing: 12) {
            Tally(size: 72, filled: 4, slash: slash)
            Text("Thanks, got it.").font(.system(size: 22, weight: .semibold)).foregroundStyle(Color("Ink"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Grouped").ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }
}

/// Exactly what goes into the email body.
struct FeedbackPreview: View {
    let text: String
    var body: some View {
        ScrollView {
            Text(text).font(.system(size: 14, design: .monospaced)).foregroundStyle(Color("Ink"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .textSelection(.enabled)
        }
        .background(Color("Grouped").ignoresSafeArea())
        .navigationTitle("What’s Sent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
    }
}

enum FeedbackDiagnostics {
    @MainActor static func text(model: PhoneModel) -> String {
        let device = UIDevice.current
        var lines = ["Clausage \(AppInfo.version), \(device.systemName) \(device.systemVersion), \(device.model)"]
        if let s = model.snapshot {
            lines.append("Last refresh: \(s.updated.formatted(date: .abbreviated, time: .shortened)) (\(model.lastResult ?? "not this session"))")
            let failed = s.unparsedLimits ?? []
            lines.append("Limits that failed to parse: \(failed.isEmpty ? "none" : failed.joined(separator: ", "))")
            lines.append("Plan: \(s.plan?.badge ?? "unknown")")
        } else {
            lines.append("No usage fetched yet")
        }
        lines.append("Background refresh: \(PhonePrefs.backgroundRefresh ? "on" : "off")")
        return lines.joined(separator: "\n")
    }

    static func usage(_ s: SharedStore.Snapshot?) -> String {
        guard let s, !s.limits.isEmpty else { return "No limits on screen" }
        var lines = Forecast.ordered(s.limits).map { l -> String in
            var line = "\(Forecast.fullName(l)) \(Int(l.percent.rounded()))%"
            if let r = l.resetsAt { line += ", resets \(r.formatted(.dateTime.weekday(.abbreviated).hour().minute()))" }
            if l.isActive == true { line += " (limiting now)" }
            return line
        }
        if let b = s.breakdown { lines.append("This week: " + b.rows.map { "\($0.name) \(Int($0.percent.rounded()))%" }.joined(separator: ", ")) }
        lines.append("As of \(s.updated.formatted(date: .abbreviated, time: .shortened))")
        return lines.joined(separator: "\n")
    }
}

/// A still image of the Usage screen's top (header and limit rows) for the feedback attachment.
enum UsageScreenshot {
    @MainActor static func render(model: PhoneModel) -> UIImage? {
        guard let s = model.snapshot, s.connected, !s.limits.isEmpty else { return nil }
        let now = model.now
        let limits = DisplayPrefs.visible(s.limits)
        let activeID = limits.first { $0.isActive == true }?.id
        let view = VStack(alignment: .leading, spacing: 0) {
            UsageHeader(plan: s.plan).padding(.bottom, 24)
            VStack(spacing: UsageSize.screen.rowGap) {
                ForEach(limits) { UsageRow(limit: $0, now: now, size: .screen, showActiveChip: $0.id == activeID, ring: Color("Paper")) }
            }
            if let b = s.breakdown, let top = b.rows.first {
                Text("\(Int(top.percent.rounded()))% of this week came from \(top.name)")
                    .font(.system(size: 15)).foregroundStyle(Color("Ink2")).padding(.top, 24)
            }
            Text("Updated \(s.updated.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 13)).foregroundStyle(Color("Ink3")).padding(.top, 16)
        }
        .padding(24)
        .frame(width: 390, alignment: .leading)
        .background(LinearGradient(colors: [Color("Paper"), Color("Paper2")], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .light)
        let r = ImageRenderer(content: view)
        r.scale = 2
        return r.uiImage
    }
}

/// Mail's compose sheet.
struct MailComposer: UIViewControllerRepresentable {
    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    let to: String
    let subject: String
    let body: String
    let attachments: [UIImage]
    let done: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([to])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        for (i, img) in attachments.enumerated() {
            if let data = img.pngData() { vc.addAttachmentData(data, mimeType: "image/png", fileName: "clausage-\(i + 1).png") }
        }
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let done: (Bool) -> Void
        init(done: @escaping (Bool) -> Void) { self.done = done }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            done(result == .sent)
        }
    }
}
