import SwiftUI
import WidgetKit
import AppIntents

// MARK: Bar

/// -45° stripes: 3pt fill, 2pt gap. Used for critical state when color can't carry it.
struct Stripes: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let h = rect.height, step: CGFloat = 5, stripe: CGFloat = 3
        var x = rect.minX - h
        while x < rect.maxX + h {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + stripe, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + stripe + h, y: rect.minY))
            p.addLine(to: CGPoint(x: x + h, y: rect.minY))
            p.closeSubpath()
            x += step
        }
        return p
    }
}

struct UsageBar: View {
    let limit: UsageLimit
    let now: Date
    let height: CGFloat
    var stale = false
    /// The color behind the bar, used for the cut-out ring around the pace tick.
    var ring: Color = UsageColor.surface

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.usageStyle) private var style
    @Environment(\.usageTint) private var tint

    private var level: Forecast.Level { Forecast.level(limit) }
    private var track: Color {
        let high = contrast == .increased
        if style == .full { return high ? Color("Ink").opacity(0.22) : Color("Sand") }
        return Color.white.opacity(high ? 0.30 : 0.22)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fillW = max(limit.percent > 0 ? height : 0, w * min(max(limit.percent, 0), 100) / 100)
            ZStack(alignment: .leading) {
                Capsule().fill(track).frame(height: height)
                fill(width: fillW)
                if DisplayPrefs.showPaceTick, let e = Forecast.elapsed(limit, now: now) { tick.offset(x: w * e - 1) }
            }
        }
        .frame(height: height)
        .opacity(stale ? 0.5 : 1)
    }

    @ViewBuilder private func fill(width: CGFloat) -> some View {
        if style == .accented {
            if level == .critical {
                Stripes().fill(tint).frame(width: width, height: height).clipShape(Capsule()).widgetAccentable()
            } else {
                Capsule().fill(tint).frame(width: width, height: height).widgetAccentable()
            }
        } else {
            Capsule().fill(UsageColor.fill(level)).frame(width: width, height: height)
        }
    }

    /// 2pt Ink tick, 2pt taller than the bar on each end, cut out of the bar by a 1.5pt ring in the surface color.
    private var tick: some View {
        ZStack {
            if style == .full && contrast != .increased {
                Capsule().fill(ring).frame(width: 5, height: height + 7)
            }
            Capsule().fill(style == .full ? AnyShapeStyle(Color("Ink")) : AnyShapeStyle(.primary)).frame(width: 2, height: height + 4)
        }
        .frame(width: 2)
    }
}

// MARK: Row

struct UsageRow: View {
    let limit: UsageLimit
    let now: Date
    let size: UsageSize
    var stale = false
    /// The Usage screen marks the binding limit with a "Limiting now" chip.
    var showActiveChip = false
    var ring: Color = UsageColor.surface

    @Environment(\.usageStyle) private var style
    @Environment(\.usageTint) private var tint

    private var level: Forecast.Level { Forecast.level(limit) }
    private var name: String { size == .small ? Forecast.shortName(limit) : Forecast.fullName(limit) }
    private var forecast: String? { Forecast.forecastText(limit, now: now) }
    private var forecastColor: Color { style == .accented ? tint : UsageColor.text(level) }

