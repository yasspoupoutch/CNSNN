import Foundation
import Observation
import CNSNNCore

/// The weekly tournament as this phone knows it (Core/Tournament.swift): next week's sign-ups (a count
/// and my place, 2 reads), and the week under way, its players once, its runs from the round not yet
/// settled. Read only when the tournament is on screen, at most once a minute.
@MainActor @Observable final class TournamentStore {
    private(set) var uid: String?
    private(set) var nextWeek = ""
    private(set) var nextCount = 0
    private(set) var nextMine = false
    private(set) var currentWeek = ""
    /// Am I in the week under way? Its whole bracket is read only then, or on the tournament screen.
    private(set) var currentMine = false
    private(set) var current: [TournamentPlayer] = []
    private(set) var currentLoaded = false
    private(set) var runs: [TournamentRun] = []
    private(set) var loading = false
    var message: String?
    private var readAt: Date?
    private var runsReadAt: Date?
    /// The last round whose runs can no longer change (its 24 hours were over when they were read).
    private var settled = 0

    var nowMs: Int { Int(Date().timeIntervalSince1970 * 1000) }
    var bracket: TournamentBracket { TournamentBracket(week: currentWeek, signedUp: current, runs: runs, nowMs: nowMs) }
    var deadline: Date? { TournamentRules.deadlineMs(week: nextWeek).map { Date(timeIntervalSince1970: Double($0) / 1000) } }

    /// The light look: next week's sign-ups and whether I play this week.
    func refresh(state: AppState, force: Bool = false) async {
        guard let cloud = state.cloud, let uid = state.uid else { return }
        let now = nowMs
        let next = TournamentRules.nextWeek(nowMs: now), week = TournamentRules.currentWeek(nowMs: now)
        if uid != self.uid || week != currentWeek {
            self.uid = uid; currentWeek = week; current = []; currentLoaded = false; runs = []; settled = 0; runsReadAt = nil; readAt = nil
        }
        if !force, next == nextWeek, let readAt, Date().timeIntervalSince(readAt) < 60 { return }
        loading = true; defer { loading = false }
        do {
            nextWeek = next
            nextMine = try await cloud.isSignedUp(week: next, uid: uid)
            nextCount = try await cloud.tournamentCount(week: next)
            if !currentLoaded { currentMine = try await cloud.isSignedUp(week: week, uid: uid) }
            readAt = Date()
            if currentMine || currentLoaded { await loadBracket(state: state, force: force) }
        } catch { message = CloudError.message(error) }
    }

    /// The week under way: its players (once: they no longer change) and the runs still moving.
    func loadBracket(state: AppState, force: Bool = false) async {
        guard let cloud = state.cloud else { return }
        if !force, let runsReadAt, Date().timeIntervalSince(runsReadAt) < 60 { return }
        do {
            if !currentLoaded {
                current = try await cloud.tournamentPlayers(week: currentWeek)
                currentLoaded = true
                if let uid { currentMine = current.contains { $0.uid == uid } }
            }
            let now = nowMs
            let total = TournamentRules.rounds(players: min(current.count, TournamentRules.maxPlayers))
            guard total > 0, let start = TournamentRules.deadlineMs(week: currentWeek), now >= start else { return }
            let from = settled + 1
            guard from <= total else { return }
            let fresh = try await cloud.tournamentRuns(week: currentWeek, fromRound: from)
            runs = runs.filter { $0.round < from } + fresh
            runsReadAt = Date()
            settled = max(settled, (1...total).last { (TournamentRules.roundEndMs(week: currentWeek, round: $0) ?? .max) <= now } ?? 0)
        } catch { message = CloudError.message(error) }
    }

    func signUp(state: AppState) async {
        guard let cloud = state.cloud, let uid = state.uid, !nextWeek.isEmpty else { return }
        if state.isSuspended { message = CloudError.suspended.errorDescription; return }
        do {
            try await cloud.signUp(week: nextWeek, uid: uid, username: state.progress.username)
            nextMine = true; nextCount += 1; message = nil
        } catch { message = CloudError.message(error) }
    }
    func withdraw(state: AppState) async {
        guard let cloud = state.cloud, let uid = state.uid, !nextWeek.isEmpty else { return }
        do {
            try await cloud.withdraw(week: nextWeek, uid: uid)
            nextMine = false; nextCount = max(0, nextCount - 1); message = nil
        } catch { message = CloudError.message(error) }
    }

    /// My run of a round, just finished: no need to read everything again.
    func note(_ run: TournamentRun) {
        runs.removeAll { $0.round == run.round && $0.uid == run.uid }
        runs.append(run)
    }
    func run(round: Int, uid: String) -> TournamentRun? { runs.first { $0.round == round && $0.uid == uid } }
}

/// One tournament match on screen: my clock starts on the server when I begin, the 5 words of the round,
/// then my time is stamped by the server. A game left halfway resumes where it was (the clock kept going).
@MainActor @Observable final class TournamentPlaySession {
    enum Phase: Equatable { case ready, starting, playing, sending, done, failed(String) }

