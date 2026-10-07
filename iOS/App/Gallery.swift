import SwiftUI

/// Debug aid: renders every widget family (dark, light, tinted) with the sample states to PNGs, so the layout can be checked
/// without adding widgets by hand. Run the app with `--render-gallery <folder>`.
enum GalleryLauncher {
    @MainActor static func runIfRequested() {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--self-test"), i + 1 < args.count {
            SelfTest.run(writingTo: args[i + 1])
            exit(0)
        }
        guard let i = args.firstIndex(of: "--render-gallery"), i + 1 < args.count else { return }
        GalleryRenderer.render(into: args[i + 1])
        exit(0)
        #endif
    }
}

#if DEBUG
private let lavender = Color(red: 0.70, green: 0.75, blue: 1.0)

struct GalleryVariant<Content: View>: View {
    let scheme: ColorScheme
    let style: UsageRenderStyle
    let size: CGSize
    let radius: CGFloat
    @ViewBuilder let content: Content

    private var wallpaper: Color {
        if style == .accented { return Color(red: 0.08, green: 0.10, blue: 0.22) }
        return scheme == .dark ? Color(red: 0.07, green: 0.07, blue: 0.09) : Color(red: 0.85, green: 0.86, blue: 0.90)
    }
    private var card: AnyShapeStyle {
        style == .accented ? AnyShapeStyle(Color.white.opacity(0.14))
            : AnyShapeStyle(LinearGradient(colors: [Color("Paper"), Color("WidgetBottom")], startPoint: .top, endPoint: .bottom))
    }

    var body: some View {
        content
            .padding(16)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(card))
            .padding(24)
            .background(wallpaper)
            .environment(\.colorScheme, style == .accented ? .dark : scheme)
            .environment(\.usageStyle, style)
            .environment(\.usageTint, lavender)
    }
}

struct GalleryLock: View {
    let snapshot: SharedStore.Snapshot
    var body: some View {
        let limits = Array(Forecast.ordered(snapshot.limits).prefix(3))
        VStack(spacing: 14) {
            Text("Mon 5  \(UsageInline.text(snapshot, now: UsageFixtures.now))")
                .font(.system(size: 17, weight: .semibold))
            Text("9:41").font(.system(size: 96, weight: .bold))
            HStack(spacing: 14) {
                if SharedStore.isFree(snapshot) {
                    FreeGauge(plainBackground: true).frame(width: 72, height: 72)
                } else {
                    ForEach(limits) { UsageGauge(limit: $0, plainBackground: true).frame(width: 72, height: 72) }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(40)
        .frame(width: 420)
        .background(LinearGradient(colors: [Color(red: 0.22, green: 0.24, blue: 0.38), Color(red: 0.07, green: 0.07, blue: 0.12)],
                                   startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)
        .environment(\.usageStyle, .accented)
    }
}

@MainActor enum GalleryRenderer {
    static func render(into dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let scenarios: [(String, SharedStore.Snapshot)] = [
            ("mixed", UsageFixtures.mixed), ("calm", UsageFixtures.calm),
            ("critical", UsageFixtures.allCritical), ("stale", UsageFixtures.stale), ("free", UsageFixtures.free)]
        let sizes: [(String, UsageSize, CGSize)] = [
            ("small", .small, CGSize(width: 158, height: 158)),
            ("medium", .medium, CGSize(width: 338, height: 158)),
            ("large", .large, CGSize(width: 338, height: 354))]
        for (name, snap) in scenarios {
            for (sizeName, size, dims) in sizes {
                let row = HStack(spacing: 0) {
                    ForEach(Array([(ColorScheme.dark, UsageRenderStyle.full), (.light, .full), (.dark, .accented)].enumerated()), id: \.offset) { _, v in
                        GalleryVariant(scheme: v.0, style: v.1, size: dims, radius: 22) {
                            UsageContent(size: size, snapshot: snap, history: UsageFixtures.history(for: snap), now: UsageFixtures.now)
                        }
                    }
                }
                write(row, to: "\(dir)/\(sizeName)-\(name).png")
            }
            write(GalleryLock(snapshot: snap), to: "\(dir)/lock-\(name).png")
        }
    }

    private static func write<V: View>(_ view: V, to path: String) {
        let r = ImageRenderer(content: view)
        r.scale = 2
        if let png = r.uiImage?.pngData() { try? png.write(to: URL(fileURLWithPath: path)) }
    }
}
#endif

#if DEBUG
/// Checks that the shared Keychain group and the App Group work in this build (they need entitlements).
enum SelfTest {
    static func run(writingTo path: String) {
        var lines: [String] = []
        let record = ClaudeSessionRecord(sessionKey: "test-key", userAgent: "test-ua", orgID: "org", orgName: "Test")
        let saved = SessionStore.save(record)
        lines.append("keychain save: \(saved)")
        lines.append("keychain load matches: \(SessionStore.load() == record)")
        SessionStore.clear()
        lines.append("keychain cleared: \(SessionStore.load() == nil)")
        let before = SharedStore.load()
        SharedStore.save(.init(limits: [], updated: Date(), connected: false))
        lines.append("app group round trip: \(SharedStore.load()?.connected == false)")
        if let before { SharedStore.save(before) }
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
#endif
