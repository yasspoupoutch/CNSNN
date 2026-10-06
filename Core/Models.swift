import Foundation

public enum Category: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case general = "Général", football = "Football", cinema = "Cinéma", geography = "Géographie", animals = "Animaux", objects = "Objets"
    public var id: String { rawValue }
}
public enum Difficulty: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case easy = "Facile", medium = "Moyen", hard = "Difficile"
    public var id: String { rawValue }
    public var basePoints: Int { switch self { case .easy: 50; case .medium: 100; case .hard: 150 } }
}
public enum GameMode: String, Codable, Sendable { case classic, daily }
public enum ReviewStatus: String, Codable, Hashable, Sendable { case pending, approved, rejected }
public struct Card: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var wordFull: String
    public var hint: String
    public var category: Category
    public var difficulty: Difficulty
    public var status: ReviewStatus
    public var wordNoVowels: String { WordEngine.consonants(wordFull) }
    public init(id: String, wordFull: String, hint: String, category: Category, difficulty: Difficulty, status: ReviewStatus = .approved) {
        self.id = id; self.wordFull = wordFull; self.hint = hint; self.category = category; self.difficulty = difficulty; self.status = status
    }
}
public struct Attempt: Identifiable, Codable, Sendable {
    public var id: String = UUID().uuidString
    public var cardID: String
    public var mode: GameMode
    public var correct: Bool
    public var timeMs: Int
    public var points: Int
    public var date: Date
    public var dailyKey: String?
    public init(cardID: String, mode: GameMode, correct: Bool, timeMs: Int, points: Int, date: Date, dailyKey: String? = nil) {
        self.cardID = cardID; self.mode = mode; self.correct = correct; self.timeMs = timeMs; self.points = points; self.date = date; self.dailyKey = dailyKey
    }
}
public struct Submission: Identifiable, Codable, Sendable {
    public var id: String = UUID().uuidString
    public var card: Card
    public var createdAt: Date = Date()
    public init(card: Card) { self.card = card }
}
public struct Progress: Codable, Sendable {
    public var username = ""
    public var attempts: [Attempt] = []
    public var recentCards: [String] = []
    public var submissions: [Submission] = []
    public var dailyStarted: [String: String] = [:]
    public var dailyStartedAt: [String: Date] = [:]
    public init() {}
    public var score: Int { attempts.reduce(0) { $0 + $1.points } }
    public var correctAnswers: Int { attempts.filter(\.correct).count }
    public var successRate: Double { attempts.isEmpty ? 0 : Double(correctAnswers) / Double(attempts.count) }
    public var bestTimeMs: Int? { attempts.filter(\.correct).map(\.timeMs).min() }
    public var averageTimeMs: Int? {
        let wins = attempts.filter(\.correct)
        return wins.isEmpty ? nil : wins.reduce(0) { $0 + $1.timeMs } / wins.count
    }
    public var dailyWins: Int { attempts.filter { $0.mode == .daily && $0.correct }.count }
    public func streak(at date: Date = Date()) -> Int {
        let days = Set(attempts.filter { $0.mode == .daily && $0.correct }.compactMap(\.dailyKey))
        var current = date
        if !days.contains(DailySchedule.key(current)) { current = DailySchedule.previousDay(current) }
        var count = 0
        while days.contains(DailySchedule.key(current)) { count += 1; current = DailySchedule.previousDay(current) }
        return count
    }
}
