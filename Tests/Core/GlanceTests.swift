import XCTest
@testable import CNSNNCore
final class GlanceTests: XCTestCase {
    private func date(_ key: String, hour: Int = 12) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        return DailySchedule.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour))!
    }

    func testSummarisesTheLatestDailyAndTheStreak() {
        var progress = CNSNNCore.Progress()
        progress.attempts = [
            Attempt(cardID: "a", mode: .daily, correct: true, timeMs: 8000, points: 90, date: date("2026-10-12"), dailyKey: "2026-10-12"),
            Attempt(cardID: "b", mode: .daily, correct: true, timeMs: 4200, points: 95, date: date("2026-10-13"), dailyKey: "2026-10-13"),
            Attempt(cardID: "c", mode: .classic, correct: false, timeMs: 1000, points: 0, date: date("2026-10-13")),
        ]
        let glance = Glance(progress: progress, streak: progress.streak(at: date("2026-10-13")))
        XCTAssertEqual(glance.lastDailyKey, "2026-10-13")
        XCTAssertEqual(glance.lastDailyTimeMs, 4200)
        XCTAssertTrue(glance.playedToday(date("2026-10-13")))
        XCTAssertFalse(glance.playedToday(date("2026-10-14")))
        XCTAssertEqual(glance.currentStreak(date("2026-10-14")), 2)
        XCTAssertEqual(glance.currentStreak(date("2026-10-15")), 0)
    }

    func testNextDayIsLocalMidnight() {
        let next = Glance.nextDay(after: date("2026-10-13", hour: 23))
        XCTAssertEqual(DailySchedule.key(next), "2026-10-14")
        XCTAssertEqual(DailySchedule.calendar.component(.hour, from: next), 0)
        XCTAssertLessThanOrEqual(next.timeIntervalSince(date("2026-10-13", hour: 23)), 3600)
    }
}
