import Foundation

/// Where the iPhone sign-in web view may go. It isn't a browser (the App Store age rating says "Unrestricted Web Access:
/// No"), so top-level pages stay on claude.ai and the Google and Apple sign-in pages it hands off to. Embedded frames
/// (Cloudflare's check, Google's cookie hops) aren't pages you can browse to, so they load. A link you tap that leads
/// anywhere else opens in Safari; anything else is dropped.
enum SignInPolicy {
    enum Decision: Equatable { case allow, openOutside, block }

    /// Exact hosts, plus any subdomain of claude.ai and Google's regional sign-in hosts.
    static let hosts: Set<String> = [
        "claude.ai",
        "accounts.google.com", "accounts.youtube.com",      // Google sign-in and its cookie check
        "gds.google.com",                                    // Google's mid-sign-in prompts (recovery options)
        "appleid.apple.com", "idmsa.apple.com",              // Sign in with Apple
    ]

    static func isAllowed(host: String) -> Bool {
        let h = host.lowercased()
        return hosts.contains(h) || h.hasSuffix(".claude.ai") || isRegionalGoogleAccounts(h)
    }

    /// After a password, Google signs you in to its country sites too, hopping the page through
    /// accounts.google.ca, accounts.google.co.uk, accounts.google.com.au… on the way back to claude.ai.
    private static func isRegionalGoogleAccounts(_ h: String) -> Bool {
        h.range(of: #"^accounts\.google\.(com?\.)?[a-z]{2,3}$"#, options: .regularExpression) != nil
    }

    /// Google's "One Tap" sheet ("Sign in to Claude with Google · Continue"), which claude.ai's page loads on its own
    /// in a frame from accounts.google.com/gsi/. Not the "Continue with Google" button, which goes to Google's pages.
    static func isGoogleOneTap(_ url: URL) -> Bool {
        url.host?.lowercased() == "accounts.google.com" && url.path.hasPrefix("/gsi/")
    }

    /// Hides claude.ai's cookie banner (no choice made means nothing beyond necessary cookies) and the empty
    /// One Tap container. Injected into the sign-in page.
    static let pageCSS = """
    [data-testid="consent-banner"], #credential_picker_container, #credential_picker_iframe,
    iframe[src*="accounts.google.com/gsi/"] { display: none !important; }
    """

    /// - Parameters:
    ///   - mainFrame: a top-level page (or a sign-in popup), as opposed to a frame inside one.
    ///   - userTapped: the person tapped a link (WebKit's `.linkActivated`).
    static func decide(_ url: URL?, mainFrame: Bool, userTapped: Bool) -> Decision {
        guard let url, let scheme = url.scheme?.lowercased() else { return .block }
        // Blank pages: new popups start at about:blank before they load.
        if scheme == "about" { return .allow }
        if !mainFrame {
            if isGoogleOneTap(url) { return .block }
            return ["https", "about", "data", "blob"].contains(scheme) ? .allow : .block
        }
        if scheme == "https", let host = url.host, isAllowed(host: host) { return .allow }
        return userTapped ? .openOutside : .block
    }
}
