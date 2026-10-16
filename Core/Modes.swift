import Foundation

// Sprint, Survie and Double sens. The rules are plain values with no clock of their own: the screen
// passes the elapsed time, so the tests replay a whole game. Android runs the same rules (Modes.kt),
// and both replay the scenarios of Scripts/generate_content.py (Tests/Core/ModeVectors.swift).

public enum PlayMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case sprint, survival, duo
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .sprint: "Sprint"
        case .survival: "Survie"
        case .duo: "Double sens"
        }
    }
}

/// SplitMix64: the same numbers from the same seed on the iPhone, on Android and in the reference script.
public struct ModeRandom: Codable, Sendable, Equatable {
    public var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    public mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
    /// A fresh seed for a new game.
    public static func seed() -> UInt64 { UInt64.random(in: 0...UInt64.max) }
}

/// The verified built-in cards played in Sprint and Survie (community cards stay in Classique),
/// in a fixed order so both platforms draw the same card from the same seed.
public enum ModeCatalogue {
    public static let cards: [Card] = (SeedCards.all + ExtraCards.all).sorted { $0.id < $1.id }
}

public enum ModePicker {
    /// Rolls a difficulty with the given weights (easy, medium, hard, out of 100), then draws a card of
    /// that difficulty never played in this game, avoiding the player's recent cards when possible.
    /// If the difficulty is used up, the nearest one is taken.
    public static func next(pool: [Card], weights: [Int], used: Set<String>, recent: Set<String>, random: inout ModeRandom) -> Card? {
        let roll = random.int(100)
        let target: Difficulty = roll < weights[0] ? .easy : roll < weights[0] + weights[1] ? .medium : .hard
        let order: [Difficulty]
        switch target {
        case .easy: order = [.easy, .medium, .hard]
        case .medium: order = [.medium, .easy, .hard]
        case .hard: order = [.hard, .medium, .easy]
        }
        for avoidRecent in [true, false] {
            for level in order {
                let options = pool.filter { $0.difficulty == level && !used.contains($0.id) && !(avoidRecent && recent.contains($0.id)) }
                if !options.isEmpty { return options[random.int(options.count)] }
            }
        }
        return nil
    }
}

// MARK: - Sprint

/// 90 seconds to find as many words as possible. Right answers in a row make a combo; a wrong answer
/// or a pass breaks it, and a pass costs 5 seconds. The clock never stops, even in the background.
public struct SprintGame: Codable, Sendable {
    public static let durationMs = 90_000
    public static let skipPenaltyMs = 5_000
    public static let weights = [40, 40, 20]

    public var random: ModeRandom
    public var card: Card?
    public var used: [String] = []
    public var recent: [String]
    public var found = 0
    /// Right answers in a row.
    public var streak = 0
    public var bestCombo = 0
    public var wrong = 0
    public var skips = 0
    public var penaltyMs = 0
    public var finished = false

    public init(seed: UInt64, recent: [String] = []) {
        random = ModeRandom(seed: seed); self.recent = recent
        draw()
    }

    public func remainingMs(elapsed: Int) -> Int { max(0, Self.durationMs - elapsed - penaltyMs) }
    /// Right answers out of all the answers checked, in percent.
    public var accuracy: Int { found + wrong == 0 ? 0 : found * 100 / (found + wrong) }

    public enum Outcome: Equatable, Sendable { case right(combo: Int), wrong, over }

    @discardableResult public mutating func answer(_ text: String, elapsed: Int) -> Outcome {
        guard !finished, remainingMs(elapsed: elapsed) > 0, let card else { finished = true; return .over }
        guard WordEngine.matches(text, word: card.wordFull) else { wrong += 1; streak = 0; return .wrong }
        streak += 1; found += 1; bestCombo = max(bestCombo, streak)
        draw()
        return .right(combo: streak)
    }

    public mutating func skip(elapsed: Int) {
        guard !finished, remainingMs(elapsed: elapsed) > 0 else { finished = true; return }
        skips += 1; streak = 0; penaltyMs += Self.skipPenaltyMs
        if remainingMs(elapsed: elapsed) == 0 { finished = true } else { draw() }
    }

    /// Ends the game once the time is up. Returns true when it just ended.
    @discardableResult public mutating func tick(elapsed: Int) -> Bool {
        guard !finished, remainingMs(elapsed: elapsed) == 0 else { return false }
        finished = true
        return true
    }

    public mutating func stop() { finished = true }

    private mutating func draw() {
        card = ModePicker.next(pool: ModeCatalogue.cards, weights: Self.weights, used: Set(used), recent: Set(recent), random: &random)
        if let card { used.append(card.id) } else { finished = true }
    }

