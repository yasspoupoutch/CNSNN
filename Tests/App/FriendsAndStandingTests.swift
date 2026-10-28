import XCTest
import CNSNNCore
@testable import CNSNN
final class FriendsAndStandingTests: XCTestCase {
    /// The free Firestore quota starts again at midnight in California, whatever the phone's time zone.
    func testServerFullUntilCaliforniaMidnight() throws {
        let iso = ISO8601DateFormatter()
        // 23:30 in Paris on 27 October 2026 (22:30 UTC): California is still on summer time (UTC-7).
        let reset = CloudError.quotaReset(after: try XCTUnwrap(iso.date(from: "2026-10-27T22:30:00Z")))
        XCTAssertEqual(reset, iso.date(from: "2026-10-28T07:00:00Z"))
        // After the US clock change: midnight is 08:00 UTC, 9 h in Paris.
        XCTAssertEqual(CloudError.quotaReset(after: try XCTUnwrap(iso.date(from: "2026-11-10T12:00:00Z"))), iso.date(from: "2026-11-11T08:00:00Z"))
        XCTAssertEqual(CloudError.code(CloudError.serverFull), .serverFull)
        XCTAssertEqual(CloudError.code(NSError(domain: "FIRFirestoreErrorDomain", code: 8)), .serverFull)
        XCTAssertTrue(CloudError.message(NSError(domain: "FIRFirestoreErrorDomain", code: 8)).hasPrefix("Beaucoup de joueurs aujourd’hui"))
    }
    func testTopPercentBadges() {
        func top(_ rank: Int, of players: Int) -> Int? { DailyStanding(rank: rank, players: players, beatenPercent: nil).topPercent }
        XCTAssertNil(top(1, of: 200))      // Shown as "numéro 1".
        XCTAssertEqual(top(2, of: 200), 1)
        XCTAssertEqual(top(10, of: 200), 5)
        XCTAssertEqual(top(20, of: 200), 10)
        XCTAssertEqual(top(50, of: 200), 25)
        XCTAssertEqual(top(100, of: 200), 50)
        XCTAssertNil(top(101, of: 200))    // Slower half: rank only.
        XCTAssertEqual(top(2, of: 4), 50)
    }

    func testFriendCodesIgnoreConfusingCharacters() {
        XCTAssertEqual(FirebaseRepository.normalizedFriendCode(" ab-c2 z9x "), "ABC2Z9")
        XCTAssertEqual(FirebaseRepository.normalizedFriendCode("o0i1l"), "L")
    }

    func testFriendsFoundTodayComeFirstByTime() {
        // The week: words found, then time.
        func row(_ uid: String, week: (Int, Int)?, today: (Bool, Int)?, hint: Bool = false) -> FriendStanding {
            FriendStanding(uid: uid, username: uid, week: week.map { DailyScore.Week(week: 1, found: $0.0, timeMs: $0.1, played: $0.0) }, streak: 0,
                           today: today.map { Attempt(cardID: "x", mode: .daily, correct: $0.0, timeMs: $0.1, points: 0, date: Date(), dailyKey: "d") },
                           todayHint: hint)
        }
        // "hint" found fastest but the hint minute puts them after "slow"; the others by the week.
        let ordered = FriendStanding.ordered([row("slow", week: (2, 90_000), today: (true, 9000)), row("idle", week: (3, 600_000), today: nil),
                                              row("fast", week: (1, 900_000), today: (true, 3000)), row("miss", week: (2, 50_000), today: (false, 2000)),
                                              row("hint", week: (2, 10_000), today: (true, 1000), hint: true), row("new", week: nil, today: nil)])
        XCTAssertEqual(ordered.map(\.uid), ["fast", "slow", "hint", "idle", "miss", "new"])
    }

    func testMistakesLine() {
        XCTAssertEqual(Mistakes.text(0), "sans faute")
        XCTAssertEqual(Mistakes.text(1), "1 erreur")
        XCTAssertEqual(Mistakes.text(3), "3 erreurs")
    }
}
