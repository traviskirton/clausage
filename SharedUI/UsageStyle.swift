import SwiftUI

/// Full color vs. the system's single-color rendering (Tinted and Clear Home Screens, Lock Screen, dimmed desktop widgets).
enum UsageRenderStyle { case full, accented }

private struct UsageStyleKey: EnvironmentKey { static let defaultValue = UsageRenderStyle.full }
private struct UsageTintKey: EnvironmentKey { static let defaultValue = Color.white }

extension EnvironmentValues {
    var usageStyle: UsageRenderStyle {
        get { self[UsageStyleKey.self] }
        set { self[UsageStyleKey.self] = newValue }
    }
    /// Color used for accentable parts in `.accented` style. The system overrides it in a real widget; only the in-app gallery uses it.
    var usageTint: Color {
        get { self[UsageTintKey.self] }
        set { self[UsageTintKey.self] = newValue }
    }
}

/// Brand state colors (dynamic, from the asset catalog). The percent text is never colored.
enum UsageColor {
    /// Calm is warm gray so orange (85%) and red (95%) stand out. Ember never fills a bar.
    static func fill(_ level: Forecast.Level) -> Color {
        switch level {
        case .normal: return Color("CalmBar")
        case .warning: return Color("NearFill")
        case .critical: return Color("CriticalFill")
        }
    }
    static func text(_ level: Forecast.Level) -> Color {
        switch level {
        case .normal: return Color("Ink2")
        case .warning: return Color("NearText")
        case .critical: return Color("CriticalText")
        }
    }
    /// Paper: widget top, screen background, and the cut-out ring around the pace tick.
    static let surface = Color("Paper")

    /// Ink text in full color; the system's primary in single-color modes (explicit dark colors would vanish there).
    static func ink(_ style: UsageRenderStyle) -> AnyShapeStyle { style == .full ? AnyShapeStyle(Color("Ink")) : AnyShapeStyle(.primary) }
    static func ink2(_ style: UsageRenderStyle) -> AnyShapeStyle { style == .full ? AnyShapeStyle(Color("Ink2")) : AnyShapeStyle(.secondary) }
    static func ink3(_ style: UsageRenderStyle) -> AnyShapeStyle { style == .full ? AnyShapeStyle(Color("Ink3")) : AnyShapeStyle(.tertiary) }
}

enum UsageSize {
    case small, medium, large
    /// The app's Usage screen.
    case screen

    var label: CGFloat { switch self { case .small: 12; case .medium: 13; case .large: 15; case .screen: 17 } }
    var labelWeight: Font.Weight { self == .small ? .medium : .semibold }
    /// Bricolage %: the label size + 2 in widgets, 18 on the screen.
    var percent: CGFloat { switch self { case .small: 14; case .medium: 15; case .large: 17; case .screen: 18 } }
    /// 8pt on the screen, 6pt in widgets, 5pt in the small widget.
    var barHeight: CGFloat { switch self { case .small: 5; case .medium, .large: 6; case .screen: 8 } }
    var forecast: CGFloat { switch self { case .small: 11; case .medium, .large: 12; case .screen: 13 } }
    var innerGap: CGFloat { switch self { case .small: 4; case .medium: 5; case .large: 6; case .screen: 8 } }
    var rowGap: CGFloat { switch self { case .small: 8; case .medium: 9; case .large: 12; case .screen: 26 } }
    /// Large and the screen show a reset line (with the forecast on its right).
    var showsResetLine: Bool { self == .large || self == .screen }
}
