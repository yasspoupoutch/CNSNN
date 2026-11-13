import Foundation

// Duel en direct: two players on the same 5 words at the same moment, each one seeing the other move
// forward. The server stamps the start and every finish (duels/{id}, see Firebase/firestore.rules);
// the same rules as LiveDuel.kt. The words and the skip penalty are those of the friend challenges.

public enum LiveDuelRules {
    /// Between the moment both players are there and the first word: a 3-2-1 for everyone.
    public static let countdownMs = 5_000
    /// A duel lasts 10 minutes at most: whoever has not finished by then loses.
    public static let maxMs = 10 * 60_000
    /// A friend has 15 minutes to open the link of a duel.
    public static let joinWindowMs = 15 * 60_000
    /// Looking for a random opponent: one minute at most, a new look every few seconds.
    public static let searchMs = 60_000
    public static let searchEveryMs = 8_000
    /// Players in the waiting line for longer than this are not taken any more (closed app).
    public static let queueFreshMs = 90_000

    /// The words of a new duel: same draw as a friend challenge.
    public static func draw(seed: UInt64, recent: [String] = []) -> [String] { ChallengeRules.draw(seed: seed, recent: recent) }
}

/// A duel as stored in Firestore, with the server's times in milliseconds.
public struct LiveDuel: Codable, Sendable, Equatable, Identifiable {
    public struct Side: Codable, Sendable, Equatable {
        public var uid: String
        public var name: String
        /// Words behind the player: found or passed.
        public var done = 0
        public var skips = 0
        public var finishedMs: Int?
        /// Left the duel before the end: it is lost.
        public var quit = false
        public init(uid: String, name: String, done: Int = 0, skips: Int = 0, finishedMs: Int? = nil, quit: Bool = false) {
            self.uid = uid; self.name = name; self.done = done; self.skips = skips; self.finishedMs = finishedMs; self.quit = quit
        }
        public var finished: Bool { finishedMs != nil }
    }

    public var id: String
    public var cardIds: [String]
    public var createdMs: Int
    /// The first word's moment, once both players are there (nil while a link waits for a friend).
    public var startMs: Int?
    public var from: Side
    public var to: Side
    /// The code of a duel by link; nil for a random opponent.
    public var code: String?

    public init(id: String, cardIds: [String], createdMs: Int, startMs: Int? = nil, from: Side, to: Side, code: String? = nil) {
        self.id = id; self.cardIds = cardIds; self.createdMs = createdMs; self.startMs = startMs; self.from = from; self.to = to; self.code = code
    }

    public func involves(_ uid: String) -> Bool { from.uid == uid || to.uid == uid }
    public func mine(_ uid: String) -> Side { from.uid == uid ? from : to }
    public func theirs(_ uid: String) -> Side { from.uid == uid ? to : from }
    /// A duel by link that nobody has joined yet.
    public var isOpen: Bool { to.uid.isEmpty }
    /// Nobody can join any more.
    public func joinClosed(now: Int) -> Bool { now >= createdMs + LiveDuelRules.joinWindowMs }

    /// Finish minus start, plus 20 s per word passed.
    public func scoreMs(_ side: Side) -> Int? {
        guard let startMs, let finishedMs = side.finishedMs else { return nil }
        return finishedMs - startMs + side.skips * ChallengeRules.skipPenaltyMs
    }
    /// The best time a player still on the words can make: the clock only goes up.
    public func boundMs(_ side: Side, now: Int) -> Int? {
        if let score = scoreMs(side) { return score }
        guard let startMs else { return nil }
        return max(0, now - startMs) + side.skips * ChallengeRules.skipPenaltyMs
    }
    public func endMs() -> Int? { startMs.map { $0 + LiveDuelRules.maxMs } }

    public enum Result: Equatable, Sendable { case won, lost, draw }

    public enum State: Equatable, Sendable {
        /// A link waiting for a friend.
        case waiting
        /// Both are there: the 3-2-1 before the first word.
        case countdown
        case playing
        /// I finished; the other one can still beat my time.
        case finished
        case over(Result)
    }

    public func state(for uid: String, now: Int) -> State {
        if let result = result(for: uid, now: now) { return .over(result) }
        guard let startMs, !isOpen else { return .waiting }
        if now < startMs { return .countdown }
        return mine(uid).finished ? .finished : .playing
    }

    /// Nil while the duel is still on. `now` is the server's time, as well as this phone can tell it.
    public func result(for uid: String, now: Int) -> Result? {
        guard startMs != nil, !isOpen else { return nil }
        let me = mine(uid), other = theirs(uid)
        // Leaving is only possible before finishing (see the rules): it loses.
        if me.quit || other.quit { return me.quit && other.quit ? .draw : me.quit ? .lost : .won }
        let over = now >= (endMs() ?? .max)
        switch (scoreMs(me), scoreMs(other)) {
        case let (mine?, theirs?): return mine == theirs ? .draw : mine < theirs ? .won : .lost
        case let (mine?, nil):
            if over { return .won }
            return (boundMs(other, now: now) ?? 0) > mine ? .won : nil
        case let (nil, theirs?):
            if over { return .lost }
            return (boundMs(me, now: now) ?? 0) > theirs ? .lost : nil
        case (nil, nil): return over ? .draw : nil
        }
    }

    /// While I wait after finishing: the time the other one has left to beat me.
    public func leftToBeatMs(for uid: String, now: Int) -> Int? {
        guard let mine = scoreMs(mine(uid)), let bound = boundMs(theirs(uid), now: now), let end = endMs() else { return nil }
        return max(0, min(mine - bound, end - now))
    }
}

/// The server's time on this phone: each write stamped by the server tells how far the phone's
/// clock is (half the round trip is taken as the way back).
public struct ServerClock: Sendable, Equatable {
    public var offsetMs = 0
    public init(offsetMs: Int = 0) { self.offsetMs = offsetMs }
    public mutating func learn(serverMs: Int, sentMs: Int, receivedMs: Int) {
        offsetMs = serverMs - (sentMs + receivedMs) / 2
    }
    public func now(localMs: Int) -> Int { localMs + offsetMs }
}

public enum LiveDuelInvite {
    public static func shareText(code: String) -> String {
        "Duel en direct sur CNSNN : mêmes 5 mots, au même moment, le plus rapide gagne ! Je t’attends, rejoins-moi avec le code \(code) : \(ChallengeInvite.link(code))"
    }
}
