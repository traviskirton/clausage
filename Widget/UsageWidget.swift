import SwiftUI
import WidgetKit

/// Desktop widgets: the same branded views as the iOS widgets. When macOS dims them (a window covers the desktop),
/// the system's monochrome glass takes over and critical bars switch to zebra stripes.
struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedStore.Snapshot?
    var history: WeeklyHistory? = nil
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        let s = UsageFixtures.mixed
        return UsageEntry(date: UsageFixtures.now, snapshot: s, history: UsageFixtures.history(for: s))
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)) }
        else { completion(UsageEntry(date: Date(), snapshot: SharedStore.load(), history: HistoryStore.load())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        let snap = SharedStore.load()
        let history = HistoryStore.load()
        let entries = UsageTimeline.dates(snap, now: now).map { UsageEntry(date: $0, snapshot: snap, history: history) }
        completion(Timeline(entries: entries, policy: .after(UsageTimeline.refreshDate(now))))
    }
}

struct UsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    private var size: UsageSize {
        switch family { case .systemSmall: .small; case .systemMedium: .medium; default: .large }
    }

    var body: some View {
        // The Mac app refreshes on its own schedule, so the large widget's "Updated" isn't a button here.
        UsageContent(size: size, snapshot: entry.snapshot, history: entry.history, now: entry.date, refreshable: false)
            .environment(\.usageStyle, mode == .fullColor ? .full : .accented)
            .containerBackground(for: .widget) { WidgetPaper() }
    }
}

@main
struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageWidget", provider: Provider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Clausage")
        .description("Your Claude plan limits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview("Small · Mixed", as: .systemSmall) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.mixed, history: UsageFixtures.history(for: UsageFixtures.mixed))
}

#Preview("Medium · All critical", as: .systemMedium) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.allCritical)
}

#Preview("Large · Mixed", as: .systemLarge) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.mixed, history: UsageFixtures.history(for: UsageFixtures.mixed))
}

#Preview("Large · Stale", as: .systemLarge) { UsageWidget() } timeline: {
    UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.stale, history: UsageFixtures.history(for: UsageFixtures.stale))
}
