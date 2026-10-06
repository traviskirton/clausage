import SwiftUI
import WidgetKit
import AppIntents

@main
struct UsageWidgets: WidgetBundle {
    var body: some Widget {
        UsageWidget()
        UsageGaugeWidget()
        UsageInlineWidget()
    }
}

// MARK: Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedStore.Snapshot?
    /// The running total the app recorded (large widget chart).
    var history: WeeklyHistory? = nil
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: UsageFixtures.now, snapshot: UsageFixtures.mixed, history: UsageFixtures.history(for: UsageFixtures.mixed))
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)) }
        else { completion(UsageEntry(date: Date(), snapshot: UsageSource.snapshot(), history: HistoryStore.load())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        let snap = UsageSource.snapshot()
        let history = HistoryStore.load()
        let entries = UsageTimeline.dates(snap, now: now).map { UsageEntry(date: $0, snapshot: snap, history: history) }
        completion(Timeline(entries: entries, policy: .after(UsageTimeline.refreshDate(now))))
    }
}

private let usageURL = URL(string: "claudeusage://usage")!

// MARK: Home Screen

struct UsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.dynamicTypeSize) private var type

    private var size: UsageSize {
        switch family { case .systemSmall: .small; case .systemMedium: .medium; default: .large }
    }

    var body: some View {
        UsageContent(size: size, snapshot: entry.snapshot, history: entry.history, now: entry.date, compact: type > .xxLarge)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .environment(\.usageStyle, mode == .fullColor ? .full : .accented)
            .widgetURL(usageURL)
            .containerBackground(for: .widget) { WidgetPaper() }
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UsageWidget", provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Clausage")
        .description("Your Claude plan limits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Lock Screen gauge (configurable)

struct LimitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Limit"
    static let defaultQuery = LimitQuery()
    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct LimitQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LimitEntity] { all().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [LimitEntity] { all() }
    func defaultResult() async -> LimitEntity? { all().first }

    private func all() -> [LimitEntity] {
        let names = Forecast.ordered(SharedStore.load()?.limits ?? []).map(Forecast.shortName)
        return (names.isEmpty ? ["Session", "All models"] : names).map { LimitEntity(id: $0) }
    }
}

struct UsageGaugeIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Limit"
    static let description = IntentDescription("Choose which limit the gauge shows.")
    @Parameter(title: "Limit") var limit: LimitEntity?
}

struct GaugeEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedStore.Snapshot?
    let limitID: String?
}

struct GaugeProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GaugeEntry {
        GaugeEntry(date: UsageFixtures.now, snapshot: UsageFixtures.mixed, limitID: nil)
    }

    func snapshot(for configuration: UsageGaugeIntent, in context: Context) async -> GaugeEntry {
        if context.isPreview { return placeholder(in: context) }
        return GaugeEntry(date: Date(), snapshot: UsageSource.snapshot(), limitID: configuration.limit?.id)
    }

    func timeline(for configuration: UsageGaugeIntent, in context: Context) async -> Timeline<GaugeEntry> {
        let now = Date()
        let snap = UsageSource.snapshot()
        let entries = UsageTimeline.dates(snap, now: now).map { GaugeEntry(date: $0, snapshot: snap, limitID: configuration.limit?.id) }
        return Timeline(entries: entries, policy: .after(UsageTimeline.refreshDate(now)))
    }
}

struct UsageGaugeView: View {
    let entry: GaugeEntry

    private var limit: UsageLimit? {
        guard let s = entry.snapshot, s.connected else { return nil }
        let all = Forecast.ordered(s.limits)
        return entry.limitID.flatMap { id in all.first { Forecast.shortName($0) == id } } ?? all.first
    }

    var body: some View {
        Group {
            if let l = limit, let s = entry.snapshot {
                UsageGauge(limit: l, stale: Forecast.isStale(updated: s.updated, now: entry.date))
            } else {
                ZStack { AccessoryWidgetBackground(); Text("Sign in").font(.system(size: 10, weight: .semibold)) }
            }
        }
        .widgetURL(usageURL)
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct UsageGaugeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "UsageGaugeWidget", intent: UsageGaugeIntent.self, provider: GaugeProvider()) { entry in
            UsageGaugeView(entry: entry)
        }
        .configurationDisplayName("Gauge")
        .description("One limit as a gauge.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: Lock Screen inline

struct UsageInlineView: View {
    let entry: UsageEntry
    var body: some View {
        Text(UsageInline.text(entry.snapshot, now: entry.date))
            .widgetURL(usageURL)
            .containerBackground(for: .widget) { Color.clear }
    }
}

struct UsageInlineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UsageInlineWidget", provider: UsageProvider()) { entry in
            UsageInlineView(entry: entry)
        }
        .configurationDisplayName("Line")
        .description("Your most pressing limit, one line.")
        .supportedFamilies([.accessoryInline])
    }
}
