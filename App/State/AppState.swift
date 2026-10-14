import SwiftUI
import Observation
import CNSNNCore

@MainActor @Observable final class AppState {
    var progress = CNSNNCore.Progress()
    var cards = SeedCards.all
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
            || (merged.dailyWords?.count ?? 0) != (progress.dailyWords?.count ?? 0) || merged.rulesVersion != progress.rulesVersion else { return }
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
        uid = nil; isAnonymous = true; email = nil; isAdmin = false; isSuspended = false; official = nil
        progress = CNSNNCore.Progress(); cards = SeedCards.all
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
        let known = Set(SeedCards.all.map { WordEngine.normalize($0.wordFull) } + DailyPool.all.map { WordEngine.normalize($0.wordFull) })
        return SeedCards.all + community.filter { !known.contains(WordEngine.normalize($0.wordFull)) }
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
        return DailyPool.card(id: id) ?? cards.first(where: { $0.id == id }) ?? SeedCards.all.first(where: { $0.id == id })
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
