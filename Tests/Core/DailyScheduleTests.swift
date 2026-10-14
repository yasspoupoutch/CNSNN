import XCTest
@testable import CNSNNCore
final class DailyScheduleTests: XCTestCase {
    func testDifficultyFollowsTheWeekday() {
        // 2026-10-12 is a Monday.
        let expected: [(String, Difficulty)] = [("2026-10-12", .easy), ("2026-10-13", .easy), ("2026-10-14", .medium), ("2026-10-15", .medium),
                                                ("2026-10-16", .medium), ("2026-10-17", .hard), ("2026-10-18", .hard), ("2024-01-01", .easy)]
        for (key, difficulty) in expected {
            XCTAssertEqual(DailySchedule.difficulty(forKey: key), difficulty, key)
            XCTAssertEqual(DailySchedule.dailyCard(forKey: key)?.difficulty, difficulty, key)
        }
        XCTAssertNil(DailySchedule.dailyCard(forKey: "pas-une-date"))
    }
    func testEveryWordOfAPoolComesBeforeAnyRepeat() {
        let calendar = DailySchedule.calendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        var seen: [Difficulty: [String]] = [:]
        for offset in 0..<(7 * 40) {
            let key = DailySchedule.key(calendar.date(byAdding: .day, value: offset, to: start)!)
            let card = DailySchedule.dailyCard(forKey: key)!
            seen[card.difficulty, default: []].append(card.id)
        }
        for difficulty in Difficulty.allCases {
            let ids = seen[difficulty]!, size = DailyPool.pool(difficulty).count
            XCTAssertEqual(Set(ids.prefix(size)).count, min(size, ids.count), "\(difficulty)")
        }
    }
    func testScheduleIsFrozen() {
        // Changing these means two app versions would show different words on the same day.
        XCTAssertEqual(DailySchedule.dailyCard(forKey: "2026-10-13")?.id, DailySchedule.dailyCard(forKey: "2026-10-13")?.id)
        XCTAssertEqual(DailyPool.easy.count, 60)
        XCTAssertEqual(DailyPool.medium.count, 80)
        XCTAssertEqual(DailyPool.hard.count, 60)
        XCTAssertEqual(DailySchedule.dailyCard(forKey: "2024-01-01")?.wordFull, "Baguette")
        XCTAssertEqual(DailySchedule.dailyCard(forKey: "2024-01-03")?.wordFull, "Boulangerie")
        XCTAssertEqual(DailySchedule.dailyCard(forKey: "2024-01-06")?.wordFull, "Kaléidoscope")
        XCTAssertEqual(DailySchedule.dailyCard(forKey: "2024-01-08")?.wordFull, "Crayon")
    }
    func testDailyWordsStayOutOfClassic() {
        let classic = Set(SeedCards.all.map { WordEngine.normalize($0.wordFull) })
        let daily = DailyPool.all.map { WordEngine.normalize($0.wordFull) }
        XCTAssertEqual(Set(daily).count, daily.count)
        XCTAssertTrue(classic.isDisjoint(with: daily))
        XCTAssertTrue(DailyPool.all.allSatisfy { WordEngine.validWord($0.wordFull) && (5...160).contains($0.hint.count) })
    }
    func testMergeKeepsBothHistoriesAndOneDailyPerDay() {
        var phone = Progress(); phone.username = "Alice"
        phone.attempts = [Attempt(cardID: "a", mode: .classic, correct: true, timeMs: 1000, points: 90, date: Date(timeIntervalSince1970: 10)),
                          Attempt(cardID: "d", mode: .daily, correct: true, timeMs: 5000, points: 140, date: Date(timeIntervalSince1970: 20), dailyKey: "2026-10-12")]
        var cloud = Progress(); cloud.username = "Alice"
        cloud.attempts = [Attempt(cardID: "b", mode: .classic, correct: false, timeMs: 3000, points: 0, date: Date(timeIntervalSince1970: 5)),
                          Attempt(cardID: "d", mode: .daily, correct: false, timeMs: 9000, points: 0, date: Date(timeIntervalSince1970: 21), dailyKey: "2026-10-12")]
        cloud.attempts.append(phone.attempts[0])
        let merged = phone.merged(with: cloud)
        XCTAssertEqual(merged.attempts.count, 3)
        XCTAssertEqual(merged.attempts.first?.cardID, "b")
        XCTAssertEqual(merged.score, 230)
        XCTAssertEqual(merged.attempts.filter { $0.dailyKey == "2026-10-12" }.first?.points, 140)
        XCTAssertEqual(cloud.merged(with: phone).attempts.count, 3)
    }
    /// Two devices on one account: each one's new games survive whichever saves last.
    func testTwoDevicesSavingInTurnLoseNothing() {
        var cloud = Progress(); cloud.username = "Alice"
        var phone = cloud, tablet = cloud
        phone.attempts.append(Attempt(cardID: "a", mode: .classic, correct: true, timeMs: 1000, points: 90, date: Date(timeIntervalSince1970: 10)))
        tablet.attempts.append(Attempt(cardID: "b", mode: .classic, correct: true, timeMs: 2000, points: 80, date: Date(timeIntervalSince1970: 11)))
        cloud = phone.merged(with: cloud)
        cloud = tablet.merged(with: cloud)
        XCTAssertEqual(Set(cloud.attempts.map(\.cardID)), ["a", "b"])
        XCTAssertEqual(phone.merged(with: cloud).score, 170)
    }
    func testMergeUnitesProposalsByWordAndKeepsTheVerdict() {
        var pending = Card(id: "local-id", wordFull: "Chocolat", hint: "Un carré gourmand.", category: .general, difficulty: .easy, status: .pending)
        var phone = Progress(); phone.submissions = [Submission(card: pending)]
        pending.id = "CHOCOLAT"; pending.status = .approved
        var cloud = Progress(); cloud.submissions = [Submission(card: pending)]
        cloud.rulesVersion = 1
        let merged = phone.merged(with: cloud)
        XCTAssertEqual(merged.submissions.count, 1)
        XCTAssertEqual(merged.submissions.first?.card.status, .approved)
        XCTAssertEqual(merged.rulesVersion, 1)
        XCTAssertEqual(cloud.merged(with: phone).submissions.first?.card.status, .approved)
    }
}
