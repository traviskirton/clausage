import XCTest

/// Today's value label on the weekly chart (BUGS.md, 2026-11-10: "0%" ran off the card's left edge).
final class ChartLabelPlacementTests: XCTestCase {
    /// The Mac Settings card: 150pt tall chart, 520 wide, insets as `RunningTotalChart.Geometry` (12/12/16, letter band 20).
    private let settingsPlot = CGRect(x: 12, y: 16, width: 520 - 24, height: 150 - 16 - 20 - 6)
    /// The large widget's compact chart: 306 × 92, insets 8/8/12, letter band 14.
    private let widgetPlot = CGRect(x: 8, y: 12, width: 306 - 16, height: 92 - 12 - 14 - 4)
    private let plateLabel = CGSize(width: 34, height: 22)  // "0%" on its plate
    private let plateGap = CGSize(width: 8, height: 8)
    private let dotRadius: CGFloat = 5

    private func plate(_ dot: CGPoint, in plot: CGRect? = nil, label: CGSize? = nil) -> CGRect {
        let size = label ?? plateLabel
        let o = ChartLabelPlacement.origin(dot: dot, label: size, plot: plot ?? settingsPlot, gap: plateGap,
                                           preferLeft: true, preferAbove: true, topClearance: 16)
        return CGRect(origin: o, size: size)
    }

    private func dotRect(_ c: CGPoint) -> CGRect {
        CGRect(x: c.x - dotRadius, y: c.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
    }

    private func assertGood(_ label: CGRect, dot: CGPoint, plot: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(plot.contains(label), "label \(label) leaves the plot \(plot)", file: file, line: line)
        XCTAssertFalse(label.intersects(dotRect(dot)), "label \(label) covers the dot at \(dot)", file: file, line: line)
    }

    // The bug: dot at the left edge at 0% (start of the week). The label goes right of the dot, above it.
    func testLeftEdgeAtZero() {
        let dot = CGPoint(x: settingsPlot.minX + 1, y: settingsPlot.maxY)
        let r = plate(dot)
        assertGood(r, dot: dot, plot: settingsPlot)
        XCTAssertEqual(r.minX, dot.x + 8)
        XCTAssertEqual(r.maxY, dot.y - 8)
    }

    // End of the week: the dot at the right edge. The label goes left of it.
    func testRightEdgeEndOfWeek() {
        let dot = CGPoint(x: settingsPlot.maxX, y: settingsPlot.maxY - settingsPlot.height * 0.7)
        let r = plate(dot)
        assertGood(r, dot: dot, plot: settingsPlot)
        XCTAssertEqual(r.maxX, dot.x - 8)
    }

    // Near 100% the label would touch the Limit line, so it goes below the dot, and right of it (the line comes in
    // from the lower left).
    func testTopEdgeNearLimit() {
        let dot = CGPoint(x: settingsPlot.midX, y: settingsPlot.minY + settingsPlot.height * 0.02)
        let r = plate(dot)
        assertGood(r, dot: dot, plot: settingsPlot)
        XCTAssertEqual(r.minY, dot.y + 8)
        XCTAssertEqual(r.minX, dot.x + 8)
    }

    // Top-right corner: end of the week at 99%. Below and left.
    func testTopRightCorner() {
        let dot = CGPoint(x: settingsPlot.maxX, y: settingsPlot.minY + 1)
        let r = plate(dot)
        assertGood(r, dot: dot, plot: settingsPlot)
        XCTAssertEqual(r.minY, dot.y + 8)
        XCTAssertEqual(r.maxX, dot.x - 8)
    }

    // Mid-plot: unchanged from before the fix, above and left, 8pt off the dot.
    func testMidPlotUnchanged() {
        let dot = CGPoint(x: settingsPlot.midX, y: settingsPlot.midY + 20)
        let r = plate(dot)
        XCTAssertEqual(r.origin, CGPoint(x: dot.x - 8 - plateLabel.width, y: dot.y - 8 - plateLabel.height))
    }

    // The halo label (iPhone, widget): mid-plot it's above and right of the dot, as before.
    func testHaloMidPlotUnchanged() {
        let size: CGFloat = 11, label = CGSize(width: 24, height: 13)
        let gap = CGSize(width: size * 1.6 - label.width / 2, height: size * 1.05 - label.height / 2)
        let dot = CGPoint(x: widgetPlot.midX, y: widgetPlot.midY + 10)
        let o = ChartLabelPlacement.origin(dot: dot, label: label, plot: widgetPlot, gap: gap, preferLeft: false, preferAbove: true)
        // Before: centered at (dot.x + 1.6 size, dot.y - 1.05 size).
        XCTAssertEqual(o.x + label.width / 2, dot.x + size * 1.6, accuracy: 0.001)
        XCTAssertEqual(o.y + label.height / 2, dot.y - size * 1.05, accuracy: 0.001)
    }

    // Narrow widths: every edge case stays inside a 200pt and a 120pt widget plot and never covers the dot.
    func testNarrowWidths() {
        for width in [306.0, 200, 120] as [CGFloat] {
            let plot = CGRect(x: 8, y: 12, width: width - 16, height: 62)
            let label = CGSize(width: 30, height: 15)
            for (fx, fy) in [(0.0, 1.0), (0.01, 1.0), (0.5, 0.5), (0.99, 0.3), (1.0, 0.0), (0.5, 0.0), (0.0, 0.0), (1.0, 1.0)] as [(CGFloat, CGFloat)] {
                let dot = CGPoint(x: plot.minX + fx * plot.width, y: plot.minY + fy * plot.height)
                for (left, aboveFirst) in [(true, true), (false, true), (false, false)] {
                    let o = ChartLabelPlacement.origin(dot: dot, label: label, plot: plot, gap: CGSize(width: 6, height: 6),
                                                       preferLeft: left, preferAbove: aboveFirst, topClearance: 4)
                    assertGood(CGRect(origin: o, size: label), dot: dot, plot: plot)
                }
            }
        }
    }

    // A plot smaller than the label: pinned to the plot's top-left rather than anywhere outside it.
    func testLabelBiggerThanPlot() {
        let plot = CGRect(x: 8, y: 12, width: 20, height: 10)
        let o = ChartLabelPlacement.origin(dot: CGPoint(x: 18, y: 17), label: CGSize(width: 30, height: 15), plot: plot,
                                           gap: CGSize(width: 6, height: 6), preferLeft: true, preferAbove: true)
        XCTAssertEqual(o, CGPoint(x: 8, y: 12))
    }
}
