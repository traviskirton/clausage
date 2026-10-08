import SwiftUI

/// The app icon, drawn: the tally (four Ink strokes, Ember slash) on the Paper → Sand gradient, as in
/// `iOS/App/clausage-tally.icon`.
struct AppIconView: View {
    var size: CGFloat
    var body: some View {
        let radius = size * 26 / 112
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.988, blue: 0.965), Color(red: 0.902, green: 0.863, blue: 0.784)],
                                     startPoint: .top, endPoint: .bottom))
            Tally(size: size * 0.78, filled: 4, slash: 1, ink: Color(red: 0.149, green: 0.137, blue: 0.122),
                  ember: Color(red: 1, green: 0.29, blue: 0.11))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: size * 0.06, y: size * 0.03)
        .accessibilityHidden(true)
    }
}

/// Signed out: app icon, wordmark, one line, and the Ink sign-in button pinned to the bottom.
struct WelcomeScreen: View {
    let message: String?
    let onSignIn: () -> Void
    /// "Try it with sample data": every screen and widget without an account (also how App Review sees the app).
    var onSample: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            AppIconView(size: 112)
            Spacer().frame(height: 28)
            Wordmark(size: 44)
            Text("Your Claude plan limits on your Home Screen and Lock Screen.")
                .font(.system(size: 17)).foregroundStyle(Color("Ink2"))
                .multilineTextAlignment(.center)
                .padding(.top, 10).padding(.horizontal, 32)
            if let message {
                Text(message).font(.system(size: 13)).foregroundStyle(Color("CriticalText"))
                    .multilineTextAlignment(.center).padding(.top, 14).padding(.horizontal, 32)
            }
            Spacer()
            Button(action: onSignIn) {
                Text("Sign in to Claude")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color("Paper"))
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color("Ink"), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            if let onSample {
                Button("Try it with sample data", action: onSample)
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Color("Ink"))
                    .frame(minHeight: 44)
                    .padding(.top, 6)
            }
            (Text("For Claude Pro and Max plans. ").fontWeight(.semibold).foregroundStyle(Color("Ink").opacity(0.82))
             + Text("You sign in on claude.ai. Clausage never sees your password and isn’t made by Anthropic."))
                .font(.system(size: 12)).foregroundStyle(Color("Ink3"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40).padding(.top, 12).padding(.bottom, 16)
        }
    }
}

/// Shown over the web view as soon as the session lands, then dismissed after about 1.2s.
struct ConnectedView: View {
    let who: String?
    /// false while the new session is being checked ("Connecting…", the tally counting).
    var connected = true
    @State private var filled = 0

    var body: some View {
        VStack(spacing: 10) {
            if connected { Tally(size: 96, filled: filled) } else { TallyLoader(size: 96) }
            Text(connected ? "Connected" : "Connecting…").font(.system(size: 28, weight: .bold)).foregroundStyle(Color("Ink"))
                .padding(.top, 8).contentTransition(.opacity)
            Text(who ?? " ").font(.system(size: 17)).foregroundStyle(Color("Ink2"))
            Text("Counting your usage…").font(.system(size: 15)).foregroundStyle(Color("Ink3")).padding(.top, 12)
                .opacity(connected ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color("Paper"), Color("Paper2")], startPoint: .top, endPoint: .bottom))
        .task(id: connected) {
            guard connected else { return }
            for i in 1...3 {
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.easeOut(duration: 0.15)) { filled = i }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
