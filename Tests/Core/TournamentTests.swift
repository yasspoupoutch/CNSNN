import XCTest
@testable import CNSNNCore

final class TournamentTests: XCTestCase {
    private let week = "2026-11-16"
    private var start: Int { TournamentRules.deadlineMs(week: week)! }
    private let day = TournamentRules.dayMs
    private func players(_ n: Int) -> [TournamentPlayer] {
        (1...n).map { TournamentPlayer(uid: String(format: "p%02d", $0), name: "Joueur \($0)", atMs: $0) }
    }

    func testCalendar() {
        XCTAssertEqual(start, 1_794_816_000_000) // Monday 16 Nov 2026, 08:00 UTC
        XCTAssertNil(TournamentRules.deadlineMs(week: "2026-11-17"))
        XCTAssertEqual(TournamentRules.nextWeek(nowMs: start - 1), week)
        XCTAssertEqual(TournamentRules.nextWeek(nowMs: start), "2026-11-23")
        XCTAssertEqual(TournamentRules.currentWeek(nowMs: start), week)
        XCTAssertEqual(TournamentRules.currentWeek(nowMs: start + 6 * day), week)
        XCTAssertEqual(TournamentRules.currentWeek(nowMs: start - 1), "2026-11-09")
        XCTAssertEqual(TournamentRules.nextWeek(nowMs: TournamentRules.deadlineMs(week: "2026-12-28")! + 1), "2027-01-04")
        XCTAssertEqual([0, 1, 2, 3, 4, 5, 9, 33, 200].map { TournamentRules.rounds(players: $0) }, [0, 0, 1, 2, 2, 3, 4, 6, 6])
        XCTAssertEqual(TournamentRules.round(week: week, players: 5, nowMs: start + day), 2)
        XCTAssertNil(TournamentRules.round(week: week, players: 5, nowMs: start + 3 * day))
    }