    public var records: (best: [String: Int], add: [String: Int]) {
        ([ModeStat.words: found, ModeStat.combo: bestCombo], [ModeStat.games: 1])
    }
}

// MARK: - Survie

/// Three lives. A wrong answer or a pass costs one; every tenth word found gives one back (three at
/// most). Every five words the level rises and hard words come more often.
public struct SurvivalGame: Codable, Sendable {
    public static let maxLives = 3
    public static let wordsPerLevel = 5
    public static let bonusEvery = 10
    /// Chances of an easy, medium and hard word at levels 1, 2, 3… (the last row repeats).
    public static let levels: [[Int]] = [[100, 0, 0], [70, 30, 0], [40, 50, 10], [20, 55, 25], [10, 50, 40], [5, 40, 55], [0, 30, 70]]
    public static func weights(level: Int) -> [Int] { levels[min(max(level, 1), levels.count) - 1] }

    public var random: ModeRandom
    public var card: Card?
    public var used: [String] = []
    public var recent: [String]
    public var lives = SurvivalGame.maxLives
    public var found = 0
    public var wrong = 0
    public var skips = 0
    public var livesGained = 0
    public var finished = false

    public init(seed: UInt64, recent: [String] = []) {
        random = ModeRandom(seed: seed); self.recent = recent
        draw()
    }

    public var level: Int { found / Self.wordsPerLevel + 1 }
    /// Lives lost: wrong answers and passes.
    public var mistakes: Int { wrong + skips }

    public enum Outcome: Equatable, Sendable { case right(lifeGained: Bool), wrong(livesLeft: Int), over }

    @discardableResult public mutating func answer(_ text: String) -> Outcome {
        guard !finished, let card else { return .over }
        guard WordEngine.matches(text, word: card.wordFull) else {
            wrong += 1; lives -= 1
            if lives == 0 { finished = true }
            return .wrong(livesLeft: lives)
        }
        found += 1
        let gained = found % Self.bonusEvery == 0 && lives < Self.maxLives
        if gained { lives += 1; livesGained += 1 }
        draw()
        return .right(lifeGained: gained)
    }

    /// Next word, for one life.
    public mutating func skip() {
        guard !finished else { return }
        skips += 1; lives -= 1
        if lives == 0 { finished = true } else { draw() }
    }

    public mutating func abandon() { finished = true }

    private mutating func draw() {
        card = ModePicker.next(pool: ModeCatalogue.cards, weights: Self.weights(level: level), used: Set(used), recent: Set(recent), random: &random)
        if let card { used.append(card.id) } else { finished = true }
    }

    public var records: (best: [String: Int], add: [String: Int]) {
        ([ModeStat.words: found, ModeStat.level: level], [ModeStat.games: 1])
    }
}

// MARK: - Double sens

public struct DuoWord: Codable, Hashable, Sendable {
    public var word: String
    public var hint: String
    public init(word: String, hint: String) { self.word = word; self.hint = hint }
}

/// Two different words with exactly the same consonants (FRN: farine, frein).
public struct Duo: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var first: DuoWord
    public var second: DuoWord
    public init(id: String, first: DuoWord, second: DuoWord) { self.id = id; self.first = first; self.second = second }
    public var consonants: String { WordEngine.consonants(first.word) }
    public var words: [DuoWord] { [first, second] }
}

/// Five rounds of two words. An answer fills the word it matches; a round can be passed. The time
/// counts while a round is open, not while its answer is shown.
public struct DuoGame: Codable, Sendable {
    public static let rounds = 5

    public var random: ModeRandom
    public var duos: [Duo] = []
    public var round = 0
    public var found: [[Bool]] = []
    public var skipped: [Bool] = []
    public var errors = 0
    public var finished = false
    /// Time spent on the answers shown between rounds, left out of the clock.
    public var excludedMs = 0
    public var completedAt: Int?
    public var endMs: Int?

    public init(seed: UInt64, recent: [String] = []) {
        random = ModeRandom(seed: seed)
        let bank = DuoBank.all.sorted { $0.id < $1.id }
        for _ in 0..<min(Self.rounds, bank.count) {
            let picked = Set(duos.map(\.id))
            var options = bank.filter { !picked.contains($0.id) && !recent.contains($0.id) }
            if options.isEmpty { options = bank.filter { !picked.contains($0.id) } }
            duos.append(options[random.int(options.count)])
        }
        found = Array(repeating: [false, false], count: duos.count)
        skipped = Array(repeating: false, count: duos.count)
    }

    public var duo: Duo? { duos.indices.contains(round) ? duos[round] : nil }
    public var roundComplete: Bool { duos.indices.contains(round) && ((found[round][0] && found[round][1]) || skipped[round]) }
    public var isLastRound: Bool { round == duos.count - 1 }

