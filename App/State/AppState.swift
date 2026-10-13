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
        isRestoring = !RuntimeFlags.isTesting && progress.username.isEmpty && FirebaseRepository.hasSignedInUser
    }

    // MARK: Saving

    /// Saves on the device at once, then in the cloud shortly after (grouping quick successive changes).
    func persist() {
        guard savingAllowed else { return }
        do { try local.save(progress) } catch { self.error = "La progression n’a pas pu être enregistrée. Réessayez avant de quitter." }
        scheduleCloudSave()
    }
    private func scheduleCloudSave() {
        guard let cloud, let uid else { return }
        cloudSave?.cancel()
        cloudSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, self.uid == uid else { return }
            try? cloud.saveCloudProgress(self.progress, uid: uid)
        }
    }
    /// Brings the cloud copy and this device together, so a reinstall or a second iPhone finds everything.
    func syncProgress() async {
        guard let cloud, let uid else { return }
        do {
            if let remote = try await cloud.cloudProgress(uid: uid) {
                var merged = progress.merged(with: remote)
                merged.username = progress.username.isEmpty ? remote.username : progress.username
                progress = merged
            }
            persist()
        } catch { /* Offline: the next change or launch syncs again. */ }
    }

    // MARK: Session

    func start(username: String) async {
        guard !isBusy else { return }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...20).contains(name.count) else { error = "Choisissez un pseudo de 2 à 20 caractères."; return }
        isBusy = true
        defer { isBusy = false }
        if let cloud {
            do {
                let profile = try await cloud.bootstrap(username: name)
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
    }
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
        uid = nil; isAnonymous = true; email = nil; isAdmin = false; official = nil
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
        do {
            if let cloud, let uid { try await cloud.rename(uid: uid, username: name) }
            progress.username = name
            persist()
            await refreshOfficial()
        } catch { self.error = CloudError.message(error) }
    }
    /// Classic plays the built-in cards plus every approved community card.
    func refreshCards() async {
        guard let cloud, uid != nil else { return }
        do {
            let community = try await cloud.cards()
            let known = Set(SeedCards.all.map { WordEngine.normalize($0.wordFull) } + DailyPool.all.map { WordEngine.normalize($0.wordFull) })
            cards = SeedCards.all + community.filter { !known.contains(WordEngine.normalize($0.wordFull)) }
        } catch { /* Offline: the built-in cards remain. */ }
    }
    func card(id: String) -> Card? {
        if let published = publishedDaily, published.card.id == id { return published.card }
        return DailyPool.card(id: id) ?? cards.first(where: { $0.id == id }) ?? SeedCards.all.first(where: { $0.id == id })
    }

    // MARK: Mot du jour

    func dailyCard(day: String) -> Card? {
        if let published = publishedDaily, published.day == day { return published.card }
        return DailySchedule.dailyCard(forKey: day)
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
        if let entry = try? await cloud.leaderboardEntry(uid: uid) { official = entry }
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
