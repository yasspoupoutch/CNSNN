import Foundation
import Observation
import FirebaseFirestore
import CNSNNCore

/// A live duel on screen: looking for a random opponent, or waiting for a friend with a link, then the
/// 3-2-1, the 5 words and the result. The duel's document is listened to the whole time (one read per
/// change), so each player sees the other move forward. Times are the server's (Core/LiveDuel.swift).
@MainActor @Observable final class LiveDuelSession {
    enum Start: Equatable {
        /// A random opponent: from the waiting line.
        case random
        /// A link to send to a friend.
        case link
        /// A friend's duel, from its code.
        case join(String)
    }
    enum Phase: Equatable {
        case connecting
        /// Looking for a random opponent; since when (this phone's clock).
        case searching(Date)
        /// Nobody was looking at the same time.
        case nobody
        /// The link is ready: waiting for the friend.
        case waiting
        /// The duel itself: its state says countdown, playing, finished or over.
        case live
        case failed(String)
    }

    let start: Start
    var phase: Phase = .connecting
    var duel: LiveDuel?
    var game: ChallengeGame?
    var clock = ServerClock()
    var answer = ""
    var answerWrong = false
    var cursor: Int?
    var mistakeTick = 0
    var successTick = 0
    var passed: String?
    var passedTick = 0
    private var duelListener: ListenerRegistration?
    private var queueListener: ListenerRegistration?
    private var searchTask: Task<Void, Never>?
    private var counted = false

    init(start: Start) { self.start = start }

    /// The server's time now, as well as this phone can tell.
    var nowMs: Int { clock.now(localMs: Int(Date().timeIntervalSince1970 * 1000)) }
    func state(uid: String?) -> LiveDuel.State? {
        guard let duel, let uid else { return nil }
        return duel.state(for: uid, now: nowMs)
    }
    /// My time so far: since the start, plus 20 s per word passed.
    var elapsedMs: Int {
        guard let start = duel?.startMs else { return 0 }
        return max(0, nowMs - start)
    }

    func begin(state: AppState) async {
        // Pictures only (offline): the invented duel plays on its own.
        if ScreenshotDemo.duelActive { demo(state: state); return }
        guard let cloud = state.cloud, let uid = state.uid else { phase = .failed(CloudError.offline.errorDescription ?? ""); return }
        if state.isSuspended { phase = .failed(CloudError.suspended.errorDescription ?? ""); return }
        phase = .connecting
        do {
            switch start {
            case .link:
                let ids = LiveDuelRules.draw(seed: ModeRandom.seed(), recent: state.progress.recentCards)
                let made = try await cloud.createLinkDuel(uid: uid, username: state.progress.username, cardIDs: ids)
                if let learnt = made.clock { clock = learnt }
                watch(made.duel, state: state)
                phase = .waiting
            case .join(let id):
                let joined = try await cloud.joinDuel(id: id, uid: uid, username: state.progress.username)
                if let learnt = joined.clock { clock = learnt }
                watch(joined.duel, state: state)
            case .random:
                await search(state: state)
            }
        } catch { phase = .failed(CloudError.message(error)) }
    }

    // MARK: Pictures (`--duel-demo`, tests only)

