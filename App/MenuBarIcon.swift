import AppKit

enum MenuDisplay: String, CaseIterable {
    case off, percent, bars, fill
}

/// Draws the menubar item from the 12 logo rays, always monochrome (Ember never appears in the menu bar).
/// In Fill and Percent modes the rays fill in clockwise as the highest limit is used: rays 11, 12, 1, 2 … 10, so
/// `round(pct / 100 × 12)` rays are filled; filled rays at 100% of the template color, empty rays at 32%.
/// Only the percent text can take a pressure color ("Tint percent by pressure"); the icon is never tinted.
enum MenuBarIcon {
    /// Fill order: the two upper-left rays (11 and 12), then clockwise from the top (1 … 10). Indices into `LogoRays.rays`.
    static let fillOrder = [10, 11] + Array(0...9)

    static func pressureColor(_ limits: [UsageLimit]) -> NSColor? {
        let m = limits.map(\.percent).max() ?? 0
        return m >= 95 ? .systemRed : (m >= 85 ? .systemOrange : nil)      // same thresholds as the popover bars
    }

    /// The limit the icon reflects: the highest one.
    static func highest(_ limits: [UsageLimit]) -> UsageLimit? { limits.max { $0.percent < $1.percent } }

    /// Number of filled rays (0...12) for a percent.
    static func raysFilled(_ pct: Double) -> Int { Int((min(max(pct, 0), 100) / 100 * 12).rounded()) }

    /// `darkMenubar` only matters when the image can't be a template (a tinted percent, or Fill with a pinned base):
    /// white rays on a dark menubar, near-black on a light one. `pinnedBase` is "Fill logo base" set to White or Dark.
    static func image(display: MenuDisplay, limits: [UsageLimit], tint: Bool, darkMenubar: Bool = true,
                      pinnedBase: Bool = false) -> NSImage {
        let top = highest(limits)
        let session = limits.first { $0.kind == "session" }
        let weekly = limits.first { $0.kind == "weekly_all" }
        let fills = display == .fill || display == .percent
        let lit = fills ? raysFilled(top?.percent ?? 0) : 12
        let pressure = (display == .percent && tint) ? pressureColor(limits) : nil
        let template = pressure == nil && !(display == .fill && pinnedBase)
        let base: NSColor = template ? .black : (darkMenubar ? .white : NSColor(white: 0.12, alpha: 1))
        let height: CGFloat = 18, logoSize: CGFloat = 16

        var text: NSAttributedString?
        var extra: CGFloat = 0
        switch display {
        case .off, .fill: break
        case .percent:
            if let top {
                let t = NSAttributedString(string: "\(Int(top.percent.rounded()))%", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: pressure ?? base])
                text = t; extra = 4 + ceil(t.size().width)
            }
        case .bars: if session != nil { extra = 4 + 22 }
        }

        let img = NSImage(size: NSSize(width: logoSize + extra, height: height), flipped: false) { _ in
            let originY = (height - logoSize) / 2
            func path(_ pts: [(Double, Double)]) -> NSBezierPath {
                let p = NSBezierPath()
                for (i, pt) in pts.enumerated() {
                    let q = NSPoint(x: pt.0 / 24 * logoSize, y: originY + (24 - pt.1) / 24 * logoSize)   // SVG y is down
                    i == 0 ? p.move(to: q) : p.line(to: q)
                }
                p.close()
                return p
            }
            for (k, index) in fillOrder.enumerated() {
                base.withAlphaComponent(k < lit ? 1 : 0.32).setFill()
                path(LogoRays.rays[index]).fill()
            }

            let x0 = logoSize + 4
            switch display {
            case .off, .fill: break
            case .percent:
                text?.draw(at: NSPoint(x: x0, y: (height - (text?.size().height ?? 0)) / 2))
            case .bars:
                for (i, l) in [session, weekly ?? session].enumerated() {
                    guard let l else { continue }
                    let y: CGFloat = i == 0 ? 10.5 : 4.5
                    let track = NSRect(x: x0, y: y, width: 22, height: 3.5)
                    base.withAlphaComponent(0.32).setFill()
                    NSBezierPath(roundedRect: track, xRadius: 1.75, yRadius: 1.75).fill()
                    var fill = track; fill.size.width = max(3.5, 22 * CGFloat(min(l.percent, 100) / 100))
                    base.setFill()
                    NSBezierPath(roundedRect: fill, xRadius: 1.75, yRadius: 1.75).fill()
                }
            }
            return true
        }
        img.isTemplate = template
        img.accessibilityDescription = top.map { "Clausage, \(Forecast.shortName($0)) \(Int($0.percent.rounded())) percent" } ?? "Clausage"
        return img
    }
}
