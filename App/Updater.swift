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

    /// Version string of an update found by a scheduled check, until the user acts on it.
    @Published private(set) var availableVersion: String?
    @Published private(set) var canCheck = false

    private let driverDelegate = UserDriverDelegate()
    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: driverDelegate)
        driverDelegate.owner = self
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

    fileprivate func setAvailable(_ version: String?) { availableVersion = version }

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
