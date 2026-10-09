import AppIntents
import WidgetKit

/// The large widget's refresh button: fetches now, whatever the snapshot's age.
struct RefreshUsageIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh usage"

    func perform() async throws -> some IntentResult {
        _ = await UsageSource.refresh()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
