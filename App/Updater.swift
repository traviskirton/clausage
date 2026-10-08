import AppKit
import Sparkle

/// Thin wrapper over Sparkle. The feed URL, public key and check interval live in Info.plist (see project.yml).
///
/// No Sparkle windows: updates download in the background, and once one is ready Settings opens on Updates
/// ("Clausage 0.0.9 is available · Install Now"). Install Now installs and relaunches right away; otherwise the update
/// installs the next time Clausage quits.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    /// What Updates and About show: the result of the last check, or an install in progress.
    enum Status: Equatable {
        case idle, checking, upToDate, available(String), installing, failed(String)
    }

    /// Version string of an update that's ready, until it's installed (the popover's "Update available" line).
    @Published private(set) var availableVersion: String?
    /// The ready update's build number ("9"), shown as "Clausage 0.0.9 (9)".
    @Published private(set) var availableBuild: String?
    /// The ready update's release notes, when the appcast has them.
    @Published private(set) var releaseNotes: URL?
    @Published private(set) var canCheck = false
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?

    private let driverDelegate = UserDriverDelegate()
    private let updaterDelegate = UpdaterDelegate()
    private let controller: SPUStandardUpdaterController
    /// Sparkle's "install and relaunch now", handed over once a downloaded update is ready.
    private var installNowHandler: (() -> Void)?
    /// Install Now was pressed before the download finished: install as soon as it's ready.
    private var installRequested = false
    /// Settings opens by itself once per version.
    private var openedSettingsFor: String?

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: driverDelegate)
        driverDelegate.owner = self
        updaterDelegate.owner = self
        // Download in the background, so Install Now is immediate and nothing interrupts with Sparkle's window.
        controller.updater.automaticallyDownloadsUpdates = true
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

    /// "Check for Updates…" and About's "Check Now": checks (and downloads) in the background; the result lands in
    /// `status`, and a found update shows up in Updates when it's ready.
    func check() {
        guard !controller.updater.sessionInProgress else { return }
        status = .checking
        controller.updater.checkForUpdatesInBackground()
    }

    /// Install Now: installs the downloaded update and relaunches. If it's still downloading, it installs when ready.
    /// Where Sparkle can't download by itself (automatic updates not allowed), Sparkle's own installer takes over.
    func installNow() {
        if let install = installNowHandler {
            status = .installing
            install()
        } else if controller.updater.automaticallyDownloadsUpdates {
            status = .installing
            installRequested = true
            if !controller.updater.sessionInProgress { controller.updater.checkForUpdatesInBackground() }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            controller.checkForUpdates(nil)
        }
    }

    /// An update is ready (downloaded, with `install`), or found where Sparkle can't download by itself (nil): show it
    /// in Updates, opening Settings there the first time for each version.
    fileprivate func found(_ item: SUAppcastItem, install: (() -> Void)?) {
        if let install { installNowHandler = install }
        let version = item.displayVersionString
        availableVersion = version
        availableBuild = item.versionString
        // The releases page, at this version's section (clausage.ai/releases/#v0.0.9).
        releaseNotes = item.fullReleaseNotesURL.flatMap { URL(string: "\($0.absoluteString)#v\(version)") } ?? item.releaseNotesURL
        lastChecked = controller.updater.lastUpdateCheckDate ?? Date()
        if installRequested, let install { install(); return }
        status = .available(version)
        if openedSettingsFor != version {
            openedSettingsFor = version
            SettingsWindow.shared.show(tab: .updates)
        }
    }

    fileprivate func finished(_ result: Status) {
        lastChecked = controller.updater.lastUpdateCheckDate ?? Date()
        switch status {
        case .available: return      // stays until it's installed
        case .installing:
            guard case .failed = result else { return }
        default: break
        }
        installRequested = false
        status = result
    }

    #if DEBUG
    /// Gallery only: a check in progress.
    func previewChecking() { status = .checking }

    /// Gallery only: the Updates pane's "update available" state.
    func previewAvailable(_ version: String, build: String) {
        availableVersion = version
        availableBuild = build
        status = .available(version)
    }
    #endif

    /// Records each check's outcome and takes over installing.
    final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
        weak var owner: Updater?

        func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
            Task { @MainActor in self.owner?.finished(.upToDate) }
        }

        /// The update is downloaded and staged. Returning true keeps Sparkle from showing its own prompt; Clausage
        /// offers Install Now instead, and Sparkle still installs it on quit.
        func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                     immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
            Task { @MainActor in self.owner?.found(item, install: immediateInstallHandler) }
            return true
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

        /// Never Sparkle's window for background checks: the update downloads and Updates offers it.
        var supportsGentleScheduledUpdateReminders: Bool { true }

        func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
            false
        }

        /// Only reached when Sparkle can't download by itself: offer the update in Updates instead of a window.
        func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
            guard !handleShowingUpdate else { return }
            Task { @MainActor in self.owner?.found(update, install: nil) }
        }
    }
}
