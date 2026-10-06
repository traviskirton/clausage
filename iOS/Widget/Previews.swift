import WidgetKit
import SwiftUI

// Previews: every family, with the four sample states. Flip Dark / Light / Tinted in the canvas.

#Preview("Small · Mixed", as: .systemSmall) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.mixed, history: UsageFixtures.history(for: UsageFixtures.mixed))
}

#Preview("Small · Calm", as: .systemSmall) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.calm, history: UsageFixtures.history(for: UsageFixtures.calm))
}

#Preview("Small · All critical", as: .systemSmall) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.allCritical, history: UsageFixtures.history(for: UsageFixtures.allCritical))
}

#Preview("Small · Stale", as: .systemSmall) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.stale, history: UsageFixtures.history(for: UsageFixtures.stale))
}

#Preview("Medium · Mixed", as: .systemMedium) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.mixed, history: UsageFixtures.history(for: UsageFixtures.mixed))
}

#Preview("Medium · Calm", as: .systemMedium) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.calm, history: UsageFixtures.history(for: UsageFixtures.calm))
}

#Preview("Medium · All critical", as: .systemMedium) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.allCritical, history: UsageFixtures.history(for: UsageFixtures.allCritical))
}

#Preview("Medium · Stale", as: .systemMedium) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.stale, history: UsageFixtures.history(for: UsageFixtures.stale))
}

#Preview("Large · Mixed", as: .systemLarge) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.mixed, history: UsageFixtures.history(for: UsageFixtures.mixed))
}

#Preview("Large · Calm", as: .systemLarge) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.calm, history: UsageFixtures.history(for: UsageFixtures.calm))
}

#Preview("Large · All critical", as: .systemLarge) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.allCritical, history: UsageFixtures.history(for: UsageFixtures.allCritical))
}

#Preview("Large · Stale", as: .systemLarge) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.stale, history: UsageFixtures.history(for: UsageFixtures.stale))
}

#Preview("Gauge · Mixed", as: .accessoryCircular) { UsageGaugeWidget() } timeline: {
    GaugeEntry(date: UsageFixtures.now, snapshot: UsageFixtures.mixed, limitID: "Session")
    GaugeEntry(date: UsageFixtures.now, snapshot: UsageFixtures.mixed, limitID: "All models")
    GaugeEntry(date: UsageFixtures.now, snapshot: UsageFixtures.mixed, limitID: "Fable")
}

#Preview("Gauge · Calm", as: .accessoryCircular) { UsageGaugeWidget() } timeline: {
    GaugeEntry(date: UsageFixtures.now, snapshot: UsageFixtures.calm, limitID: "Session")
    GaugeEntry(date: UsageFixtures.now, snapshot: UsageFixtures.calm, limitID: "All models")
    GaugeEntry(date: UsageFixtures.now, snapshot: UsageFixtures.calm, limitID: "Fable")
}

#Preview("Gauge · All critical", as: .accessoryCircular) { UsageGaugeWidget() } timeline: {
    GaugeEntry(date: UsageFixtures.now, snapshot: UsageFixtures.allCritical, limitID: "Session")
    GaugeEntry(date: UsageFixtures.now, snapshot: UsageFixtures.allCritical, limitID: "All models")
    GaugeEntry(date: UsageFixtures.now, snapshot: UsageFixtures.allCritical, limitID: "Fable")
}

#Preview("Gauge · Stale", as: .accessoryCircular) { UsageGaugeWidget() } timeline: {
    GaugeEntry(date: UsageFixtures.now, snapshot: UsageFixtures.stale, limitID: "Session")
    GaugeEntry(date: UsageFixtures.now, snapshot: UsageFixtures.stale, limitID: "All models")
    GaugeEntry(date: UsageFixtures.now, snapshot: UsageFixtures.stale, limitID: "Fable")
}

#Preview("Inline · Mixed", as: .accessoryInline) { UsageInlineWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.mixed, history: UsageFixtures.history(for: UsageFixtures.mixed))
}

#Preview("Inline · Calm", as: .accessoryInline) { UsageInlineWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.calm, history: UsageFixtures.history(for: UsageFixtures.calm))
}

#Preview("Inline · All critical", as: .accessoryInline) { UsageInlineWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.allCritical, history: UsageFixtures.history(for: UsageFixtures.allCritical))
}

#Preview("Inline · Stale", as: .accessoryInline) { UsageInlineWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.stale, history: UsageFixtures.history(for: UsageFixtures.stale))
}

