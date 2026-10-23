import Foundation
import Observation
import CNSNNCore

@MainActor @Observable final class GameSession {
    enum Phase: Equatable { case loading, playing, failed(String) }
    var phase: Phase = .playing
    var card: Card?
    var answer = ""
    var feedback: String?
    var usedHint = false
    var result: Attempt?
    var wrongAnswers = 0
    var wrongGuesses: [String] = []
    var resumedDaily = false
    /// The daily game is timed and scored by the server (signed in with Firebase).
    var ranked = false
    /// The finish is recorded on this iPhone and waits for the network to become official.
    var pendingOfficial = false
    var standing: DailyStanding?
    /// The word is secret: the server checks each guess and reveals the word at the end.
    var secret = false
    /// A guess or the hint is on its way to the server.
    var checking = false
    /// Why the last check could not reach the server (network), shown under the board.
    var notice: String?
    private var dailyKey: String?
    /// Rattrapage: a missed daily word of the week, played later and counted in the week (see CatchUp).
    private(set) var catchUpDay: String?
    private var dailyStart: Date?
    private var start = ContinuousClock.now
    private var elapsedBeforePause: Duration = .zero
    private var paused = false

    func load(mode: GameMode, category: CNSNNCore.Category?, difficulty: Difficulty?, catchUp: String? = nil, state: AppState) {
        answer = ""; feedback = nil; result = nil; usedHint = false; wrongAnswers = 0; wrongGuesses = []
        start = .now; elapsedBeforePause = .zero; paused = false; dailyKey = nil; dailyStart = nil; catchUpDay = catchUp
        ranked = false; pendingOfficial = false; standing = nil; phase = .playing; secret = false; checking = false; notice = nil
        if mode == .daily {
            let key = catchUp ?? DailySchedule.key(); dailyKey = key
            if state.cloud != nil || catchUp != nil {
                // With a server, the daily game is always the official one: no offline replay to learn the word.
                ranked = true; phase = .loading
                Task {
                    if state.uid == nil { await state.connectIfConfigured() }
                    guard let cloud = state.cloud, let uid = state.uid else { phase = .failed(CloudError.offline.errorDescription ?? ""); return }
                    if state.isSuspended, (try? await cloud.dailySession(uid: uid, day: key)) == nil { phase = .failed(AppState.suspendedText); return }
                    await loadRankedDaily(key: key, catchUp: catchUp != nil, cloud: cloud, uid: uid, state: state)
                }
            } else {
                loadLocalDaily(key: key, state: state)
            }
        } else if ScreenshotDemo.isActive {
            // App Store screenshots: always the same public Classique card.
            card = ScreenshotDemo.classicCard
        } else {
            card = CardPicker.candidates(cards: state.cards, category: category, difficulty: difficulty, recent: state.progress.recentCards).randomElement()
        }
    }

    /// The first-launch tutorial: the Mot du jour page with an example word, nothing recorded or sent.
    func loadTutorial(_ example: Card) {
        guard card?.id != example.id else { return }
        answer = ""; feedback = nil; result = nil; usedHint = false; wrongAnswers = 0; wrongGuesses = []
        start = .now; elapsedBeforePause = .zero; paused = false; dailyKey = nil; dailyStart = nil; catchUpDay = nil
        ranked = false; pendingOfficial = false; standing = nil; secret = false; checking = false; notice = nil
        card = example; phase = .playing
    }

    /// Without Firebase (tests, missing configuration): the start time is kept on this iPhone.
    private func loadLocalDaily(key: String, state: AppState) {
        if let existing = state.progress.attempts.first(where: { $0.dailyKey == key }) {
            result = existing; card = state.card(id: existing.cardID); return
        }
        if let locked = state.progress.dailyStarted[key] {
            card = state.card(id: locked); resumedDaily = true
        } else {
            card = state.dailyCard(day: key)
            if let card { state.progress.dailyStarted[key] = card.id; state.progress.dailyStartedAt[key] = Date(); state.persist() }
        }
        dailyStart = state.progress.dailyStartedAt[key] ?? Date()
    }

