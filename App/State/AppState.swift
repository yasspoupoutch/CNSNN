import SwiftUI
import Observation
import CNSNNCore

@MainActor @Observable final class AppState {
    var progress = CNSNNCore.Progress()
    var cards = SeedCards.all + ExtraCards.all
    var error: String?
    var isBusy = false
    var cloud: FirebaseRepository?
    var uid: String?
    var isAnonymous = true
    var email: String?
    var isAdmin = false
    /// A moderator suspended this account: no ranked daily, proposals or reports.
    var isSuspended = false
    /// Official totals from the leaderboard, when signed in.
    var official: LeaderboardEntry?
    /// Today's word when a moderator published one, replacing the built-in schedule.
    var publishedDaily: (day: String, card: Card)?
    /// True while a returning player's profile is being fetched at launch: hide onboarding meanwhile.
    var isRestoring = false
    /// Friend challenges sent and received (see Core/Challenge.swift).
    var challenges: [Challenge] = []
    /// Asks the home page to open the challenge sheet (from the daily result).
    var challengeRequest = 0
    /// The code of a challenge link the app was opened with, waiting for the challenge sheet to join it.
    var inviteCode: String?
    /// Asks the shell to show the leaderboard (from the home page).
    var leaderboardRequest = 0
    private var local: any ProgressRepository
    private var savingAllowed = true
    private var cloudSave: Task<Void, Never>?
    init(local: any ProgressRepository = LocalRepository()) {
        if RuntimeFlags.isTesting { self.local = MemoryRepository() } else { self.local = local }
        do { progress = try self.local.load() } catch { savingAllowed = false; self.error = "La sauvegarde locale est illisible. Elle n’a pas été écrasée." }
        if !RuntimeFlags.isTesting, let cached = CardCache.load() { cards = Self.catalogue(community: cached.cards) }
        isRestoring = !RuntimeFlags.isTesting && progress.username.isEmpty && FirebaseRepository.hasSignedInUser
    }

    // MARK: Saving

