import XCTest

/// The iPhone sign-in web view stays on claude.ai and the Google / Apple sign-in pages (age rating: no unrestricted web access).
final class SignInPolicyTests: XCTestCase {
    private func top(_ s: String, tapped: Bool = false) -> SignInPolicy.Decision {
        SignInPolicy.decide(URL(string: s), mainFrame: true, userTapped: tapped)
    }

    func testSignInPagesLoad() {
        for s in ["https://claude.ai/login", "https://claude.ai/login?returnTo=%2F", "https://www.claude.ai/",
                  "https://accounts.google.com/o/oauth2/v2/auth?client_id=x", "https://accounts.youtube.com/accounts/SetSID",
                  "https://appleid.apple.com/auth/authorize?client_id=x", "https://idmsa.apple.com/appleauth/auth",
                  // Google's sign-in hop through its country sites after a password
                  "https://accounts.google.ca/accounts/SetSID", "https://accounts.google.co.uk/accounts/SetSID",
                  "https://accounts.google.com.au/accounts/SetSID", "https://accounts.google.de/accounts/SetSID"] {
            XCTAssertEqual(top(s), .allow, s)
        }
        XCTAssertEqual(top("about:blank"), .allow)          // a popup before it loads
    }

    func testEverywhereElseIsOffLimits() {
        // Tapped: hand it to Safari. Not tapped (redirects, scripts): drop it.
        XCTAssertEqual(top("https://www.anthropic.com/legal/consumer-terms", tapped: true), .openOutside)
        XCTAssertEqual(top("https://www.anthropic.com/legal/consumer-terms"), .block)
        XCTAssertEqual(top("https://www.google.com/search?q=x", tapped: true), .openOutside)
        XCTAssertEqual(top("https://example.okta.com/sso", tapped: false), .block)
        XCTAssertEqual(top("http://claude.ai/login"), .block)                     // https only
        XCTAssertEqual(top("https://claude.ai.evil.example/login"), .block)       // lookalike host
        XCTAssertEqual(top("https://notclaude.ai/"), .block)
        XCTAssertEqual(top("https://accounts.google.evil.example/"), .block)
        XCTAssertEqual(top("https://accounts.google.ca.evil.example/"), .block)
        XCTAssertEqual(top("https://mail.google.ca/"), .block)
        XCTAssertEqual(top("mailto:support@anthropic.com", tapped: true), .openOutside)
        XCTAssertEqual(SignInPolicy.decide(nil, mainFrame: true, userTapped: true), .block)
    }

    func testEmbeddedFramesLoad() {
        // Cloudflare's check and Google's cookie frames aren't pages you can browse to.
        XCTAssertEqual(SignInPolicy.decide(URL(string: "https://challenges.cloudflare.com/cdn-cgi/challenge-platform/x"),
                                           mainFrame: false, userTapped: false), .allow)
        XCTAssertEqual(SignInPolicy.decide(URL(string: "about:srcdoc"), mainFrame: false, userTapped: false), .allow)
        XCTAssertEqual(SignInPolicy.decide(URL(string: "http://example.com/"), mainFrame: false, userTapped: false), .block)
    }

    func testGoogleOneTapSheetDoesNotLoad() {
        XCTAssertEqual(SignInPolicy.decide(URL(string: "https://accounts.google.com/gsi/iframe/select?client_id=x"),
                                           mainFrame: false, userTapped: false), .block)
        // The "Continue with Google" button's pages still load.
        XCTAssertEqual(top("https://accounts.google.com/o/oauth2/v2/auth?client_id=x"), .allow)
        XCTAssertEqual(SignInPolicy.decide(URL(string: "https://accounts.google.com/RotateCookiesPage"),
                                           mainFrame: false, userTapped: false), .allow)
    }
}
