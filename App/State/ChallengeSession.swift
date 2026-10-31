import Foundation
import Observation
import CNSNNCore

/// One side of a friend challenge on screen. The official time is the server's (start and finish
/// stamped in Firestore); the chrono shown while playing is this iPhone's. The game is saved after
/// every word, so a closed app picks up at the same word, the time away included.
@MainActor @Observable final class ChallengeSession {
    enum Phase: Equatable { case starting, playing, sending, done, failed(String) }

    var challenge: Challenge
    var game: ChallengeGame?
    var phase: Phase = .starting
    var answer = ""
    /// The last answer was wrong: it stays on screen in red, so a typo is fixed without retyping it all.
    var answerWrong = false
    var mistakeTick = 0
    var successTick = 0
    /// The answer of the word just passed, shown for a moment.
    var passed: String?
    var passedTick = 0
    private var start = ContinuousClock.now
    private var baseMs = 0

    init(challenge: Challenge) { self.challenge = challenge }

    var elapsedMs: Int {
        let duration = start.duration(to: .now)
        return baseMs + Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    /// Starts the friend's clock on the server (the challenger's started with the challenge), then plays.
    func begin(state: AppState) async {
        guard let uid = state.uid else { phase = .failed(CloudError.offline.errorDescription ?? ""); return }
        if challenge.mine(uid).finished { ChallengeStore.clear(challenge.id); phase = .done; return }
        if Int(Date().timeIntervalSince1970 * 1000) >= challenge.finishDeadlineMs() {
            ChallengeStore.clear(challenge.id); phase = .failed(Self.expiredText); return
        }
        guard let cards = ChallengeRules.cards(challenge.cardIds) else { phase = .failed(CloudError.challengeUnavailable.errorDescription ?? ""); return }
        do { challenge = try await state.startChallenge(challenge) }
        catch { phase = .failed(CloudError.message(error)); return }
        // A result sent earlier may have reached the server after all.
        if challenge.mine(uid).finished { ChallengeStore.clear(challenge.id); phase = .done; return }
        if let saved = ChallengeStore.load(challenge.id) {
            game = saved.game
            baseMs = saved.elapsedMs + max(0, Int(Date().timeIntervalSince(saved.savedAt) * 1000))
        } else {
            game = ChallengeGame(cards: cards)
            baseMs = 0
        }
        start = .now
        phase = .playing
        if game?.finished == true { await finish(state: state) }
    }

    func press(_ letter: String) {
        guard phase == .playing, answer.count < 40 else { return }
        if letter == " ", answer.isEmpty || answer.hasSuffix(" ") { return }
        answer += letter; answerWrong = false
    }
    func delete() { if !answer.isEmpty { answer.removeLast() }; answerWrong = false }
    /// Long press on ⌫.
    func clear() { answer = ""; answerWrong = false }

    func submit(state: AppState) {
        guard phase == .playing, var game, !WordEngine.normalize(answer).isEmpty else { mistakeTick += 1; return }
        switch game.answer(answer) {
        case .right: answer = ""; answerWrong = false; successTick += 1; Haptics.success()
        case .wrong: answerWrong = true; mistakeTick += 1; Haptics.retry()
        case .over: break
        }
        self.game = game
        afterMove(state: state)
    }

    /// Next word, for 20 seconds.
    func skip(state: AppState) {
        guard phase == .playing, var game else { return }
        answer = ""; answerWrong = false
        if let word = game.card?.wordFull { passed = word; passedTick += 1 }
        game.skip()
        self.game = game
        afterMove(state: state)
    }

    /// Gives up: the words left count as skipped.
    func abandon(state: AppState) {
        guard phase == .playing, var game else { return }
        while !game.finished { game.skip() }
        self.game = game
        afterMove(state: state)
    }

    private func afterMove(state: AppState) {
        guard let game else { return }
        if game.finished { Task { await finish(state: state) } }
        else { ChallengeStore.save(ChallengeStore.Run(game: game, elapsedMs: elapsedMs, savedAt: Date()), id: challenge.id) }
    }

    /// The game is kept on the phone until the server confirms the finish: a lost connection never
    /// loses a result, and "Réessayer" (or the next launch) sends it again.
    private func finish(state: AppState) async {
        guard phase == .playing, let game else { return }
        phase = .sending
        ChallengeStore.save(ChallengeStore.Run(game: game, elapsedMs: elapsedMs, savedAt: Date()), id: challenge.id)
        let (fresh, outcome) = await state.finishChallenge(challenge, skips: game.skips, errors: game.errors)
        challenge = fresh
        switch outcome {
        case .confirmed: ChallengeStore.clear(challenge.id); phase = .done
        case .expired: ChallengeStore.clear(challenge.id); phase = .failed(Self.expiredText)
        case .pending: phase = .failed(Self.pendingText)
        }
    }
    static let pendingText = "Résultat en attente de validation. Votre partie est gardée sur ce téléphone : vérifiez le réseau puis réessayez. Le chrono officiel s’arrête quand le serveur reçoit votre résultat."
    static let expiredText = "Le délai de ce défi est dépassé : ce résultat n’a pas pu être enregistré."

    /// My time as the server measured it, or this iPhone's while the server has not confirmed.
    func myScoreMs(uid: String) -> Int {
        challenge.mine(uid).scoreMs ?? game?.scoreMs(elapsed: elapsedMs) ?? 0
    }
}

/// The unfinished challenge games of this device.
enum ChallengeStore {
    struct Run: Codable { var game: ChallengeGame; var elapsedMs: Int; var savedAt: Date }
    private static func key(_ id: String) -> String { "challenge.run." + id }
    static func save(_ run: Run, id: String) {
        if let data = try? JSONEncoder().encode(run) { UserDefaults.standard.set(data, forKey: key(id)) }
    }
    static func load(_ id: String) -> Run? {
        UserDefaults.standard.data(forKey: key(id)).flatMap { try? JSONDecoder().decode(Run.self, from: $0) }
    }
    static func clear(_ id: String) { UserDefaults.standard.removeObject(forKey: key(id)) }
}

/// The challenges list kept on this device, per player: the app then reads only the recent ones.
enum ChallengeCache {
    struct Saved: Codable { var challenges: [Challenge]; var fullAtMs: Int }
    private static func key(_ uid: String) -> String { "challenges.cache." + uid }
    static func load(uid: String) -> Saved? {
        UserDefaults.standard.data(forKey: key(uid)).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
    }
    static func save(_ saved: Saved, uid: String) {
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: key(uid)) }
    }
    static func clear(uid: String) { UserDefaults.standard.removeObject(forKey: key(uid)) }
}