    /// Saves on the device at once, then in the cloud shortly after (grouping quick successive changes).
    func persist() {
        guard savingAllowed else { return }
        do { try local.save(progress) } catch { self.error = "La progression n’a pas pu être enregistrée. Réessayez avant de quitter." }
        scheduleCloudSave()
        refreshGlance()
    }
    /// Home screen widget and daily reminders.
    func refreshGlance(force: Bool = false) {
        Reminders.update(progress: progress, streak: official?.currentStreak() ?? progress.streak(), force: force)
    }
    private func scheduleCloudSave() {
        guard let cloud, let uid else { return }
        cloudSave?.cancel()
        cloudSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, self.uid == uid else { return }
            await self.syncProgress()
        }
    }
    /// Brings the cloud copy and this device together, so a reinstall or a second device finds everything.
    /// The cloud copy is merged in a transaction, never overwritten: games saved by another device in the
    /// meantime are kept. Offline, nothing is written and the next change, launch or return to the app syncs again.
    func syncProgress() async {
        guard let cloud, let uid else { return }
        guard let merged = try? await cloud.saveCloudProgress(progress, uid: uid), self.uid == uid else { return }
        adopt(merged)
    }
    /// Takes in what another device saved. Saved on this device only: the cloud already has it.
    private func adopt(_ cloudCopy: CNSNNCore.Progress) {
        let merged = progress.merged(with: cloudCopy)
        guard merged.attempts.count != progress.attempts.count || merged.submissions.count != progress.submissions.count
            || (merged.dailyWords?.count ?? 0) != (progress.dailyWords?.count ?? 0) || merged.rulesVersion != progress.rulesVersion
            || merged.modes != progress.modes else { return }
        progress = merged
        guard savingAllowed else { return }
        try? local.save(progress)
        refreshGlance()
    }

    // MARK: Session

    func start(username: String) async {
        guard !isBusy else { return }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...20).contains(name.count) else { error = "Choisissez un pseudo de 2 à 20 caractères."; return }
        guard NameFilter.isAllowed(name) else { error = AppState.refusedName; return }
        isBusy = true
        defer { isBusy = false }
        if let cloud {
            do {
                let profile = try await cloud.bootstrap(username: name, rulesVersion: progress.rulesVersion)
                try activate(profile, preservingGuest: true)
            } catch { self.error = "Connexion impossible : " + CloudError.message(error); return }
        }
        if cloud == nil { progress.username = name }
        // Interface tests: today's word already found, the longest one and in hours, to check the home card fits.
        if RuntimeFlags.isTesting, ProcessInfo.processInfo.arguments.contains("--daily-found"),
           let card = ModeCatalogue.cards.max(by: { $0.wordFull.count < $1.wordFull.count }) {
            progress.attempts.append(Attempt(cardID: card.id, mode: .daily, correct: true, timeMs: 71_485_000, points: 50,
                                             date: Date(), dailyKey: DailySchedule.key()))
        }
        persist()
        await refreshAll()
    }
    func connectIfConfigured() async {
        defer { isRestoring = false }
        guard !RuntimeFlags.isTesting, FirebaseRepository.isConfigured else { return }
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        cloud = FirebaseRepository()
        guard !progress.username.isEmpty || cloud!.hasCurrentUser else { return }
        do {
            let profile = try await cloud!.bootstrap(username: progress.username.isEmpty ? "Joueur" : progress.username)
            try activate(profile, preservingGuest: true)
        } catch CloudError.deletionPending {
            await resumeDeletion(); return
        } catch {
            // Offline launches stay quiet: Classique works and the home screen says it is offline.
            if ![CloudError.Code.network, .unavailable].contains(CloudError.code(error)), !(error is CloudError) { self.error = CloudError.message(error) }
            return
        }
        await refreshAll()
    }
    /// Everything that follows a successful sign-in.
    func refreshAll() async {
        await syncProgress()
        await refreshCards()
        await refreshDailyChallenge()
        await finishPendingDaily()
        await refreshOfficial()
        await refreshChallenges()
        isAdmin = (try? await cloud?.isAdmin()) ?? false
        if let cloud, let uid { isSuspended = (try? await cloud.isSuspended(uid: uid)) ?? isSuspended }
    }
    static let refusedName = "Ce pseudo n’est pas autorisé. Choisissez-en un autre."
    static let suspendedText = "Votre compte est suspendu par la modération : le mot du jour classé, les propositions et les signalements ne sont plus disponibles. Contactez le support depuis votre profil."

    func activate(_ profile: CloudProfile, preservingGuest: Bool) throws {
        if uid != profile.uid {
            let archive = LocalRepository(scope: profile.uid)
            let restored = try archive.load()
            if !restored.username.isEmpty { progress = preservingGuest ? restored.merged(with: progress) : restored }
            else if !preservingGuest { progress = CNSNNCore.Progress() }
            local = archive
        }
        uid = profile.uid; isAnonymous = profile.anonymous; email = profile.email
        progress.username = profile.username; persist()
    }
    func signOut() throws {
        // Keep the current per-UID archive for a future login on this device.
        persist()
        cloudSave?.cancel()
        try cloud?.signOut()
        resetToGuest()
    }
    private func resetToGuest() {
        ModeRunStore.clearAll()
        uid = nil; isAnonymous = true; email = nil; isAdmin = false; isSuspended = false; official = nil; challenges = []; challengesReadAt = nil; rankings = Rankings()
        ChallengeWatch.setActive(false)
        progress = CNSNNCore.Progress(); cards = SeedCards.all + ExtraCards.all
        local = LocalRepository(); persist()
    }

    // MARK: Accounts

    /// Saves the guest as a permanent account (same UID, nothing moves).
    func createAccount(email: String, password: String) async throws {
        guard let cloud else { return }
        let profile = try await cloud.createPermanentAccount(email: email, password: password)
        try activate(profile, preservingGuest: true)
        await refreshAll()
    }
    /// Switches to an existing account. The guest's practice games on this iPhone join that account;
    /// official daily results stay with the profile that played them.
    func signIn(email: String, password: String) async throws {
        guard let cloud else { return }
        var guestPractice = progress
        guestPractice.attempts = guestPractice.attempts.filter { $0.mode == .classic }
        guestPractice.dailyStarted = [:]; guestPractice.dailyStartedAt = [:]; guestPractice.submissions = []
        persist()
        let profile: CloudProfile
        do { profile = try await cloud.signIn(email: email, password: password) }
        catch CloudError.deletionPending { await resumeDeletion(); return }
        try activate(profile, preservingGuest: false)
        progress = progress.merged(with: guestPractice)
        progress.username = profile.username
        persist()
        await refreshAll()
    }
    /// Deletes the account and everything stored for it, online and on this iPhone.
    func deleteAccount(password: String?) async throws {
        guard let cloud, let uid else { return }
        cloudSave?.cancel()
        try await cloud.deleteAccount(uid: uid, password: password)
        LocalRepository(scope: uid).erase()
        LocalRepository().erase()
        ChallengeCache.clear(uid: uid)
        UserDefaults.standard.removeObject(forKey: CNSNNTheme.avatarKey)
        resetToGuest()
    }

    /// Finishes a deletion that was cut off halfway (the profile is gone, the tombstone is there):
    /// at launch, or when the player signs in again. Nothing is brought back.
    func resumeDeletion() async {
        guard let cloud, let id = cloud.currentUID else { return }
        do {
            try await cloud.deleteAccount(uid: id, password: nil)
            error = "La suppression de votre compte est terminée."
        } catch where CloudError.code(error) == .requiresRecentLogin {
            // The data is gone; only the sign-in remains, and Firebase wants a fresh password for it.
            try? cloud.signOut()
            self.error = "Vos données sont supprimées. Reconnectez-vous une fois avec votre email pour supprimer aussi le compte."
        } catch {
            // Offline: still signed in, so the next launch tries again.
            self.error = "La suppression de votre compte n’est pas terminée. Elle reprendra au prochain lancement avec du réseau."
            return
        }
        LocalRepository(scope: id).erase()
        ChallengeCache.clear(uid: id)
        UserDefaults.standard.removeObject(forKey: CNSNNTheme.avatarKey)
        resetToGuest()
    }

    // MARK: Profile and catalogue

    func rename(_ name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...20).contains(name.count) else { error = "Le pseudo doit contenir 2 à 20 caractères."; return }
        guard NameFilter.isAllowed(name) else { error = AppState.refusedName; return }
        do {
            if let cloud, let uid { try await cloud.rename(uid: uid, username: name) }
            progress.username = name
            persist()
            await refreshOfficial()
        } catch { self.error = CloudError.message(error) }
    }
    /// Classic plays the built-in cards plus every approved community card. The community cards are kept
    /// on this device and downloaded again only when a moderator changed the catalogue (`meta/cards`),
    /// so a launch costs one read instead of one per card on the free plan.
    func refreshCards() async {
        guard let cloud, uid != nil else { return }
        do {
            let cached = CardCache.load()
            let version = try await cloud.cardsVersion()
            if let cached, cached.isCurrent(version: version) { cards = Self.catalogue(community: cached.cards); return }
            let community = try await cloud.cards()
            CardCache.save(CardCache(version: version ?? 0, savedAt: Date(), cards: community))
            cards = Self.catalogue(community: community)
        } catch { /* Offline: the cards kept on this device remain. */ }
    }
    private static func catalogue(community: [Card]) -> [Card] {
        let known = Set((SeedCards.all + ExtraCards.all).map { WordEngine.normalize($0.wordFull) } + DailyPool.all.map { WordEngine.normalize($0.wordFull) })
        return SeedCards.all + ExtraCards.all + community.filter { !known.contains(WordEngine.normalize($0.wordFull)) }
    }

    // MARK: Community rules

    /// The player has a pseudo but has not accepted the current community rules yet.
    var needsRulesAcceptance: Bool { !progress.username.isEmpty && (progress.rulesVersion ?? 0) < CommunityRules.version }
    func acceptRules() {
        progress.rulesVersion = CommunityRules.version
        persist()
        if let cloud, let uid { cloud.acceptRules(uid: uid, version: CommunityRules.version) }
    }
    func card(id: String) -> Card? {
        if let day = FirebaseRepository.secretDay(cardID: id) { return progress.dailyWords?[day] }
        if let published = publishedDaily, published.card.id == id { return published.card }
        return DailyPool.card(id: id) ?? cards.first(where: { $0.id == id }) ?? ModeCatalogue.cards.first(where: { $0.id == id })
    }

    // MARK: Mot du jour

    func dailyCard(day: String) -> Card? {
        if let published = publishedDaily, published.day == day { return published.card }
        return DailySchedule.dailyCard(forKey: day)
    }
    /// Keeps a secret daily word on this iPhone: masked while playing, revealed once the game is over.
    func storeDailyWord(_ card: Card, day: String) {
        if let known = progress.dailyWords?[day], !known.wordFull.isEmpty, card.wordFull.isEmpty { return }
        var words = progress.dailyWords ?? [:]
        words[day] = card
        progress.dailyWords = words.filter { $0.key >= DailySchedule.key(Date().addingTimeInterval(-400 * 86_400)) }
        persist()
    }
    func refreshDailyChallenge() async {
        let day = DailySchedule.key()
        guard let cloud, uid != nil, let card = try? await cloud.dailyChallenge(day: day) else { return }
        publishedDaily = (day, card)
    }
    /// Publishes results whose finish reached the server but whose result did not (app closed, network lost).
    func finishPendingDaily() async {
        guard let cloud, let uid else { return }
        let now = Date()
        for day in [DailySchedule.key(DailySchedule.previousDay(now)), DailySchedule.key(now)] {
            guard let session = try? await cloud.dailySession(uid: uid, day: day), session.finished,
                  let official = try? await cloud.publishDailyResult(uid: uid, day: day) else { continue }
            recordOfficial(official)
        }
    }
    func refreshOfficial() async {
        guard let cloud, let uid else { return }
        if let entry = try? await cloud.leaderboardEntry(uid: uid) { official = entry; refreshGlance() }
    }

    /// The public rankings, kept a few minutes: everybody reads the same lines, so opening the page
    /// again (or switching tabs back and forth) costs nothing until they may have moved.
    struct Rankings {
        var today: [DailyRank] = []
        var players: [LeaderboardEntry] = []
        var fastest: [LeaderboardEntry] = []
        var myRank: (rank: Int, players: Int)?
        var friends: [FriendStanding] = []
        var friendCode: String?
        /// Friends in the list when it was last read, to notice one who typed my code since.
        var friendCount: Int?
        var readAt: [String: Date] = [:]
    }
    var rankings = Rankings()
    /// A new friend: the friends ranking is read again next time it shows.
    func forgetFriendsRanking() { rankings.readAt = rankings.readAt.filter { !$0.key.hasPrefix("friends-") } }
    /// Whether a ranking needs reading: after 5 minutes, or 30 seconds when the player pulls to refresh.
    func rankingIsStale(_ key: String, force: Bool) -> Bool {
        guard let at = rankings.readAt[key] else { return true }
        return Date().timeIntervalSince(at) > (force ? 30 : 300)
    }

    // MARK: Results

    func record(_ attempt: Attempt) {
        guard attempt.dailyKey == nil || !progress.attempts.contains(where: { $0.dailyKey == attempt.dailyKey }) else { return }
        if attempt.dailyKey != nil { rankings.readAt = [:] }
        progress.attempts.append(attempt)
        progress.recentCards.removeAll { $0 == attempt.cardID }
        progress.recentCards.append(attempt.cardID)
        progress.recentCards = Array(progress.recentCards.suffix(20))
        persist()
    }
    /// The server's result replaces this device's measurement for that day.
    func recordOfficial(_ attempt: Attempt) {
        guard let day = attempt.dailyKey else { return }
        rankings.readAt = [:]
        if let index = progress.attempts.firstIndex(where: { $0.dailyKey == day }) {
            var official = attempt
            official.id = progress.attempts[index].id
            progress.attempts[index] = official
            persist()
        } else {
            record(attempt)
        }
    }

    // MARK: Sprint, Survie, Double sens

    /// Adds a finished game to the personal records (never to the official leaderboard), saves it on
    /// this device and soon in the cloud. Returns the records it beat.
    @discardableResult func recordMode(_ mode: PlayMode, best: [String: Int], add: [String: Int]) -> Set<String> {
        let beaten = progress.recordMode(mode, best: best, add: add, device: ModeRunStore.deviceID)
        persist()
        return beaten
    }
    /// A Sprint whose app was closed during play is over: it counts as it stood (its clock never stops).
    func finishInterruptedSprint() {
        guard let run = ModeRunStore.load(.sprint), var game = run.sprint else { return }
        ModeRunStore.clear(.sprint)
        game.stop()
        recordMode(.sprint, best: game.records.best, add: game.records.add)
    }

    // MARK: Friend challenges

    private var challengesReadAt: Date?
    /// Reads the challenges of the last two days only (a few documents) and keeps the older ones on
    /// the phone, since a challenge never changes after its 50 hours. The whole list is read on the
    /// first launch and then once a week. Back-to-back calls (home, return to the app) share one read.
    func refreshChallenges(force: Bool = false) async {
        guard let cloud, let uid else { return }
        if !force, let challengesReadAt, Date().timeIntervalSince(challengesReadAt) < 30 { return }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let cached = ChallengeCache.load(uid: uid)
        let list: [Challenge]
        var fullAt = cached?.fullAtMs ?? 0
        if let cached, now - cached.fullAtMs < ChallengeRules.fullRefreshMs {
            guard let recent = try? await cloud.recentChallenges(uid: uid, nowMs: now) else { return }
            list = ChallengeRules.merge(cached: cached.challenges, recent: recent, nowMs: now)
        } else {
            guard let all = try? await cloud.challenges(uid: uid) else { return }
            list = all; fullAt = now
        }
        guard self.uid == uid else { return }
        challengesReadAt = Date()
        ChallengeWatch.noteRead()
        ChallengeCache.save(.init(challenges: list, fullAtMs: fullAt), uid: uid)
        challenges = list
        ChallengeWatch.markSeen(list, uid: uid)
        await sendPendingChallenges(list, uid: uid)
        await befriendJoiners(list, uid: uid)
        // Background checks only for players someone can challenge (one read, once a week at most).
        if !list.isEmpty { ChallengeWatch.setActive(true) }
        else if fullAt == now { ChallengeWatch.setActive((try? await cloud.hasFriends(uid: uid)) ?? ChallengeWatch.isActive) }
    }
    /// The challenge the home tile shows: a friend's challenge to play first (the closest deadline),
    /// then one of mine left unfinished, then the latest one waiting for the friend.
    func featuredChallenge(now: Int = Int(Date().timeIntervalSince1970 * 1000)) -> (challenge: Challenge, state: Challenge.State)? {
        guard let uid else { return nil }
        let open = challenges.compactMap { c -> (Challenge, Challenge.State)? in
            let state = c.state(for: uid, now: now)
            if case .over = state { return nil }
            return ChallengeRules.cards(c.cardIds) == nil ? nil : (c, state)
        }
        if let turn = open.filter({ $0.1 == .yourTurn }).min(by: { $0.0.createdMs < $1.0.createdMs }) { return turn }
        if let playing = open.first(where: { $0.1 == .playing }) { return playing }
        return open.first { $0.1 == .waiting }
    }
    func challengeTally(friend: String? = nil) -> ChallengeTally {
        guard let uid else { return ChallengeTally() }
        return ChallengeTally.of(challenges, me: uid, friend: friend, now: Int(Date().timeIntervalSince1970 * 1000))
    }
    /// Draws 5 public words (avoiding the player's recent ones) and starts the challenger's clock.
    func sendChallenge(to friend: String, name: String) async throws -> Challenge {
        guard let cloud, let uid else { throw CloudError.offline }
        if isSuspended { throw CloudError.suspended }
        let ids = ChallengeRules.draw(seed: ModeRandom.seed(), recent: progress.recentCards)
        let challenge = try await cloud.createChallenge(uid: uid, username: progress.username, friend: friend, friendName: name, cardIDs: ids)
        challenges.insert(challenge, at: 0)
        ChallengeWatch.setActive(true)
        return challenge
    }
    /// A challenge by link: same words and clock as for a friend, but anyone with the code can join.
    func sendOpenChallenge() async throws -> Challenge {
        guard let cloud, let uid else { throw CloudError.offline }
        if isSuspended { throw CloudError.suspended }
        let ids = ChallengeRules.draw(seed: ModeRandom.seed(), recent: progress.recentCards)
        let challenge = try await cloud.createOpenChallenge(uid: uid, username: progress.username, cardIDs: ids)
        challenges.insert(challenge, at: 0)
        ChallengeWatch.setActive(true)
        return challenge
    }
    /// Joins a challenge by its code (typed, or from an opened link); its author becomes a friend.
    func joinChallenge(code: String) async throws -> Challenge {
        guard let cloud, let uid else { throw CloudError.offline }
        if isSuspended { throw CloudError.suspended }
        let challenge = try await cloud.joinChallenge(code: code, uid: uid, username: progress.username)
        replace(challenge)
        forgetFriendsRanking()
        ChallengeWatch.setActive(true)
        return challenge
    }
    /// Whoever joined my challenges by link becomes a friend too, once (remembered on the phone).
    private func befriendJoiners(_ list: [Challenge], uid: String) async {
        guard let cloud else { return }
        let key = "challenge.befriended." + uid
        var done = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        for c in list where c.code != nil && c.from.uid == uid && !c.isOpen && !done.contains(c.id) {
            guard (try? await cloud.addFriend(uid: uid, friend: c.to.uid, name: c.to.name)) != nil else { continue }
            done.insert(c.id)
            forgetFriendsRanking()
        }
        UserDefaults.standard.set(Array(done), forKey: key)
    }
    /// Starts (or resumes) my side of a challenge: the friend's clock starts on the server here.
    func startChallenge(_ challenge: Challenge) async throws -> Challenge {
        guard let cloud, let uid else { throw CloudError.offline }
        let fresh = challenge.to.uid == uid ? try await cloud.startChallenge(challenge, uid: uid) : challenge
        replace(fresh)
        ChallengeWatch.setActive(true)
        return fresh
    }
    /// What the server made of a finished challenge game.
    enum ChallengeSend { case confirmed, pending, expired }
    /// Sends the finish, then reads the challenge back: only the server's copy says it counts. Sending
    /// twice is harmless (the rules accept one finish), so a retry after a lost answer is safe.
    func finishChallenge(_ challenge: Challenge, skips: Int, errors: Int) async -> (Challenge, ChallengeSend) {
        guard let cloud, let uid else { return (challenge, .pending) }
        var refused = false
        do { _ = try await cloud.finishChallenge(challenge, uid: uid, skips: skips, errors: errors) }
        catch { refused = CloudError.code(error) == .permissionDenied }
        guard let fresh = try? await cloud.challenge(id: challenge.id) else { return (challenge, .pending) }
        replace(fresh)
        if fresh.mine(uid).finished { return (fresh, .confirmed) }
        if refused && Int(Date().timeIntervalSince1970 * 1000) >= fresh.finishDeadlineMs() { return (fresh, .expired) }
        return (fresh, .pending)
    }
    /// Finished games the server has not confirmed yet (network lost, app closed): sent again.
    private func sendPendingChallenges(_ list: [Challenge], uid: String) async {
        for challenge in list where !challenge.mine(uid).finished {
            guard let run = ChallengeStore.load(challenge.id), run.game.finished else { continue }
            let (_, outcome) = await finishChallenge(challenge, skips: run.game.skips, errors: run.game.errors)
            if outcome != .pending { ChallengeStore.clear(challenge.id) }
        }
    }
    private func replace(_ challenge: Challenge) {
        if let index = challenges.firstIndex(where: { $0.id == challenge.id }) { challenges[index] = challenge } else { challenges.insert(challenge, at: 0) }
    }

    // MARK: Community

    func submit(_ card: Card) async -> Bool {
        do {
            var stored = card
            let word = WordEngine.normalize(card.wordFull)
            if (cards + DailyPool.all).contains(where: { WordEngine.normalize($0.wordFull) == word }) { throw CloudError.duplicateWord }
            if cloud != nil && uid == nil { throw CloudError.offline }
            if let cloud, let uid { stored = try await cloud.submit(card: card, uid: uid) }
            else if progress.submissions.contains(where: { WordEngine.normalize($0.card.wordFull) == WordEngine.normalize(card.wordFull) }) {
                throw CloudError.duplicateWord
            }
            progress.submissions.append(Submission(card: stored)); persist(); return true
        } catch { self.error = CloudError.message(error); return false }
    }
    func refreshSubmissions() async {
        guard let cloud, let uid else { return }
        do { progress.submissions = try await cloud.submissions(uid: uid); persist() }
        catch { /* Offline: keep the last known statuses. */ }
    }
}
