import SwiftUI
import CoreText

// MARK: Type

/// Bricolage Grotesque Bold (OFL, bundled in every target) for big titles, the wordmark, section headers and every percentage.
enum BrandFont {
    static let name = "BricolageGrotesque-Bold"

    /// Registers the bundled font once per process. The app and each widget extension carry their own copy.
    static let registered: Bool = {
        guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()
}

extension Font {
    /// Brand display face at a fixed size (titles, wordmark, headline numbers).
    static func clausageDisplay(_ size: CGFloat) -> Font {
        _ = BrandFont.registered
        return .custom(BrandFont.name, fixedSize: size)
    }

    /// Percentages: the brand face with monospaced digits, so numbers don't jitter.
    static func clausagePercent(_ size: CGFloat) -> Font { clausageDisplay(size).monospacedDigit() }
}

extension View {
    /// Tracking as a fraction of the point size, e.g. `brandTracking(-0.035, size: 38)` for −3.5%.
    func brandTracking(_ fraction: CGFloat, size: CGFloat) -> some View { tracking(fraction * size) }
}

// MARK: Mark and wordmark

/// The in-app mark: rays 1–10 in Ink, rays 11 and 12 in Ember with a faint Ember halo (`icon-rays.svg` + `icon-halo.svg`).
/// `size` is the 24-unit logo box; the halo bleeds slightly outside it.
struct BrandMark: View {
    var size: CGFloat
    /// Ink by default; pass a color to draw the plain rays in something else (e.g. on Night).
    var ink: Color = Color("Ink")
    var ember: Color = Color("Ember")

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 24
            func path(_ pts: [(Double, Double)]) -> Path {
                var p = Path()
                for (i, pt) in pts.enumerated() {
                    let q = CGPoint(x: pt.0 * s, y: pt.1 * s)
                    i == 0 ? p.move(to: q) : p.addLine(to: q)
                }
                p.closeSubpath()
                return p
            }
            for (i, r) in LogoRays.rays.enumerated() where i < 10 { ctx.fill(path(r), with: .color(ink)) }
            let accent = LogoRays.rays[10...].map(path)
            for p in accent {
                ctx.stroke(p, with: .color(ember.opacity(0.2)), style: StrokeStyle(lineWidth: 2.5 * s, lineJoin: .round))
            }
            for p in accent { ctx.fill(p, with: .color(ember)) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Lowercase "clausage" in Bricolage, tracked −3.5%.
struct Wordmark: View {
    var size: CGFloat
    var body: some View {
        Text("clausage")
            .font(.clausageDisplay(size))
            .brandTracking(-0.035, size: size)
            .foregroundStyle(Color("Ink"))
            .accessibilityLabel("Clausage")
    }
}

// MARK: Tally

/// Four tally strokes and the Ember slash. Used as the loader (strokes count up), the "updated" mark (the slash lands)
/// and in empty states (faded). `filled` is 0...4; `slash` is 0...1 (how far the slash has been drawn).
struct Tally: View {
    var size: CGFloat
    var filled: Int = 4
    var slash: Double = 0
    var ink: Color = Color("Ink")
    var empty: Color = Color("Ink").opacity(0.18)
    var ember: Color = Color("Ember")

    var body: some View {
        Canvas { ctx, canvas in
            let w = canvas.width
            let stroke = max(1.2, w * 0.085)
            let top = w * 0.20, bottom = w * 0.80
            for i in 0..<4 {
                let x = w * (0.29 + 0.14 * Double(i))
                var p = Path()
                p.move(to: CGPoint(x: x, y: top))
                p.addLine(to: CGPoint(x: x, y: bottom))
                ctx.stroke(p, with: .color(i < filled ? ink : empty),
                           style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
            if slash > 0 {
                let a = CGPoint(x: w * 0.14, y: w * 0.70), b = CGPoint(x: w * 0.86, y: w * 0.34)
                let t = min(max(slash, 0), 1)
                var p = Path()
                p.move(to: a)
                p.addLine(to: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                ctx.stroke(p, with: .color(ember), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The empty tally: four faint strokes and no slash. Marks the Free plan state, where there's nothing to count.
struct EmptyTally: View {
    var size: CGFloat
    var body: some View {
        Tally(size: size, filled: 0, empty: Color("Ink").opacity(0.18)).accessibilityHidden(true)
    }
}

/// Copy for the Free plan state (claude.ai has no usage page on Free), shared by both apps and the widgets.
enum FreePlanCopy {
    static let headline = "Nothing on the plate yet"
    static let bodyScreen = "claude.ai only shows usage on Pro and Max plans, so on Free there’s nothing for Clausage to count."
    static let bodyShort = "claude.ai only shows usage on Pro and Max plans."
    static let widgetLine = "Clausage needs a Claude Pro or Max plan."
    static let widgetSub = "Needs Pro or Max"
    static let switchAccount = "Use another account"
}

/// Tally strokes counting up one at a time (0→4, then again), for loading states.
struct TallyLoader: View {
    var size: CGFloat
    var interval: Double = 0.18
    var ink: Color = Color("Ink")

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { ctx in
            let step = Int(ctx.date.timeIntervalSinceReferenceDate / interval) % 5
            Tally(size: size, filled: step, ink: ink, empty: ink.opacity(0.18))
        }
    }
}

// MARK: Chips

/// Small capsule chip: plan badge, "Limiting now", Keychain / App Group tags.
struct BrandChip: View {
    let text: String
    var size: CGFloat = 11
    var fill: Color = Color("Sand2")
    var ink: Color = Color("Ink")

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.vertical, size * 0.36).padding(.horizontal, size * 0.64)
            .background(fill, in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}
