import Foundation

/// The Mot du jour is scored on time only, the lower the better: the hint adds one minute, and a lost
/// (or unplayed) day counts ten minutes, the most a day can cost. Same arithmetic as firestore.rules.
public enum DailyScore {
    public static let hintPenaltyMs = 60_000
    public static let missedMs = 600_000
    /// Days from 1970-01-01 to 2024-01-01, where DailySchedule.dayNumber starts.
    static let epochOffset = 19_723

    public static func scoreMs(timeMs: Int, usedHint: Bool, correct: Bool) -> Int {
        correct ? min(timeMs + (usedHint ? hintPenaltyMs : 0), missedMs) : missedMs
    }
    /// Days since 1970 for a yyyy-MM-dd key, as the rules' `dayIndex`.
    public static func dayIndex(_ day: String) -> Int? { DailySchedule.dayNumber(forKey: day).map { $0 + epochOffset } }
    /// One number per result that sorts the day's results: the day first, then the score (lost last).
    public static func rank(day: String, scoreMs: Int, correct: Bool) -> Int? {
        dayIndex(day).map { $0 * 1_000_000 + (correct ? scoreMs : 999_999) }
    }
    public static func dayBase(_ day: String) -> Int? { dayIndex(day).map { $0 * 1_000_000 } }
    public static func monthIndex(_ day: String) -> Int? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return parts.count == 3 ? parts[0] * 12 + parts[1] - 1 : nil
    }
    public static func monthRank(month: Int, saved: Int) -> Int { month * 100_000_000 + saved }
    /// The month's total time after `days` days: every day costs ten minutes minus what was saved.
    public static func monthTotal(saved: Int, days: Int) -> Int { max(0, missedMs * days - saved) }
    public static func dayOfMonth(_ day: String) -> Int { day.split(separator: "-").compactMap { Int($0) }.last ?? 1 }

    public struct Month: Equatable, Sendable {
        public var month: Int, saved: Int, played: Int
        public init(month: Int, saved: Int, played: Int) { self.month = month; self.saved = saved; self.played = played }
        public var rank: Int { DailyScore.monthRank(month: month, saved: saved) }
    }
    /// The month tally after one more result: a new month starts from zero, and a late result from an
    /// older month leaves the current one alone (same as the rules' `tallyMonth`).
    public static func tally(old: Month, day: String, scoreMs: Int) -> Month {
        guard let month = monthIndex(day), month >= old.month else { return old }
        let same = month == old.month
        return Month(month: month, saved: (same ? old.saved : 0) + missedMs - scoreMs, played: (same ? old.played : 0) + 1)
    }
}

/// Classique has no points: the level grows with the words found.
public enum ClassicLevel {
    public static let wordsPerLevel = 20
    public static func level(words: Int) -> Int { words / wordsPerLevel + 1 }
    public static func into(words: Int) -> Int { words % wordsPerLevel }
}
/// The Mot du jour calendar, keyed yyyy-MM-dd on the phone's own time zone: the word changes at the
/// player's local midnight (firestore.rules accepts a day while it is that day somewhere on Earth).
public enum DailySchedule {
    public static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .current
        return value
    }
    public static func key(_ date: Date = Date(), in timeZone: TimeZone = .current) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func previousDay(_ date: Date, in timeZone: TimeZone = .current) -> Date {
        var calendar = calendar
        calendar.timeZone = timeZone
        return calendar.date(byAdding: .day, value: -1, to: date)!
    }
    /// Monday-Tuesday easy, Wednesday-Friday medium, weekend hard (same table as firestore.rules).
    public static func difficulty(forKey key: String) -> Difficulty? {
        guard let day = dayNumber(forKey: key) else { return nil }
        switch ((day % 7) + 7) % 7 { case 0, 1: return .easy; case 2, 3, 4: return .medium; default: return .hard }
    }
    /// The shared Mot du jour: each difficulty walks its frozen pool in order, one word per matching day.
    public static func dailyCard(forKey key: String) -> Card? {
        guard let day = dayNumber(forKey: key), let difficulty = difficulty(forKey: key) else { return nil }
        let week = day >= 0 ? day / 7 : (day - 6) / 7
        let weekday = day - week * 7
        let occurrence: Int
        switch difficulty {
        case .easy: occurrence = week * 2 + weekday
        case .medium: occurrence = week * 3 + weekday - 2
        case .hard: occurrence = week * 2 + weekday - 5
        }
        let pool = DailyPool.pool(difficulty)
        guard !pool.isEmpty else { return nil }
        return pool[((occurrence % pool.count) + pool.count) % pool.count]
    }
    public static func dailyCard(for date: Date = Date()) -> Card? { dailyCard(forKey: key(date)) }
    /// Days since Monday 2024-01-01.
    public static func dayNumber(forKey key: String) -> Int? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let date = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              let reference = utc.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12)) else { return nil }
        return utc.dateComponents([.day], from: reference, to: date).day
    }
    /// Legacy local schedule over an arbitrary catalogue, kept for older saves.
    public static func card(for date: Date, cards: [Card]) -> Card? {
        let sorted = cards.filter { $0.status == .approved }.sorted { $0.id < $1.id }
        guard !sorted.isEmpty else { return nil }
        let seed = key(date).utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return sorted[Int(seed % UInt64(sorted.count))]
    }
}
public enum CardPicker {
    public static func candidates(cards: [Card], category: Category?, difficulty: Difficulty?, recent: [String]) -> [Card] {
        let eligible = cards.filter { $0.status == .approved && (category == nil || $0.category == category) && (difficulty == nil || $0.difficulty == difficulty) }
        let fresh = eligible.filter { !recent.contains($0.id) }
        if !fresh.isEmpty { return fresh }
        guard let oldest = eligible.min(by: { (recent.firstIndex(of: $0.id) ?? -1) < (recent.firstIndex(of: $1.id) ?? -1) }) else { return [] }
        return [oldest]
    }
}