    var body: some View {
        VStack(alignment: .leading, spacing: size.innerGap) {
            HStack(alignment: .center, spacing: 8) {
                Text(name).font(.system(size: size.label, weight: size.labelWeight))
                    .foregroundStyle(UsageColor.ink(style))
                if showActiveChip, limit.isActive == true {
                    BrandChip(text: "Limiting now", size: 11)
                }
                Spacer(minLength: 6)
                Text("\(Int(limit.percent.rounded()))%")
                    .font(.clausagePercent(size.percent))      // never colored
                    .foregroundStyle(UsageColor.ink(style))
                    .opacity(stale ? 0.5 : 1)
            }
            .frame(height: size.percent)      // a fixed line box, so tight widgets don't squeeze some rows' text
            .lineLimit(1).minimumScaleFactor(0.8)

            UsageBar(limit: limit, now: now, height: size.barHeight, stale: stale, ring: ring)

            detail
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var detail: some View {
        if size.showsResetLine {
            let font: CGFloat = size == .screen ? 13 : 12
            HStack {
                if let r = Forecast.resetText(limit) {
                    Text(r).font(.system(size: font)).foregroundStyle(UsageColor.ink2(style))
                }
                Spacer(minLength: 6)
                if let f = forecast {
                    Text(f).font(.system(size: font, weight: .semibold)).foregroundStyle(forecastColor).widgetAccentable(style == .accented)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
        } else if let f = forecast {
            Text(f).font(.system(size: size.forecast, weight: .medium)).foregroundStyle(forecastColor)
                .widgetAccentable(style == .accented)
                .frame(height: size.forecast, alignment: .leading).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private var accessibilityText: String {
        var s = "\(Forecast.fullName(limit)), \(Int(limit.percent.rounded())) percent used"
        if showActiveChip, limit.isActive == true { s += ", limiting now" }
        if level != .normal, let hit = Forecast.hitDate(limit, now: now) {
            let when = limit.windowLength > 86_400
                ? hit.formatted(.dateTime.weekday(.wide).hour().minute())
                : hit.formatted(.dateTime.hour().minute())
            s += ", out around \(when)"
        } else if size.showsResetLine, let r = limit.resetsAt {
            s += ", resets \(Forecast.timeText(r, window: limit.windowLength))"
        }
        return s
    }
}

// MARK: Content per widget size

struct SignInPrompt: View {
    var text = "Open the app to sign in"
    @Environment(\.usageStyle) private var style
    var body: some View {
        Text(text)
            .font(.footnote).foregroundStyle(UsageColor.ink2(style)).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Paper → warm Paper, top to bottom: the Home Screen and desktop widget background.
struct WidgetPaper: View {
    var body: some View {
        LinearGradient(colors: [Color("Paper"), Color("WidgetBottom")], startPoint: .top, endPoint: .bottom)
    }
}

struct UsageContent: View {
    let size: UsageSize
    let snapshot: SharedStore.Snapshot?
    /// The running total recorded by the app (large widget chart).
    var history: WeeklyHistory? = nil
    let now: Date
    /// Very large Dynamic Type: the small widget keeps only Session and All models.
    var compact = false
    /// The large widget's "Updated … ↻" refreshes in place (iOS); elsewhere it's plain text.
    var refreshable = true

    @Environment(\.usageStyle) private var style

    var body: some View {
        if let s = snapshot, s.cleared == true {
            SignInPrompt(text: "No data")
        } else if let s = snapshot, s.connected, !s.limits.isEmpty {
            filled(s)
        } else if let s = snapshot, s.connected {
            SignInPrompt(text: "Nothing to count")
        } else {
            SignInPrompt()
        }
    }

    @ViewBuilder private func filled(_ s: SharedStore.Snapshot) -> some View {
        let stale = Forecast.isStale(updated: s.updated, now: now)
        let all = DisplayPrefs.visible(s.limits)
        if size == .large {
            let chart = s.weekly.flatMap { WeeklyChart.make(history: history ?? WeeklyHistory(), window: $0, now: now) }
            let hasChart = s.weekly != nil
            let rows = Array(all.prefix(hasChart ? 3 : 5))
            VStack(alignment: .leading, spacing: 0) {
                header(s, stale: stale)
                Spacer().frame(height: 12)
                VStack(spacing: size.rowGap) {
                    ForEach(rows) { UsageRow(limit: $0, now: now, size: size, stale: stale) }
                }
                Spacer(minLength: 8)
                if let w = s.weekly {
                    let level = s.limits.first { $0.kind == "weekly_all" }.map(Forecast.level) ?? (w.percent >= 95 ? .critical : w.percent >= 85 ? .warning : .normal)
                    chartBlock(chart, level: level)
                }
            }
        } else {
            let rows = Array(all.prefix(size == .small && compact ? 2 : 3))
            VStack(spacing: size.rowGap) {
                ForEach(rows) { UsageRow(limit: $0, now: now, size: size, stale: stale) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Mark + "clausage" wordmark, with "Updated 10:44 AM ↻" on the right.
    private func header(_ s: SharedStore.Snapshot, stale: Bool) -> some View {
        HStack(spacing: 6) {
            BrandMark(size: 16, ink: style == .full ? Color("Ink") : .primary, ember: style == .full ? Color("Ember") : .primary)
            Text("clausage").font(.clausageDisplay(19)).brandTracking(-0.035, size: 19).foregroundStyle(UsageColor.ink(style))
            Spacer(minLength: 6)
            updatedLabel(s, stale: stale)
        }
        .lineLimit(1)
    }

    @ViewBuilder private func updatedLabel(_ s: SharedStore.Snapshot, stale: Bool) -> some View {
        let label = HStack(spacing: 4) {
            Text(updatedText(s.updated, stale: stale))
            if refreshable { Image(systemName: "arrow.clockwise") }
        }
        .font(.system(size: 12)).foregroundStyle(UsageColor.ink2(style))
        #if os(iOS)
        if refreshable {
            Button(intent: RefreshUsageIntent()) { label }.buttonStyle(.plain)
        } else {
            label
        }
        #else
        label
        #endif
    }

    @ViewBuilder private func chartBlock(_ chart: WeeklyChart?, level: Forecast.Level) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("All models · this week").font(.system(size: 12, weight: .semibold)).foregroundStyle(UsageColor.ink(style))
                Spacer(minLength: 6)
                if let chart { Text(chart.rightLabel).font(.system(size: 12)).foregroundStyle(UsageColor.ink2(style)) }
            }
            .lineLimit(1)
            if let chart {
                RunningTotalChart(chart: chart, level: level, now: now, lineWidth: 4, compact: true)
                    .frame(height: 92)
            } else {
                HStack(spacing: 8) {
                    Tally(size: 22, filled: 1, ink: style == .full ? Color("Ink") : .primary)
                    Text("One tally down. Your week shows up once there are a couple of readings.")
                        .font(.system(size: 12)).foregroundStyle(UsageColor.ink2(style))
                }
                .frame(height: 40)
            }
        }
    }

    private func updatedText(_ updated: Date, stale: Bool) -> String {
        if stale {
            let h = max(Int(now.timeIntervalSince(updated) / 3600), 3)
            return "Updated \(h)h ago"
        }
        return "Updated \(updated.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: Lock Screen

#if os(iOS)
struct UsageGauge: View {
    let limit: UsageLimit
    var stale = false
    /// The widget uses the system's accessory background; the in-app gallery draws its own.
    var plainBackground = false

    private var level: Forecast.Level { Forecast.level(limit) }
    private var progress: CGFloat { CGFloat(min(max(limit.percent, 0), 100) / 100) }

    var body: some View {
        ZStack {
            if plainBackground { Circle().fill(Color.white.opacity(0.14)) } else { AccessoryWidgetBackground() }
            ring.padding(4)
            VStack(spacing: 0) {
                Text("\(Int(limit.percent.rounded()))")
                    .font(.system(size: 18, weight: .bold)).monospacedDigit()
                Text(Forecast.gaugeName(limit))
                    .font(.system(size: 9, weight: .semibold)).opacity(0.75)
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 10)
            .opacity(stale ? 0.5 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Forecast.gaugeName(limit)), \(Int(limit.percent.rounded())) percent used")
    }

    private var ring: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let circumference = .pi * (d - 5)
            // Critical: radial stripes, about 4° on and 3° off.
            let stripes = StrokeStyle(lineWidth: 5, dash: [circumference * 4 / 360, circumference * 3 / 360])
            ZStack {
                Circle().inset(by: 2.5).stroke(Color.white.opacity(0.30), lineWidth: 5)
                Circle().inset(by: 2.5).trim(from: 0, to: progress)
                    .rotation(.degrees(-90))
                    .stroke(Color.white, style: level == .critical ? stripes : StrokeStyle(lineWidth: 5))
                    .widgetAccentable()
            }
            .frame(width: d, height: d)
            .opacity(stale ? 0.5 : 1)
        }
    }
}
#endif

/// Inline Lock Screen text: the most pressing limit, `Session 96% · Out ~11:20 AM`.
enum UsageInline {
    static func text(_ s: SharedStore.Snapshot?, now: Date) -> String {
        guard let s, s.connected, let l = Forecast.mostPressing(DisplayPrefs.visible(s.limits)) else { return "Open the app to sign in" }
        let head = "\(Forecast.shortName(l)) \(Int(l.percent.rounded()))%"
        guard let tail = Forecast.forecastText(l, now: now) ?? Forecast.resetText(l) else { return head }
        return "\(head) · \(tail)"
    }
}
