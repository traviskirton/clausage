import SwiftUI

enum Palette {
    static let panelDark = Color(red: 0.137, green: 0.141, blue: 0.161)     // ≈ #232429
    static let panelLight = Color(red: 0.965, green: 0.965, blue: 0.969)    // ≈ #F6F6F7
    static let track = Color.primary.opacity(0.07)      // white in dark mode, black in light mode
    static let blue = Color(red: 0.27, green: 0.47, blue: 0.97)
    static let orange = Color(red: 0.88, green: 0.56, blue: 0.20)
    static let red = Color(red: 0.90, green: 0.30, blue: 0.30)

    static func panel(_ scheme: ColorScheme) -> Color { scheme == .dark ? panelDark : panelLight }

    /// Forecast line colors, darkened in light mode for 4.5:1 contrast.
    static func warningText(_ scheme: ColorScheme) -> Color { Color("NearText") }
    static func criticalText(_ scheme: ColorScheme) -> Color { Color("CriticalText") }
}

/// One limit: name and percent, a 6pt bar with a pace tick, and a forecast line when it is projected to run out.
/// Hovering the row crossfades the name to when it resets.
struct UsageBar: View {
    let limit: UsageLimit
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var level: Forecast.Level { Forecast.level(limit) }
    private var hit: Date? { Forecast.hitDate(limit) }
    /// Short row name: "Current session", "All models", "Fable".
    private var name: String { limit.title.replacingOccurrences(of: "Weekly · ", with: "") }

    /// Calm bars are warm gray so orange and red stand out; no accent color, so no accent-clash zebra.
    private var fill: Color {
        switch level {
        case .normal: return Color("CalmBar")
        case .warning: return Color("NearFill")
        case .critical: return Color("CriticalFill")
        }
    }

    private var forecastColor: Color { level == .critical ? Palette.criticalText(scheme) : Palette.warningText(scheme) }

    private var forecastText: String? {
        guard level != .normal, let hit else { return nil }
        return "Out ~\(Forecast.timeText(hit, window: limit.windowLength))"
    }

    private var hoverText: String {
        if let r = limit.resetsAt { return "Resets \(Forecast.timeText(r, window: limit.windowLength))" }
        return name
    }

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

    /// Sand tracks (a translucent warm white in dark mode); stronger with Increase Contrast.
    private var trackColor: Color {
        if contrast == .increased { return Color("Ink").opacity(scheme == .dark ? 0.30 : 0.20) }
        return Color("Sand")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                ZStack(alignment: .leading) {
                    Text(name).opacity(hovering ? 0 : 1)
                    Text(hoverText).opacity(hovering ? 1 : 0)
                }
                .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 6)
                Text("\(Int(limit.percent.rounded()))%")
                    .font(.clausagePercent(13.5))      // Bricolage with fixed-width numerals; never colored
            }
            .frame(height: 13)      // line box ≈ font size, so the 5pt/10pt gaps read as 5pt/10pt
            .foregroundStyle(Color("Ink"))

            bar

            if let text = forecastText {
                Text(text)
                    .font(.system(size: 11)).foregroundStyle(forecastColor)
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

    private var bar: some View {
        GeometryReader { g in
            let fillWidth = g.size.width * min(max(limit.percent, 0), 100) / 100
            let pace = Forecast.elapsed(limit)
            ZStack(alignment: .leading) {
                trackColor
                Rectangle().fill(fill).frame(width: fillWidth)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: limit.percent)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: level)
            // rounded bar shape, with a transparent 1.5pt knock-out around the pace tick
            .mask {
                // The knock-out is an overlay so its 13pt height can't resize the 6pt rounded shape.
                RoundedRectangle(cornerRadius: 3).fill(Color.black)
                    .overlay(alignment: .leading) {
                        if let pace, contrast != .increased {
                            RoundedRectangle(cornerRadius: 2.5)
                                .frame(width: 5, height: 13)
                                .offset(x: g.size.width * pace - 2.5)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
            }
            .overlay(alignment: .leading) {
                if let pace {
                    PaceTick(color: Color("Ink"))
                        .offset(x: g.size.width * pace - 1)
                }
            }
        }
        .frame(height: 6)
    }
}

/// 2×10pt tick centered on the bar (the bar knocks out a 1.5pt ring around it, see `bar`).
private struct PaceTick: View {
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 1).fill(color)
            .frame(width: 2, height: 10)
            .frame(width: 2, height: 6)
            .fixedSize()
    }
}