    let week: String
    let round: Int
    var phase: Phase = .ready
    var run: TournamentRun?
    var game: ChallengeGame?
    var clock = ServerClock()
    var answer = ""
    var answerWrong = false
    var cursor: Int?
    var mistakeTick = 0
    var successTick = 0
    var passed: String?
    var passedTick = 0

    init(week: String, round: Int) { self.week = week; self.round = round }

    private var saveKey: String { "tournament-\(week)-\(round)" }
    var nowMs: Int { clock.now(localMs: Int(Date().timeIntervalSince1970 * 1000)) }
    var endMs: Int { TournamentRules.roundEndMs(week: week, round: round) ?? 0 }
    var elapsedMs: Int { max(0, nowMs - (run?.startedMs ?? nowMs)) }

    /// A run already started (the app was closed): straight back into it.
    func resume(state: AppState) async {
        guard let uid = state.uid, let cloud = state.cloud else { return }
        if let known = state.tournament.run(round: round, uid: uid) {
            run = known
            if known.finishedMs != nil { phase = .done; return }
            await start(state: state)
        } else if let found = try? await cloud.tournamentRun(week: week, round: round, uid: uid) {
            run = found
            state.tournament.note(found)
            if found.finishedMs != nil { phase = .done } else { await start(state: state) }
        }
    }

    func start(state: AppState) async {
        guard let cloud = state.cloud, let uid = state.uid else { phase = .failed(CloudError.offline.errorDescription ?? ""); return }
        if state.isSuspended { phase = .failed(CloudError.suspended.errorDescription ?? ""); return }
        phase = .starting
        do {
            let started = try await cloud.startTournamentRound(week: week, round: round, uid: uid)
            if let learnt = started.clock { clock = learnt }
            run = started.run
            guard let cards = ChallengeRules.cards(started.cardIds) else { phase = .failed(CloudError.offline.errorDescription ?? ""); return }
            if let data = UserDefaults.standard.data(forKey: saveKey), let saved = try? JSONDecoder().decode(ChallengeGame.self, from: data),
               saved.cards.map(\.id) == cards.map(\.id) {
                game = saved
            } else {
                game = ChallengeGame(cards: cards)
                state.noteLiveDuelPlayed()
            }
            if game?.finished == true { await finish(state: state) } else { phase = .playing }
        } catch { phase = .failed(CloudError.message(error)) }
    }

    var playing: Bool { phase == .playing && game?.finished == false && nowMs < endMs }

    func press(_ letter: String) { guard playing else { return }; edit { $0.insert(letter) } }
    func delete() { edit { $0.deleteBackward() } }
    func clear() { edit { $0 = TypedAnswer(text: "") } }
    func moveCursor(by steps: Int) { edit { $0.move(by: steps) } }
    func placeCursor(_ index: Int) { edit { $0.place(index) } }
    private func edit(_ change: (inout TypedAnswer) -> Void) {
        var typed = TypedAnswer(text: answer, cursor: cursor)
        change(&typed)
        answer = typed.text; cursor = typed.cursor; answerWrong = false
    }

    func submit(state: AppState) {
        guard playing, var game, !WordEngine.normalize(answer).isEmpty else { mistakeTick += 1; return }
        switch game.answer(answer) {
        case .right: answer = ""; answerWrong = false; successTick += 1; Haptics.success()
        case .wrong: answerWrong = true; mistakeTick += 1; Haptics.retry()
        case .over: break
        }
        self.game = game
        moved(state: state)
    }

    func skip(state: AppState) {
        guard playing, var game else { return }
        answer = ""; answerWrong = false
        if let word = game.card?.wordFull { passed = word; passedTick += 1 }
        game.skip()
        self.game = game
        moved(state: state)
    }

    private func moved(state: AppState) {
        guard let game else { return }
        if let data = try? JSONEncoder().encode(game) { UserDefaults.standard.set(data, forKey: saveKey) }
        if game.finished { Task { await finish(state: state) } }
    }

    /// The server stamps the end; a failed send (network) can be tried again.
    func finish(state: AppState) async {
        guard let cloud = state.cloud, let uid = state.uid, let game else { return }
        phase = .sending
        do {
            let sent = try await cloud.finishTournamentRound(week: week, round: round, uid: uid, skips: game.skips, errors: game.errors)
            let fresh = try await cloud.tournamentRun(week: week, round: round, uid: uid)
            guard sent || fresh?.finishedMs != nil, let fresh else { phase = .failed(CloudError.offline.errorDescription ?? ""); return }
            run = fresh
            state.tournament.note(fresh)
            UserDefaults.standard.removeObject(forKey: saveKey)
            phase = .done
        } catch {
            // Already stamped (sent twice): read it back.
            if let fresh = try? await cloud.tournamentRun(week: week, round: round, uid: uid), fresh.finishedMs != nil {
                run = fresh; state.tournament.note(fresh); UserDefaults.standard.removeObject(forKey: saveKey); phase = .done
            } else { phase = .failed(CloudError.message(error)) }
        }
    }
}
