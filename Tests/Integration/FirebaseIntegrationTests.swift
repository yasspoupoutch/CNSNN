import XCTest
import CNSNNCore
@testable import CNSNN

/// End-to-end checks of FirebaseRepository against the Auth and Firestore emulators, which enforce
/// the real Firebase/firestore.rules. Run by the iOS workflow with TEST_RUNNER_CNSNN_EMULATOR=1.
@MainActor final class FirebaseIntegrationTests: XCTestCase {
    private let project = "demo-cnsnn"
    private var repo: FirebaseRepository!

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["CNSNN_EMULATOR"] == "1" else { throw XCTSkip("Émulateurs Firebase non lancés.") }
        FirebaseRepository.configureForEmulator(projectID: project)
        repo = FirebaseRepository()
        try? repo.signOut()
        try await emulator("DELETE", "http://127.0.0.1:8080/emulator/v1/projects/\(project)/databases/(default)/documents")
        try await emulator("DELETE", "http://127.0.0.1:9099/emulator/v1/projects/\(project)/accounts")
    }

    func testOfficialDailyFlowMatchesTheRules() async throws {
        let alice = try await repo.bootstrap(username: "Alice")
        XCTAssertTrue(alice.anonymous)
        let day = DailySchedule.key()
        let card = try XCTUnwrap(DailySchedule.dailyCard(forKey: day))
        let session = try await repo.startDaily(uid: alice.uid, day: day, cardID: card.id)
        XCTAssertFalse(session.finished)
        // A second start would reset the clock: the rules refuse it.
        await assertThrows { _ = try await self.repo.startDaily(uid: alice.uid, day: day, cardID: card.id) }
        repo.revealDailyHint(uid: alice.uid, day: day)
        try await Task.sleep(for: .milliseconds(1200))
        let confirmed = try await repo.finishDaily(uid: alice.uid, day: day, correct: true, wrongAnswers: 2)
        XCTAssertTrue(confirmed)
        let official = try await XCTUnwrapAsync(try await repo.publishDailyResult(uid: alice.uid, day: day))
        XCTAssertGreaterThanOrEqual(official.timeMs, 1000)
        XCTAssertEqual(official.points, Scoring.points(difficulty: card.difficulty, timeMs: official.timeMs, usedHint: true, correct: true))
        // Publishing again returns the same result and does not count twice.
        let again = try await XCTUnwrapAsync(try await repo.publishDailyResult(uid: alice.uid, day: day))
        XCTAssertEqual(again.timeMs, official.timeMs)
        let entry = try await XCTUnwrapAsync(try await repo.leaderboardEntry(uid: alice.uid, source: .server))
        XCTAssertEqual(entry.points, official.points)
        XCTAssertEqual(entry.played, 1)
        XCTAssertEqual(entry.streak, 1)
        XCTAssertEqual(entry.bestTimeMs, official.timeMs)
        let alone = try await repo.standing(day: day, timeMs: official.timeMs, correct: true)
        XCTAssertEqual(alone.players, 1)
        XCTAssertEqual(alone.rank, 1)
        XCTAssertNil(alone.beatenPercent)

        // A slower second player: real rank and percentile for both.
        try repo.signOut()
        let bob = try await repo.bootstrap(username: "Bob")
        _ = try await repo.startDaily(uid: bob.uid, day: day, cardID: card.id)
        try await Task.sleep(for: .milliseconds(Double(official.timeMs) + 800))
        _ = try await repo.finishDaily(uid: bob.uid, day: day, correct: true, wrongAnswers: 0)
        let bobResult = try await XCTUnwrapAsync(try await repo.publishDailyResult(uid: bob.uid, day: day))
        XCTAssertGreaterThan(bobResult.timeMs, official.timeMs)
        let bobStanding = try await repo.standing(day: day, timeMs: bobResult.timeMs, correct: true)
        XCTAssertEqual(bobStanding.rank, 2)
        XCTAssertEqual(bobStanding.beatenPercent, 0)
        let aliceStanding = try await repo.standing(day: day, timeMs: official.timeMs, correct: true)
        XCTAssertEqual(aliceStanding.rank, 1)
        XCTAssertEqual(aliceStanding.beatenPercent, 100)
        let ranking = try await repo.dailyRanking(day: day)
        XCTAssertEqual(ranking.map(\.username), ["Alice", "Bob"])
        let top = try await repo.topPlayers()
        XCTAssertEqual(top.count, 2)
        let fastest = try await repo.fastestPlayers()
        XCTAssertEqual(fastest.first?.username, "Alice")
        let rank = try await repo.rank(points: bobResult.points)
        XCTAssertEqual(rank.players, 2)
    }

    func testProgressSyncRenameAndDeletion() async throws {
        let player = try await repo.bootstrap(username: "Camille")
        var progress = CNSNNCore.Progress(); progress.username = "Camille"
        progress.attempts = [Attempt(cardID: "seed-001", mode: .classic, correct: true, timeMs: 3000, points: 97, date: Date())]
        try repo.saveCloudProgress(progress, uid: player.uid)
        try await Task.sleep(for: .milliseconds(800))
        let restored = try await XCTUnwrapAsync(try await repo.cloudProgress(uid: player.uid))
        XCTAssertEqual(restored.score, 97)
        XCTAssertEqual(restored.attempts.first?.id, progress.attempts.first?.id)

        // Rename reaches the leaderboard line once it exists.
        let day = DailySchedule.key()
        _ = try await repo.startDaily(uid: player.uid, day: day, cardID: "x")
        _ = try await repo.finishDaily(uid: player.uid, day: day, correct: false, wrongAnswers: 3)
        let lost = try await XCTUnwrapAsync(try await repo.publishDailyResult(uid: player.uid, day: day))
        XCTAssertEqual(lost.points, 0)
        try await repo.rename(uid: player.uid, username: "Camilla")
        let renamed = try await repo.leaderboardEntry(uid: player.uid, source: .server)
        XCTAssertEqual(renamed?.username, "Camilla")
        XCTAssertEqual(renamed?.streak, 0)

        // Deletion leaves nothing behind.
        _ = try await repo.submit(card: Card(id: "local", wordFull: "Montgolfière", hint: "Un ballon à air chaud.", category: .objects, difficulty: .hard, status: .pending), uid: player.uid)
        try await repo.deleteAccount(uid: player.uid, password: nil)
        XCTAssertFalse(repo.hasCurrentUser)
        let other = try await repo.bootstrap(username: "Témoin")
        XCTAssertNotEqual(other.uid, player.uid)
        let gone = try await repo.leaderboardEntry(uid: player.uid, source: .server)
        XCTAssertNil(gone)
        let result = try await repo.dailyResult(uid: player.uid, day: day)
        XCTAssertNil(result)
        // The deleted author's pending word is free again.
        _ = try await repo.submit(card: Card(id: "local", wordFull: "Montgolfière", hint: "Il vole grâce à l’air chaud.", category: .objects, difficulty: .hard, status: .pending), uid: other.uid)
    }

    func testProposalsDuplicatesQuotaAndModeration() async throws {
        let author = try await repo.bootstrap(username: "Auteur")
        let proposal = Card(id: "local", wordFull: "Pâte à crêpes", hint: "On la laisse reposer avant la poêle.", category: .general, difficulty: .medium, status: .pending)
        let stored = try await repo.submit(card: proposal, uid: author.uid)
        XCTAssertEqual(stored.id, "PATEACREPES")
        await assertThrows(CloudError.duplicateWord) { _ = try await self.repo.submit(card: proposal, uid: author.uid) }
        await assertThrows(CloudError.proposalTooSoon) {
            _ = try await self.repo.submit(card: Card(id: "x", wordFull: "Galette", hint: "On la mange à l’Épiphanie.", category: .general, difficulty: .easy), uid: author.uid)
        }
        let mine = try await repo.submissions(uid: author.uid)
        XCTAssertEqual(mine.map(\.card.status), [.pending])
        let notAdmin = try await repo.isAdmin()
        XCTAssertFalse(notAdmin)
        await assertThrows { _ = try await self.repo.pendingCards() }

        // Another player cannot see or take the word.
        try repo.signOut()
        let rival = try await repo.bootstrap(username: "Rival")
        await assertThrows(CloudError.duplicateWord) { _ = try await self.repo.submit(card: proposal, uid: rival.uid) }

        // A moderator (admins/{uid} created like from the console) approves it with a corrected hint.
        try await emulator("PATCH", "http://127.0.0.1:8080/v1/projects/\(project)/databases/(default)/documents/admins/\(rival.uid)", body: #"{"fields":{}}"#)
        let admin = try await repo.isAdmin()
        XCTAssertTrue(admin)
        var pending = try await XCTUnwrapAsync(try await repo.pendingCards().first)
        pending.hint = "Elle repose avant de finir dans la poêle."
        try await repo.review(card: pending, approved: true)
        let catalogue = try await repo.cards()
        XCTAssertEqual(catalogue.first { $0.id == "PATEACREPES" }?.hint, "Elle repose avant de finir dans la poêle.")

        // Reports: one per player and card, then resolved by the moderator.
        try repo.signOut()
        _ = try await repo.bootstrap(username: "Lecteur")
        try await repo.report(cardID: "PATEACREPES", reason: "L’indice est trop facile.")
        await assertThrows(CloudError.alreadyReported) { try await self.repo.report(cardID: "PATEACREPES", reason: "Encore une fois.") }
    }

    // MARK: Helpers

    private func emulator(_ method: String, _ url: String, body: String? = nil) async throws {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        // "owner" bypasses the security rules on the Firestore emulator only.
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = Data(body.utf8); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        XCTAssertTrue((200..<300).contains(status), "\(method) \(url) → \(status)")
    }
    private func assertThrows(_ expected: CloudError? = nil, file: StaticString = #filePath, line: UInt = #line, _ work: () async throws -> Void) async {
        do {
            try await work()
            XCTFail("Une erreur était attendue.", file: file, line: line)
        } catch {
            if let expected { XCTAssertEqual((error as? CloudError).map { "\($0)" }, "\(expected)", file: file, line: line) }
        }
    }
    private func XCTUnwrapAsync<T>(_ value: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
        try XCTUnwrap(try await value(), file: file, line: line)
    }
}
