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

    func testOnlyTheFirst64() {
        let bracket = TournamentBracket(week: week, signedUp: players(70), runs: [], nowMs: start)
        XCTAssertEqual(bracket.players.count, 64)
        XCTAssertFalse(bracket.players.contains { ["p65", "p66", "p70"].contains($0.uid) })
        XCTAssertEqual(TournamentFormat.roundName(6, of: 6), "Finale")
        XCTAssertEqual(TournamentFormat.roundName(1, of: 6), "Tour 1")
    }
}
