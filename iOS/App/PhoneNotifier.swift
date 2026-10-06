import Foundation
import UserNotifications

/// iPhone settings (App Group, so the background task and widgets see the same values).
enum PhonePrefs {
    private static var d: UserDefaults { SharedStore.defaults }
    private static func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }

    /// "Near limit: when a limit reaches 85%".
    static var notifyNear: Bool { get { bool("notifyNear", true) } set { d.set(newValue, forKey: "notifyNear") } }
    /// "Critical: when a limit reaches 95%".
    static var notifyCritical: Bool { get { bool("notifyCritical", true) } set { d.set(newValue, forKey: "notifyCritical") } }
    /// "Runout forecast: only if you'll run out before it resets".
    static var notifyRunout: Bool { get { bool("notifyRunout", true) } set { d.set(newValue, forKey: "notifyRunout") } }
    /// "Limit resets".
    static var notifyResets: Bool { get { bool("notifyResets", false) } set { d.set(newValue, forKey: "notifyResets") } }
    /// "Refresh in background" (BGAppRefreshTask).
    static var backgroundRefresh: Bool { get { bool("backgroundRefresh", true) } set { d.set(newValue, forKey: "backgroundRefresh") } }
}

/// Local notifications on the iPhone, decided after each refresh (foreground or background). Nothing is sent anywhere.
@MainActor
enum PhoneNotifier {
    private static var center: UNUserNotificationCenter { .current() }
    private static var d: UserDefaults { SharedStore.defaults }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func cancelAll() {
        center.removeAllPendingNotificationRequests()
        d.removeObject(forKey: "notifyFired")
        d.removeObject(forKey: "notifySeeded")
    }

    /// Threshold (85% / 95%) and runout alerts fire when a refresh sees a new crossing in a window; reset alerts are
    /// scheduled for the reset time. On the very first run, what's already crossed is recorded without alerting.
    static func process(now: Date = Date()) async {
        guard let s = SharedStore.load(), s.connected else { return }
        let limits = DisplayPrefs.visible(s.limits)
        var fired = Set(d.stringArray(forKey: "notifyFired") ?? [])
        let seeded = d.bool(forKey: "notifySeeded")

        for l in limits {
            guard let reset = l.resetsAt else { continue }
            let window = Int((reset.timeIntervalSince1970 / 600).rounded())
            let name = Forecast.shortName(l)
            let pct = Int(l.percent.rounded())
            let hit = Forecast.hitDate(l, now: now)
            let level = Forecast.level(l)
            let forecast = hit.map { "At this pace you’ll reach the limit \(Forecast.timeText($0, window: l.windowLength))." }

            var crossed: String?
            if level == .critical, PhonePrefs.notifyCritical { crossed = "95" }
            else if level != .normal, PhonePrefs.notifyNear { crossed = "85" }
            if let t = crossed {
                let key = "\(l.kind)|\(window)|\(t)"
                if fired.insert(key).inserted, seeded {
                    let body = (PhonePrefs.notifyRunout ? forecast : nil) ?? Forecast.resetText(l).map { "\($0)." } ?? ""
                    post(id: "threshold-\(l.id)-\(t)", title: "\(name) is at \(pct)%", body: body)
                }
            } else if PhonePrefs.notifyRunout, level != .normal, let hit {
                let key = "\(l.kind)|\(window)|runout"
                if fired.insert(key).inserted, seeded {
                    post(id: "runout-\(l.id)", title: "\(name) is at \(pct)%",
                         body: "At this pace you’ll reach the \(name) limit \(Forecast.timeText(hit, window: l.windowLength)).")
                }
            }

            let resetID = "reset-\(l.id)"
            center.removePendingNotificationRequests(withIdentifiers: [resetID])
            if PhonePrefs.notifyResets, reset > now {
                post(id: resetID, title: "Your \(name) limit just reset", body: "Back to 0%.", after: reset.timeIntervalSince(now) + 2)
            }
        }
        if fired.count > 300 { fired = Set(fired.sorted().suffix(100)) }
        d.set(Array(fired), forKey: "notifyFired")
        d.set(true, forKey: "notifySeeded")
    }

    private static func post(id: String, title: String, body: String, after: TimeInterval = 1) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, after), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
    }
}
