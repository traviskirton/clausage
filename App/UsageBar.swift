import SwiftUI

/// One popover limit: name and percent, a 6pt bar with a pace tick, and a forecast line when it is projected to run out.
/// Hovering the row crossfades the name to when it resets.
struct UsageBar: View {
    let limit: UsageLimit
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var level: Forecast.Level { Forecast.level(limit) }
    private var hit: Date? { Forecast.hitDate(limit) }
    /// Short row name: "Current session", "All models", "Fable".
    private var name: String { Forecast.fullName(limit) }

    private var forecastText: String? { Forecast.forecastText(limit) }

    private var hoverText: String { Forecast.resetText(limit) ?? name }

    private var accessibilityText: String {
        var s = "\(name), \(Int(limit.percent.rounded())) percent used"
        if level != .normal, let hit {
            let when = limit.windowLength > 86_400
                ? hit.formatted(.dateTime.weekday(.wide).hour().minute())
                : hit.formatted(.dateTime.hour().minute())
            s += ", out around \(when)"
        }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                ZStack(alignment: .leading) {
                    Text(name).opacity(hovering ? 0 : 1)
                    Text(hoverText).opacity(hovering ? 1 : 0)
                }
                .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 6)
                Text("\(Int(limit.percent.rounded()))%")
                    .font(.clausagePercent(15)).brandTracking(-0.03, size: 15)      // never colored
            }
            .frame(height: 15)      // line box ≈ font size, so the 5pt/12pt gaps read as 5pt/12pt
            .foregroundStyle(Color("Ink"))

            LimitBar(limit: limit, height: 6, tick: 10)

            if let text = forecastText {
                Text(text)
                    .font(.system(size: 11)).foregroundStyle(UsageColor.text(level))
                    .frame(height: 11)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: forecastText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

/// A capsule bar: Sand track, the level's fill (warm gray, orange at 85%, red at 95%), and a 2pt Ink pace tick that
/// stands `tick` tall, with a transparent 1.5pt knock-out around it so it reads on any surface.
struct LimitBar: View {
    let limit: UsageLimit
    var height: CGFloat = 6
    var tick: CGFloat = 10
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var level: Forecast.Level { Forecast.level(limit) }

    /// Sand tracks (a translucent warm white in dark mode); stronger with Increase Contrast.
    private var trackColor: Color {
        if contrast == .increased { return Color("Ink").opacity(scheme == .dark ? 0.30 : 0.20) }
        return Color("Sand")
    }

    var body: some View {
        GeometryReader { g in
            let fillWidth = g.size.width * min(max(limit.percent, 0), 100) / 100
            let pace = Forecast.elapsed(limit)
            ZStack(alignment: .leading) {
                trackColor
                Capsule().fill(UsageColor.fill(level)).frame(width: max(fillWidth, limit.percent > 0 ? height : 0))
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: limit.percent)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: level)
            // rounded bar shape, with a transparent 1.5pt knock-out around the pace tick
            .mask {
                // The knock-out is an overlay so its height can't resize the bar's capsule.
                Capsule().fill(Color.black)
                    .overlay(alignment: .leading) {
                        if let pace, contrast != .increased {
                            Capsule()
                                .frame(width: 5, height: tick + 3)
                                .offset(x: g.size.width * pace - 2.5)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
            }
            .overlay(alignment: .leading) {
                if let pace {
                    Capsule().fill(Color("Ink"))
                        .frame(width: 2, height: tick)
                        .frame(width: 2, height: height)
                        .offset(x: g.size.width * pace - 1)
                }
            }
        }
        .frame(height: height)
    }
}
