import Foundation

// Tournoi de la semaine: everyone can sign up until Monday 9 h (Paris, winter time: 08:00 UTC). Then a
// knockout bracket, one round a day: each player of a match plays the same 5 words whenever they want
// within the 24 hours, the best time goes through (+20 s per word passed), the other one is out.
// No server: the bracket follows from the players signed up (a draw seeded by the week) and from the
// runs stamped by Firestore (tournaments/{week}/…, see Firebase/firestore.rules). Same as Tournament.kt.

public enum TournamentRules {
    public static let maxPlayers = 64
    public static let dayMs = 86_400_000
    /// Sign-ups close, and the first round opens, on Monday at 08:00 UTC.
    public static let startHourMs = 8 * 3_600_000

    /// A week's id: its Monday, "2026-11-16".
    public static func deadlineMs(week: String) -> Int? {
        let parts = week.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        let day = daysFromCivil(parts[0], parts[1], parts[2])
        guard weekday(day) == 0 else { return nil }
        return day * dayMs + startHourMs
    }
    /// The tournament whose sign-ups are open now.
    public static func nextWeek(nowMs: Int) -> String {
        let day = floorDiv(nowMs - startHourMs, dayMs)
        var monday = day - weekday(day)
        if monday * dayMs + startHourMs <= nowMs { monday += 7 }
        return civil(monday)
    }
    /// The tournament under way (or just over): the one that started last Monday.
    public static func currentWeek(nowMs: Int) -> String {
        civil(floorDiv((deadlineMs(week: nextWeek(nowMs: nowMs)) ?? 0) - startHourMs, dayMs) - 7)
    }
    /// Round r (from 1) is open for 24 hours, the first one from the Monday deadline.
    public static func roundStartMs(week: String, round: Int) -> Int? { deadlineMs(week: week).map { $0 + (round - 1) * dayMs } }
    public static func roundEndMs(week: String, round: Int) -> Int? { deadlineMs(week: week).map { $0 + round * dayMs } }
    /// 2 players: 1 round (the final); up to 64: 6 rounds.
    public static func rounds(players: Int) -> Int {
        var size = 1, rounds = 0
        while size < min(players, maxPlayers) { size *= 2; rounds += 1 }
        return players < 2 ? 0 : rounds
    }
    /// The round open at this moment, if any.
    public static func round(week: String, players: Int, nowMs: Int) -> Int? {
        guard let start = deadlineMs(week: week), nowMs >= start else { return nil }
        let round = (nowMs - start) / dayMs + 1
        return round <= rounds(players: players) ? round : nil
    }
    /// The words of a round, drawn by the first player who starts it (then kept in Firestore).
    public static func draw(week: String, round: Int) -> [String] { ChallengeRules.draw(seed: seed(week + "#\(round)")) }

    /// FNV-1a, 64 bits: the same seed on both platforms.
    public static func seed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return hash
    }

    // Calendar arithmetic on days since 1970-01-01 (a Thursday), so no time zone is involved.
    static func weekday(_ day: Int) -> Int { ((day + 3) % 7 + 7) % 7 }
    static func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = floorDiv(y, 400)
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
    static func civil(_ days: Int) -> String {
        let z = days + 719_468
        let era = floorDiv(z, 146_097)
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}

public struct TournamentPlayer: Codable, Sendable, Equatable {
    public var uid: String
    public var name: String
    public var atMs: Int
    public init(uid: String, name: String, atMs: Int) { self.uid = uid; self.name = name; self.atMs = atMs }
}

/// One player's 5 words in one round, timed by the server.
public struct TournamentRun: Codable, Sendable, Equatable {
    public var uid: String
    public var round: Int
    public var startedMs: Int
    public var finishedMs: Int?
    public var skips = 0
    public var errors = 0
    public init(uid: String, round: Int, startedMs: Int, finishedMs: Int? = nil, skips: Int = 0, errors: Int = 0) {
        self.uid = uid; self.round = round; self.startedMs = startedMs; self.finishedMs = finishedMs; self.skips = skips; self.errors = errors
    }
    public var scoreMs: Int? { finishedMs.map { $0 - startedMs + skips * ChallengeRules.skipPenaltyMs } }
}

public struct TournamentBracket: Sendable, Equatable {
    public enum Slot: Sendable, Equatable {
        case player(TournamentPlayer)
        /// Nobody: a bye, or a match where neither player played.
        case empty
        /// Not known yet: the match before is still being played.
        case pending
        public var player: TournamentPlayer? { if case .player(let p) = self { return p }; return nil }
    }
    public struct Match: Sendable, Equatable {
        public var a: Slot
        public var b: Slot
        /// Decided: who goes through (nil when nobody does).
        public var decided = false
        public var winner: TournamentPlayer?
        public func has(_ uid: String) -> Bool { a.player?.uid == uid || b.player?.uid == uid }
        public func opponent(of uid: String) -> Slot { a.player?.uid == uid ? b : a }
    }

