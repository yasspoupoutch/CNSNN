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
        uid = nil; isAnonymous = true; email = nil; isAdmin = false; isSuspended = false; official = nil; challenges = []
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
        let profile = try await cloud.signIn(email: email, password: password)
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

    // MARK: Results

    func record(_ attempt: Attempt) {
        guard attempt.dailyKey == nil || !progress.attempts.contains(where: { $0.dailyKey == attempt.dailyKey }) else { return }
        progress.attempts.append(attempt)
        progress.recentCards.removeAll { $0 == attempt.cardID }
        progress.recentCards.append(attempt.cardID)
        progress.recentCards = Array(progress.recentCards.suffix(20))
        persist()
    }
    /// The server's result replaces this device's measurement for that day.
    func recordOfficial(_ attempt: Attempt) {
        guard let day = attempt.dailyKey else { return }
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

    func refreshChallenges() async {
        guard let cloud, let uid else { return }
        if let list = try? await cloud.challenges(uid: uid), self.uid == uid { challenges = list }
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
        return challenge
    }
    /// Starts (or resumes) my side of a challenge: the friend's clock starts on the server here.
    func startChallenge(_ challenge: Challenge) async throws -> Challenge {
        guard let cloud, let uid else { throw CloudError.offline }
        let fresh = challenge.to.uid == uid ? try await cloud.startChallenge(challenge, uid: uid) : challenge
        replace(fresh)
        return fresh
    }
    /// Stamps my finish on the server, then reads back the official times.
    func finishChallenge(_ challenge: Challenge, skips: Int, errors: Int) async -> Challenge {
        guard let cloud, let uid else { return challenge }
        _ = try? await cloud.finishChallenge(challenge, uid: uid, skips: skips, errors: errors)
        guard let fresh = try? await cloud.challenge(id: challenge.id) else { return challenge }
        replace(fresh)
        return fresh
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
