import XCTest
import CNSNNCore
@testable import CNSNN
final class RepositoryTests: XCTestCase {
    func testAtomicRoundTripAndAccountIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let alice = LocalRepository(scope: "alice", directoryOverride: directory)
        let bob = LocalRepository(scope: "bob", directoryOverride: directory)
        var progress = Progress(); progress.username = "Alice"
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
}
