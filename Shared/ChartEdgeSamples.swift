#if DEBUG
import Foundation

/// Debug aid for the galleries: weekly charts with today's dot at the plot's edges (start of the week at 0%, end of the
/// week, near the Limit line), so the value label's placement can be checked in every place the chart is drawn.
enum ChartEdgeSamples {
    static let cases: [(name: String, x: Double, value: Double)] = [
        ("start-0", 0.01, 0), ("mid-40", 0.45, 40), ("end-70", 0.99, 70), ("top-98", 0.5, 98), ("end-99", 0.99, 99)]

    /// A straight climb from (window start, 0) to (`x`, `value`), with a hollow marker at each past day's end.
    static func chart(x: Double, value: Double) -> WeeklyChart {
        let start = Calendar.current.startOfDay(for: UsageFixtures.now)
        let today = min(6, Int(x * 7))
        var points: [WeeklyChart.Point] = (0..<today).map { d in
            let dx = Double(d + 1) / 7
            return WeeklyChart.Point(day: d, value: value * dx / x, kind: .measured, x: dx)
        }
        points.append(WeeklyChart.Point(day: today, value: value, kind: .measured, x: x))
        let line = (0...12).map { i in WeeklyChart.Sample(x: x * Double(i) / 12, value: value * Double(i) / 12) }
        return WeeklyChart(today: today, points: points, line: line, beforeInstall: false, gapFromStart: false, ghost: nil,
                           dayCenters: (0..<7).map { (Double($0) + 0.5) / 7 }, current: value, windowStart: start,
                           resetsAt: start.addingTimeInterval(7 * 86_400), rightLabel: "Running total", caption: "")
    }
}
#endif
