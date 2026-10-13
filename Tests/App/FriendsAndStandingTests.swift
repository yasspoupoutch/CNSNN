import XCTest
import CNSNNCore
@testable import CNSNN
final class FriendsAndStandingTests: XCTestCase {
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
        func row(_ uid: String, points: Int, today: (Bool, Int)?) -> FriendStanding {
            FriendStanding(uid: uid, username: uid, points: points, streak: 0,
                           today: today.map { Attempt(cardID: "x", mode: .daily, correct: $0.0, timeMs: $0.1, points: 0, date: Date(), dailyKey: "d") })
        }
        let ordered = FriendStanding.ordered([row("slow", points: 900, today: (true, 9000)), row("idle", points: 5000, today: nil),
                                              row("fast", points: 10, today: (true, 3000)), row("miss", points: 100, today: (false, 2000))])
        XCTAssertEqual(ordered.map(\.uid), ["fast", "slow", "idle", "miss"])
    }
}
