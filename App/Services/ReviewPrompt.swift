import Foundation

/// When to show Apple's "Enjoying CNSNN?" prompt: once a game is closed after a found daily word,
/// from the third found daily word on, at most once per app version, never in tests. Apple itself
/// shows it at most three times a year, and never in TestFlight builds.
enum ReviewPrompt {
    static let minimumDailyWins = 3
    static let askedVersionKey = "cnsnn.reviewAskedVersion"

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    static func shouldAsk(dailyWins: Int, version: String = appVersion, defaults: UserDefaults = .standard) -> Bool {
        guard !RuntimeFlags.isTesting else { return false }
        return isDue(dailyWins: dailyWins, version: version, defaults: defaults)
    }

    /// The rule without the test guard, so the unit tests can check it.
    static func isDue(dailyWins: Int, version: String, defaults: UserDefaults) -> Bool {
        dailyWins >= minimumDailyWins && defaults.string(forKey: askedVersionKey) != version
    }

    static func markAsked(version: String = appVersion, defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: askedVersionKey)
    }
}
