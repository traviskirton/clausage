import SwiftUI

/// "All models · this week" as a running total toward the limit (design 5b, states 6a–6e).
/// x = the 7 days of the window, y = 0–100%. The line is in the All models state color; Ember never appears.
struct RunningTotalChart: View {
    let chart: WeeklyChart
    let level: Forecast.Level
    var now: Date = Date()
    /// 5pt in the app, 4pt in the large widget.
    var lineWidth: CGFloat = 5
    /// Smaller markers and labels (large widget).
    var compact = false
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
        var step: CGFloat { (size.width - left - right) / 6 }
        func x(_ day: Double) -> CGFloat { left + CGFloat(day) * step }
        func y(_ v: Double) -> CGFloat { plotBottom - CGFloat(min(max(v, 0), 100) / 100) * plotHeight }
        func p(_ day: Double, _ v: Double) -> CGPoint { CGPoint(x: x(day), y: y(v)) }
        /// The window starts a little before day 1's point.
        var originX: Double { -0.2 }
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext, _ g: Geometry) {
        let ink3 = style == .full ? Color("Ink3") : Color.white.opacity(0.5)
        let paceColor = style == .full ? Color("PaceLine") : Color.white.opacity(0.35)

        // Limit: dotted line at 100%.
        var limit = Path()
        limit.move(to: CGPoint(x: g.left, y: g.y(100)))
        limit.addLine(to: CGPoint(x: g.size.width - g.right, y: g.y(100)))
        ctx.stroke(limit, with: .color(ink3.opacity(0.8)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [0.1, 4]))

        // Even pace: 1/7 at day 1 to 100% at day 7.
        var pace = Path()
        pace.move(to: g.p(0, WeeklyChart.pace(day: 0)))
        pace.addLine(to: g.p(6, 100))
        ctx.stroke(pace, with: .color(paceColor), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))

        // Last week, faint, while this week is still short (6e).
        if let ghost = chart.ghost {
            var p = Path()
            for (d, v) in ghost.enumerated() { d == 0 ? p.move(to: g.p(0, v)) : p.addLine(to: g.p(Double(d), v)) }
            let ghostColor = style == .full ? Color("Ghost") : Color.white.opacity(0.3)
            ctx.stroke(p, with: .color(ghostColor), style: StrokeStyle(lineWidth: compact ? 2.5 : 3, lineCap: .round, lineJoin: .round))
        }

        let pts = chart.points
        guard let first = pts.first else { return }

        // Before install (6a/6b): dotted Ink 3 from (window start, 0) to the first point.
        if chart.beforeInstall {
            var p = Path()
            p.move(to: g.p(g.originX, 0))
            p.addLine(to: g.p(Double(first.day), first.value))
            ctx.stroke(p, with: .color(ink3), style: StrokeStyle(lineWidth: compact ? 1.5 : 2, lineCap: .round, dash: [0.1, compact ? 3.5 : 4.5]))
        }

        let dashed = StrokeStyle(lineWidth: lineWidth * 0.8, lineCap: .round, lineJoin: .round, dash: [0.1, lineWidth * 1.7])
        let solid = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let shading: GraphicsContext.Shading = .color(lineColor)

        // Missed days from the window start (installed earlier, app didn't run): dashed from (start, 0).
        if chart.gapFromStart {
            var p = Path()
            p.move(to: g.p(g.originX, 0))
            p.addLine(to: g.p(Double(first.day), first.value))
            ctx.stroke(p, with: shading, style: dashed)
        }

        // Day-to-day segments: solid between measured days, dashed across a missed day (6c).
        if pts.count > 1 {
            for i in 1..<pts.count {
                let a = pts[i - 1], b = pts[i]
                var p = Path()
                p.move(to: g.p(Double(a.day), a.value))
                p.addLine(to: g.p(Double(b.day), b.value))
                ctx.stroke(p, with: shading, style: (a.kind == .missing || b.kind == .missing) ? dashed : solid)
            }
        }

        // Markers: hollow Paper dots for past days, a dashed ring for a missed day, a filled dot for today.
        let r: CGFloat = compact ? 2.5 : 3
        for pt in pts where pt.day != chart.today || pt.kind == .missing {
            let c = g.p(Double(pt.day), pt.value)
            if pt.kind == .missing {
                let rr = r + 1.5
                let circle = Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
                ctx.fill(circle, with: .color(paper))
                ctx.stroke(circle, with: shading, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
            } else {
                let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.fill(circle, with: .color(paper))
                ctx.stroke(circle, with: shading, lineWidth: 1.5)
            }
        }
        if let today = pts.last(where: { $0.day == chart.today && $0.kind == .measured }) {
            let c = g.p(Double(today.day), today.value)
            let tr: CGFloat = compact ? 4.5 : 5.5
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

        if chart.beforeInstall, let first = chart.points.first {
            let mid = g.p((g.originX + Double(first.day)) / 2, first.value / 2)
            Text("Before Clausage").font(.system(size: small)).foregroundStyle(UsageColor.ink3(style))
                .fixedSize()
                .position(x: max(mid.x, g.left + 40), y: mid.y + (compact ? 9 : 12))
        }

        // Today's running total, with a Paper halo; above the point, or below once it's over 85%.
        if let today = chart.points.last(where: { $0.day == chart.today }) {
            let c = g.p(Double(today.day), today.value)
            let below = today.value > 85
            let nearRight = today.day >= 5
            let size: CGFloat = compact ? 11 : 14
            HaloText(text: "\(Int(chart.current.rounded()))%", size: size, halo: paper)
                .fixedSize()
                .position(x: nearRight ? c.x - size * 1.7 : c.x + size * 1.6,
                          y: below ? c.y + size * 1.05 : c.y - size * 1.05)
        }

        // Day letters: today bold Ink, past days Ink 3, future days faint.
        ForEach(0..<7, id: \.self) { d in
            let date = calendar.date(byAdding: .day, value: d, to: chart.windowStart) ?? chart.windowStart
            Text(WeeklyChart.Formatters(calendar: calendar).letter(date))
                .font(.system(size: compact ? 9 : 11, weight: d == chart.today ? .bold : .regular))
                .foregroundStyle(d == chart.today ? UsageColor.ink(style)
                                 : d < chart.today ? UsageColor.ink3(style)
                                 : (style == .full ? AnyShapeStyle(Color("PaceLine")) : AnyShapeStyle(.quaternary)))
                .fixedSize()
                .position(x: g.x(Double(d)), y: g.size.height - g.letterBand / 2)
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
