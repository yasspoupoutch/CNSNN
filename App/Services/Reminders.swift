import Foundation
import UserNotifications
import WidgetKit
import CNSNNCore

/// Local daily reminders for the Mot du jour (no server needed) and the home screen widget data.
@MainActor enum Reminders {
    nonisolated static let enabledKey = "reminders.enabled"
    static let minutesKey = "reminders.minutes"
    private static let prefix = "cnsnn.daily."
    private static var lastGlance: Glance?

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    /// Minutes after midnight, 12:00 by default.
    nonisolated static let defaultMinutes = 12 * 60
    static var minutes: Int {
        get { UserDefaults.standard.object(forKey: minutesKey) as? Int ?? defaultMinutes }
        set { UserDefaults.standard.set(newValue, forKey: minutesKey) }
    }

    /// Asks for permission when needed. Returns false when the player refused notifications.
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        UserDefaults.standard.set(allowed, forKey: enabledKey)
        return allowed
    }
    static func disable() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Refreshes the widget and the next reminders after anything that changes the day's state.
    /// `force` reschedules even when nothing changed (app back in the foreground, settings changed).
    static func update(progress: CNSNNCore.Progress, streak: Int, force: Bool = false) {
        let glance = Glance(progress: progress, streak: streak)
        guard force || glance != lastGlance else { return }
        if glance != lastGlance {
            lastGlance = glance
            glance.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
        schedule(glance: glance)
    }

    private static var identifiers: [String] { (0..<8).map { prefix + String($0) } + [prefix + "evening"] }

    /// The next seven mornings at the chosen time, skipping today once played, plus an evening
    /// warning when today's game would keep a streak alive.
    private static func schedule(glance: Glance) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard isEnabled, !RuntimeFlags.isTesting else { return }
        let now = Date()
        let calendar = Calendar.current
        let playedToday = glance.playedToday(now)
        let streak = glance.currentStreak(now)
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  fire > now, !(offset == 0 && playedToday) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "N’oubliez pas le mot du jour"
            if offset == 0 && streak > 0 {
                content.body = "Gardez votre série de \(streak) jour\(streak > 1 ? "s" : "") : trouvez le mot avant ce soir."
            } else {
                content.body = "Nouveau mot, nouveau classement. Serez-vous le numéro 1 aujourd’hui ?"
            }
            content.sound = .default
            add(prefix + String(offset), content, at: fire, calendar: calendar)
        }
        if !playedToday, streak > 0, let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now), evening > now {
            let content = UNMutableNotificationContent()
            content.title = "Votre série est en jeu"
            content.body = "\(streak) jour\(streak > 1 ? "s" : "") d’affilée : le mot du jour s’arrête à minuit."
            content.sound = .default
            add(prefix + "evening", content, at: evening, calendar: calendar)
        }
    }
    private static func add(_ id: String, _ content: UNMutableNotificationContent, at date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }
}

/// The reminder is offered once, when a game is closed after a found daily word, to every player
/// who does not have it yet (new players and those from before 1.2). Refused, it is never asked again;
/// it stays in Profil either way.
enum ReminderOffer {
    static let offeredKey = "reminders.offered"

    enum Step: Equatable {
        /// Notifications never asked: Apple's prompt alone, a yes turns the reminder on.
        case systemPrompt
        /// Notifications already allowed (friend challenges): CNSNN asks in its own words.
        case askInApp
        /// Notifications refused in Réglages: nothing to offer.
        case unavailable
    }

    static func shouldOffer(defaults: UserDefaults = .standard) -> Bool {
        guard !RuntimeFlags.isTesting else { return false }
        return isDue(defaults: defaults)
    }
    /// The rule without the test guard, so the unit tests can check it.
    static func isDue(defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: Reminders.enabledKey) && !defaults.bool(forKey: offeredKey)
    }
    static func markOffered(defaults: UserDefaults = .standard) { defaults.set(true, forKey: offeredKey) }

    static func step(for status: UNAuthorizationStatus) -> Step {
        switch status {
        case .notDetermined: .systemPrompt
        case .denied: .unavailable
        default: .askInApp
        }
    }
    /// Marks the offer as made, then says how to make it.
    @MainActor static func start() async -> Step {
        markOffered()
        return step(for: await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }
}
