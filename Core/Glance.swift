import Foundation

/// What the home screen widget shows, written by the app into the shared App Group.
/// Without the App Group (some sideloading setups), the widget falls back to the day's difficulty.
public struct Glance: Codable, Equatable, Sendable {
    public static let appGroup = "group.com.poupoutch.cnsnn"
    static let storageKey = "glance"

    /// Day key (local calendar) of the last daily result, if any.
    public var lastDailyKey: String?
    public var lastDailyCorrect: Bool
    public var lastDailyTimeMs: Int
    /// Streak of found daily words, counted up to the last win.
    public var streak: Int
    public var lastWinKey: String?

    public init(lastDailyKey: String? = nil, lastDailyCorrect: Bool = false, lastDailyTimeMs: Int = 0, streak: Int = 0, lastWinKey: String? = nil) {
        self.lastDailyKey = lastDailyKey; self.lastDailyCorrect = lastDailyCorrect; self.lastDailyTimeMs = lastDailyTimeMs
        self.streak = streak; self.lastWinKey = lastWinKey
    }

    /// Built from the player's history: the latest daily result and the current streak.
    public init(progress: Progress, streak: Int, now: Date = Date()) {
        let last = progress.attempts.filter { $0.mode == .daily && $0.dailyKey != nil }.max { ($0.dailyKey ?? "") < ($1.dailyKey ?? "") }
        let lastWin = progress.attempts.filter { $0.mode == .daily && $0.correct }.compactMap(\.dailyKey).max()
        self.init(lastDailyKey: last?.dailyKey, lastDailyCorrect: last?.correct ?? false, lastDailyTimeMs: last?.timeMs ?? 0,
                  streak: streak, lastWinKey: lastWin)
    }

    /// Today's result, if the player already played today.
    public func playedToday(_ date: Date = Date()) -> Bool { lastDailyKey == DailySchedule.key(date) }
    /// The streak still counts while the last win is today or yesterday.
    public func currentStreak(_ date: Date = Date()) -> Int {
        guard let lastWinKey else { return 0 }
        return lastWinKey == DailySchedule.key(date) || lastWinKey == DailySchedule.key(DailySchedule.previousDay(date)) ? streak : 0
    }

    public static func load() -> Glance? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Glance.self, from: data)
    }
    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.storageKey)
    }

    /// The next local midnight, when the Mot du jour changes.
    public static func nextDay(after date: Date = Date()) -> Date {
        let calendar = DailySchedule.calendar
        return calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? date.addingTimeInterval(3600)
    }
}
