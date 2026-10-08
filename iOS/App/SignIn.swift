import SwiftUI
import WebKit

/// claude.ai sign-in inside the app. When the `sessionKey` cookie shows up and the API accepts it, the session is saved to the
/// shared Keychain and `onSignedIn` fires. The web view's own cookies are only a means to get there; refreshes use the Keychain copy.
struct ClaudeWebView: UIViewRepresentable {
    var onSignedIn: () -> Void
    /// A page `SignInPolicy` refused to open (shown in debug builds, to find sign-in hosts it's missing).
    var onBlocked: (URL) -> Void = { _ in }
    /// claude.ai has set a session and Clausage is checking it (true), or the check didn't pass yet (false).
    var onConnecting: (Bool) -> Void = { _ in }

    static let store = WKWebsiteDataStore.default()

    func makeCoordinator() -> Coordinator { Coordinator(onSignedIn: onSignedIn, onBlocked: onBlocked, onConnecting: onConnecting) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.store
        // Look like Mobile Safari: Google refuses to sign in inside embedded web views that don't say "Safari".
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"
        // No cookie banner or Google One Tap sheet over the sign-in page.
        let css = SignInPolicy.pageCSS.replacingOccurrences(of: "`", with: "")
        config.userContentController.addUserScript(WKUserScript(
            source: "(() => { const s = document.createElement('style'); s.textContent = `\(css)`; document.documentElement.appendChild(s); })();",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        context.coordinator.webView = view
        context.coordinator.watchTaps(on: view)
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver, UIGestureRecognizerDelegate {
        let onSignedIn: () -> Void
        let onBlocked: (URL) -> Void
        let onConnecting: (Bool) -> Void
        weak var webView: WKWebView?
        private var busy = false
        private var done = false

        init(onSignedIn: @escaping () -> Void, onBlocked: @escaping (URL) -> Void, onConnecting: @escaping (Bool) -> Void) {
            self.onSignedIn = onSignedIn
            self.onBlocked = onBlocked
            self.onConnecting = onConnecting
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { Task { @MainActor in await tryComplete() } }

        /// Top-level pages stay on claude.ai and the Google / Apple sign-in pages (`SignInPolicy`); a tapped link to
        /// anywhere else opens in Safari. Applies to the sign-in popups too.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            switch decide(navigationAction) {
            case .allow: decisionHandler(.allow)
            case .openOutside:
                decisionHandler(.cancel)
                if let url = navigationAction.request.url { UIApplication.shared.open(url) }
            case .block:
                decisionHandler(.cancel)
                if let url = navigationAction.request.url { onBlocked(url) }
            }
        }

        private func decide(_ action: WKNavigationAction) -> SignInPolicy.Decision {
            SignInPolicy.decide(action.request.url, mainFrame: action.targetFrame?.isMainFrame ?? true,
                                userTapped: action.navigationType == .linkActivated || tappedJustNow)
        }

        // claude.ai's menus open links from scripts, which WebKit reports as `.other`, not `.linkActivated`. A page that
        // opens right after a tap counts as tapped, so it goes to Safari instead of being dropped.
        private var lastTap = Date.distantPast
        private var tappedJustNow: Bool { Date().timeIntervalSince(lastTap) < 1.5 }

        func watchTaps(on view: UIView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            view.addGestureRecognizer(tap)
        }

        @objc private func tapped() { lastTap = Date() }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { Task { @MainActor in await tryComplete() } }

        // Google / SSO popups: a real popup view (from WebKit's configuration) laid over the sign-in page, so it keeps
        // `window.opener`, hands the result back to claude.ai and closes itself. Loading it in place strands it on a blank page.
        private var popup: WKWebView?

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            switch decide(navigationAction) {
            case .allow: break
            case .openOutside:
                if let url = navigationAction.request.url { UIApplication.shared.open(url) }
                return nil
            case .block:
                if let url = navigationAction.request.url { onBlocked(url) }
                return nil
            }
            popup?.removeFromSuperview()
            let v = WKWebView(frame: webView.bounds, configuration: configuration)
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            v.uiDelegate = self
            v.navigationDelegate = self
            watchTaps(on: v)
            webView.addSubview(v)
            popup = v
            return v
        }

        func webViewDidClose(_ webView: WKWebView) {
            guard webView === popup else { return }
            webView.removeFromSuperview()
            popup = nil
        }

        @MainActor private func tryComplete() async {
            guard !busy, !done, let webView else { return }
            busy = true
            defer { busy = false }
            let cookies = await ClaudeWebView.store.httpCookieStore.allCookies()
            guard let key = cookies.first(where: { $0.name == "sessionKey" && $0.domain.hasSuffix("claude.ai") })?.value else { return }
            // Cover claude.ai's page right away: it carries on into its own app while the check below runs.
            onConnecting(true)
            let ua = (try? await webView.evaluateJavaScript("navigator.userAgent")) as? String ?? ""
            var record = ClaudeSessionRecord(sessionKey: key, userAgent: ua, orgID: "", orgName: "")
            // Not signed in yet (or not finished) until the API accepts the cookie.
            guard let org = try? await UsageClient.resolveOrg(CookieTransport(record: record)) else { onConnecting(false); return }
            record.orgID = org.id
            record.orgName = org.name
            guard SessionStore.save(record) else { return }
            done = true
            onSignedIn()
        }
    }
}

/// Sheet chrome around claude.ai's own sign-in page: a Cancel pill, the title and "🔒 claude.ai". As soon as claude.ai
/// sets a session, a native screen covers the web view: "Connecting…" while Clausage checks it, then "Connected" for
/// about 1.2s (the email fills in when it arrives).
struct SignInSheet: View {
    var onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var connecting = false
    @State private var connected = false
    @State private var who: String?
    @State private var blocked: URL?

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

            ZStack(alignment: .bottom) {
                ClaudeWebView(onSignedIn: { Task { await finish() } },
                              onBlocked: { url in if !SignInPolicy.isGoogleOneTap(url) { blocked = url } },   // One Tap is meant to be blocked
                              onConnecting: { on in withAnimation(.easeInOut(duration: 0.2)) { connecting = on } })
                #if DEBUG
                if let blocked {
                    Text("Blocked: \(blocked.host ?? blocked.absoluteString)\(blocked.host == nil ? "" : blocked.path)")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.white)
                        .lineLimit(2).padding(10)
                        .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                        .padding(12)
                        .textSelection(.enabled)
                }
                #endif
                if connecting || connected {
                    ConnectedView(who: who, connected: connected).transition(.opacity)
                }
            }
        }
        .interactiveDismissDisabled(connecting || connected)
    }

    private func finish() async {
        withAnimation(.easeInOut(duration: 0.2)) { connected = true }
        let shown = Date()
        if let record = SessionStore.load() {
            // A fresh snapshot: nothing from a previous account carries over (plan, credits, email).
            var snap = SharedStore.Snapshot(limits: [], updated: Date(), connected: true)
            snap.cleared = true          // no numbers yet; the first refresh fills them in
            SharedStore.save(snap)
            let email = await UsageClient.accountEmail(CookieTransport(record: record))
            snap.email = email
            SharedStore.save(snap)
            withAnimation(.easeOut(duration: 0.2)) { who = email ?? record.orgName }
        }
        let left = 1.2 - Date().timeIntervalSince(shown)
        if left > 0 { try? await Task.sleep(for: .seconds(left)) }
        onSignedIn()
        dismiss()
    }
}
