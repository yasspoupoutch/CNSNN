import XCTest
import CNSNNCore
@testable import CNSNN
final class RepositoryTests: XCTestCase {
    func testAtomicRoundTripAndAccountIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let alice = LocalRepository(scope: "alice", directoryOverride: directory)
        let bob = LocalRepository(scope: "bob", directoryOverride: directory)
        var progress = CNSNNCore.Progress(); progress.username = "Alice"
        progress.attempts.append(Attempt(cardID: "card", mode: .classic, correct: true, timeMs: 1234, points: 90, date: Date()))
        try alice.save(progress)
        XCTAssertEqual(try alice.load().score, 90)
        XCTAssertEqual(try alice.load().username, "Alice")
        XCTAssertTrue(try bob.load().attempts.isEmpty)
        XCTAssertTrue(try bob.load().username.isEmpty)
    }
    func testCorruptSaveIsNotSilentlyReset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("corrupt".utf8)
        let file = directory.appendingPathComponent("cnsnn-progress-v1-guest.json")
        try bytes.write(to: file)
        XCTAssertThrowsError(try LocalRepository(directoryOverride: directory).load())
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    @MainActor func testDailyCannotCreditTwice() throws {
        let state = AppState(local: MemoryRepository())
        let key = DailySchedule.key()
        let result = Attempt(cardID: "card", mode: .daily, correct: true, timeMs: 5000, points: 95, date: Date(), dailyKey: key)
        state.record(result); state.record(result)
        XCTAssertEqual(state.progress.attempts.count, 1)
        XCTAssertEqual(state.progress.score, 95)
    }
    @MainActor func testDailySessionResumesExistingResult() {
        let state = AppState(local: MemoryRepository())
        let session = GameSession()
        session.load(mode: .daily, category: nil, difficulty: nil, state: state)
        session.answer = session.card!.wordFull
        session.submit(mode: .daily, state: state)
        let original = session.result!.id
        let next = GameSession()
        next.load(mode: .daily, category: nil, difficulty: nil, state: state)
        XCTAssertEqual(next.result?.id, original)
        XCTAssertEqual(state.progress.attempts.count, 1)
    }
    @MainActor func testOfficialResultReplacesTheLocalMeasurement() {
        let state = AppState(local: MemoryRepository())
        let key = DailySchedule.key()
        state.record(Attempt(cardID: "daily-e-001", mode: .daily, correct: true, timeMs: 4000, points: 96, date: Date(), dailyKey: key))
        let localID = state.progress.attempts[0].id
        state.recordOfficial(Attempt(cardID: "daily-e-001", mode: .daily, correct: true, timeMs: 4300, points: 96, date: Date(), dailyKey: key))
        XCTAssertEqual(state.progress.attempts.count, 1)
        XCTAssertEqual(state.progress.attempts[0].timeMs, 4300)
        XCTAssertEqual(state.progress.attempts[0].id, localID)
    }
    @MainActor func testLeaderboardTallyMatchesTheRules() {
        let first = FirebaseRepository.tally(old: nil, uid: "a", username: "Alice", day: "2026-10-12", correct: true, timeMs: 4000, points: 96)
        XCTAssertEqual(first["points"] as? Int, 96)
        XCTAssertEqual(first["streak"] as? Int, 1)
        XCTAssertEqual(first["bestTimeMs"] as? Int, 4000)
        XCTAssertEqual(first["lastWinDay"] as? String, "2026-10-12")
        let old = LeaderboardEntry(uid: "a", username: "Alice", points: 96, played: 1, wins: 1, streak: 1, bestStreak: 1, bestTimeMs: 4000, lastWinDay: "2026-10-12")
        let next = FirebaseRepository.tally(old: old, uid: "a", username: "Alice", day: "2026-10-13", correct: true, timeMs: 9000, points: 91)
        XCTAssertEqual(next["streak"] as? Int, 2)
        XCTAssertEqual(next["bestStreak"] as? Int, 2)
        XCTAssertEqual(next["bestTimeMs"] as? Int, 4000)
        XCTAssertEqual(next["points"] as? Int, 187)
        let gap = FirebaseRepository.tally(old: old, uid: "a", username: "Alice", day: "2026-10-15", correct: true, timeMs: 9000, points: 91)
        XCTAssertEqual(gap["streak"] as? Int, 1)
        let lost = FirebaseRepository.tally(old: old, uid: "a", username: "Alice", day: "2026-10-13", correct: false, timeMs: 9000, points: 0)
        XCTAssertEqual(lost["streak"] as? Int, 0)
        XCTAssertEqual(lost["bestStreak"] as? Int, 1)
        XCTAssertEqual(lost["wins"] as? Int, 1)
        XCTAssertEqual(lost["played"] as? Int, 2)
    }
    func testLeaderboardStreakExpires() {
        let calendar = DailySchedule.calendar
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        let entry = LeaderboardEntry(uid: "a", username: "A", points: 0, played: 3, wins: 3, streak: 3, bestStreak: 3, bestTimeMs: nil, lastWinDay: "2026-10-11")
        XCTAssertEqual(entry.currentStreak(at: monday), 3)
        XCTAssertEqual(entry.currentStreak(at: calendar.date(byAdding: .day, value: 1, to: monday)!), 0)
    }
}
