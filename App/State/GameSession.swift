import Foundation
import Observation
import CNSNNCore

@MainActor @Observable final class GameSession {
    var card: Card?
    var answer = ""
    var feedback: String?
    var usedHint = false
    var result: Attempt?
    var wrongAnswers = 0
    var wrongGuesses: [String] = []
    var resumedDaily = false
    private var dailyKey: String?
    private var dailyStart: Date?
    private var start = ContinuousClock.now
    private var elapsedBeforePause: Duration = .zero
    private var paused = false
    func load(mode: GameMode, category: CNSNNCore.Category?, difficulty: Difficulty?, state: AppState) {
        answer = ""; feedback = nil; result = nil; usedHint = false; wrongAnswers = 0; wrongGuesses = []
        start = .now; elapsedBeforePause = .zero; paused = false; dailyKey = nil; dailyStart = nil
        if mode == .daily {
            let key = DailySchedule.key(); dailyKey = key
            if let existing = state.progress.attempts.first(where: { $0.dailyKey == key }) {
                result = existing; card = SeedCards.all.first { $0.id == existing.cardID }; return
            }
            if let locked = state.progress.dailyStarted[key] {
                card = SeedCards.all.first { $0.id == locked }; resumedDaily = true
            } else {
                card = DailySchedule.card(for: Date(), cards: SeedCards.all)
                if let card { state.progress.dailyStarted[key] = card.id; state.progress.dailyStartedAt[key] = Date(); state.persist() }
            }
            dailyStart = state.progress.dailyStartedAt[key] ?? Date()
        } else {
            card = CardPicker.candidates(cards: state.cards, category: category, difficulty: difficulty, recent: state.progress.recentCards).randomElement()
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
    func submit(mode: GameMode, state: AppState) {
        guard let card, result == nil, !WordEngine.normalize(answer).isEmpty else { return }
        guard WordEngine.matches(answer, word: card.wordFull) else {
            wrongAnswers += 1; wrongGuesses.append(answer); feedback = "Pas encore. Essaie une autre idée."; Haptics.retry(); return
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
    }
}
