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
        // A win needs at least 2 s of play.
        try await Task.sleep(for: .milliseconds(2200))
        try await seedSecret(day: day, card: card)
        let guesses = try await repo.registerGuess(uid: alice.uid, day: day, guess: WordEngine.normalize(card.wordFull))
        XCTAssertEqual(guesses, 1)
        let confirmed = try await repo.finishDaily(uid: alice.uid, day: day, correct: true, wrongAnswers: 0, answer: WordEngine.normalize(card.wordFull))
        XCTAssertTrue(confirmed)
        let official = try await XCTUnwrapAsync(try await repo.publishDailyResult(uid: alice.uid, day: day))
        XCTAssertGreaterThanOrEqual(official.timeMs, 2000)
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
        _ = try await repo.registerGuess(uid: bob.uid, day: day, guess: WordEngine.normalize(card.wordFull))
        _ = try await repo.finishDaily(uid: bob.uid, day: day, correct: true, wrongAnswers: 0, answer: WordEngine.normalize(card.wordFull))
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

    func testSecretDailyWordIsCheckedByTheServer() async throws {
        let day = DailySchedule.key()
        let docs = "http://127.0.0.1:8080/v1/projects/\(project)/databases/(default)/documents"
        try await emulator("PATCH", "\(docs)/dailyPuzzles/\(day)", body: #"{"fields":{"consonants":{"stringValue":"CHCLT"},"category":{"stringValue":"Général"},"difficulty":{"stringValue":"Facile"}}}"#)
        try await emulator("PATCH", "\(docs)/dailyHints/\(day)", body: #"{"fields":{"hint":{"stringValue":"Un carré gourmand."}}}"#)
        try await emulator("PATCH", "\(docs)/dailySecrets/\(day)", body: #"{"fields":{"answer":{"stringValue":"CHOCOLAT"},"word":{"stringValue":"Chocolat"},"hint":{"stringValue":"Un carré gourmand."},"category":{"stringValue":"Général"},"difficulty":{"stringValue":"Facile"}}}"#)
        let alice = try await repo.bootstrap(username: "Alice")
        let puzzle = try await XCTUnwrapAsync(try await repo.dailyPuzzle(day: day))
        XCTAssertEqual(puzzle.wordNoVowels, "CHCLT")
        XCTAssertTrue(puzzle.wordFull.isEmpty)
        // Before playing, neither the hint nor the word can be read.
        await assertThrows { _ = try await self.repo.dailySecret(day: day) }
        await assertThrows { _ = try await self.repo.dailyHint(day: day) }
        _ = try await repo.startDaily(uid: alice.uid, day: day, cardID: puzzle.id)
        let hint = try await repo.revealSecretHint(uid: alice.uid, day: day)
        XCTAssertEqual(hint, "Un carré gourmand.")
        await assertThrows { _ = try await self.repo.dailySecret(day: day) }
        // Every guess is counted first: a wrong one is refused and counts as an error, the right one finishes the game.
        try await Task.sleep(for: .milliseconds(2200))
        let first = try await repo.registerGuess(uid: alice.uid, day: day, guess: "CHOCOLATS")
        XCTAssertEqual(first, 1)
        await assertThrows(nil) { _ = try await self.repo.finishDaily(uid: alice.uid, day: day, correct: true, wrongAnswers: 0, answer: "CHOCOLATS") }
        // One guess per second at most.
        await assertThrows(nil) { _ = try await self.repo.registerGuess(uid: alice.uid, day: day, guess: "CHOCOLAT") }
        try await Task.sleep(for: .milliseconds(1200))
        let second = try await repo.registerGuess(uid: alice.uid, day: day, guess: WordEngine.normalize("chocolat"))
        XCTAssertEqual(second, 2)
        let resumed = try await XCTUnwrapAsync(try await repo.dailySession(uid: alice.uid, day: day))
        XCTAssertEqual(resumed.guesses, 2)
        let accepted = try await repo.finishDaily(uid: alice.uid, day: day, correct: true, wrongAnswers: 1, answer: WordEngine.normalize("chocolat"))
        XCTAssertTrue(accepted)
        let secret = try await XCTUnwrapAsync(try await repo.dailySecret(day: day))
        XCTAssertEqual(secret.wordFull, "Chocolat")
        let official = try await XCTUnwrapAsync(try await repo.publishDailyResult(uid: alice.uid, day: day))
        XCTAssertTrue(official.correct)
        XCTAssertEqual(official.cardID, FirebaseRepository.secretCardID(day: day))
    }

    func testFriendsCodeAndBoard() async throws {
        let alice = try await repo.bootstrap(username: "Alice")
        let code = try await repo.friendCode(uid: alice.uid, username: "Alice")
        XCTAssertEqual(code.count, 6)
        let same = try await repo.friendCode(uid: alice.uid, username: "Alice")
        XCTAssertEqual(same, code)
        await assertThrows(CloudError.friendIsYou) { _ = try await self.repo.addFriend(code: code, uid: alice.uid) }
        // Alice finds today's word.
        let day = DailySchedule.key()
        let card = try XCTUnwrap(DailySchedule.dailyCard(forKey: day))
        try await win(uid: alice.uid, day: day, card: card)

        try repo.signOut()
        let bob = try await repo.bootstrap(username: "Bob")
        await assertThrows(CloudError.friendNotFound) { _ = try await self.repo.addFriend(code: "ZZZZZZ", uid: bob.uid) }
        let name = try await repo.addFriend(code: code.lowercased(), uid: bob.uid)
        XCTAssertEqual(name, "Alice")
        let board = try await repo.friendsBoard(uid: bob.uid, username: "Bob", day: day)
        XCTAssertEqual(board.map(\.username), ["Alice", "Bob"])
        XCTAssertEqual(board.first?.today?.correct, true)
        XCTAssertNil(board.last?.today)
        try await repo.removeFriend(uid: bob.uid, friend: alice.uid)
        let alone = try await repo.friendsBoard(uid: bob.uid, username: "Bob", day: day)
        XCTAssertEqual(alone.map(\.uid), [bob.uid])
    }

    /// A friend challenge from end to end: sent to a friend only, both clocks kept by the server,
    /// the same winner on both sides, and gone with either account.
    func testFriendChallengeFlow() async throws {
        let alice = try await repo.bootstrap(username: "Alice")
        _ = try await repo.createPermanentAccount(email: "alice@cnsnn.test", password: "motdepasse1")
        let aliceCode = try await repo.friendCode(uid: alice.uid, username: "Alice")
        try repo.signOut()
        let bob = try await repo.bootstrap(username: "Bob")
        _ = try await repo.createPermanentAccount(email: "bob@cnsnn.test", password: "motdepasse2")
        let ids = ChallengeRules.draw(seed: 42)
        // Only a friend can be challenged.
        await assertThrows { _ = try await self.repo.createChallenge(uid: bob.uid, username: "Bob", friend: alice.uid, friendName: "Alice", cardIDs: ids) }
        _ = try await repo.addFriend(code: aliceCode, uid: bob.uid)
        let challenge = try await repo.createChallenge(uid: bob.uid, username: "Bob", friend: alice.uid, friendName: "Alice", cardIDs: ids)
        XCTAssertEqual(challenge.cardIds, ids)
        XCTAssertNotNil(challenge.from.startedMs)
        XCTAssertNil(challenge.to.startedMs)
        // Too fast for 5 words: refused. Bob skips all 5 (+100 s).
        await assertThrows { _ = try await self.repo.finishChallenge(challenge, uid: bob.uid, skips: 0, errors: 0) }
        let bobFinished = try await repo.finishChallenge(challenge, uid: bob.uid, skips: 5, errors: 2)
        XCTAssertTrue(bobFinished)
        let sent = try await repo.challenges(uid: bob.uid)
        XCTAssertEqual(sent.map(\.id), [challenge.id])
        XCTAssertEqual(sent.first?.state(for: bob.uid, now: now()), .waiting)

        // Alice sees it, starts her clock (and gets Bob as a friend), then finds 2 words and skips 3.
        try repo.signOut()
        _ = try await repo.signIn(email: "alice@cnsnn.test", password: "motdepasse1")
        let inbox = try await repo.challenges(uid: alice.uid)
        let received = try XCTUnwrap(inbox.first)
        XCTAssertEqual(received.state(for: alice.uid, now: now()), .yourTurn)
        XCTAssertEqual(received.from.name, "Bob")
        let started = try await repo.startChallenge(received, uid: alice.uid)
        XCTAssertNotNil(started.to.startedMs)
        let friends = try await repo.friends(uid: alice.uid)
        XCTAssertEqual(friends.map(\.uid), [bob.uid])
        await assertThrows { _ = try await self.repo.finishChallenge(started, uid: alice.uid, skips: 3, errors: 0) }
        try await Task.sleep(for: .milliseconds(4300))
        let aliceFinished = try await repo.finishChallenge(started, uid: alice.uid, skips: 3, errors: 1)
        XCTAssertTrue(aliceFinished)
        let over = try await XCTUnwrapAsync(try await repo.challenge(id: challenge.id))
        XCTAssertEqual(over.result(for: alice.uid, now: now()), .won)
        XCTAssertEqual(over.result(for: bob.uid, now: now()), .lost)
        XCTAssertEqual(ChallengeTally.of([over], me: alice.uid, friend: bob.uid, now: now()).label, "1 victoire · 0 défaite")

        // Deleting Alice's account removes the challenge for Bob too.
        try await repo.deleteAccount(uid: alice.uid, password: "motdepasse1")
        _ = try await repo.signIn(email: "bob@cnsnn.test", password: "motdepasse2")
        let left = try await repo.challenges(uid: bob.uid)
        XCTAssertTrue(left.isEmpty)
    }
    private func now() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    /// Sprint, Survie and Double sens records follow the account: two devices that never saw each
    /// other's games keep both, a reinstall gets them back, and a cut connection loses nothing.
    func testModeRecordsSyncAcrossDevices() async throws {
        let player = try await repo.bootstrap(username: "Lou")
        var phone = CNSNNCore.Progress(); phone.username = "Lou"
        phone.recordMode(.sprint, best: [ModeStat.score: 240, ModeStat.words: 9, ModeStat.combo: 6], add: [ModeStat.games: 1], device: "phone")
        phone.recordMode(.duo, best: [ModeStat.score: 900], add: [ModeStat.games: 1, ModeStat.perfect: 1, ModeStat.duosSolved: 5, ModeStat.duosPlayed: 5], device: "phone")
        _ = try await repo.saveCloudProgress(phone, uid: player.uid)
        var tablet = CNSNNCore.Progress(); tablet.username = "Lou"
        tablet.recordMode(.sprint, best: [ModeStat.score: 300, ModeStat.words: 7], add: [ModeStat.games: 1], device: "tablet")
        tablet.recordMode(.survival, best: [ModeStat.words: 23, ModeStat.level: 5], add: [ModeStat.games: 1], device: "tablet")
        let merged = try await repo.saveCloudProgress(tablet, uid: player.uid)
        XCTAssertEqual(merged.records(.sprint).best(ModeStat.score), 300)
        XCTAssertEqual(merged.records(.sprint).best(ModeStat.words), 9)
        XCTAssertEqual(merged.records(.sprint).best(ModeStat.combo), 6)
        XCTAssertEqual(merged.records(.sprint).total(ModeStat.games), 2)
        XCTAssertEqual(merged.records(.survival).best(ModeStat.words), 23)
        XCTAssertEqual(merged.records(.duo).total(ModeStat.perfect), 1)
        // The phone saves again (same games, nothing new): no game is counted twice.
        let again = try await repo.saveCloudProgress(phone, uid: player.uid)
        XCTAssertEqual(again.records(.sprint).total(ModeStat.games), 2)
        // Offline, the phone plays on; back online, its new game joins without erasing the tablet's.
        try await setNetwork(enabled: false)
        phone.recordMode(.sprint, best: [ModeStat.score: 50], add: [ModeStat.games: 1], device: "phone")
        try await setNetwork(enabled: true)
        _ = try await repo.saveCloudProgress(phone, uid: player.uid)
        // A reinstall (empty phone) gets everything back.
        let restored = try await XCTUnwrapAsync(try await repo.cloudProgress(uid: player.uid))
        XCTAssertEqual(restored.records(.sprint).total(ModeStat.games), 3)
        XCTAssertEqual(restored.records(.sprint).best(ModeStat.score), 300)
        XCTAssertEqual(restored.records(.survival).total(ModeStat.games), 1)
        XCTAssertEqual(restored.records(.duo).best(ModeStat.score), 900)
        // Records never touch the official numbers.
        XCTAssertEqual(restored.score, 0)
        XCTAssertTrue(restored.attempts.isEmpty)
    }

    func testProgressSyncRenameAndDeletion() async throws {
        let player = try await repo.bootstrap(username: "Camille")
        var progress = CNSNNCore.Progress(); progress.username = "Camille"
        progress.attempts = [Attempt(cardID: "seed-001", mode: .classic, correct: true, timeMs: 3000, points: 97, date: Date())]
        _ = try await repo.saveCloudProgress(progress, uid: player.uid)
        let restored = try await XCTUnwrapAsync(try await repo.cloudProgress(uid: player.uid))
        XCTAssertEqual(restored.score, 97)
        XCTAssertEqual(restored.attempts.first?.id, progress.attempts.first?.id)
        // A second device that never saw this game saves its own: both are kept.
        var tablet = CNSNNCore.Progress(); tablet.username = "Camille"
        tablet.attempts = [Attempt(cardID: "seed-002", mode: .classic, correct: true, timeMs: 4000, points: 96, date: Date())]
        let merged = try await repo.saveCloudProgress(tablet, uid: player.uid)
        XCTAssertEqual(merged.score, 193)
        let both = try await XCTUnwrapAsync(try await repo.cloudProgress(uid: player.uid))
        XCTAssertEqual(Set(both.attempts.map(\.cardID)), ["seed-001", "seed-002"])
        // A cut connection overwrites nothing either. (Transactions bypass disableNetwork and still
        // reach the emulator; a real outage makes the save fail.) The next sync merges again.
        try await setNetwork(enabled: false)
        if let during = try? await repo.saveCloudProgress(progress, uid: player.uid) { XCTAssertEqual(during.score, 193) }
        try await setNetwork(enabled: true)
        let afterOutage = try await repo.saveCloudProgress(progress, uid: player.uid)
        XCTAssertEqual(afterOutage.score, 193)

        // Rename reaches the leaderboard line once it exists.
        let day = DailySchedule.key()
        _ = try await repo.startDaily(uid: player.uid, day: day, cardID: "x")
        _ = try await repo.finishDaily(uid: player.uid, day: day, correct: false, wrongAnswers: 0)
        let lost = try await XCTUnwrapAsync(try await repo.publishDailyResult(uid: player.uid, day: day))
        XCTAssertEqual(lost.points, 0)
        try await repo.rename(uid: player.uid, username: "Camilla")
        let renamed = try await repo.leaderboardEntry(uid: player.uid, source: .server)
        XCTAssertEqual(renamed?.username, "Camilla")
        XCTAssertEqual(renamed?.streak, 0)

        // Deletion leaves nothing behind: more than 80 published cards lose the author's name and id,
        // and the suspension record and the reports naming the player go too.
        _ = try await repo.submit(card: Card(id: "local", wordFull: "Montgolfière", hint: "Un ballon à air chaud.", category: .objects, difficulty: .hard, status: .pending), uid: player.uid)
        let docs = "http://127.0.0.1:8080/v1/projects/\(project)/databases/(default)/documents"
        for index in 0..<85 {
            let id = "MOTPUBLIE\(index)"
            try await emulator("PATCH", "\(docs)/cards/\(id)", body: #"{"fields":{"wordFull":{"stringValue":"Mot publié"},"wordNoVowels":{"stringValue":"MTPBL"},"normalizedAnswer":{"stringValue":""# + id + #""},"hint":{"stringValue":"Un mot de test."},"category":{"stringValue":"Général"},"difficulty":{"stringValue":"Facile"},"status":{"stringValue":"approved"},"createdBy":{"stringValue":""# + player.uid + #""},"authorName":{"stringValue":"Camilla"}}}"#)
        }
        try await emulator("PATCH", "\(docs)/banned/\(player.uid)", body: #"{"fields":{"username":{"stringValue":"Camilla"},"reason":{"stringValue":"Test"}}}"#)
        try await emulator("PATCH", "\(docs)/playerReports/someone_\(player.uid)", body: #"{"fields":{"userId":{"stringValue":"someone"},"playerId":{"stringValue":""# + player.uid + #""},"username":{"stringValue":"Camilla"}}}"#)
        try await repo.deleteAccount(uid: player.uid, password: nil)
        let leftovers = try await emulatorText("GET", "\(docs)/cards?pageSize=300")
        XCTAssertFalse(leftovers.contains(player.uid), "Une carte garde l’identifiant du joueur supprimé.")
        XCTAssertFalse(leftovers.contains("Camilla"), "Une carte garde le pseudo du joueur supprimé.")
        let reports = try await emulatorText("GET", "\(docs)/playerReports")
        XCTAssertFalse(reports.contains(player.uid))
        let banned = try await emulatorText("GET", "\(docs)/banned")
        XCTAssertFalse(banned.contains(player.uid))
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
        let before = try await repo.cardsVersion()
        XCTAssertNil(before)
        try await repo.review(card: pending, approved: true)
        // Approving moves the catalogue version, so players download the cards again.
        let after = try await repo.cardsVersion()
        XCTAssertNotNil(after)
        let catalogue = try await repo.cards()
        XCTAssertEqual(catalogue.first { $0.id == "PATEACREPES" }?.hint, "Elle repose avant de finir dans la poêle.")

        // Reports: one per player and card, then resolved by the moderator.
        try repo.signOut()
        _ = try await repo.bootstrap(username: "Lecteur")
        try await repo.report(cardID: "PATEACREPES", reason: "L’indice est trop facile.")
        await assertThrows(CloudError.alreadyReported) { try await self.repo.report(cardID: "PATEACREPES", reason: "Encore une fois.") }
    }

    func testSuspensionHidesThenGivesEverythingBack() async throws {
        let day = DailySchedule.key()
        let card = try XCTUnwrap(DailySchedule.dailyCard(forKey: day))
        let cheater = try await repo.bootstrap(username: "Rapide")
        try await win(uid: cheater.uid, day: day, card: card)
        let points = try await XCTUnwrapAsync(try await repo.leaderboardEntry(uid: cheater.uid, source: .server)).points

        try repo.signOut()
        let mod = try await repo.bootstrap(username: "Modo")
        try await emulator("PATCH", "http://127.0.0.1:8080/v1/projects/\(project)/databases/(default)/documents/admins/\(mod.uid)", body: #"{"fields":{}}"#)
        let suspicious = try await repo.suspiciousResults(day: day)
        XCTAssertTrue(suspicious.allSatisfy { $0.timeMs < 5000 })
        try await repo.suspend(player: cheater.uid, username: "Rapide", reason: "Temps suspect")
        let hiddenTop = try await repo.topPlayers()
        XCTAssertFalse(hiddenTop.contains { $0.uid == cheater.uid })
        let hiddenToday = try await repo.dailyRanking(day: day)
        XCTAssertFalse(hiddenToday.contains { $0.uid == cheater.uid })
        // Nothing was deleted.
        let kept = try await repo.leaderboardEntry(uid: cheater.uid, source: .server)
        XCTAssertEqual(kept?.points, points)
        let result = try await repo.dailyResult(uid: cheater.uid, day: day)
        XCTAssertNotNil(result)

        try await repo.unsuspend(player: cheater.uid)
        let back = try await repo.topPlayers()
        XCTAssertEqual(back.first { $0.uid == cheater.uid }?.points, points)
        let today = try await repo.dailyRanking(day: day)
        XCTAssertTrue(today.contains { $0.uid == cheater.uid })
    }

    // MARK: Helpers

    /// Finds today's word as the app does: a registered guess, then the finish, then the official result.
    private func win(uid: String, day: String, card: Card) async throws {
        _ = try await repo.startDaily(uid: uid, day: day, cardID: card.id)
        try await seedSecret(day: day, card: card)
        try await Task.sleep(for: .milliseconds(2200))
        let guesses = try await repo.registerGuess(uid: uid, day: day, guess: WordEngine.normalize(card.wordFull))
        _ = try await repo.finishDaily(uid: uid, day: day, correct: true, wrongAnswers: guesses - 1, answer: WordEngine.normalize(card.wordFull))
        _ = try await repo.publishDailyResult(uid: uid, day: day)
    }
    private func setNetwork(enabled: Bool) async throws { try await repo.setNetwork(enabled: enabled) }
    private func emulatorText(_ method: String, _ url: String) async throws -> String {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        return String(decoding: try await URLSession.shared.data(for: request).0, as: UTF8.self)
    }

    /// Every day has a secret word on the server, and a win must name it.
    private func seedSecret(day: String, card: Card) async throws {
        let docs = "http://127.0.0.1:8080/v1/projects/\(project)/databases/(default)/documents"
        try await emulator("PATCH", "\(docs)/dailySecrets/\(day)", body: #"{"fields":{"answer":{"stringValue":""# + WordEngine.normalize(card.wordFull) + #""}}}"#)
    }
    private func emulator(_ method: String, _ url: String, body: String? = nil) async throws {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
        request.httpMethod = method
        // "owner" bypasses the security rules on the Firestore emulator only.
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = Data(body.utf8); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        // The emulators can be slow to answer their first request on a busy CI runner: retry a timeout.
        var response: URLResponse?
        for attempt in 0..<3 where response == nil {
            do { response = try await URLSession.shared.data(for: request).1 }
            catch let error as URLError where error.code == .timedOut && attempt < 2 { continue }
        }
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
        let unwrapped = try await value()
        return try XCTUnwrap(unwrapped, file: file, line: line)
    }
}
