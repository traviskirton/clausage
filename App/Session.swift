import AppKit
import WebKit

/// Owns the claude.ai web session: a sign-in window and a hidden web view used to call claude.ai's own API
/// with the user's cookies (so requests look like the website's, including Cloudflare checks).
@MainActor
final class ClaudeSession: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private static let safariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    let accountID: UUID
    private var signInWindow: NSWindow?
    private var signInView: WKWebView?
    private var popupWindow: NSWindow?
    private var popupView: WKWebView?
    private var pollTimer: Timer?
    private var onSignedIn: ((Bool) -> Void)?

    init(accountID: UUID) {
        self.accountID = accountID
        super.init()
    }

    /// Each account gets its own isolated cookie store.
    private func makeConfiguration() -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = WKWebsiteDataStore(forIdentifier: accountID)
        return c
    }

    private lazy var apiView: WKWebView = {
        let v = WKWebView(frame: .zero, configuration: makeConfiguration())
        v.customUserAgent = Self.safariUA
        v.navigationDelegate = self
        return v
    }()
    private var apiLoaded = false
    private var apiWaiters: [CheckedContinuation<Void, Never>] = []

    // MARK: Sign in

    func signIn(completion: @escaping (Bool) -> Void) {
        onSignedIn = completion
        if let w = signInWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        if signInWindow == nil {
            let v = WKWebView(frame: .zero, configuration: makeConfiguration())
            v.customUserAgent = Self.safariUA
            v.navigationDelegate = self
            v.uiDelegate = self
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Sign in to Claude"
            w.contentView = v
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            signInView = v; signInWindow = w
            AppActivation.push()
        }
        signInView?.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        NSApp.activate(ignoringOtherApps: true)
        signInWindow?.makeKeyAndOrderFront(nil)
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollSignIn() }
        }
    }

    private func pollSignIn() async {
        guard let v = signInView, v.url?.host?.hasSuffix("claude.ai") == true,
              let res = try? await Self.fetch("/api/organizations", in: v), res.status == 200 else { return }
        finishSignIn(true)
    }

    private func finishSignIn(_ ok: Bool) {
        pollTimer?.invalidate(); pollTimer = nil
        closePopup()
        let cb = onSignedIn; onSignedIn = nil
        signInWindow?.delegate = nil
        signInWindow?.close()
        signInWindow = nil; signInView = nil
        AppActivation.pop()
        cb?(ok)
    }

    func windowWillClose(_ notification: Notification) {
        guard onSignedIn != nil else { return }
        finishSignIn(false)
    }

    // Google/SSO popups get a real child window built from WebKit's configuration, so the popup keeps `window.opener`,
    // can post the sign-in result back to claude.ai and close itself. Loading it in the same view strands it on a blank page.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        closePopup()
        let v = WKWebView(frame: .zero, configuration: configuration)
        v.customUserAgent = Self.safariUA
        v.uiDelegate = self
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Sign in"
        w.contentView = v
        w.isReleasedWhenClosed = false
        if let parent = signInWindow {
            let p = parent.frame
            w.setFrameOrigin(NSPoint(x: p.midX - w.frame.width / 2, y: p.midY - w.frame.height / 2))
            parent.addChildWindow(w, ordered: .above)
        } else {
            w.center()
        }
        w.makeKeyAndOrderFront(nil)
        popupView = v; popupWindow = w
        return v
    }

    /// The popup called `window.close()` (Google does this once it has handed the result back).
    func webViewDidClose(_ webView: WKWebView) {
        if webView === popupView { closePopup() }
    }

    private func closePopup() {
        guard let w = popupWindow else { return }
        w.parent?.removeChildWindow(w)
        w.close()
        popupWindow = nil; popupView = nil
    }

    /// Forgets this account's cookies and web data.
    func signOut() async {
        pollTimer?.invalidate()
        apiLoaded = false
        try? await WKWebsiteDataStore.remove(forIdentifier: accountID)
    }

    // MARK: API

    /// GET a path on claude.ai with the signed-in session. Returns HTTP status and body text.
    func get(_ path: String) async throws -> (status: Int, body: String) {
        await ensureAPIPage()
        return try await Self.fetch(path, in: apiView)
    }

    private func ensureAPIPage() async {
        if apiLoaded { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            apiWaiters.append(c)
            if apiWaiters.count == 1 {
                apiView.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard webView === self.apiView else { return }
            self.apiLoaded = true
            let ws = self.apiWaiters; self.apiWaiters = []
            ws.forEach { $0.resume() }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            guard webView === self.apiView else { return }
            let ws = self.apiWaiters; self.apiWaiters = []
            ws.forEach { $0.resume() }   // let the fetch fail with a real error
        }
    }

    private static func fetch(_ path: String, in view: WKWebView) async throws -> (status: Int, body: String) {
        let js = """
        const r = await fetch(path, {credentials: 'include', headers: {'Accept': 'application/json'}});
        return {status: r.status, body: await r.text()};
        """
        let out = try await view.callAsyncJavaScript(js, arguments: ["path": path], in: nil, contentWorld: .page)
        guard let d = out as? [String: Any], let s = d["status"] as? Int, let b = d["body"] as? String
        else { throw UsageError.badResponse }
        return (s, b)
    }
}

extension ClaudeSession: UsageTransport {}
