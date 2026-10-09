import AppKit

enum MenuDisplay: String, CaseIterable {
    case off, percent, bars, fill
}

/// Draws the menubar item from the 12 logo rays, monochrome unless Fill is in accent color.
/// In Fill and Percent modes the rays fill in clockwise from the top as All models is used: rays 1, 2 … 12, so
/// `round(pct / 100 × 12)` rays are filled; filled rays at 100% of the template color, empty rays at 32%.
/// Only the percent text can take a pressure color ("Tint percent by pressure"). Fill can opt into drawing its filled
/// rays in the system accent color over solid white ones ("Fill in accent color"; the app's Ember when the system
/// accent is Multicolor).
enum MenuBarIcon {
    /// Fill order: clockwise from the top (rays 1 … 12). Indices into `LogoRays.rays`.
    static let fillOrder = Array(0...11)

    static func pressureColor(_ limit: UsageLimit?) -> NSColor? {
        let m = limit?.percent ?? 0
        return m >= 95 ? .systemRed : (m >= 85 ? .systemOrange : nil)      // same thresholds as the popover bars
    }

    /// The limit the icon reflects: All models, or Session when the account has no All models limit. Never whichever
    /// limit happens to be highest, so the number doesn't silently switch between limits.
    static func shown(_ limits: [UsageLimit]) -> UsageLimit? {
        limits.first { $0.kind == "weekly_all" } ?? limits.first { $0.kind == "session" }
    }

    /// Number of filled rays (0...12) for a percent.
    static func raysFilled(_ pct: Double) -> Int { Int((min(max(pct, 0), 100) / 100 * 12).rounded()) }

    /// `darkMenubar` only matters when the image can't be a template (a tinted percent, or Fill with a pinned base):
    /// white rays on a dark menubar, near-black on a light one. `pinnedBase` is "Fill logo base" set to White or Dark.
    /// `free`: a Free plan has nothing to count, so every display mode shows the empty icon (all rays at glass
    /// opacity, no number, no bars). The saved mode is untouched and applies again once there's usage.
    static func image(display: MenuDisplay, limits: [UsageLimit], tint: Bool, darkMenubar: Bool = true,
                      pinnedBase: Bool = false, accentFill: Bool = false, free: Bool = false) -> NSImage {
        let display = free ? .off : display
        let limits = free ? [] : limits
        let top = shown(limits)
        let session = limits.first { $0.kind == "session" }
        let weekly = limits.first { $0.kind == "weekly_all" }
        let fills = display == .fill || display == .percent
        let lit = free ? 0 : (fills ? raysFilled(top?.percent ?? 0) : 12)
        let pressure = (display == .percent && tint) ? pressureColor(top) : nil
        let accent = display == .fill && accentFill
        let template = pressure == nil && !(display == .fill && (pinnedBase || accent))
        let base: NSColor = template ? .black : (accent ? .white : (darkMenubar ? .white : NSColor(white: 0.12, alpha: 1)))
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
                // Accent Fill: filled rays in the accent color, the rest solid white underneath.
                (accent ? (k < lit ? NSColor.controlAccentColor : .white) : base.withAlphaComponent(k < lit ? 1 : 0.32)).setFill()
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
        img.accessibilityDescription = free ? "Clausage, Free plan" : top.map { "Clausage, \(Forecast.shortName($0)) \(Int($0.percent.rounded())) percent" } ?? "Clausage"
        return img
    }
}