    /// An invented duel against Léa, played on its own: the search, the 3-2-1, both players moving
    /// forward (she passes a word and finishes first, then you), and the result. Nothing is sent.
    private func demo(state: AppState) {
        let uid = state.uid ?? ScreenshotDemo.uid
        let now = { Int(Date().timeIntervalSince1970 * 1000) }
        if start == .link {
            duel = LiveDuel(id: "demo", cardIds: ChallengeRules.draw(seed: 21), createdMs: now(),
                            from: .init(uid: uid, name: state.progress.username), to: .init(uid: "", name: ""), code: "K7M2QX")
            phase = .waiting
            return
        }
        phase = .searching(Date())
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled else { return }
            let startMs = now() + LiveDuelRules.countdownMs
            let found = LiveDuel(id: "demo", cardIds: ChallengeRules.draw(seed: 21), createdMs: now(), startMs: startMs,
                                 from: .init(uid: uid, name: state.progress.username), to: .init(uid: "demo-lea", name: "Léa"))
            self.apply(found, state: state)
            try? await Task.sleep(for: .milliseconds(LiveDuelRules.countdownMs))
            // Every 0.5 s: Léa moves every 3 s (a word passed, then the finish at 15 s), and you every 4 s,
            // the next answer half typed in between.
            var lea = 0, me = 0
            for tick in 1...40 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, var current = self.duel, var game = self.game else { return }
                let elapsed = tick * 500
                if elapsed % 3_000 == 0, lea < ChallengeRules.words {
                    lea += 1
                    current.to.done = lea
                    if lea == 2 { current.to.skips = 1 }
                    if lea == ChallengeRules.words { current.to.finishedMs = startMs + elapsed }
                }
                if elapsed % 4_000 == 0, me < ChallengeRules.words, let card = game.card {
                    me += 1
                    game.answer(card.wordFull)
                    self.answer = ""
                    self.successTick += 1
                    current.from.done = me
                    if me == ChallengeRules.words { current.from.finishedMs = startMs + elapsed }
                } else if elapsed % 4_000 == 1_500, let card = game.card {
                    self.answer = String(card.wordFull.uppercased().prefix(3))
                }
                self.game = game
                self.duel = current
                if me == ChallengeRules.words { return }
            }
        }
    }

    // MARK: Random opponent

    private func search(state: AppState) async {
        guard let cloud = state.cloud, let uid = state.uid else { return }
        let since = Date()
        phase = .searching(since)
        let username = state.progress.username
        do {
            if let taken = try await cloud.takeOpponent(uid: uid, username: username, cardIDs: draw(state), clock: clock) {
                if let learnt = taken.clock { clock = learnt }
                watch(taken.duel, state: state)
                return
            }
            if let learnt = try await cloud.enterDuelQueue(uid: uid, username: username) { clock = learnt }
        } catch { phase = .failed(CloudError.message(error)); return }
        queueListener = cloud.listenDuelQueue(uid: uid) { [weak self] id in
            Task { @MainActor in self?.taken(id, state: state) }
        }
        // Someone may have come in at the same moment: a new look now and then, then give up.
        searchTask = Task { [weak self] in
            while Date().timeIntervalSince(since) * 1000 < Double(LiveDuelRules.searchMs) {
                try? await Task.sleep(for: .milliseconds(LiveDuelRules.searchEveryMs))
                guard let self, self.isSearching, !Task.isCancelled else { return }
                if let taken = try? await cloud.takeOpponent(uid: uid, username: username, cardIDs: self.draw(state), clock: self.clock) {
                    self.stopQueue()
                    if let learnt = taken.clock { self.clock = learnt }
                    self.watch(taken.duel, state: state)
                    return
                }
            }
            guard let self, self.isSearching, !Task.isCancelled else { return }
            self.queueListener?.remove(); self.queueListener = nil
            if let id = await cloud.leaveDuelQueue(uid: uid) { self.taken(id, state: state) } else { self.phase = .nobody }
        }
    }
    var isSearching: Bool { if case .searching = phase { return true }; return false }
    private func draw(_ state: AppState) -> [String] { LiveDuelRules.draw(seed: ModeRandom.seed(), recent: state.progress.recentCards) }

    private func taken(_ id: String, state: AppState) {
        guard duel == nil, let cloud = state.cloud else { return }
        stopQueue()
        Task {
            guard let found = try? await cloud.duel(id: id) else { phase = .failed(CloudError.offline.errorDescription ?? ""); return }
            if let uid = state.uid { _ = await cloud.leaveDuelQueue(uid: uid) }
            watch(found, state: state)
        }
    }
    private func stopQueue() {
        searchTask?.cancel(); searchTask = nil
        queueListener?.remove(); queueListener = nil
    }
    /// Looks again (after "personne pour l'instant").
    func searchAgain(state: AppState) {
        guard start == .random else { return }
        Task { await search(state: state) }
    }

    // MARK: The duel

    private func watch(_ found: LiveDuel, state: AppState) {
        apply(found, state: state)
        guard let cloud = state.cloud, duelListener == nil else { return }
        duelListener = cloud.listenDuel(id: found.id) { [weak self] fresh in
            Task { @MainActor in
                guard let self else { return }
                if let fresh { self.apply(fresh, state: state) }
                else if self.duel?.isOpen == true { self.phase = .failed(CloudError.duelGone.errorDescription ?? "") }
            }
        }
    }
    private func apply(_ fresh: LiveDuel, state: AppState) {
        duel = fresh
        if fresh.isOpen { phase = .waiting; return }
        phase = .live
        if game == nil, let cards = ChallengeRules.cards(fresh.cardIds) {
            game = ChallengeGame(cards: cards)
            if !counted { counted = true; state.noteLiveDuelPlayed() }
        }
    }

    var playing: Bool {
        guard phase == .live, let duel, let uid = myUID else { return false }
        return duel.state(for: uid, now: nowMs) == .playing && game?.finished == false
    }
    /// Set by the screen from the app state (the session does not keep the app state).
    var myUID: String?

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
        send(state: state)
    }

    func skip(state: AppState) {
        guard playing, var game else { return }
        answer = ""; answerWrong = false
        if let word = game.card?.wordFull { passed = word; passedTick += 1 }
        game.skip()
        self.game = game
        send(state: state)
    }

    /// My total so far, after each word: the other player sees it at once.
    private func send(state: AppState) {
        guard let cloud = state.cloud, let uid = state.uid, let duel, let game else { return }
        let done = game.index
        guard done > duel.mine(uid).done else { return }
        cloud.moveInDuel(duel, uid: uid, done: done, skips: game.skips) { _ in }
    }
    /// A finish the server did not take (network): sent again.
    func resend(state: AppState) { send(state: state) }

    /// Leaving before the end loses the duel; a link nobody joined is withdrawn.
    func leave(state: AppState) {
        stopQueue()
        if let cloud = state.cloud, let uid = state.uid {
            if case .searching = phase { Task { _ = await cloud.leaveDuelQueue(uid: uid) } }
            if let duel {
                if duel.isOpen && duel.from.uid == uid { Task { await cloud.cancelLinkDuel(duel) } }
                else if !duel.isOpen, duel.result(for: uid, now: nowMs) == nil, !duel.mine(uid).finished { cloud.quitDuel(duel, uid: uid) }
            }
        }
        duelListener?.remove(); duelListener = nil
    }
}
