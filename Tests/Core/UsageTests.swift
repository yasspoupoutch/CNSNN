import XCTest
@testable import CNSNNCore
final class UsageTests: XCTestCase {
    func testANewPhoneCountsOnceADay() {
        var tally = UsageTally()
        tally.open(day: "2026-10-25", platform: "Ios", returning: false)
        tally.open(day: "2026-10-25", platform: "Ios", returning: false)
        XCTAssertEqual(tally.pending["2026-10-25"], ["newIos": 1, "opensIos": 1])
        tally.play("classic", day: "2026-10-25")
        tally.play("classic", day: "2026-10-25")
        tally.play("daily", day: "2026-10-25")
        XCTAssertEqual(tally.pending["2026-10-25"], ["newIos": 1, "opensIos": 1, "players": 1, "newPlayers": 1, "classic": 2, "daily": 1])
        tally.open(day: "2026-10-26", platform: "Ios", returning: true)
        tally.play("sprint", day: "2026-10-26")
        XCTAssertEqual(tally.pending["2026-10-26"], ["opensIos": 1, "players": 1, "sprint": 1])
    }

    func testAPlayerUpdatingTheAppIsNotNew() {
        var tally = UsageTally()
        tally.open(day: "2026-10-25", platform: "Ios", returning: true)
        tally.play("duo", day: "2026-10-25")
        XCTAssertEqual(tally.pending["2026-10-25"], ["opensIos": 1, "players": 1, "duo": 1])
    }

    func testUnknownModesAreIgnored() {
        var tally = UsageTally()
        tally.play("players", day: "2026-10-25")
        tally.play("other", day: "2026-10-25")
        XCTAssertTrue(tally.pending.isEmpty)
    }

    func testTakeSendsOnlyOpeningsWithoutAccountAndDropsOldDays() {
        var tally = UsageTally()
        tally.open(day: "2026-10-20", platform: "Android", returning: false)
        tally.open(day: "2026-10-25", platform: "Android", returning: false)
        tally.play("survival", day: "2026-10-25")
        let guest = tally.take(oldest: "2026-10-23", signedIn: false)
        XCTAssertEqual(guest, ["2026-10-25": ["opensAndroid": 1]])
        XCTAssertEqual(tally.pending, ["2026-10-25": ["players": 1, "newPlayers": 1, "survival": 1]])
        let player = tally.take(oldest: "2026-10-23", signedIn: true)
        XCTAssertEqual(player, ["2026-10-25": ["players": 1, "newPlayers": 1, "survival": 1]])
        XCTAssertTrue(tally.pending.isEmpty)
        XCTAssertTrue(tally.take(oldest: "2026-10-23", signedIn: true).isEmpty)
    }
}