    /// Signed in: one server session per day. The consonants appear only once the server has
    /// recorded the start, and a finished day always shows its official result.
    /// A caught-up day (`catchUp`) runs the same way: its answer stays secret until the week is over.
    private func loadRankedDaily(key: String, catchUp: Bool, cloud: FirebaseRepository, uid: String, state: AppState) async {
        do {
            if let session = try await cloud.dailySession(uid: uid, day: key) {
                secret = FirebaseRepository.secretDay(cardID: session.cardID) != nil
                card = state.card(id: session.cardID)
                if secret, session.finished, let revealed = try await cloud.dailySecret(day: key) {
                    state.storeDailyWord(revealed, day: key); card = revealed
                } else if secret, card == nil {
                    card = try await cloud.dailyPuzzle(day: key)
                    if let card { state.storeDailyWord(card, day: key) }
                }
                if secret, session.hintUsed, !session.finished, card?.hint.isEmpty == true, var masked = card {
                    masked.hint = try await cloud.dailyHint(day: key) ?? ""
                    card = masked; state.storeDailyWord(masked, day: key)
                }
                if session.finished {
                    if let official = try await cloud.publishDailyResult(uid: uid, day: key) {
                        state.recordOfficial(official); result = official
                        await loadStanding(cloud: cloud, attempt: official)
                    } else if let local = state.progress.attempts.first(where: { $0.dailyKey == key }) {
                        result = local; pendingOfficial = true
                    }
                    phase = .playing
                    return
                }
                usedHint = session.hintUsed; resumedDaily = true
                wrongAnswers = session.guesses
                dailyStart = session.startedAt
                if let local = state.progress.attempts.first(where: { $0.dailyKey == key }) {
                    // Finished on this iPhone but the finish never reached the server: send it again.
                    result = local; pendingOfficial = true; phase = .playing
                    await makeOfficial(cloud: cloud, uid: uid, day: key, correct: local.correct, state: state)
                    return
                }
            } else {
                if let local = state.progress.attempts.first(where: { $0.dailyKey == key }) {
                    // Already played on this iPhone before the account existed: no second try.
                    result = local; card = state.card(id: local.cardID); ranked = false; phase = .playing
                    return
                }
                let puzzle = try await cloud.dailyPuzzle(day: key)
                guard let daily = puzzle ?? (catchUp ? nil : state.dailyCard(day: key)) else { phase = .failed("Le mot du jour est indisponible."); return }
                let session = try await cloud.startDaily(uid: uid, day: key, cardID: daily.id, catchUp: catchUp)
                card = daily; dailyStart = session.startedAt; secret = puzzle != nil
                if secret { state.storeDailyWord(daily, day: key) }
            }
            if let card {
                state.progress.dailyStarted[key] = card.id
                state.progress.dailyStartedAt[key] = dailyStart
                state.persist()
            }
            phase = card == nil ? .failed("Cette carte n’existe pas dans cette version. Mettez l’application à jour.") : .playing
        } catch {
            phase = .failed(CloudError.message(error))
        }
    }

    func retry(state: AppState) {
        load(mode: .daily, category: nil, difficulty: nil, catchUp: catchUpDay, state: state)
    }

    func revealHint(state: AppState) {
        guard !usedHint, result == nil, !checking else { return }
        guard ranked, let cloud = state.cloud, let uid = state.uid, let dailyKey else { usedHint = true; return }
        guard secret else { usedHint = true; cloud.revealDailyHint(uid: uid, day: dailyKey); return }
        // The server opens the hint only once it has recorded its use.
        checking = true; notice = nil
        Task {
            defer { checking = false }
            do {
                guard let hint = try await cloud.revealSecretHint(uid: uid, day: dailyKey), var revealed = card else {
                    notice = CloudError.offline.errorDescription; return
                }
                revealed.hint = hint; card = revealed; usedHint = true
                state.storeDailyWord(revealed, day: dailyKey)
            } catch {
                notice = CloudError.message(error)
            }
        }
    }