    public let week: String
    /// The players in the draw: the first 64 signed up.
    public let players: [TournamentPlayer]
    public private(set) var rounds: [[Match]] = []

    /// The bracket as it stands at `nowMs` (the server's time) given the runs read so far.
    public init(week: String, signedUp: [TournamentPlayer], runs: [TournamentRun], nowMs: Int) {
        self.week = week
        var entrants = Array(signedUp.sorted { ($0.atMs, $0.uid) < ($1.atMs, $1.uid) }.prefix(TournamentRules.maxPlayers))
        var random = ModeRandom(seed: TournamentRules.seed(week))
        if entrants.count > 1 {
            for i in stride(from: entrants.count - 1, to: 0, by: -1) { entrants.swapAt(i, random.int(i + 1)) }
        }
        players = entrants
        let total = TournamentRules.rounds(players: entrants.count)
        guard total > 0 else { return }
        let half = (1 << total) / 2
        var current: [Match] = (0..<half).map { k in
            Match(a: .player(entrants[k]), b: k + half < entrants.count ? .player(entrants[k + half]) : .empty)
        }
        var byKey: [String: TournamentRun] = [:]
        for run in runs { byKey["\(run.round)_\(run.uid)"] = run }
        for round in 1...total {
            let end = TournamentRules.roundEndMs(week: week, round: round) ?? 0
            current = current.map { Self.decide($0, round: round, end: end, now: nowMs, runs: byKey) }
            rounds.append(current)
            guard round < total else { break }
            current = stride(from: 0, to: current.count, by: 2).map { k in
                Match(a: Self.next(current[k]), b: Self.next(current[k + 1]))
            }
        }
    }

    private static func next(_ match: Match) -> Slot {
        guard match.decided else { return .pending }
        return match.winner.map { .player($0) } ?? .empty
    }

    private static func decide(_ match: Match, round: Int, end: Int, now: Int, runs: [String: TournamentRun]) -> Match {
        var m = match
        switch (m.a, m.b) {
        case (.pending, _), (_, .pending): return m
        case (.empty, .empty): m.decided = true
        case (.player(let p), .empty), (.empty, .player(let p)): m.decided = true; m.winner = p
        case (.player(let a), .player(let b)):
            func score(_ p: TournamentPlayer) -> TournamentRun? {
                guard let run = runs["\(round)_\(p.uid)"], let finished = run.finishedMs, finished <= end, run.scoreMs != nil else { return nil }
                return run
            }
            let ra = score(a), rb = score(b)
            // Both finished: no need to wait for the end of the day.
            guard (ra != nil && rb != nil) || now >= end else { return m }
            m.decided = true
            switch (ra, rb) {
            case let (x?, y?): m.winner = Self.better(x, y) ? a : b
            case (_?, nil): m.winner = a
            case (nil, _?): m.winner = b
            case (nil, nil): m.winner = nil
            }
        }
        return m
    }
    /// Best time, then fewer errors, then the first one to finish.
    static func better(_ x: TournamentRun, _ y: TournamentRun) -> Bool {
        let sx = x.scoreMs ?? .max, sy = y.scoreMs ?? .max
        if sx != sy { return sx < sy }
        if x.errors != y.errors { return x.errors < y.errors }
        if x.finishedMs != y.finishedMs { return (x.finishedMs ?? .max) < (y.finishedMs ?? .max) }
        return x.uid < y.uid
    }

    /// The champion, once the final is decided.
    public var champion: TournamentPlayer? { rounds.last?.first.flatMap { $0.decided ? $0.winner : nil } }

    public enum Standing: Equatable, Sendable {
        /// Not in the draw (signed up too late, or not at all).
        case out
        /// My match of this round: to play, or waiting for the other one / the end of the day.
        case match(round: Int, Match)
        /// Waiting for the next round to open.
        case through(round: Int)
        case eliminated(round: Int)
        case champion
    }

    public func standing(of uid: String, nowMs: Int) -> Standing {
        guard players.contains(where: { $0.uid == uid }) else { return .out }
        for (index, matches) in rounds.enumerated() {
            let round = index + 1
            guard let match = matches.first(where: { $0.has(uid) }) else { return .through(round: round) }
            if !match.decided { return .match(round: round, match) }
            if match.winner?.uid != uid { return .eliminated(round: round) }
            if round == rounds.count { return .champion }
            // Through: shown on this round until the next one opens.
            if nowMs < (TournamentRules.roundEndMs(week: week, round: round) ?? 0) { return .match(round: round, match) }
        }
        return .out
    }
}

public enum TournamentFormat {
    /// "Finale", "Demi-finales", "Quarts de finale", "8es de finale", or "Tour 1".
    public static func roundName(_ round: Int, of total: Int) -> String {
        switch total - round {
        case 0: return "Finale"
        case 1: return "Demi-finales"
        case 2: return "Quarts de finale"
        case 3: return "8es de finale"
        case 4: return "16es de finale"
        default: return "Tour \(round)"
        }
    }
}
