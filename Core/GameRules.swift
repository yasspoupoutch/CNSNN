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
    /// Local-only schedule; production uses server-published dailyChallenges.
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
