import SwiftUI

/// "All models · this week" as a running total toward the limit (design 5b, states 6a–6e).
/// x = the window from start to reset, each reading at its hour; y = 0–100%. The line is in the All models state color;
/// Ember never appears.
struct RunningTotalChart: View {
    let chart: WeeklyChart
    let level: Forecast.Level
    var now: Date = Date()
    /// 4pt, in the app and the large widget. Dashed stretches are 1pt thinner; last week's line is 2pt.
    var lineWidth: CGFloat = 4
    /// Smaller markers and labels (large widget).
    var compact = false
    /// Mac Settings: today's % sits on a small plate of this color, above and left of the dot (below and right when
    /// that would touch the Limit line), so it never lands on the line. nil keeps the haloed label (iPhone, widget).
    var labelBackground: Color? = nil
    var calendar: Calendar = .current

    @Environment(\.usageStyle) private var style
    @Environment(\.usageTint) private var tint

    private var lineColor: Color { style == .accented ? tint : UsageColor.fill(level) }
    private var paper: Color { style == .accented ? .clear : Color("Paper") }

    var body: some View {
        GeometryReader { geo in
            let g = Geometry(size: geo.size, compact: compact)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in draw(&ctx, g) }
                labels(g)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Layout

    private struct Geometry {
        let size: CGSize
        let compact: Bool
        var letterBand: CGFloat { compact ? 14 : 20 }
        var top: CGFloat { compact ? 12 : 16 }
        var left: CGFloat { compact ? 8 : 12 }
        var right: CGFloat { compact ? 8 : 12 }
        var plotBottom: CGFloat { size.height - letterBand - (compact ? 4 : 6) }
        var plotHeight: CGFloat { max(10, plotBottom - top) }
        /// `f`: 0 at the window start, 1 at the reset.
        func x(_ f: Double) -> CGFloat { left + CGFloat(f) * (size.width - left - right) }
        func y(_ v: Double) -> CGFloat { plotBottom - CGFloat(min(max(v, 0), 100) / 100) * plotHeight }
        func p(_ f: Double, _ v: Double) -> CGPoint { CGPoint(x: x(f), y: y(v)) }
    }

    /// Adds the stretch from `a` to `b`. A drop (an early reset) is a cliff at `b`'s time: level, then straight down.
    private static func stretch(_ path: inout Path, _ a: WeeklyChart.Sample, _ b: WeeklyChart.Sample, _ g: Geometry) {
        if b.value < a.value { path.addLine(to: g.p(b.x, a.value)) }
        path.addLine(to: g.p(b.x, b.value))
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext, _ g: Geometry) {
        let ink3 = style == .full ? Color("Ink3") : Color.white.opacity(0.5)
        let paceColor = style == .full ? Color("PaceLine") : Color.white.opacity(0.35)

        // Limit: dotted line at 100% (in the app, Ink 1pt in 2/4 dashes).
        var limit = Path()
        limit.move(to: CGPoint(x: g.left, y: g.y(100)))
        limit.addLine(to: CGPoint(x: g.size.width - g.right, y: g.y(100)))
        if compact || style != .full {
            ctx.stroke(limit, with: .color(ink3.opacity(0.8)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [0.1, 4]))
        } else {
            ctx.stroke(limit, with: .color(Color("Ink")), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
        }

        // Even pace: 0% at the window start to 100% at the reset.
        var pace = Path()
        pace.move(to: g.p(0, 0))
        pace.addLine(to: g.p(1, 100))
        ctx.stroke(pace, with: .color(paceColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 5]))

        // Last week, faint, while this week is still short (6e).
        if let ghost = chart.ghost, let g0 = ghost.first {
            var p = Path()
            p.move(to: g.p(g0.x, g0.value))
            for i in ghost.indices.dropFirst() { Self.stretch(&p, ghost[i - 1], ghost[i], g) }
            let ghostColor = style == .full ? Color("Ghost") : Color.white.opacity(0.3)
            ctx.stroke(p, with: .color(ghostColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }

        let line = chart.line
        guard let first = line.first else { return }

        // Before install (6a/6b): dotted Ink 3 from (window start, 0) to the first reading.
        if chart.beforeInstall {
            var p = Path()
            p.move(to: g.p(0, 0))
            p.addLine(to: g.p(first.x, first.value))
            ctx.stroke(p, with: .color(ink3), style: StrokeStyle(lineWidth: compact ? 1.5 : 2, lineCap: .round, dash: [0.1, compact ? 3.5 : 4.5]))
        }

        let dashed = StrokeStyle(lineWidth: lineWidth - 1, lineCap: .round, lineJoin: .round, dash: [0.1, lineWidth * 1.7])
        let solid = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let shading: GraphicsContext.Shading = .color(lineColor)

        // Missed days from the window start (installed earlier, app didn't run): dashed from (start, 0).
        if chart.gapFromStart {
            var p = Path()
            p.move(to: g.p(0, 0))
            p.addLine(to: g.p(first.x, first.value))
            ctx.stroke(p, with: shading, style: dashed)
        }

        // Reading to reading: straight segments with round joins, one solid path, broken by dashed stretches across
        // missed days (6c).
        var run = Path()
        run.move(to: g.p(first.x, first.value))
        for i in line.indices.dropFirst() {
            let a = line[i - 1], b = line[i]
            if b.dashed {
                ctx.stroke(run, with: shading, style: solid)
                var gap = Path()
                gap.move(to: g.p(a.x, a.value))
                Self.stretch(&gap, a, b, g)
                ctx.stroke(gap, with: shading, style: dashed)
                run = Path()
                run.move(to: g.p(b.x, b.value))
            } else {
                Self.stretch(&run, a, b, g)
            }
        }
        ctx.stroke(run, with: shading, style: solid)

        // Markers: hollow Paper dots at each past day's last reading, a dashed ring for a missed day, a filled dot for now.
        let pts = chart.points
        let r: CGFloat = compact ? 2.5 : 3
        for pt in pts where pt.day != chart.today || pt.kind == .missing {
            let c = g.p(pt.x, pt.value)
            if pt.kind == .missing {
                let rr = r + 1.5
                let circle = Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
                ctx.fill(circle, with: .color(paper))
                ctx.stroke(circle, with: shading, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
            } else {
                let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.fill(circle, with: .color(paper))
                ctx.stroke(circle, with: shading, lineWidth: compact ? 1.5 : 2)
            }
        }
        if let today = pts.last(where: { $0.day == chart.today && $0.kind == .measured }) {
            let c = g.p(today.x, today.value)
            let tr: CGFloat = compact ? 4.5 : 5
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - tr, y: c.y - tr, width: tr * 2, height: tr * 2)), with: shading)
        }
    }

    // MARK: Labels

    @ViewBuilder private func labels(_ g: Geometry) -> some View {
        let small: CGFloat = compact ? 9 : 10
        // "Limit", left, just above the dotted line.
        Text("Limit").font(.system(size: small)).foregroundStyle(UsageColor.ink2(style))
            .fixedSize()
            .position(x: g.left + (compact ? 12 : 14), y: g.y(100) - (compact ? 7 : 8))

        if chart.beforeInstall, let first = chart.line.first {
            let mid = g.p(first.x / 2, first.value / 2)
            Text("Before Clausage").font(.system(size: small)).foregroundStyle(UsageColor.ink3(style))
                .fixedSize()
                .position(x: max(mid.x, g.left + 40), y: mid.y + (compact ? 9 : 12))
        }

        // Today's running total, with a Paper halo; above the point, or below once it's over 85%.
        if let today = chart.points.last(where: { $0.day == chart.today }) {
            let c = g.p(today.x, today.value)
            let size: CGFloat = compact ? 11 : 14
            if let plate = labelBackground {
                // About 8pt off the dot. Above-left unless the label's top would come within 16pt of the Limit line.
                let height = size + 4
                let flip = c.y - 8 - height - g.y(100) < 16
                Color.clear.frame(width: 0, height: 0)
                    .overlay(alignment: flip ? .topLeading : .bottomTrailing) {
                        Text("\(Int(chart.current.rounded()))%").font(.clausagePercent(size)).foregroundStyle(UsageColor.ink(style))
                            .padding(.vertical, 2).padding(.horizontal, 4)
                            .background(plate, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .fixedSize()
                            .offset(x: flip ? 8 : -8, y: flip ? 8 : -8)
                    }
                    .position(c)
            } else {
                let below = today.value > 85
                let nearRight = today.x > 0.72
                HaloText(text: "\(Int(chart.current.rounded()))%", size: size, halo: paper)
                    .fixedSize()
                    .position(x: nearRight ? c.x - size * 1.7 : c.x + size * 1.6,
                              y: below ? c.y + size * 1.05 : c.y - size * 1.05)
            }
        }

        // Day letters: today bold Ink, past days Ink 3, future days faint.
        ForEach(0..<7, id: \.self) { d in
            let date = calendar.date(byAdding: .day, value: d, to: chart.windowStart) ?? chart.windowStart
            Text(WeeklyChart.Formatters(calendar: calendar).letter(date))
                .font(.system(size: compact ? 9 : 11, weight: d == chart.today ? .bold : (compact ? .regular : .medium)))
                .foregroundStyle(d == chart.today ? UsageColor.ink(style)
                                 : d < chart.today ? UsageColor.ink3(style)
                                 : (style == .full ? AnyShapeStyle(Color("PaceLine")) : AnyShapeStyle(.quaternary)))
                .fixedSize()
                .position(x: g.x(chart.dayCenters[d]), y: g.size.height - g.letterBand / 2)
        }
    }

    private var accessibilityText: String {
        let pace = Int((min(max(now.timeIntervalSince(chart.windowStart) / chart.resetsAt.timeIntervalSince(chart.windowStart), 0), 1) * 100).rounded())
        return "All models this week: \(Int(chart.current.rounded())) percent used so far. An even pace would be \(pace) percent by now."
    }
}

/// Text with a soft halo in the surface color, so it reads over the lines.
private struct HaloText: View {
    let text: String
    let size: CGFloat
    let halo: Color
    @Environment(\.usageStyle) private var style

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) * .pi / 4
                Text(text).font(.clausagePercent(size)).foregroundStyle(halo)
                    .offset(x: cos(a) * 2, y: sin(a) * 2)
            }
            Text(text).font(.clausagePercent(size)).foregroundStyle(UsageColor.ink(style))
        }
    }
}

/// 6f: fewer than two readings, so no chart yet. Just the tally.
struct NotEnoughYet: View {
    @Environment(\.usageStyle) private var style
    var body: some View {
        VStack(spacing: 8) {
            Tally(size: 34, filled: 1)
            Text("One tally down").font(.system(size: 16, weight: .semibold)).foregroundStyle(UsageColor.ink(style))
            Text("Clausage just started counting. Your week shows up here once it has a couple of readings to connect.")
                .font(.system(size: 13)).foregroundStyle(UsageColor.ink2(style))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
