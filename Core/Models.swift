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
    /// Pseudo of the player who proposed a community card (nil for built-in cards).
    public var author: String?
    /// Consonants given by the server for a secret Mot du jour, whose word stays unknown until the end.
    public var masked: String?
    public var wordNoVowels: String { masked ?? WordEngine.consonants(wordFull) }
    public init(id: String, wordFull: String, hint: String, category: Category, difficulty: Difficulty, status: ReviewStatus = .approved, author: String? = nil, masked: String? = nil) {
        self.id = id; self.wordFull = wordFull; self.hint = hint; self.category = category; self.difficulty = difficulty; self.status = status; self.author = author; self.masked = masked
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
    /// Secret Mot du jour words, revealed by the server once the day's game is over (by day key).
    public var dailyWords: [String: Card]?
    /// Version of the community rules the player accepted (nil: never).
    public var rulesVersion: Int?
    /// Personal records of Sprint, Survie and Double sens (by PlayMode raw value). Never official.
    public var modes: [String: ModeRecords]?
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

extension Progress {
    /// Combines two copies of the same player's progress (this device and the cloud, or two devices).
    /// History only grows: attempts are united by id, and a day keeps a single daily result.
    public func merged(with other: Progress) -> Progress {
        var result = self
        if result.username.isEmpty { result.username = other.username }
        var ids = Set(result.attempts.map(\.id))
        var days = Set(result.attempts.compactMap(\.dailyKey))
        for attempt in other.attempts where !ids.contains(attempt.id) {
            if let day = attempt.dailyKey {
                guard !days.contains(day) else { continue }
                days.insert(day)
            }
            ids.insert(attempt.id)
            result.attempts.append(attempt)
        }
        result.attempts.sort { $0.date < $1.date }
        result.dailyStarted.merge(other.dailyStarted) { mine, _ in mine }
        result.dailyStartedAt.merge(other.dailyStartedAt) { mine, _ in mine }
        if let words = other.dailyWords { result.dailyWords = (result.dailyWords ?? [:]).merging(words) { mine, theirs in mine.wordFull.isEmpty ? theirs : mine } }
        // A proposal is one word: two devices may know it under different ids, and one may already
        // have its moderation verdict.
        for theirs in other.submissions {
            let word = WordEngine.normalize(theirs.card.wordFull)
            if let index = result.submissions.firstIndex(where: { WordEngine.normalize($0.card.wordFull) == word }) {
                if result.submissions[index].card.status == .pending && theirs.card.status != .pending { result.submissions[index] = theirs }
            } else {
                result.submissions.append(theirs)
            }
        }
        if result.recentCards.isEmpty { result.recentCards = other.recentCards }
        if let theirs = other.rulesVersion, theirs > (result.rulesVersion ?? 0) { result.rulesVersion = theirs }
        if let theirs = other.modes {
            var mine = result.modes ?? [:]
            for (mode, records) in theirs { mine[mode] = (mine[mode] ?? ModeRecords()).merged(with: records) }
            result.modes = mine
        }
        return result
    }
}
