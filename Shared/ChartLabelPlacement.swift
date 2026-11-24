import CoreGraphics

/// Where today's value label ("0%", "72%") goes on the weekly running-total chart. Pure geometry, so it's unit-tested
/// (`ChartLabelPlacementTests`); `RunningTotalChart` feeds it the label's measured size.
///
/// The label sits `gap` away from the dot on its preferred sides and flips to the other side of an axis when it wouldn't
/// fit in `plot`, so it never runs off the card: right of the dot at the start of the week, left of it at the end, below
/// it near the Limit line. Because it is always offset from the dot on both axes, it never covers the dot. Only when the
/// plot is too small for either side does it clamp to the plot's edge.
enum ChartLabelPlacement {
    /// - Parameters:
    ///   - dot: the center of today's dot.
    ///   - label: the label's size.
    ///   - plot: the area the label must stay inside (the Limit line at the top, the 0% line at the bottom).
    ///   - gap: from the dot's center to the label's nearest edge, horizontally and vertically.
    ///   - preferLeft: the side when the label is above the dot and both sides fit. Below the dot it always prefers the
    ///     right, because the line comes in from the lower left.
    ///   - preferAbove: the vertical side when both fit.
    ///   - topClearance: above the dot, the label's top must stay at least this far below `plot.minY`, or it goes below.
    /// - Returns: the label's top-left corner.
    static func origin(dot: CGPoint, label: CGSize, plot: CGRect, gap: CGSize,
                       preferLeft: Bool, preferAbove: Bool, topClearance: CGFloat = 0) -> CGPoint {
        let aboveY = dot.y - gap.height - label.height
        let belowY = dot.y + gap.height
        let fitsAbove = aboveY >= plot.minY + topClearance
        let fitsBelow = belowY + label.height <= plot.maxY
        let above: Bool
        switch (fitsAbove, fitsBelow) {
        case (true, true): above = preferAbove
        case (true, false): above = true
        case (false, true): above = false
        case (false, false): above = dot.y - plot.minY > plot.maxY - dot.y  // the side with more room
        }

        let leftX = dot.x - gap.width - label.width
        let rightX = dot.x + gap.width
        let fitsLeft = leftX >= plot.minX
        let fitsRight = rightX + label.width <= plot.maxX
        let wantsLeft = above && preferLeft
        let left: Bool
        switch (fitsLeft, fitsRight) {
        case (true, true): left = wantsLeft
        case (true, false): left = true
        case (false, true): left = false
        case (false, false): left = dot.x - plot.minX > plot.maxX - dot.x
        }

        return CGPoint(x: clamp(left ? leftX : rightX, plot.minX, plot.maxX - label.width),
                       y: clamp(above ? aboveY : belowY, plot.minY, plot.maxY - label.height))
    }

    /// Keeps `v` in `lo...hi`; `lo` wins when the label is bigger than the plot.
    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(lo, min(v, hi)) }
}
