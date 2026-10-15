import Foundation
import BackgroundTasks
import UserNotifications
import CNSNNCore

/// Friend challenge notifications without a server: when iOS gives the app a background refresh, it
/// reads the challenges of the last two days (a few documents) and shows a local notification for a
/// new challenge or a result. iOS decides how often, to protect the battery.
@MainActor enum ChallengeWatch {
    static let identifier = "cnsnn.challenges"
    /// Set while the player has friends or challenges: nobody to hear from means no background work.
    static let activeKey = "challenges.watch"
    private static let seenKey = "challenges.alerts.seen"

    static var isActive: Bool { UserDefaults.standard.bool(forKey: activeKey) }
    static func setActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: activeKey)
        if active { schedule() } else { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
    }

    /// Asks iOS for the next refresh, in 15 minutes at the earliest.
    static func schedule() {
        guard isActive, !RuntimeFlags.isTesting else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Asks for notifications the first time the player sends or plays a challenge.
    static func requestPermission() async {
        guard !RuntimeFlags.isTesting else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// The background refresh: one small read, then a notification for each new event.
    static func run() async {
        schedule()
        guard isActive, FirebaseRepository.hasSignedInUser else { return }
        let cloud = FirebaseRepository()
        guard let uid = cloud.currentUID else { return }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        guard let recent = try? await cloud.recentChallenges(uid: uid, nowMs: now) else { return }
        let alerts = ChallengeAlerts.pending(recent, uid: uid, now: now, seen: seen)
        remember(alerts.map(\.key))
        guard !alerts.isEmpty, await allowed() else { return }
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cnsnn.challenge." + alert.key, content: content, trigger: nil))
        }
    }

    /// What the app already showed on screen needs no notification later.
    static func markSeen(_ challenges: [Challenge], uid: String) {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        remember(ChallengeAlerts.all(challenges, uid: uid, now: now).map(\.key))
    }

    private static func allowed() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return [.authorized, .provisional, .ephemeral].contains(status)
    }
    private static var seen: Set<String> { Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? []) }
    private static func remember(_ keys: [String]) {
        var list = UserDefaults.standard.stringArray(forKey: seenKey) ?? []
        let fresh = keys.filter { !list.contains($0) }
        guard !fresh.isEmpty else { return }
        list = Array((list + fresh).suffix(300))
        UserDefaults.standard.set(list, forKey: seenKey)
    }
}