    func testSameSeedAndDrawAsAndroid() {
        XCTAssertEqual(TournamentRules.seed(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(TournamentRules.seed("a"), 0xaf63_dc4c_8601_ec8c)
        // Same values in TournamentTest.kt.
        let bracket = TournamentBracket(week: week, signedUp: players(5), runs: [], nowMs: start)
        XCTAssertEqual(bracket.players.map(\.uid), ["p02", "p05", "p03", "p04", "p01"])
        XCTAssertEqual(TournamentRules.seed(week + "#1"), 0x472c_2207_3cb5_a8c4)
        XCTAssertEqual(Set(TournamentRules.draw(week: week, round: 1)).count, 5)
    }

    func testByesThenBestTimeGoesThrough() {
        let bracket0 = TournamentBracket(week: week, signedUp: players(5), runs: [], nowMs: start)
        let order = bracket0.players
        XCTAssertEqual(bracket0.rounds.count, 3)
        let first = bracket0.rounds[0]
        XCTAssertEqual(first.count, 4)
        XCTAssertEqual(first.filter(\.decided).count, 3)
        let a = order[0], b = order[4]
        XCTAssertTrue(first[0].has(a.uid) && first[0].has(b.uid) && !first[0].decided)
        let runs = [TournamentRun(uid: a.uid, round: 1, startedMs: start + 1_000, finishedMs: start + 41_000, skips: 1),
                    TournamentRun(uid: b.uid, round: 1, startedMs: start + 5_000, finishedMs: start + 60_000)]
        let after = TournamentBracket(week: week, signedUp: players(5), runs: runs, nowMs: start + 100_000)
        XCTAssertEqual(after.rounds[0][0].winner, b)
        XCTAssertEqual(after.rounds[1][0].a, .player(b))
        XCTAssertEqual(after.standing(of: a.uid, nowMs: start + 100_000), .eliminated(round: 1))
        XCTAssertEqual(after.standing(of: b.uid, nowMs: start + 100_000), .match(round: 1, after.rounds[0][0]))
    }

    func testNobodyPlayedOrOneFinishedAtTheEnd() {
        let order = TournamentBracket(week: week, signedUp: players(4), runs: [], nowMs: start).players
        let runs = [TournamentRun(uid: order[0].uid, round: 1, startedMs: start + 10, finishedMs: start + 50_000),
                    TournamentRun(uid: order[1].uid, round: 1, startedMs: start + 10)]
        let end = TournamentBracket(week: week, signedUp: players(4), runs: runs, nowMs: start + day)
        XCTAssertEqual(end.rounds[0][0].winner, order[0])
        XCTAssertTrue(end.rounds[0][1].decided)
        XCTAssertNil(end.rounds[0][1].winner)
        XCTAssertEqual(end.rounds[1][0].b, .empty)
        XCTAssertEqual(end.champion, order[0])
        XCTAssertEqual(end.standing(of: order[0].uid, nowMs: start + day), .champion)
        XCTAssertEqual(end.standing(of: "x", nowMs: start + day), .out)
    }

    func testEveryonePlaysEveryRoundFromDecember() {
        let later = "2026-12-07"
        let begin = TournamentRules.deadlineMs(week: later)!
        XCTAssertTrue(TournamentRules.everyonePlays(week: later))
        XCTAssertFalse(TournamentRules.everyonePlays(week: week))
        XCTAssertEqual([0, 1, 2, 3, 4, 7, 10, 64, 200].map { TournamentRules.rounds(players: $0, week: later) }, [0, 0, 1, 1, 2, 2, 3, 6, 6])
        // 14 players (too many for matches of 3 on Monday): 7 matches, then 3 (the last one by 3), then a
        // final by 3. Nobody alone.
        let bracket = TournamentBracket(week: later, signedUp: players(14), runs: [], nowMs: begin)
        XCTAssertEqual(bracket.rounds.map(\.count), [7, 3, 1])
        XCTAssertTrue(bracket.rounds[0].allSatisfy { $0.c == nil && $0.slots.allSatisfy { $0.player != nil } && !$0.decided })
        let semis = bracket.rounds[1]
        XCTAssertEqual(semis[0].from, [0, 1])
        XCTAssertEqual(semis[2].from, [4, 5, 6])
        XCTAssertEqual(semis[2].c, .pending)
        let order = bracket.players
        XCTAssertEqual(TournamentFormat.slotName(bracket, round: 2, match: semis[0], position: 1), "Gagnant de \(order[2].name) / \(order[3].name)")
        XCTAssertEqual(TournamentFormat.slotName(bracket, round: 3, match: bracket.rounds[2][0], position: 0), "Gagnant du match 1")
        let next = bracket.following(round: 1, index: 6)
        XCTAssertEqual(next?.match, semis[2])
        XCTAssertEqual(next?.others, [0, 1])
        // Round 1 finished: the fastest of each match goes on, in the same order.
        let runs = (0..<14).map { TournamentRun(uid: order[$0].uid, round: 1, startedMs: begin + 1_000, finishedMs: begin + 30_000 + $0 * 1_000) }
        let after = TournamentBracket(week: later, signedUp: players(14), runs: runs, nowMs: begin + 100_000)
        XCTAssertEqual(after.rounds[0].map(\.winner), stride(from: 0, to: 14, by: 2).map { order[$0] })
        let three = after.rounds[1][2]
        XCTAssertEqual(three.slots, [order[8], order[10], order[12]].map { .player($0) })
        XCTAssertEqual(three.opponents(of: order[10].uid).count, 2)
        // The match of 3: the fastest goes through, the two others are out.
        let second = runs + [TournamentRun(uid: order[8].uid, round: 2, startedMs: begin + day, finishedMs: begin + day + 50_000),
                             TournamentRun(uid: order[10].uid, round: 2, startedMs: begin + day, finishedMs: begin + day + 20_000),
                             TournamentRun(uid: order[12].uid, round: 2, startedMs: begin + day, finishedMs: begin + day + 40_000)]
        let later2 = TournamentBracket(week: later, signedUp: players(14), runs: second, nowMs: begin + day + 60_000)
        XCTAssertEqual(later2.rounds[1][2].winner, order[10])
        XCTAssertEqual(later2.standing(of: order[12].uid, nowMs: begin + day + 60_000), .eliminated(round: 2))
        XCTAssertEqual(later2.rounds[2][0].c, .player(order[10]))
        // Yasin's idea: 35 players, 16 matches on Monday (3 of them by 3), then 16 left: 8, 4, 2, 1.
        XCTAssertEqual(TournamentRules.firstRoundThrees(players: 35), (0..<16).map { [5, 10, 15].contains($0) })
        let big = TournamentBracket(week: later, signedUp: players(35), runs: [], nowMs: begin)
        XCTAssertEqual(big.rounds.map(\.count), [16, 8, 4, 2, 1])
        XCTAssertEqual(big.rounds[0].filter { $0.c != nil }.count, 3)
        XCTAssertEqual(big.rounds[0].flatMap { $0.slots.compactMap { $0.player?.uid } }, big.players.map(\.uid))
        XCTAssertTrue(big.rounds.dropFirst().allSatisfy { $0.allSatisfy { $0.c == nil } })
        XCTAssertEqual(TournamentBracket(week: later, signedUp: players(10), runs: [], nowMs: begin).rounds.map(\.count), [4, 2, 1])
        XCTAssertNil(TournamentRules.firstRoundThrees(players: 8))
        XCTAssertNil(TournamentRules.firstRoundThrees(players: 49))
        XCTAssertEqual(TournamentRules.firstRoundThrees(players: 48), Array(repeating: true, count: 16))
        // 3 players: one match of 3, which is the final.
        let small = TournamentBracket(week: later, signedUp: players(3), runs: [], nowMs: begin)
        XCTAssertEqual(small.rounds.count, 1)
        XCTAssertEqual(small.rounds[0][0].slots.count, 3)
    }

    func testOnlyTheFirst64() {
        let bracket = TournamentBracket(week: week, signedUp: players(70), runs: [], nowMs: start)
        XCTAssertEqual(bracket.players.count, 64)
        XCTAssertFalse(bracket.players.contains { ["p65", "p66", "p70"].contains($0.uid) })
        XCTAssertEqual(TournamentFormat.roundName(6, of: 6), "Finale")
        XCTAssertEqual(TournamentFormat.roundName(1, of: 6), "Tour 1")
    }

    func testWeeksToDeleteWithTheAccount() {
        let monday16 = TournamentRules.deadlineMs(week: "2026-11-16")!
        XCTAssertEqual(TournamentRules.weeks(untilMs: monday16 - 1), ["2026-11-09", "2026-11-16"])
        XCTAssertEqual(TournamentRules.weeks(untilMs: monday16), ["2026-11-09", "2026-11-16", "2026-11-23"])
    }

    func testNobodyPlayedTheMatch() {
        let later = TournamentRules.everyonePlaysFrom
        let begin = TournamentRules.deadlineMs(week: later)!
        let order = TournamentBracket(week: later, signedUp: players(4), runs: [], nowMs: begin).players
        // Round 1: match 2 played, match 1 not at all -> the first signed up of the two goes through.
        let first = [order[2], order[3]].enumerated().map { TournamentRun(uid: $1.uid, round: 1, startedMs: begin, finishedMs: begin + 30_000 + $0 * 1_000) }
        let after = TournamentBracket(week: later, signedUp: players(4), runs: first, nowMs: begin + day)
        XCTAssertEqual(after.rounds[0][0].winner, [order[0], order[1]].min { $0.atMs < $1.atMs })
        // The final not played either: the best time of the round before (match 2's winner had one).
        let final = TournamentBracket(week: later, signedUp: players(4), runs: first, nowMs: begin + 2 * day)
        XCTAssertEqual(final.rounds[1][0].winner, order[2])
        // Before December (old bracket): nobody goes through.
        XCTAssertNil(TournamentBracket(week: week, signedUp: players(4), runs: [], nowMs: start + day).rounds[0][0].winner)
    }

    func testDrawnLikeAFootballBracketWithReminders() {
        let later = TournamentRules.everyonePlaysFrom
        let begin = TournamentRules.deadlineMs(week: later)!
        let layout = TournamentLayout(TournamentBracket(week: later, signedUp: players(10), runs: [], nowMs: begin), height: { $0 == 3 ? 84 : 60 }, gap: 10)
        XCTAssertEqual(layout.columns, 5)
        XCTAssertEqual(layout.height, 154, accuracy: 0.01)
        XCTAssertEqual(layout.nodes.count, 7)
        XCTAssertEqual(layout.node(round: 1, index: 0)?.y ?? 0, 30, accuracy: 0.01)
        XCTAssertEqual(layout.node(round: 1, index: 1)?.y ?? 0, 112, accuracy: 0.01)
        XCTAssertEqual(layout.node(round: 1, index: 3)?.column, 4)
        XCTAssertEqual(layout.node(round: 2, index: 1)?.y ?? 0, 71, accuracy: 0.01)
        XCTAssertEqual(layout.node(round: 3, index: 0)?.y ?? 0, 77, accuracy: 0.01)
        XCTAssertEqual(layout.node(round: 3, index: 0)?.side, .center)
        XCTAssertEqual(layout.node(round: 3, index: 0)?.column, 2)

        let demo = TournamentDemo.make(me: "me", name: "Camille")
        let bracket = TournamentBracket(week: TournamentDemo.week, signedUp: demo.players, runs: demo.runs, nowMs: demo.nowMs)
        let next = TournamentRules.nextWeek(nowMs: demo.nowMs)
        let plan = TournamentReminders.plan(nextWeek: next, nextMine: true, bracket: bracket, uid: "me", runs: demo.runs, nowMs: demo.nowMs) { _ in "demain" }
        XCTAssertEqual(plan.map(\.id), ["start", "late", "round3"])
        XCTAssertEqual(plan[2].title, "Finale du tournoi")
    }
}
