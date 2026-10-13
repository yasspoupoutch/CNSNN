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
    private var dailyKey: String?
    private var dailyStart: Date?
    private var start = ContinuousClock.now
    private var elapsedBeforePause: Duration = .zero
    private var paused = false

    func load(mode: GameMode, category: CNSNNCore.Category?, difficulty: Difficulty?, state: AppState) {
        answer = ""; feedback = nil; result = nil; usedHint = false; wrongAnswers = 0; wrongGuesses = []
        start = .now; elapsedBeforePause = .zero; paused = false; dailyKey = nil; dailyStart = nil
        ranked = false; pendingOfficial = false; standing = nil; phase = .playing
        if mode == .daily {
            let key = DailySchedule.key(); dailyKey = key
            if state.cloud != nil {
                // With a server, the daily game is always the official one: no offline replay to learn the word.
                ranked = true; phase = .loading
                Task {
                    if state.uid == nil { await state.connectIfConfigured() }
                    guard let cloud = state.cloud, let uid = state.uid else { phase = .failed(CloudError.offline.errorDescription ?? ""); return }
                    await loadRankedDaily(key: key, cloud: cloud, uid: uid, state: state)
                }
            } else {
                loadLocalDaily(key: key, state: state)
            }
        } else {
            card = CardPicker.candidates(cards: state.cards, category: category, difficulty: difficulty, recent: state.progress.recentCards).randomElement()
        }
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
    private func loadRankedDaily(key: String, cloud: FirebaseRepository, uid: String, state: AppState) async {
        do {
            if let session = try await cloud.dailySession(uid: uid, day: key) {
                card = state.card(id: session.cardID)
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
                guard let daily = state.dailyCard(day: key) else { phase = .failed("Le mot du jour est indisponible."); return }
                let session = try await cloud.startDaily(uid: uid, day: key, cardID: daily.id)
                card = daily; dailyStart = session.startedAt
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
        load(mode: .daily, category: nil, difficulty: nil, state: state)
    }

    func revealHint(state: AppState) {
        guard !usedHint, result == nil else { return }
        usedHint = true
        if ranked, let cloud = state.cloud, let uid = state.uid, let dailyKey { cloud.revealDailyHint(uid: uid, day: dailyKey) }
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
    func submit(mode: GameMode, state: AppState) {
        guard let card, result == nil, !WordEngine.normalize(answer).isEmpty else { return }
        guard WordEngine.matches(answer, word: card.wordFull) else {
            wrongAnswers += 1; wrongGuesses.append(answer); feedback = "Pas encore. Essayez une autre idée."; Haptics.retry(); return
        }
        finish(correct: true, mode: mode, state: state)
    }
    func finish(correct: Bool, mode: GameMode, state: AppState) {
        guard let card, result == nil else { return }
        let ms = elapsedMs
        let points = Scoring.points(difficulty: card.difficulty, timeMs: ms, usedHint: usedHint, correct: correct)
        let attempt = Attempt(cardID: card.id, mode: mode, correct: correct, timeMs: ms, points: points, date: Date(), dailyKey: dailyKey)
        result = attempt; state.record(attempt)
        if correct { Haptics.success() }
        if ranked, let cloud = state.cloud, let uid = state.uid, let dailyKey {
            pendingOfficial = true
            Task { await makeOfficial(cloud: cloud, uid: uid, day: dailyKey, correct: correct, state: state) }
        }
    }
    /// Stamps the finish on the server, then shows the server's time and points instead of the local ones.
    private func makeOfficial(cloud: FirebaseRepository, uid: String, day: String, correct: Bool, state: AppState) async {
        do {
            guard try await cloud.finishDaily(uid: uid, day: day, correct: correct, wrongAnswers: wrongAnswers),
                  let official = try await cloud.publishDailyResult(uid: uid, day: day) else { return }
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
        guard let day = attempt.dailyKey else { return }
        standing = try? await cloud.standing(day: day, timeMs: attempt.timeMs, correct: attempt.correct)
    }
}
