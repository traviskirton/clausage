import AppKit
import Sparkle

/// Thin wrapper over Sparkle. The feed URL, public key and check interval live in Info.plist (see project.yml).
///
/// Menubar apps are "background" apps, so Sparkle's scheduled-check alert can go unnoticed. We use Sparkle's
/// gentle-reminder hooks: when a scheduled check finds an update we post a notification and show an
/// "Update available" line in the popover instead of popping up a window out of nowhere.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    /// What About shows: the result of the last check (scheduled or "Check Now").
    enum Status: Equatable {
        case idle, checking, upToDate, available(String), failed(String)
    }

    /// Version string of an update found by a scheduled check, until the user acts on it.
    @Published private(set) var availableVersion: String?
    @Published private(set) var canCheck = false
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?

    private let driverDelegate = UserDriverDelegate()
    private let updaterDelegate = UpdaterDelegate()
    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: driverDelegate)
        driverDelegate.owner = self
        updaterDelegate.owner = self
        lastChecked = controller.updater.lastUpdateCheckDate
        if lastChecked != nil { status = .upToDate }
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        // Sparkle's schedule alone waits a full interval after the last check, so also check shortly after launch.
        if controller.updater.automaticallyChecksForUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.controller.updater.checkForUpdatesInBackground()
            }
        }
    }

    var automaticChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
            if newValue { controller.updater.checkForUpdatesInBackground() }
        }
    }

    /// User-initiated: shows Sparkle's standard update window.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// "Check Now" in About: asks the feed without showing Sparkle's window; the result lands in `status`.
    func probe() {
        guard !controller.updater.sessionInProgress else { return }
        status = .checking
        controller.updater.checkForUpdateInformation()
    }

    fileprivate func setAvailable(_ version: String?) { availableVersion = version }

    fileprivate func finished(_ result: Status) {
        status = result
        lastChecked = controller.updater.lastUpdateCheckDate ?? Date()
    }

    /// Records each check's outcome (scheduled, user-initiated or a probe).
    final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
        weak var owner: Updater?

        func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
            let version = item.displayVersionString
            Task { @MainActor in self.owner?.finished(.available(version)) }
        }

        func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
            Task { @MainActor in self.owner?.finished(.upToDate) }
        }

        func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
            guard let error = error as NSError? else { return }
            let benign: [SUError] = [.noUpdateError, .installationCanceledError, .installationAuthorizeLaterError]
            if error.domain == SUSparkleErrorDomain, benign.contains(where: { Int($0.rawValue) == error.code }) { return }
            let message = error.localizedDescription
            Task { @MainActor in self.owner?.finished(.failed(message)) }
        }
    }

    final class UserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
        weak var owner: Updater?

        var supportsGentleScheduledUpdateReminders: Bool { true }

        /// Let Sparkle show its window only if the user is already looking at the app; otherwise we remind gently.
        func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
            immediateFocus
        }

        func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
            guard !handleShowingUpdate else { return }
            let version = update.displayVersionString
            Task { @MainActor in
                self.owner?.setAvailable(version)
                Notifier.postUpdateAvailable(version: version)
            }
        }

        func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
            Task { @MainActor in self.owner?.setAvailable(nil) }
        }

        func standardUserDriverWillFinishUpdateSession() {
            Task { @MainActor in self.owner?.setAvailable(nil) }
        }
    }
}