    public enum Outcome: Equatable, Sendable { case first, second, already, wrong, over }

    @discardableResult public mutating func answer(_ text: String, elapsed: Int) -> Outcome {
        guard !finished, !roundComplete, let duo else { return .over }
        let key = WordEngine.normalize(text)
        let words = [WordEngine.normalize(duo.first.word), WordEngine.normalize(duo.second.word)]
        guard let index = words.firstIndex(of: key) else { errors += 1; return .wrong }
        guard !found[round][index] else { return .already }
        found[round][index] = true
        if roundComplete { close(elapsed: elapsed) }
        return index == 0 ? .first : .second
    }

    /// Gives up the words still hidden in this round.
    public mutating func skip(elapsed: Int) {
        guard !finished, !roundComplete else { return }
        skipped[round] = true
        close(elapsed: elapsed)
    }

    private mutating func close(elapsed: Int) {
        completedAt = elapsed
        if isLastRound { finished = true; endMs = elapsed - excludedMs }
    }

    public mutating func next(elapsed: Int) {
        guard !finished, roundComplete, let completedAt else { return }
        excludedMs += elapsed - completedAt
        self.completedAt = nil
        round += 1
    }

    /// Ends the game now; the rounds not played count as not found.
    public mutating func abandon(elapsed: Int) {
        guard !finished else { return }
        endMs = playMs(elapsed: elapsed); finished = true
    }

    public func playMs(elapsed: Int) -> Int {
        if let endMs { return endMs }
        return elapsed - excludedMs - (completedAt.map { elapsed - $0 } ?? 0)
    }
    public var wordsFound: Int { found.reduce(0) { $0 + $1.filter { $0 }.count } }
    public var solved: Int { found.filter { $0[0] && $0[1] }.count }
    public var perfect: Bool { wordsFound == duos.count * 2 && errors == 0 }
    public func records(elapsed: Int) -> (best: [String: Int], add: [String: Int]) {
        ([ModeStat.duo: DuoRecord.value(solved: solved, ms: playMs(elapsed: elapsed))],
         [ModeStat.games: 1, ModeStat.perfect: perfect ? 1 : 0, ModeStat.duosSolved: solved, ModeStat.duosPlayed: duos.count])
    }
}

// MARK: - Personal records

/// A Double sens game in one number that only grows with a better game: more pairs found, then less time.
public enum DuoRecord {
    public static func value(solved: Int, ms: Int) -> Int { solved * 100_000 + max(0, 99_999 - max(0, ms) / 1000) }
    public static func solved(_ value: Int) -> Int { value / 100_000 }
    public static func seconds(_ value: Int) -> Int { 99_999 - value % 100_000 }
}

public enum ModeStat {
    public static let words = "words", combo = "combo", level = "level"
    /// Double sens best: pairs found first, then the time (see DuoRecord).
    public static let duo = "duo"
    public static let games = "games", perfect = "perfect", duosSolved = "duosSolved", duosPlayed = "duosPlayed"
}

/// One mode's personal records, merged safely between devices: a best only grows (the highest wins),
/// and each counter keeps one total per device, so two phones playing offline never lose a game.
public struct ModeRecords: Codable, Sendable, Equatable {
    public var best: [String: Int] = [:]
    /// Counter name → device id → games counted on that device.
    public var counts: [String: [String: Int]] = [:]
    public init() {}
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        best = try values.decodeIfPresent([String: Int].self, forKey: .best) ?? [:]
        counts = try values.decodeIfPresent([String: [String: Int]].self, forKey: .counts) ?? [:]
    }

    public func total(_ key: String) -> Int { counts[key]?.values.reduce(0, +) ?? 0 }
    public func best(_ key: String) -> Int { best[key] ?? 0 }

    public func merged(with other: ModeRecords) -> ModeRecords {
        var result = self
        result.best.merge(other.best) { max($0, $1) }
        for (key, devices) in other.counts {
            result.counts[key, default: [:]].merge(devices) { max($0, $1) }
        }
        return result
    }
}

extension Progress {
    public func records(_ mode: PlayMode) -> ModeRecords { modes?[mode.rawValue] ?? ModeRecords() }

    /// Adds one finished game. Returns the records it beat (its first game sets them).
    @discardableResult public mutating func recordMode(_ mode: PlayMode, best: [String: Int], add: [String: Int], device: String) -> Set<String> {
        var records = self.records(mode)
        var beaten = Set<String>()
        for (key, value) in best where value > records.best(key) && value > 0 {
            records.best[key] = value; beaten.insert(key)
        }
        for (key, value) in add where value > 0 {
            records.counts[key, default: [:]][device, default: 0] += value
        }
        var all = modes ?? [:]
        all[mode.rawValue] = records
        modes = all
        return beaten
    }
}
