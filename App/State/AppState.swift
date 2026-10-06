import SwiftUI
import Observation
import CNSNNCore

@MainActor @Observable final class AppState {
    var progress = Progress()
    var cards = SeedCards.all
    var error: String?
    var isBusy = false
    var cloud: FirebaseRepository?
    var uid: String?
    var isAnonymous = true
    private var local: any ProgressRepository
    private var savingAllowed = true
    init(local: any ProgressRepository = LocalRepository()) {
        if RuntimeFlags.isTesting { self.local = MemoryRepository() } else { self.local = local }
        do { progress = try self.local.load() } catch { savingAllowed = false; self.error = "La sauvegarde locale est illisible. Elle n’a pas été écrasée." }
    }
    func persist() {
        guard savingAllowed else { return }
        do { try local.save(progress) } catch { self.error = "La progression n’a pas pu être enregistrée. Réessaie avant de quitter." }
    }
    func start(username: String) async {
        guard !isBusy else { return }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...20).contains(name.count) else { error = "Choisis un pseudo de 2 à 20 caractères."; return }
        isBusy = true
        defer { isBusy = false }
        if let cloud {
            do {
                let profile = try await cloud.bootstrap(username: name)
                try activate(profile, preservingGuest: true)
            } catch { self.error = "Connexion impossible : \(error.localizedDescription)"; return }
        }
        if cloud == nil { progress.username = name }
        persist()
        await refreshCards()
    }
    func connectIfConfigured() async {
        guard !RuntimeFlags.isTesting, FirebaseRepository.isConfigured else { return }
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        cloud = FirebaseRepository()
        guard !progress.username.isEmpty || cloud!.hasCurrentUser else { return }
        do {
            let profile = try await cloud!.bootstrap(username: progress.username.isEmpty ? "Joueur" : progress.username)
            try activate(profile, preservingGuest: true)
            await refreshCards()
        } catch { self.error = "Firebase est indisponible. Le jeu local reste accessible. \(error.localizedDescription)" }
    }
    func refreshCards() async {
        guard let cloud, uid != nil else { return }
        do {
            let publicCards = try await cloud.cards()
            cards = publicCards.isEmpty ? SeedCards.all : publicCards
        } catch {
            self.error = "Le catalogue en ligne est indisponible. Les cartes locales restent accessibles. \(error.localizedDescription)"
        }
    }
    func activate(_ profile: CloudProfile, preservingGuest: Bool) throws {
        if uid != profile.uid {
            let archive = LocalRepository(scope: profile.uid)
            let restored = try archive.load()
            if !restored.username.isEmpty { progress = restored }
            else if !preservingGuest { progress = Progress() }
            local = archive
        }
        uid = profile.uid; isAnonymous = profile.anonymous
        progress.username = profile.username; persist()
    }
    func signOut() throws {
        // Keep the current per-UID archive for a future login on this device.
        persist()
        try cloud?.signOut()
        uid = nil; isAnonymous = true; progress = Progress(); cards = SeedCards.all
        local = LocalRepository(); persist()
    }
    func rename(_ name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...20).contains(name.count) else { error = "Le pseudo doit contenir 2 à 20 caractères."; return }
        do {
            if let cloud, let uid { try await cloud.rename(uid: uid, username: name) }
            progress.username = name
            persist()
        } catch { self.error = error.localizedDescription }
    }
    func record(_ attempt: Attempt) {
        guard attempt.dailyKey == nil || !progress.attempts.contains(where: { $0.dailyKey == attempt.dailyKey }) else { return }
        progress.attempts.append(attempt)
        progress.recentCards.removeAll { $0 == attempt.cardID }
        progress.recentCards.append(attempt.cardID)
        progress.recentCards = Array(progress.recentCards.suffix(20))
        persist()
    }
    func submit(_ card: Card) async -> Bool {
        do {
            if let cloud, let uid { try await cloud.submit(card: card, uid: uid) }
            progress.submissions.append(Submission(card: card)); persist(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func refreshSubmissions() async {
        guard let cloud, let uid else { return }
        do { progress.submissions = try await cloud.submissions(uid: uid); persist() }
        catch { self.error = error.localizedDescription }
    }
}
