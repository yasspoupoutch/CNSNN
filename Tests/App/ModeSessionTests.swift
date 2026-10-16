import XCTest
import CNSNNCore
@testable import CNSNN

/// Sprint, Survie and Double sens as the screens drive them: moves, saving, resuming, quitting and records.
@MainActor final class ModeSessionTests: XCTestCase {
    override func setUp() { ModeRunStore.clearAll() }

    func testSprintScoresQuitsAndRecords() throws {
        let state = AppState(local: MemoryRepository())
        let session = ModeSession(mode: .sprint)
        session.begin(state: state)
        let card = try XCTUnwrap(session.sprint?.card)
        session.answer = card.wordFull
        session.submit(state: state)
        XCTAssertEqual(session.sprint?.found, 1)
        XCTAssertEqual(session.sprint?.streak, 1)
        session.answer = "XQ"; session.submit(state: state)
        XCTAssertEqual(session.sprint?.streak, 0)
        XCTAssertEqual(session.mistakeTick, 1)
        session.skip(state: state)
        XCTAssertEqual(session.sprint?.penaltyMs, SprintGame.skipPenaltyMs)
        XCTAssertNotNil(ModeRunStore.load(.sprint), "A Sprint in play is saved after every move")
        session.quit(state: state)
        XCTAssertTrue(session.over)
        XCTAssertNil(ModeRunStore.load(.sprint))
        let records = state.progress.records(.sprint)
        XCTAssertEqual(records.best(ModeStat.words), 1)
        XCTAssertEqual(records.total(ModeStat.games), 1)
        XCTAssertTrue(session.beaten.contains(ModeStat.words))
        XCTAssertFalse(session.improved(ModeStat.words), "The first game sets the record without a celebration")
        // Records stay out of the official numbers.
        XCTAssertTrue(state.progress.attempts.isEmpty)
        XCTAssertEqual(state.progress.level, 1)
    }

    func testSprintClosedDuringPlayCountsAtNextLaunch() {
        let state = AppState(local: MemoryRepository())
        let session = ModeSession(mode: .sprint)
        session.begin(state: state)
        let card = session.sprint!.card!
        session.answer = card.wordFull; session.submit(state: state)
        // The app is killed here: nothing recorded yet, the game is saved.
        XCTAssertEqual(state.progress.records(.sprint).total(ModeStat.games), 0)
        let next = AppState(local: MemoryRepository())
        next.finishInterruptedSprint()
        XCTAssertEqual(next.progress.records(.sprint).total(ModeStat.games), 1)
        XCTAssertEqual(next.progress.records(.sprint).best(ModeStat.words), 1)
        XCTAssertNil(ModeRunStore.load(.sprint))
    }

    func testSurvivalLosesLivesEndsAndResumes() throws {
        let state = AppState(local: MemoryRepository())
        let session = ModeSession(mode: .survival)
        session.begin(state: state)
        session.answer = try XCTUnwrap(session.survival?.card?.wordFull)
        session.submit(state: state)
        XCTAssertEqual(session.survival?.found, 1)
        // Reopened: the same run picks up.
        let reopened = ModeSession(mode: .survival)
        reopened.begin(state: state)
        XCTAssertTrue(reopened.resumed)
        XCTAssertEqual(reopened.survival?.found, 1)
        reopened.answer = "XQ"; reopened.submit(state: state)
        XCTAssertEqual(reopened.survival?.lives, 2)
        XCTAssertEqual(reopened.lifeLostTick, 1)
        reopened.skip(state: state); reopened.skip(state: state)
        XCTAssertEqual(reopened.survival?.lives, 0)
        XCTAssertTrue(reopened.over)
        XCTAssertNil(ModeRunStore.load(.survival))
        let records = state.progress.records(.survival)
        XCTAssertEqual(records.best(ModeStat.words), 1)
        XCTAssertEqual(records.best(ModeStat.level), 1)
        XCTAssertEqual(records.total(ModeStat.games), 1)
        // Replay starts a fresh run.
        reopened.begin(state: state)
        XCTAssertFalse(reopened.resumed)
        XCTAssertEqual(reopened.survival?.lives, SurvivalGame.maxLives)
    }

    func testSurvivalAbandonCountsTheRun() {
        let state = AppState(local: MemoryRepository())
        let session = ModeSession(mode: .survival)
        session.begin(state: state)
        session.quit(state: state)
        XCTAssertTrue(session.over)
        XCTAssertEqual(state.progress.records(.survival).total(ModeStat.games), 1)
    }

    func testDuoRoundsShowWordsThenResults() throws {
        let state = AppState(local: MemoryRepository())
        let session = ModeSession(mode: .duo)
        session.begin(state: state)
        let duo = try XCTUnwrap(session.duo?.duo)
        session.answer = duo.second.word; session.submit(state: state)
        session.answer = duo.second.word; session.submit(state: state)
        XCTAssertEqual(session.duo?.errors, 0, "A word given twice is not an error")
        session.answer = "XQ"; session.submit(state: state)
        XCTAssertEqual(session.duo?.errors, 1)
        session.answer = duo.first.word; session.submit(state: state)
        XCTAssertEqual(session.duo?.roundComplete, true)
        session.nextRound(state: state)
        XCTAssertEqual(session.duo?.round, 1)
        for _ in 1..<DuoGame.rounds {
            session.skip(state: state)
            if session.duo?.finished == true { break }
            session.nextRound(state: state)
        }
        // The last round's words show first; the results follow.
        XCTAssertEqual(session.duo?.finished, true)
        XCTAssertFalse(session.over)
        session.nextRound(state: state)
        XCTAssertTrue(session.over)
        let records = state.progress.records(.duo)
        XCTAssertEqual(records.total(ModeStat.games), 1)
        XCTAssertEqual(records.total(ModeStat.duosSolved), 1)
        XCTAssertEqual(records.total(ModeStat.duosPlayed), DuoGame.rounds)
        XCTAssertEqual(records.total(ModeStat.perfect), 0)
        XCTAssertEqual(DuoRecord.solved(records.best(ModeStat.duo)), 1)
    }

    func testRecordsFromTwoDevicesMergeWithoutLoss() {
        var phone = CNSNNCore.Progress(), tablet = CNSNNCore.Progress()
        phone.recordMode(.sprint, best: [ModeStat.words: 12], add: [ModeStat.games: 1], device: "phone")
        phone.recordMode(.sprint, best: [ModeStat.words: 8], add: [ModeStat.games: 1], device: "phone")
        tablet.recordMode(.sprint, best: [ModeStat.words: 15], add: [ModeStat.games: 1], device: "tablet")
        let merged = phone.merged(with: tablet)
        XCTAssertEqual(merged.records(.sprint).best(ModeStat.words), 15)
        XCTAssertEqual(merged.records(.sprint).total(ModeStat.games), 3)
        // Merging again (the cloud copy coming back) adds nothing.
        XCTAssertEqual(merged.merged(with: tablet).merged(with: phone).modes, merged.modes)
    }
}