    func pause() {
        guard !paused, result == nil else { return }
        elapsedBeforePause += start.duration(to: .now); paused = true
    }
    func resume() { guard paused else { return }; start = .now; paused = false }
    var elapsedMs: Int {
        if let dailyStart { return max(0, Int(Date().timeIntervalSince(dailyStart) * 1000)) }
        let duration = elapsedBeforePause + (paused ? .zero : start.duration(to: .now))
        return max(0, Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000))
    }
    func submit(mode: GameMode, state: AppState) async {
        guard let card, result == nil, !checking, !WordEngine.normalize(answer).isEmpty else { return }
        if secret {
            await submitSecret(state: state)
            return
        }
        guard WordEngine.matches(answer, word: card.wordFull) else { missed(); return }
        finish(correct: true, mode: mode, state: state)
    }
    private func missed() {
        wrongAnswers += 1; wrongGuesses.append(answer); feedback = "Pas encore. Essayez une autre idée."; Haptics.retry()
    }
    /// "Plus que 3 essais" once five or fewer guesses remain on a secret word (20 a day).
    var guessesNotice: String? {
        let left = DailyGuesses.max - wrongAnswers
        guard secret, result == nil, left <= 5 else { return nil }
        return left == 1 ? "Plus qu’un essai" : "Plus que \(left) essais"
    }
    /// The guess is first counted on the server (20 a day), then sent as the finish of the session:
    /// accepted only if it is the word.
    private func submitSecret(state: AppState) async {
        guard let cloud = state.cloud, let uid = state.uid, let dailyKey else { return }
        let guess = WordEngine.normalize(answer)
        checking = true; notice = nil
        defer { checking = false }
        let count: Int
        do {
            count = try await cloud.registerGuess(uid: uid, day: dailyKey, guess: guess)
        } catch let error where CloudError.code(error) == .permissionDenied {
            notice = "Patientez une seconde avant de réessayer."; return
        } catch {
            if (error as? CloudError) == .noGuessesLeft { notice = CloudError.noGuessesLeft.errorDescription; await giveUp(cloud: cloud, uid: uid, day: dailyKey, state: state) }
            else { notice = CloudError.message(error) }
            return
        }
        do {
            guard try await cloud.finishDaily(uid: uid, day: dailyKey, correct: true, wrongAnswers: count - 1, answer: guess) else {
                // Not confirmed in time. If it was right, the server keeps it and the next opening shows the result.
                notice = "Connexion trop lente. Vérifiez le réseau puis réessayez."; return
            }
            await reveal(cloud: cloud, day: dailyKey, state: state)
            finish(correct: true, mode: .daily, state: state, alreadyFinished: true)
        } catch let error where CloudError.code(error) == .permissionDenied {
            wrongAnswers = count - 1
            missed()
            // The twentieth wrong guess ends the game.
            if count >= DailyGuesses.max { await giveUp(cloud: cloud, uid: uid, day: dailyKey, state: state) }
        } catch {
            wrongAnswers = count
            notice = CloudError.message(error)
        }
    }
    /// Records the loss on the server with the errors it counted, then reveals the word.
    /// Returns false if the server could not be reached.
    @discardableResult private func giveUp(cloud: FirebaseRepository, uid: String, day: String, state: AppState) async -> Bool {
        var confirmed = (try? await cloud.finishDaily(uid: uid, day: day, correct: false, wrongAnswers: wrongAnswers)) == true
        if !confirmed, let session = try? await cloud.dailySession(uid: uid, day: day), !session.finished {
            // This iPhone's count was off (a guess sent from elsewhere): use the server's.
            wrongAnswers = session.guesses
            confirmed = (try? await cloud.finishDaily(uid: uid, day: day, correct: false, wrongAnswers: wrongAnswers)) == true
        }
        guard confirmed else { notice = CloudError.offline.errorDescription; return false }
        await reveal(cloud: cloud, day: day, state: state)
        finish(correct: false, mode: .daily, state: state, alreadyFinished: true)
        return true
    }
    /// Swaps the masked card for the real word once the server has recorded the end of the game.
    private func reveal(cloud: FirebaseRepository, day: String, state: AppState) async {
        guard let revealed = try? await cloud.dailySecret(day: day) else { return }
        card = revealed; state.storeDailyWord(revealed, day: day)
    }
    func finish(correct: Bool, mode: GameMode, state: AppState, alreadyFinished: Bool = false) {
        guard result == nil, !checking || alreadyFinished else { return }
        if secret, !correct, !alreadyFinished, let cloud = state.cloud, let uid = state.uid, let dailyKey {
            // Giving up: the server records the loss first, then reveals the word.
            checking = true; notice = nil
            Task {
                defer { checking = false }
                await giveUp(cloud: cloud, uid: uid, day: dailyKey, state: state)
            }
            return
        }
        guard let card else { return }
        let ms = elapsedMs
        let attempt = Attempt(cardID: card.id, mode: mode, correct: correct, timeMs: ms, points: 0, date: Date(), dailyKey: dailyKey,
                              catchUp: catchUpDay != nil ? true : nil)
        result = attempt
        state.record(attempt)
        if correct { Haptics.success() }
        if ranked, let cloud = state.cloud, let uid = state.uid, let dailyKey {
            pendingOfficial = true
            Task { await makeOfficial(cloud: cloud, uid: uid, day: dailyKey, correct: correct, state: state, finished: alreadyFinished) }
        }
    }
    /// Stamps the finish on the server, then shows the server's time instead of the local ones.
    private func makeOfficial(cloud: FirebaseRepository, uid: String, day: String, correct: Bool, state: AppState, finished: Bool = false) async {
        do {
            if !finished { guard try await cloud.finishDaily(uid: uid, day: day, correct: correct, wrongAnswers: wrongAnswers) else { return } }
            guard let official = try await cloud.publishDailyResult(uid: uid, day: day) else { return }
            state.recordOfficial(official)
            if let current = result { var shown = official; shown.id = current.id; result = shown }
            pendingOfficial = false
            await state.refreshOfficial()
            await loadStanding(cloud: cloud, attempt: official)
        } catch {
            // Stays pending: AppState.finishPendingDaily publishes it on a later launch.
        }
    }
    private func loadStanding(cloud: FirebaseRepository, attempt: Attempt) async {
        // A caught-up day is out of the day's ranking.
        guard let day = attempt.dailyKey, catchUpDay == nil else { return }
        standing = try? await cloud.standing(day: day, scoreMs: DailyScore.scoreMs(timeMs: attempt.timeMs, usedHint: usedHint, correct: attempt.correct), correct: attempt.correct)
    }
}
