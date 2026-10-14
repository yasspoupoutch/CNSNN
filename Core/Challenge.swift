import Foundation

// Défi entre amis: the same 5 words for two friends, the best time wins. Firestore times both players
// (challenges/{id}, see Firebase/firestore.rules); these are the shared rules, also in Challenge.kt.

public enum ChallengeRules {
    public static let words = 5
    /// A skipped word adds 20 s to the time.
    public static let skipPenaltyMs = 20_000
    /// The friend has 48 h to start, and everyone must finish before the 50th hour.
    public static let startWindowMs = 48 * 3_600_000
    public static let finishWindowMs = 50 * 3_600_000
    /// 2 easy, 2 medium and 1 hard word, in that order.
    public static let levels: [[Int]] = [[100, 0, 0], [100, 0, 0], [0, 100, 0], [0, 100, 0], [0, 0, 100]]

    /// The words of a new challenge, drawn from the public catalogue (never the secret daily words).
    public static func draw(seed: UInt64, recent: [String] = []) -> [String] {
        var random = ModeRandom(seed: seed)
        var used: [String] = []
        for weights in levels {
            guard let card = ModePicker.next(pool: ModeCatalogue.cards, weights: weights, used: Set(used), recent: Set(recent), random: &random) else { break }
            used.append(card.id)
        }
        return used
    }

    public static func cards(_ ids: [String]) -> [Card]? {
        let found = ids.compactMap { id in ModeCatalogue.cards.first { $0.id == id } }
        return found.count == ids.count && found.count == words ? found : nil
    }
}

/// One player's run through the 5 words. The clock is the server's: the screen passes the elapsed time.
public struct ChallengeGame: Codable, Sendable {
    public let cards: [Card]
    public var index = 0
    public var found = 0
    public var skips = 0
    public var errors = 0
    public var finished: Bool { index >= cards.count }

    public init(cards: [Card]) { self.cards = cards }

    public var card: Card? { finished ? nil : cards[index] }

    public enum Outcome: Equatable, Sendable { case right, wrong, over }

    @discardableResult public mutating func answer(_ text: String) -> Outcome {
        guard let card else { return .over }
        guard WordEngine.matches(text, word: card.wordFull) else { errors += 1; return .wrong }
        found += 1; index += 1
        return .right
    }

    public mutating func skip() {
        guard !finished else { return }
        skips += 1; index += 1
    }

    /// The time shown and compared: play time plus 20 s per skipped word.
    public func scoreMs(elapsed: Int) -> Int { elapsed + skips * ChallengeRules.skipPenaltyMs }
}

/// A challenge as stored in Firestore, with times in milliseconds.
public struct Challenge: Codable, Sendable, Equatable, Identifiable {
    public struct Side: Codable, Sendable, Equatable {
        public var uid: String
        public var name: String
        public var startedMs: Int?
        public var finishedMs: Int?
        public var skips = 0
        public var errors = 0
        public init(uid: String, name: String, startedMs: Int? = nil, finishedMs: Int? = nil, skips: Int = 0, errors: Int = 0) {
            self.uid = uid; self.name = name; self.startedMs = startedMs; self.finishedMs = finishedMs; self.skips = skips; self.errors = errors
        }
        public var finished: Bool { finishedMs != nil }
        /// Finish minus start, plus the skip penalty.
        public var scoreMs: Int? {
            guard let startedMs, let finishedMs else { return nil }
            return finishedMs - startedMs + skips * ChallengeRules.skipPenaltyMs
        }
    }

    public var id: String
    public var cardIds: [String]
    public var createdMs: Int
    public var from: Side
    public var to: Side

    public init(id: String, cardIds: [String], createdMs: Int, from: Side, to: Side) {
        self.id = id; self.cardIds = cardIds; self.createdMs = createdMs; self.from = from; self.to = to
    }

    public func involves(_ uid: String) -> Bool { from.uid == uid || to.uid == uid }
    public func mine(_ uid: String) -> Side { from.uid == uid ? from : to }
    public func theirs(_ uid: String) -> Side { from.uid == uid ? to : from }

    /// Time left for the friend to start, then for everyone to finish.
    public func startDeadlineMs() -> Int { createdMs + ChallengeRules.startWindowMs }
    public func finishDeadlineMs() -> Int { createdMs + ChallengeRules.finishWindowMs }

    public enum Result: Equatable, Sendable { case won, lost, draw, expired }

    public enum State: Equatable, Sendable {
        /// The friend challenged me and I have not played yet.
        case yourTurn
        /// I started but did not finish (the app was closed): the clock kept running.
        case playing
        /// I finished; the other player has not.
        case waiting
        case over(Result)
    }

    public func state(for uid: String, now: Int) -> State {
        let me = mine(uid)
        if let result = result(for: uid, now: now) { return .over(result) }
        if me.startedMs == nil { return .yourTurn }
        return me.finished ? .waiting : .playing
    }

    /// Nil while the challenge is still open.
    public func result(for uid: String, now: Int) -> Result? {
        let me = mine(uid), other = theirs(uid)
        if let mine = me.scoreMs, let theirs = other.scoreMs {
            if mine != theirs { return mine < theirs ? .won : .lost }
            if me.errors != other.errors { return me.errors < other.errors ? .won : .lost }
            return .draw
        }
        let closed = now >= finishDeadlineMs() || (to.startedMs == nil && now >= startDeadlineMs())
        guard closed else { return nil }
        // The friend never started: nobody wins. Someone who started and gave up loses.
        if to.startedMs == nil { return .expired }
        if me.finished { return .won }
        if other.finished { return .lost }
        return .expired
    }
}

public struct ChallengeTally: Equatable, Sendable {
    public var wins = 0
    public var losses = 0
    public var draws = 0
    public init(wins: Int = 0, losses: Int = 0, draws: Int = 0) { self.wins = wins; self.losses = losses; self.draws = draws }

    /// "2 victoires · 1 défaite", or nil before the first finished challenge.
    public var label: String? {
        guard wins + losses + draws > 0 else { return nil }
        var parts = ["\(wins) victoire\(wins > 1 ? "s" : "")", "\(losses) défaite\(losses > 1 ? "s" : "")"]
        if draws > 0 { parts.append("\(draws) égalité\(draws > 1 ? "s" : "")") }
        return parts.joined(separator: " · ")
    }

    /// Wins and losses against one friend (or everyone when `friend` is nil).
    public static func of(_ challenges: [Challenge], me: String, friend: String? = nil, now: Int) -> ChallengeTally {
        var tally = ChallengeTally()
        for challenge in challenges where challenge.involves(me) && (friend == nil || challenge.theirs(me).uid == friend) {
            switch challenge.result(for: me, now: now) {
            case .won: tally.wins += 1
            case .lost: tally.losses += 1
            case .draw: tally.draws += 1
            case .expired, nil: break
            }
        }
        return tally
    }
}

public enum ChallengeFormat {
    /// 1:58, or 12:04 past ten minutes; the hour is folded into minutes.
    public static func time(_ ms: Int) -> String {
        let seconds = max(0, ms) / 1000
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
    /// "31 h" or "45 min" left.
    public static func left(_ ms: Int) -> String {
        let minutes = max(0, ms) / 60_000
        return minutes >= 60 ? "\(minutes / 60) h" : "\(max(1, minutes)) min"
    }
}
