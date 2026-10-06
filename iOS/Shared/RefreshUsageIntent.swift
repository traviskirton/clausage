import AppIntents
import WidgetKit

/// The large widget's refresh button. The only place a widget touches the network.
struct RefreshUsageIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh usage"

    func perform() async throws -> some IntentResult {
        _ = await UsageSource.refresh()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
