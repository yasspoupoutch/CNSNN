import Foundation

public enum Scoring {
    public static func points(difficulty: Difficulty, timeMs: Int, usedHint: Bool, correct: Bool) -> Int {
        guard correct else { return 0 }
        let bonus = max(0, 50 - max(0, timeMs) / 1000)
        return (difficulty.basePoints + bonus) / (usedHint ? 2 : 1)
    }
}
public enum DailySchedule {
    public static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Paris")!
        return value
    }
    public static func key(_ date: Date = Date()) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func previousDay(_ date: Date) -> Date { calendar.date(byAdding: .day, value: -1, to: date)! }
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
    /// Days since Monday 2024-01-01, counted on the Paris calendar.
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
