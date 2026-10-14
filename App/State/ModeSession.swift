import Foundation
import Observation
import CNSNNCore

/// One Sprint, Survie or Double sens game on screen. The rules live in CNSNNCore; this class adds the
/// clock, the saving after every move and the personal records at the end.
///
/// Leaving and coming back:
/// - Sprint: the clock never stops (ContinuousClock keeps running while the iPhone sleeps). A Sprint
///   whose app is closed is over and counts as it stood at the next launch.
/// - Survie: no clock. The game is saved after every word and picks up where it was.
/// - Double sens: the clock keeps running, in the background too; a closed game picks up where it was,
///   the time away included.
@MainActor @Observable final class ModeSession {
    let mode: PlayMode
    var sprint: SprintGame?
    var survival: SurvivalGame?
    var duo: DuoGame?
    var answer = ""
    /// Bumped on each event, so the screen can shake, glow or animate a heart.
    var mistakeTick = 0
    var successTick = 0
    var lifeLostTick = 0
    var lifeGainedTick = 0
    /// "+60 · ×3" after a right Sprint answer.
    var gain: String?
    /// The game picked up from a save.
    var resumed = false
    /// Results screen, with the records the game beat and the ones before it.
    var over = false
    var beaten: Set<String> = []
    var previous = ModeRecords()
    private var start = ContinuousClock.now
    private var baseMs = 0
    private var recorded = false

    init(mode: PlayMode) { self.mode = mode }

    var elapsedMs: Int {
        let duration = start.duration(to: .now)
        return baseMs + Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
    var finished: Bool { sprint?.finished ?? survival?.finished ?? duo?.finished ?? false }

    /// Picks up the saved game of this mode, or starts a new one.
    func begin(state: AppState) {
        answer = ""; gain = nil; over = false; beaten = []; recorded = false
        previous = state.progress.records(mode)
        if mode != .sprint, let run = ModeRunStore.load(mode), !run.finished {
            sprint = nil; survival = run.survival; duo = run.duo
            baseMs = run.resumedElapsedMs; start = .now; resumed = true
            return
        }
        resumed = false
        let seed = Self.seed ?? ModeRandom.seed()
        let recent = ModeRunStore.recent(mode)
        sprint = mode == .sprint ? SprintGame(seed: seed, recent: recent) : nil
        survival = mode == .survival ? SurvivalGame(seed: seed, recent: recent) : nil
        duo = mode == .duo ? DuoGame(seed: seed, recent: recent) : nil
        baseMs = 0; start = .now
        save()
    }

    /// Fixed seed for the interface tests (`--mode-seed=42`), so they know the words.
    static var seed: UInt64? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--mode-seed=") }.flatMap { UInt64($0.dropFirst("--mode-seed=".count)) }
    }

    // MARK: Typing

    func press(_ letter: String) {
        guard !finished, answer.count < 40 else { return }
        if letter == " ", answer.isEmpty || answer.hasSuffix(" ") { return }
        answer += letter
    }
    func delete() { if !answer.isEmpty { answer.removeLast() } }

    func submit(state: AppState) {
        guard !finished, !WordEngine.normalize(answer).isEmpty else { mistakeTick += 1; return }
        let text = answer, now = elapsedMs
        switch mode {
        case .sprint:
            switch sprint?.answer(text, elapsed: now) {
            case .right(let points, let multiplier)?:
                answer = ""; successTick += 1; gain = "+\(points)" + (multiplier > 1 ? " · ×\(multiplier)" : ""); Haptics.success()
            case .wrong?: wrong()
            default: break
            }
        case .survival:
            switch survival?.answer(text) {
            case .right(let gained)?:
                answer = ""; successTick += 1; Haptics.success()
                if gained { lifeGainedTick += 1 }
            case .wrong?: wrong(); lifeLostTick += 1; Haptics.failure()
            default: break
            }
        case .duo:
            switch duo?.answer(text, elapsed: now) {
            case .first?, .second?: answer = ""; successTick += 1; Haptics.success()
            case .already?: answer = ""
            case .wrong?: wrong()
            default: break
            }
        }
        afterMove(state: state)
    }
    private func wrong() {
        answer = ""; mistakeTick += 1; Haptics.retry()
    }

    /// Sprint: next word for 5 seconds. Survie: next word for one life. Double sens: gives up the round.
    func skip(state: AppState) {
        guard !finished else { return }
        answer = ""
        switch mode {
        case .sprint: sprint?.skip(elapsed: elapsedMs); gain = nil
        case .survival: survival?.skip(); lifeLostTick += 1; Haptics.failure()
        case .duo: duo?.skip(elapsed: elapsedMs)
        }
        afterMove(state: state)
    }

    /// Double sens: on to the next round once the words are shown.
    func nextRound(state: AppState) {
        if finished { over = true; return }
        duo?.next(elapsed: elapsedMs)
        save()
    }

    /// Sprint: ends the game when the time is up (called by the screen's clock and on return).
    func tick(state: AppState) {
        guard mode == .sprint, sprint?.tick(elapsed: elapsedMs) == true else { return }
        Haptics.failure()
        afterMove(state: state)
    }

    /// Ends the game now and counts it: a Sprint with its score so far, a Survie run as it stands, a
    /// Double sens game with its unplayed rounds lost.
    func quit(state: AppState) {
        guard !finished else { return }
        switch mode {
        case .sprint: sprint?.stop()
        case .survival: survival?.abandon()
        case .duo: duo?.abandon(elapsed: elapsedMs)
        }
        afterMove(state: state)
        over = true
    }

    private func afterMove(state: AppState) {
        if finished { finish(state: state) } else { save() }
    }

    private func save() {
        guard !finished else { return }
        ModeRunStore.save(ModeRun(mode: mode, sprint: sprint, survival: survival, duo: duo, elapsedMs: elapsedMs, savedAt: Date()))
    }

    private func finish(state: AppState) {
        guard !recorded else { return }
        recorded = true
        ModeRunStore.clear(mode)
        let now = elapsedMs
        switch mode {
        case .sprint:
            guard let sprint else { return }
            beaten = state.recordMode(.sprint, best: sprint.records.best, add: sprint.records.add)
            ModeRunStore.remember(sprint.used, mode: .sprint)
        case .survival:
            guard let survival else { return }
            beaten = state.recordMode(.survival, best: survival.records.best, add: survival.records.add)
            ModeRunStore.remember(survival.used, mode: .survival)
        case .duo:
            guard let duo else { return }
            let records = duo.records(elapsed: now)
            beaten = state.recordMode(.duo, best: records.best, add: records.add)
            ModeRunStore.remember(duo.duos.map(\.id), mode: .duo)
        }
        // The last Double sens round first shows its words; "Voir le résultat" opens the results.
        over = mode != .duo || duo?.roundComplete != true
    }

    /// A record beaten that existed before this game (the first game only sets them).
    func improved(_ key: String) -> Bool { beaten.contains(key) && previous.best(key) > 0 }
}
