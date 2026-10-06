import AppKit
import UserNotifications

struct AccountLimits {
    let id: UUID
    let name: String
    let limits: [UsageLimit]
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }

    /// Clicking the "update available" notification opens Sparkle's update window.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix("update-") {
            Task { @MainActor in Updater.shared.checkForUpdates() }
        }
        completionHandler()
    }
}

/// Threshold alerts fire when a refresh sees a new crossing. "Resets soon" and "reset" alerts are scheduled
/// as local notifications so they arrive even if the app isn't refreshing at that moment.
@MainActor
enum Notifier {
    private static let delegate = NotificationDelegate()
    private static var center: UNUserNotificationCenter { .current() }

    static func setup() { center.delegate = delegate }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    static func process(_ accounts: [AccountLimits], now: Date = Date()) {
        let d = UserDefaults.standard
        let multi = accounts.count > 1
        center.removeAllPendingNotificationRequests()
        for a in accounts {
            let who = multi ? a.name : nil
            checkThresholds(a, who: who, now: now, defaults: d)
            schedule(a, who: who, now: now, defaults: d)
        }
        d.set(true, forKey: "thresholdsSeeded")
    }

    // MARK: Thresholds

    private static func checkThresholds(_ a: AccountLimits, who: String?, now: Date, defaults d: UserDefaults) {
        let thresholds = Prefs.thresholds
        var fired = d.stringArray(forKey: "firedThresholds") ?? []
        let seeded = d.bool(forKey: "thresholdsSeeded")

        for l in a.limits {
            guard let r = l.resetsAt else { continue }
            let window = Int((r.timeIntervalSince1970 / 600).rounded())
            var newly: [Int] = []
            for t in thresholds.sorted() where l.percent >= Double(t) {
                let key = "\(a.id)|\(l.kind)|\(window)|\(t)"
                if !fired.contains(key) { fired.append(key); newly.append(t) }
            }
            // On the very first run just record what's already crossed instead of alerting.
            guard seeded, newly.max() != nil else { continue }
            // Long form: "All models is at 88%" / "At this pace you'll reach the limit Tue 3:32 AM."
            let body: String
            if let hit = Forecast.hitDate(l, now: now) {
                body = "At this pace you’ll reach the limit \(Forecast.timeText(hit, window: l.windowLength))."
            } else if let until = DateComponentsFormatter.until(r, from: now) {
                body = "\(until.prefix(1).uppercased() + until.dropFirst()) until it resets."
            } else {
                body = ""
            }
            post(id: "threshold-\(a.id)-\(l.id)-\(newly.max()!)", title: "\(Forecast.shortName(l)) is at \(Int(l.percent.rounded()))%",
                 subtitle: who, body: body, after: 1)
        }
        if fired.count > 400 { fired = Array(fired.suffix(100)) }
        d.set(fired, forKey: "firedThresholds")
    }

    // MARK: Scheduled alerts

    private static func schedule(_ a: AccountLimits, who: String?, now: Date, defaults d: UserDefaults) {
        let soon = d.bool(forKey: "notifySoon"), minutes = d.integer(forKey: "soonMinutes")
        let reset = d.bool(forKey: "notifyReset")

        for l in a.limits {
            guard let r = l.resetsAt, r > now else { continue }
            if soon, l.kind == "session" {
                let delta = r.timeIntervalSince(now) - Double(minutes * 60)
                if delta > 5 {
                    let p = Int(l.percent.rounded())
                    post(id: "soon-\(a.id)-\(l.id)", title: "Session resets in \(minutes) min", subtitle: who,
                         body: p >= 75 ? "You’re at \(p)%. Worth waiting before starting a long task." : "You’re at \(p)%.",
                         after: delta)
                }
            }
            if reset {
                let other = a.limits.filter { $0.id != l.id }.max { $0.percent < $1.percent }
                var body = "Back to 0%."
                if let o = other { body += " \(Forecast.shortName(o)) is still at \(Int(o.percent.rounded()))%." }
                let name = l.kind == "session" ? "session" : Forecast.shortName(l)
                post(id: "reset-\(a.id)-\(l.id)", title: "Your \(name) limit just reset", subtitle: who,
                     body: body, after: r.timeIntervalSince(now) + 2)
            }
        }
    }

    static func sendTest() {
        post(id: "test", title: "Clausage notifications are on", subtitle: nil,
             body: "You’ll see usage alerts like this one.", after: 1)
    }

    static func postUpdateAvailable(version: String) {
        post(id: "update-\(version)", title: "Clausage \(version) is available", subtitle: nil,
             body: "Click to update.", after: 1)
    }

    static func postOutage(id: String, title: String, body: String) {
        post(id: "outage-\(id)", title: title, subtitle: nil, body: body, after: 1)
    }

    /// Notifications carry the app icon (the system adds it); no custom attachment.
    private static func post(id: String, title: String, subtitle: String?, body: String, after: TimeInterval) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        if let subtitle { c.subtitle = subtitle }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, after), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
    }
}

extension DateComponentsFormatter {
    /// "2 days", "5 hours", "40 minutes" until `date`.
    static func until(_ date: Date, from now: Date) -> String? {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour, .minute]
        f.maximumUnitCount = 1
        f.unitsStyle = .full
        let interval = date.timeIntervalSince(now)
        return interval > 0 ? f.string(from: interval) : nil
    }
}
