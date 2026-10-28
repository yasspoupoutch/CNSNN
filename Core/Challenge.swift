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

    /// Document ids start with the sending phone's clock (13 digits, then a random part), so the
    /// background check can ask for the latest challenges with a cursor on the id: no composite index.
    public static func newId(nowMs: Int, random: String) -> String { padded(max(0, nowMs)) + "-" + random }
    /// Ids above this one cover the challenges still open, with 2 h of slack for a wrong phone clock.
    public static func recentFromId(nowMs: Int) -> String { padded(max(0, nowMs - finishWindowMs - 2 * 3_600_000)) }
    /// The whole list is read again once a week (to drop the challenges of deleted accounts);
    /// otherwise only the recent ones, since a challenge never changes after its 50 hours.
    public static let fullRefreshMs = 7 * 24 * 3_600_000
    /// The list kept on the phone, brought up to date with the recent challenges just read.
    public static func merge(cached: [Challenge], recent: [Challenge], nowMs: Int) -> [Challenge] {
        let cursor = recentFromId(nowMs: nowMs)
        let fresh = Set(recent.map(\.id))
        let frozen = cached.filter { $0.id <= cursor && !fresh.contains($0.id) }
        return (frozen + recent).sorted { $0.createdMs > $1.createdMs }
    }
    /// Background checks for notifications: every 30 minutes at most, none at night (midnight to
    /// 7 am, local time), and none soon after the app itself read the challenges.
    public static let checkEveryMs = 30 * 60_000
    public static func nextCheck(after date: Date, calendar: Calendar = .current) -> Date {
        let next = date.addingTimeInterval(TimeInterval(checkEveryMs / 1000))
        guard calendar.component(.hour, from: next) < 7 else { return next }
        return calendar.date(bySettingHour: 7, minute: 0, second: 0, of: next) ?? next
    }
    public static func shouldCheck(at date: Date, lastReadMs: Int?, calendar: Calendar = .current) -> Bool {
        guard calendar.component(.hour, from: date) >= 7 else { return false }
        guard let lastReadMs else { return true }
        return Int(date.timeIntervalSince1970 * 1000) - lastReadMs >= checkEveryMs / 2
    }
    private static func padded(_ ms: Int) -> String {
        let digits = String(ms)
        return String(repeating: "0", count: max(0, 13 - digits.count)) + digits
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
    /// Positions of the words passed (optional: games saved by older versions have none).
    public var skipped: [Int]?
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
        skips += 1; skipped = (skipped ?? []) + [index]; index += 1
    }
    /// The words passed, shown at the end.
    public var missed: [String] { (skipped ?? []).compactMap { cards.indices.contains($0) ? cards[$0].wordFull : nil } }

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
    /// The invite code of a challenge by link (nil for a challenge sent to a friend).
    public var code: String?

    public init(id: String, cardIds: [String], createdMs: Int, from: Side, to: Side, code: String? = nil) {
        self.id = id; self.cardIds = cardIds; self.createdMs = createdMs; self.from = from; self.to = to; self.code = code
    }

    public func involves(_ uid: String) -> Bool { from.uid == uid || to.uid == uid }
    public func mine(_ uid: String) -> Side { from.uid == uid ? from : to }
    public func theirs(_ uid: String) -> Side { from.uid == uid ? to : from }
    /// A challenge by link that nobody has joined yet.
    public var isOpen: Bool { to.uid.isEmpty }
    /// The other player's name, or what stands for it while nobody has joined.
    public func opponentName(_ uid: String) -> String { isOpen && from.uid == uid ? "Défi par lien" : theirs(uid).name }
    /// The same challenge under the players' current pseudos: the names are saved when it is made,
    /// so a player who renamed since would otherwise keep their old pseudo here.
    public func renaming(_ names: [String: String]) -> Challenge {
        var copy = self
        if let name = names[from.uid], !name.isEmpty { copy.from.name = name }
        if let name = names[to.uid], !name.isEmpty { copy.to.name = name }
        return copy
    }

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

/// Challenges by link: a 6-character code (the friend-code alphabet, no 0/O or 1/I) and its web page,
/// which opens the app (cnsnn://d/CODE) or tells how to get it.
public enum ChallengeInvite {
    public static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    public static let host = "cnsnn-9ctosy.web.app"
    public static func link(_ code: String) -> String { "https://\(host)/d/\(code)" }
    public static func newCode() -> String { String((0..<6).map { _ in alphabet.randomElement()! }) }
    /// The code in a typed text, a pasted link or an opened URL; nil when there is none.
    public static func code(in text: String) -> String? {
        var part = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = part.range(of: "/d/", options: .backwards) { part = String(part[range.upperBound...]) }
        else if part.lowercased().hasPrefix("cnsnn://") { part = String(part.dropFirst("cnsnn://".count)) }
        let letters = part.uppercased().prefix { $0 != "?" && $0 != "#" && $0 != "/" }.filter { $0.isLetter || $0.isNumber }
        guard letters.count == 6, letters.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return String(letters)
    }
    public static func shareText(code: String) -> String {
        "Je te défie sur CNSNN : 5 mots sans leurs voyelles, le plus rapide gagne ! Rejoins mon défi avec le code \(code) : \(link(code))"
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

/// The notifications a background check shows: a friend's new challenge, and the result once the
/// friend finished after you. Each one has a key, remembered so it is shown only once.
public enum ChallengeAlerts {
    public struct Alert: Equatable, Sendable {
        public let key: String
        public let challengeID: String
        public let title: String
        public let body: String
    }

    public static func all(_ challenges: [Challenge], uid: String, now: Int) -> [Alert] {
        challenges.compactMap { alert($0, uid: uid, now: now) }
    }
    public static func pending(_ challenges: [Challenge], uid: String, now: Int, seen: Set<String>) -> [Alert] {
        all(challenges, uid: uid, now: now).filter { !seen.contains($0.key) }
    }

    private static func alert(_ c: Challenge, uid: String, now: Int) -> Alert? {
        guard c.involves(uid) else { return nil }
        let mine = c.mine(uid), theirs = c.theirs(uid)
        if c.state(for: uid, now: now) == .yourTurn && c.to.uid == uid {
            return Alert(key: c.id + ".new", challengeID: c.id, title: "\(theirs.name) vous a défié !",
                         body: "Mêmes 5 mots, le plus rapide gagne. Plus que \(ChallengeFormat.left(c.startDeadlineMs() - now)) pour jouer.")
        }
        guard let result = c.result(for: uid, now: now), result != .expired,
              let mineAt = mine.finishedMs, let theirsAt = theirs.finishedMs, theirsAt > mineAt else { return nil }
        let title: String
        switch result {
        case .won: title = "Victoire contre \(theirs.name) !"
        case .lost: title = "Défaite contre \(theirs.name)"
        default: title = "Égalité avec \(theirs.name)"
        }
        let body = "Votre chrono : \(ChallengeFormat.time(mine.scoreMs ?? 0)) · \(theirs.name) : \(ChallengeFormat.time(theirs.scoreMs ?? 0))"
        return Alert(key: c.id + ".done", challengeID: c.id, title: title, body: body)
    }
}
