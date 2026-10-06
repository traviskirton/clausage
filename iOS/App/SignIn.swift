import SwiftUI
import WebKit

/// claude.ai sign-in inside the app. When the `sessionKey` cookie shows up and the API accepts it, the session is saved to the
/// shared Keychain and `onSignedIn` fires. The web view's own cookies are only a means to get there; refreshes use the Keychain copy.
struct ClaudeWebView: UIViewRepresentable {
    var onSignedIn: () -> Void

    static let store = WKWebsiteDataStore.default()

    func makeCoordinator() -> Coordinator { Coordinator(onSignedIn: onSignedIn) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.store
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        context.coordinator.webView = view
        Self.store.httpCookieStore.add(context.coordinator)
        view.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        store.httpCookieStore.remove(coordinator)
    }

    /// Forget the web view's cookies (sign out).
    static func clearCookies() async {
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        let onSignedIn: () -> Void
        weak var webView: WKWebView?
        private var busy = false
        private var done = false

        init(onSignedIn: @escaping () -> Void) { self.onSignedIn = onSignedIn }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { Task { @MainActor in await tryComplete() } }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { Task { @MainActor in await tryComplete() } }

        // Google / SSO popups: load them in the same view instead of opening a new one.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            webView.load(navigationAction.request)
            return nil
        }

        @MainActor private func tryComplete() async {
            guard !busy, !done, let webView else { return }
            busy = true
            defer { busy = false }
            let cookies = await ClaudeWebView.store.httpCookieStore.allCookies()
            guard let key = cookies.first(where: { $0.name == "sessionKey" && $0.domain.hasSuffix("claude.ai") })?.value else { return }
            let ua = (try? await webView.evaluateJavaScript("navigator.userAgent")) as? String ?? ""
            var record = ClaudeSessionRecord(sessionKey: key, userAgent: ua, orgID: "", orgName: "")
            // Not signed in yet (or not finished) until the API accepts the cookie.
            guard let org = try? await UsageClient.resolveOrg(CookieTransport(record: record)) else { return }
            record.orgID = org.id
            record.orgName = org.name
            guard SessionStore.save(record) else { return }
            done = true
            onSignedIn()
        }
    }
}

/// Sheet chrome around claude.ai's own sign-in page: a Cancel pill, the title and "🔒 claude.ai". When the session lands,
/// a native "Connected" screen covers the web view for about 1.2s.
struct SignInSheet: View {
    var onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var connected = false
    @State private var who: String?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Sign in to Claude").font(.system(size: 17, weight: .semibold))
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 17))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16).frame(height: 44)
                        .background(Color(.systemGray6), in: Capsule())
                    Spacer()
                }
            }
            .padding(.horizontal, 16).padding(.top, 14)
            HStack(spacing: 4) {
                Image(systemName: "lock.fill").font(.system(size: 11))
                Text("claude.ai").font(.system(size: 13))
            }
            .foregroundStyle(.secondary)
            .padding(.top, 6).padding(.bottom, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Secure page on claude.ai")

            ZStack {
                ClaudeWebView(onSignedIn: { Task { await finish() } })
                if connected {
                    ConnectedView(who: who).transition(.opacity)
                }
            }
        }
        .interactiveDismissDisabled(connected)
    }

    private func finish() async {
        if let record = SessionStore.load() {
            let email = await UsageClient.accountEmail(CookieTransport(record: record))
            // A fresh snapshot: nothing from a previous account carries over (plan, credits, email).
            var snap = SharedStore.Snapshot(limits: [], updated: Date(), connected: true)
            snap.email = email
            snap.cleared = true          // no numbers yet; the first refresh fills them in
            SharedStore.save(snap)
            who = email ?? record.orgName
        }
        withAnimation(.easeInOut(duration: 0.2)) { connected = true }
        try? await Task.sleep(for: .milliseconds(1200))
        onSignedIn()
        dismiss()
    }
}
