import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import CNSNNCore

struct CloudProfile { let uid: String; let anonymous: Bool; let username: String; var email: String? = nil }
struct CardReport: Identifiable { let id: String; let cardID: String; let reason: String; var word: String? }
/// A pseudo reported from the leaderboard.
struct PlayerReport: Identifiable { let id: String; let playerID: String; let username: String; let reason: String }
/// A player a moderator suspended.
struct SuspendedPlayer: Identifiable { let id: String; let username: String; let reason: String }

/// Official totals of one player (`leaderboard/{uid}`), only ever moved by the security rules' checks.
struct LeaderboardEntry: Identifiable, Equatable {
    var id: String { uid }
    let uid: String
    let username: String
    let points: Int
    let played: Int
    let wins: Int
    let streak: Int
    let bestStreak: Int
    let bestTimeMs: Int?
    let lastWinDay: String
    /// The stored streak only counts while the last win is today or yesterday.
    func currentStreak(at date: Date = Date()) -> Int {
        lastWinDay == DailySchedule.key(date) || lastWinDay == DailySchedule.key(DailySchedule.previousDay(date)) ? streak : 0
    }
    var successRate: Double { played == 0 ? 0 : Double(wins) / Double(played) }
}

/// One line of the friends ranking: the player's totals and today's Mot du jour, when played.
struct FriendStanding: Identifiable, Equatable {
    var id: String { uid }
    let uid: String
    let username: String
    let points: Int
    let streak: Int
    let today: Attempt?
    /// Wrong guesses on today's word, when the player has a result.
    var todayWrong: Int? = nil

    static func == (a: FriendStanding, b: FriendStanding) -> Bool {
        a.uid == b.uid && a.username == b.username && a.points == b.points && a.streak == b.streak
            && a.today?.timeMs == b.today?.timeMs && a.today?.correct == b.today?.correct
    }
    /// Found today first (fastest first), then the others by points.
    static func ordered(_ rows: [FriendStanding]) -> [FriendStanding] {
        rows.sorted { a, b in
            let fa = a.today?.correct == true, fb = b.today?.correct == true
            if fa != fb { return fa }
            if fa, let ta = a.today?.timeMs, let tb = b.today?.timeMs, ta != tb { return ta < tb }
            if a.points != b.points { return a.points > b.points }
            return a.username.localizedCaseInsensitiveCompare(b.username) == .orderedAscending
        }
    }
}

/// One line of the day's ranking.
struct DailyRank: Identifiable, Equatable {
    var id: String { uid }
    let uid: String
    let username: String
    let timeMs: Int
    let points: Int
    let usedHint: Bool
    var wrongAnswers = 0
}

/// Where a finished daily result stands among today's players.
struct DailyStanding: Equatable {
    let rank: Int?
    let players: Int
    /// Share of the other players this result beat (slower or not found). Nil when alone.
    let beatenPercent: Int?
    /// "Top X %" badge: the share of today's players at or above this rank, rounded up to
    /// 1, 5, 10, 25 or 50 %. Nil for the fastest player (shown as number 1) and the slower half.
    var topPercent: Int? {
        guard let rank, rank > 1, players > 1 else { return nil }
        let share = Double(rank) * 100 / Double(players)
        return [1, 5, 10, 25, 50].first { share <= Double($0) }
    }
}

/// Server state of today's Mot du jour for the signed-in player.
struct DailySessionState {
    let day: String
    let cardID: String
    let startedAt: Date
    let hintUsed: Bool
    let finished: Bool
    /// Guesses registered on the server (firestore.rules allows `DailyGuesses.max` a day).
    var guesses = 0
}

enum DailyGuesses {
    static let max = 20
}

@MainActor final class FirebaseRepository {
    static var isConfigured: Bool { FirebaseApp.app() != nil }
    /// A Firebase account survives reinstalls (keychain), so a returning player can be restored.
    static var hasSignedInUser: Bool { isConfigured && Auth.auth().currentUser != nil }
    static func configureIfPresent() {
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else { return }
        FirebaseApp.configure()
    }
    #if DEBUG
    /// Integration tests only: points the SDK at the local Firebase emulators (Firebase/firebase.json).
    static func configureForEmulator(projectID: String) {
        guard FirebaseApp.app() == nil else { return }
        let options = FirebaseOptions(googleAppID: "1:123456789012:ios:0123456789abcdef", gcmSenderID: "123456789012")
        options.projectID = projectID
        options.apiKey = "emulator-api-key"
        FirebaseApp.configure(options: options)
        Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
        let settings = Firestore.firestore().settings
        settings.host = "127.0.0.1:8080"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
    }
    var currentUID: String? { auth.currentUser?.uid }
    /// Integration tests only: cuts or restores the connection, like a network outage.
    func setNetwork(enabled: Bool) async throws {
        if enabled { try await db.enableNetwork() } else { try await db.disableNetwork() }
    }
    #endif
    private var auth: Auth { Auth.auth() }
    var hasCurrentUser: Bool { auth.currentUser != nil }
    var currentEmail: String? { auth.currentUser?.email }
    private var db: Firestore { Firestore.firestore() }

    // MARK: Profile

    func bootstrap(username: String, rulesVersion: Int? = nil) async throws -> CloudProfile {
        let user: User
        if let current = auth.currentUser { user = current }
        else { user = try await auth.signInAnonymously().user }
        let ref = db.collection("users").document(user.uid)
        // Falls back to the cached profile offline, so a returning player keeps their identity.
        let doc = try await ref.getDocument()
        if !doc.exists {
            guard !doc.metadata.isFromCache else { throw CloudError.offline }
            var data: [String: Any] = ["uid":user.uid,"username":username,"createdAt":FieldValue.serverTimestamp(),"updatedAt":FieldValue.serverTimestamp(),"score":0,"gamesPlayed":0,"correctAnswers":0,"bestTimeMs":NSNull(),"currentStreak":0]
            if let rulesVersion { data["rulesVersion"] = rulesVersion; data["rulesAcceptedAt"] = FieldValue.serverTimestamp() }
            try await ref.setData(data)
        }
        return CloudProfile(uid:user.uid,anonymous:user.isAnonymous,username:doc.data()?["username"] as? String ?? username,email:user.email)
    }
    /// Renames the profile and, in the same batch, the public leaderboard line.
    func rename(uid: String, username: String) async throws {
        let batch = db.batch()
        batch.updateData(["username":username,"updatedAt":FieldValue.serverTimestamp()], forDocument: db.collection("users").document(uid))
        if try await leaderboardEntry(uid: uid) != nil {
            batch.updateData(["username":username,"updatedAt":FieldValue.serverTimestamp()], forDocument: db.collection("leaderboard").document(uid))
        }
        try await batch.commit()
    }

    /// Records that the player accepted the community rules (best effort: the app keeps its own copy).
    func acceptRules(uid: String, version: Int) {
        db.collection("users").document(uid).updateData(["rulesVersion": version, "rulesAcceptedAt": FieldValue.serverTimestamp()])
    }

    // MARK: Accounts

    /// Turns the guest into a permanent account. Linking keeps the UID, so nothing is lost.
    func createPermanentAccount(email: String, password: String) async throws -> CloudProfile {
        let credential = EmailAuthProvider.credential(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        if let current = auth.currentUser {
            guard current.isAnonymous else { throw CloudError.permanentAccountAlreadyConnected }
            _ = try await current.link(with: credential)
        } else {
            _ = try await auth.createUser(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        }
        return try await bootstrap(username: "Joueur")
    }
    func signIn(email: String, password: String) async throws -> CloudProfile {
        _ = try await auth.signIn(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        return try await bootstrap(username: "Joueur")
    }
    func resetPassword(email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func signOut() throws { try auth.signOut() }

    /// Deletes every document the player owns, then the Firebase account itself.
    /// Permanent accounts must confirm their password first (Firebase requires a recent login).
    func deleteAccount(uid: String, password: String?) async throws {
        guard let user = auth.currentUser, user.uid == uid else { throw CloudError.authentication }
        if let password, let email = user.email {
            _ = try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: password))
        }
        var refs: [DocumentReference] = [
            db.collection("users").document(uid),
            db.collection("users").document(uid).collection("private").document("progress"),
            db.collection("leaderboard").document(uid),
        ]
        refs += try await db.collection("users").document(uid).collection("friends").getDocuments(source: .server).documents.map(\.reference)
        refs += try await db.collection("friendCodes").whereField("uid", isEqualTo: uid).getDocuments(source: .server).documents.map(\.reference)
        for (collection, field) in [("dailyResults", "userId"), ("dailySessions", "userId"), ("reports", "userId"), ("playerReports", "userId"),
                                    ("challenges", "from"), ("challenges", "to")] {
            refs += try await db.collection(collection).whereField(field, isEqualTo: uid).getDocuments(source: .server).documents.map(\.reference)
        }
        // Approved cards stay in the game without the author's name or id; the other proposals go.
        let authored = try await db.collection("cards").whereField("createdBy", isEqualTo: uid).getDocuments(source: .server).documents
        refs += authored.filter { $0.data()["status"] as? String != "approved" }.map(\.reference)
        let live = authored.filter { $0.data()["status"] as? String == "approved" }.map(\.reference)
        // The profile goes first, with the tombstone that lets friends drop this account and the
        // suspension record: the rules only let the daily history and the rest go once it is gone.
        var writes: [BatchWrite] = [.set(["deletedAt": FieldValue.serverTimestamp()], db.collection("deletedUsers").document(uid)),
                                    .delete(db.collection("banned").document(uid))]
        writes += refs.map { BatchWrite.delete($0) }
        writes += live.map { BatchWrite.update(["createdBy": "deleted", "authorName": FieldValue.delete()], $0) }
        try await commit(writes)
        // Reports naming this player can only be read once the profile is gone.
        let about = try await db.collection("playerReports").whereField("playerId", isEqualTo: uid).getDocuments(source: .server).documents
        try await commit(about.map { BatchWrite.delete($0.reference) })
        do { try await user.delete() }
        catch where CloudError.code(error) == .requiresRecentLogin && user.isAnonymous {
            // A guest cannot sign in again: its data is already gone, so simply leave the account.
            try auth.signOut()
        }
    }

    enum BatchWrite {
        case set([String: Any], DocumentReference)
        case update([String: Any], DocumentReference)
        case delete(DocumentReference)
    }
    /// Commits writes in order, 400 per batch (Firestore allows 500).
    private func commit(_ writes: [BatchWrite]) async throws {
        for start in stride(from: 0, to: writes.count, by: 400) {
            let batch = db.batch()
            for write in writes[start..<min(start + 400, writes.count)] {
                switch write {
                case let .set(data, ref): batch.setData(data, forDocument: ref)
                case let .update(data, ref): batch.updateData(data, forDocument: ref)
                case let .delete(ref): batch.deleteDocument(ref)
                }
            }
            try await batch.commit()
        }
    }

    // MARK: Synced progress (practice, not official)

    private func progressRef(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid).collection("private").document("progress")
    }
    func cloudProgress(uid: String) async throws -> CNSNNCore.Progress? {
        let snapshot = try await progressRef(uid).getDocument()
        guard let json = snapshot.data()?["json"] as? String else { return nil }
        return try JSONDecoder().decode(CNSNNCore.Progress.self, from: Data(json.utf8))
    }
    /// Merges this device's progress into the cloud copy in a transaction, so another device's games
    /// saved in the meantime are never overwritten. Returns the merged copy. Needs the network:
    /// offline, nothing is written and the next sync tries again.
    func saveCloudProgress(_ progress: CNSNNCore.Progress, uid: String) async throws -> CNSNNCore.Progress {
        let ref = progressRef(uid)
        let merged = try await Self.transact(db) { transaction in
            let snapshot = try transaction.getDocument(ref)
            var merged = progress
            if let json = snapshot.data()?["json"] as? String {
                merged = progress.merged(with: try JSONDecoder().decode(CNSNNCore.Progress.self, from: Data(json.utf8)))
            }
            let data = try JSONEncoder().encode(merged)
            guard data.count <= 900_000 else { throw CloudError.progressTooLarge }
            transaction.setData(["json": String(decoding: data, as: UTF8.self), "schema": 1, "updatedAt": FieldValue.serverTimestamp()], forDocument: ref)
            return data
        }
        guard let data = merged as? Data else { throw CloudError.offline }
        return try JSONDecoder().decode(CNSNNCore.Progress.self, from: data)
    }

    // MARK: Mot du jour

    private func sessionRef(_ uid: String, _ day: String) -> DocumentReference { db.collection("dailySessions").document(uid + "_" + day) }
    private func resultRef(_ uid: String, _ day: String) -> DocumentReference { db.collection("dailyResults").document(uid + "_" + day) }

    /// A word published by a moderator for that day, which replaces the built-in schedule.
    func dailyChallenge(day: String) async throws -> Card? {
        let doc = try await db.collection("dailyChallenges").document(day).getDocument()
        guard let d = doc.data(), let id = d["cardId"] as? String, let word = d["wordFull"] as? String, let hint = d["hint"] as? String,
              let category = CNSNNCore.Category(rawValue: d["category"] as? String ?? ""),
              let difficulty = Difficulty(rawValue: d["difficulty"] as? String ?? "") else { return nil }
        return Card(id: id, wordFull: word, hint: hint, category: category, difficulty: difficulty)
    }
    // Secret daily words: the server gives the consonants, the hint once revealed and the word
    // once the game is over. A win is accepted only with the right answer (firestore.rules).
    nonisolated static func secretCardID(day: String) -> String { "secret-" + day }
    nonisolated static func secretDay(cardID: String) -> String? {
        cardID.hasPrefix("secret-") ? String(cardID.dropFirst("secret-".count)) : nil
    }
    func dailyPuzzle(day: String) async throws -> Card? {
        let doc = try await db.collection("dailyPuzzles").document(day).getDocument()
        guard let d = doc.data(), let consonants = d["consonants"] as? String, !consonants.isEmpty,
              let category = CNSNNCore.Category(rawValue: d["category"] as? String ?? ""),
              let difficulty = Difficulty(rawValue: d["difficulty"] as? String ?? "") else { return nil }
        return Card(id: Self.secretCardID(day: day), wordFull: "", hint: "", category: category, difficulty: difficulty, masked: consonants)
    }
    func dailyHint(day: String) async throws -> String? {
        try await db.collection("dailyHints").document(day).getDocument().data()?["hint"] as? String
    }
    func dailySecret(day: String) async throws -> Card? {
        let doc = try await db.collection("dailySecrets").document(day).getDocument()
        guard let d = doc.data(), let word = d["word"] as? String, let hint = d["hint"] as? String,
              let category = CNSNNCore.Category(rawValue: d["category"] as? String ?? ""),
              let difficulty = Difficulty(rawValue: d["difficulty"] as? String ?? "") else { return nil }
        return Card(id: Self.secretCardID(day: day), wordFull: word, hint: hint, category: category, difficulty: difficulty)
    }
    func publishDailyChallenge(day: String, card: Card) async throws {
        guard let uid = auth.currentUser?.uid else { throw CloudError.authentication }
        try await db.collection("dailyChallenges").document(day).setData(["cardId":card.id,"wordFull":card.wordFull,"hint":card.hint,"category":card.category.rawValue,"difficulty":card.difficulty.rawValue,"publishedBy":uid,"publishedAt":FieldValue.serverTimestamp()])
    }

    func dailySession(uid: String, day: String) async throws -> DailySessionState? {
        let doc = try await sessionRef(uid, day).getDocument(source: .server)
        return doc.data().flatMap { Self.session(day: day, $0) }
    }
    /// Starts today's clock on the server. Only returns once the server has recorded the start,
    /// so the consonants are never shown before the official timer runs.
    func startDaily(uid: String, day: String, cardID: String) async throws -> DailySessionState {
        let ref = sessionRef(uid, day)
        let acknowledged = try await Self.awaitWrite { done in
            ref.setData(["userId":uid,"day":day,"cardId":cardID,"startedAt":FieldValue.serverTimestamp(),"hintUsed":false], completion: done)
        }
        guard acknowledged, let session = try await dailySession(uid: uid, day: day) else { throw CloudError.offline }
        return session
    }
    func revealDailyHint(uid: String, day: String) {
        sessionRef(uid, day).updateData(["hintUsed": true])
    }
    /// Records the hint on the server first, since the rules open the hint only after that.
    func revealSecretHint(uid: String, day: String) async throws -> String? {
        let ref = sessionRef(uid, day)
        guard try await Self.awaitWrite({ done in ref.updateData(["hintUsed": true], completion: done) }) else { return nil }
        return try await dailyHint(day: day)
    }
    /// Counts a guess on the server before it can be checked (at most 20 a day, one per second), so a
    /// script cannot try answers until one is accepted. Returns the number of guesses made today.
    func registerGuess(uid: String, day: String, guess: String) async throws -> Int {
        let ref = sessionRef(uid, day)
        let count = try await Self.transact(db) { transaction in
            let data = try transaction.getDocument(ref).data() ?? [:]
            let next = (data["guesses"] as? Int ?? 0) + 1
            guard data["finishedAt"] == nil, next <= DailyGuesses.max else { throw CloudError.noGuessesLeft }
            transaction.updateData(["guesses": next, "guess": guess, "guessAt": FieldValue.serverTimestamp()], forDocument: ref)
            return next
        }
        guard let count = count as? Int else { throw CloudError.offline }
        return count
    }
    /// Stamps the finish with the server time. Returns false if the network did not confirm in time:
    /// the write stays queued and the official result is published on a later launch.
    /// For a secret word, `answer` is the normalized guess: the server refuses a wrong one (permission denied).
    func finishDaily(uid: String, day: String, correct: Bool, wrongAnswers: Int, answer: String? = nil) async throws -> Bool {
        let ref = sessionRef(uid, day)
        var data: [String: Any] = ["finishedAt":FieldValue.serverTimestamp(),"correct":correct,"wrongAnswers":wrongAnswers]
        if let answer { data["answer"] = answer }
        let payload = data
        return try await Self.awaitWrite { done in ref.updateData(payload, completion: done) }
    }
    func dailyResult(uid: String, day: String) async throws -> Attempt? {
        let doc = try await resultRef(uid, day).getDocument(source: .server)
        return doc.data().flatMap { Self.attempt(day: day, $0) }
    }
    /// Publishes the official result of a finished session together with the leaderboard tally,
    /// exactly as the security rules recompute them. Returns the existing result if already published.
    func publishDailyResult(uid: String, day: String) async throws -> Attempt? {
        if let existing = try await dailyResult(uid: uid, day: day) { return existing }
        let sessionDoc = try await sessionRef(uid, day).getDocument(source: .server)
        guard let s = sessionDoc.data(), let started = s["startedAt"] as? Timestamp, let finished = s["finishedAt"] as? Timestamp,
              let cardID = s["cardId"] as? String else { return nil }
        let correct = s["correct"] as? Bool ?? false, usedHint = s["hintUsed"] as? Bool ?? false, wrong = s["wrongAnswers"] as? Int ?? 0
        let timeMs = Self.millis(finished) - Self.millis(started)
        guard let difficulty = DailySchedule.difficulty(forKey: day) else { return nil }
        let points = Scoring.points(difficulty: difficulty, timeMs: timeMs, usedHint: usedHint, correct: correct)
        let profile = try await db.collection("users").document(uid).getDocument(source: .server)
        let username = profile.data()?["username"] as? String ?? "Joueur"
        let old = try await leaderboardEntry(uid: uid, source: .server)
        let tally = Self.tally(old: old, uid: uid, username: username, day: day, correct: correct, timeMs: timeMs, points: points)
        let result: [String: Any] = ["userId":uid,"username":username,"day":day,"cardId":cardID,"correct":correct,"usedHint":usedHint,
                                     "wrongAnswers":wrong,"timeMs":timeMs,"points":points,"startedAt":started,"finishedAt":finished]
        let batch = db.batch()
        batch.setData(result, forDocument: resultRef(uid, day))
        batch.setData(tally, forDocument: db.collection("leaderboard").document(uid))
        _ = try await Self.awaitWrite { done in batch.commit(completion: done) }
        return Attempt(cardID: cardID, mode: .daily, correct: correct, timeMs: timeMs, points: points, date: finished.dateValue(), dailyKey: day)
    }

    // MARK: Leaderboard

    func leaderboardEntry(uid: String, source: FirestoreSource = .default) async throws -> LeaderboardEntry? {
        let doc = try await db.collection("leaderboard").document(uid).getDocument(source: source)
        return doc.data().flatMap { Self.entry(uid: uid, $0) }
    }
    // Rankings show 25 lines: a few more are read so suspended players can be left out.
    func topPlayers(limit: Int = 25) async throws -> [LeaderboardEntry] {
        let docs = try await db.collection("leaderboard").order(by: "points", descending: true).limit(to: limit + 10).getDocuments().documents
        return Array(docs.filter(Self.visible).compactMap { Self.entry(uid: $0.documentID, $0.data()) }.prefix(limit))
    }
    func fastestPlayers(limit: Int = 25) async throws -> [LeaderboardEntry] {
        let docs = try await db.collection("leaderboard").whereField("bestTimeMs", isGreaterThan: 0).order(by: "bestTimeMs").limit(to: limit + 10).getDocuments().documents
        return Array(docs.filter(Self.visible).compactMap { Self.entry(uid: $0.documentID, $0.data()) }.prefix(limit))
    }
    /// A suspended player's totals and results stay stored but are hidden from everyone else.
    private static func visible(_ doc: QueryDocumentSnapshot) -> Bool { doc.data()["suspended"] as? Bool != true }
    /// Rank by official points among every player.
    func rank(points: Int) async throws -> (rank: Int, players: Int) {
        let board = db.collection("leaderboard")
        let ahead = try await Self.count(board.whereField("points", isGreaterThan: points))
        return (ahead + 1, try await Self.count(board))
    }
    func dailyRanking(day: String, limit: Int = 25) async throws -> [DailyRank] {
        let docs = try await db.collection("dailyResults").whereField("day", isEqualTo: day).whereField("correct", isEqualTo: true)
            .order(by: "timeMs").limit(to: limit + 10).getDocuments().documents
        return Array(docs.filter(Self.visible).compactMap(Self.rank).prefix(limit))
    }
    /// Moderation: today's wins under 5 s, too fast to be read and typed by hand.
    func suspiciousResults(day: String) async throws -> [DailyRank] {
        let docs = try await db.collection("dailyResults").whereField("day", isEqualTo: day).whereField("correct", isEqualTo: true)
            .whereField("timeMs", isLessThan: 5000).order(by: "timeMs").limit(to: 20).getDocuments(source: .server).documents
        return docs.filter(Self.visible).compactMap(Self.rank)
    }
    private static func rank(_ doc: QueryDocumentSnapshot) -> DailyRank? {
        let d = doc.data()
        guard let uid = d["userId"] as? String, let timeMs = d["timeMs"] as? Int else { return nil }
        return DailyRank(uid: uid, username: d["username"] as? String ?? "Joueur", timeMs: timeMs, points: d["points"] as? Int ?? 0, usedHint: d["usedHint"] as? Bool ?? false,
                         wrongAnswers: d["wrongAnswers"] as? Int ?? 0)
    }
    /// "Plus rapide que 98 % des joueurs": players who were slower or did not find the word,
    /// among everyone else who played today.
    func standing(day: String, timeMs: Int, correct: Bool) async throws -> DailyStanding {
        let today = db.collection("dailyResults").whereField("day", isEqualTo: day)
        let players = try await Self.count(today)
        guard correct else { return DailyStanding(rank: nil, players: players, beatenPercent: nil) }
        let missed = try await Self.count(today.whereField("correct", isEqualTo: false))
        let slower = try await Self.count(today.whereField("correct", isEqualTo: true).whereField("timeMs", isGreaterThan: timeMs))
        let faster = try await Self.count(today.whereField("correct", isEqualTo: true).whereField("timeMs", isLessThan: timeMs))
        let others = players - 1
        return DailyStanding(rank: faster + 1, players: players, beatenPercent: others > 0 ? min(100, (slower + missed) * 100 / others) : nil)
    }
    private static func count(_ query: Query) async throws -> Int {
        try await query.count.getAggregation(source: .server).count.intValue
    }

    // MARK: Friends

    /// Letters and digits that cannot be confused when read aloud or typed (no I, O, 0, 1).
    nonisolated static let friendCodeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    nonisolated static func normalizedFriendCode(_ text: String) -> String {
        String(text.uppercased().filter { friendCodeAlphabet.contains($0) }.prefix(6))
    }
    /// The player's friend code, created on first use. The code is the document id, so it is unique.
    func friendCode(uid: String, username: String) async throws -> String {
        let mine = try await db.collection("friendCodes").whereField("uid", isEqualTo: uid).limit(to: 1).getDocuments(source: .server)
        if let existing = mine.documents.first { return existing.documentID }
        for _ in 0..<5 {
            let code = String((0..<6).map { _ in Self.friendCodeAlphabet.randomElement()! })
            let ref = db.collection("friendCodes").document(code)
            do {
                let saved = try await Self.awaitWrite { done in
                    ref.setData(["uid": uid, "username": username, "createdAt": FieldValue.serverTimestamp()], completion: done)
                }
                guard saved else { throw CloudError.offline }
                return code
            } catch where CloudError.code(error) == .permissionDenied {
                continue // Taken by someone else: draw another code.
            }
        }
        throw CloudError.offline
    }
    /// Adds the owner of a friend code to the player's friends. Returns the friend's pseudo.
    func addFriend(code: String, uid: String) async throws -> String {
        let code = Self.normalizedFriendCode(code)
        guard code.count == 6 else { throw CloudError.friendNotFound }
        let doc = try await db.collection("friendCodes").document(code).getDocument(source: .server)
        guard let data = doc.data(), let friend = data["uid"] as? String else { throw CloudError.friendNotFound }
        guard friend != uid else { throw CloudError.friendIsYou }
        let name = try await leaderboardEntry(uid: friend, source: .server)?.username ?? data["username"] as? String ?? "Joueur"
        let ref = db.collection("users").document(uid).collection("friends").document(friend)
        let saved = try await Self.awaitWrite { done in
            ref.setData(["username": name, "addedAt": FieldValue.serverTimestamp()], completion: done)
        }
        guard saved else { throw CloudError.offline }
        return name
    }
    func removeFriend(uid: String, friend: String) async throws {
        try await db.collection("users").document(uid).collection("friends").document(friend).delete()
    }
    /// The friends' ids and names only (one read each, for the challenge list).
    func friends(uid: String) async throws -> [(uid: String, name: String)] {
        let docs = try await db.collection("users").document(uid).collection("friends").limit(to: 100).getDocuments(source: .server).documents
        return docs.map { (uid: $0.documentID, name: $0.data()["username"] as? String ?? "Joueur") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    /// The player and their friends, with today's Mot du jour result for each.
    func friendsBoard(uid: String, username: String, day: String) async throws -> [FriendStanding] {
        let friends = try await db.collection("users").document(uid).collection("friends").limit(to: 100).getDocuments(source: .server).documents
        var players: [(uid: String, name: String)] = friends.map { (uid: $0.documentID, name: $0.data()["username"] as? String ?? "Joueur") }
        players.insert((uid: uid, name: username), at: 0)
        var rows: [FriendStanding] = []
        for player in players {
            let doc = try await db.collection("leaderboard").document(player.uid).getDocument(source: .server)
            let entry = doc.data().flatMap { Self.entry(uid: player.uid, $0) }
            if player.uid != uid {
                // A friend who deleted their account leaves the list for good (deleted accounts have no totals).
                if entry == nil, try await db.collection("deletedUsers").document(player.uid).getDocument(source: .server).exists {
                    try? await removeFriend(uid: uid, friend: player.uid)
                    continue
                }
                if doc.data()?["suspended"] as? Bool == true { continue }
            }
            let data = try await resultRef(player.uid, day).getDocument(source: .server).data()
            let today = data.flatMap { Self.attempt(day: day, $0) }
            rows.append(FriendStanding(uid: player.uid, username: entry?.username ?? player.name, points: entry?.points ?? 0,
                                       streak: entry?.currentStreak() ?? 0, today: today, todayWrong: data?["wrongAnswers"] as? Int))
        }
        return FriendStanding.ordered(rows)
    }

    // MARK: Friend challenges

    /// Sends a challenge to a friend and starts the challenger's clock on the server at once.
    func createChallenge(uid: String, username: String, friend: String, friendName: String, cardIDs: [String]) async throws -> Challenge {
        let random = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        let ref = db.collection("challenges").document(ChallengeRules.newId(nowMs: Int(Date().timeIntervalSince1970 * 1000), random: random))
        let data: [String: Any] = ["from": uid, "fromName": username, "to": friend, "toName": friendName, "cardIds": cardIDs,
                                   "createdAt": FieldValue.serverTimestamp(), "fromStartedAt": FieldValue.serverTimestamp()]
        guard try await Self.awaitWrite({ done in ref.setData(data, completion: done) }), let challenge = try await self.challenge(id: ref.documentID) else { throw CloudError.offline }
        return challenge
    }
    /// Starts the friend's clock (once), and adds the challenger to their friends so the scores show up.
    func startChallenge(_ challenge: Challenge, uid: String) async throws -> Challenge {
        let ref = db.collection("challenges").document(challenge.id)
        if challenge.to.startedMs == nil {
            guard try await Self.awaitWrite({ done in ref.updateData(["toStartedAt": FieldValue.serverTimestamp()], completion: done) }) else { throw CloudError.offline }
            let friend = db.collection("users").document(uid).collection("friends").document(challenge.from.uid)
            let known = try await friend.getDocument(source: .server).exists
            if !known {
                try? await friend.setData(["username": challenge.from.name, "addedAt": FieldValue.serverTimestamp()])
            }
        }
        guard let fresh = try await self.challenge(id: challenge.id) else { throw CloudError.offline }
        return fresh
    }
    /// Stamps the finish with the server time. False if the network did not confirm in time (the write stays queued).
    func finishChallenge(_ challenge: Challenge, uid: String, skips: Int, errors: Int) async throws -> Bool {
        let side = challenge.from.uid == uid ? "from" : "to"
        let ref = db.collection("challenges").document(challenge.id)
        let data: [String: Any] = [side + "FinishedAt": FieldValue.serverTimestamp(), side + "Skips": skips, side + "Errors": errors]
        return try await Self.awaitWrite { done in ref.updateData(data, completion: done) }
    }
    func challenge(id: String) async throws -> Challenge? {
        let doc = try await db.collection("challenges").document(id).getDocument(source: .server)
        return doc.data().flatMap { Self.challenge(id: id, $0) }
    }
    /// The challenges sent and received, newest first (equality queries only: no composite index needed).
    func challenges(uid: String) async throws -> [Challenge] {
        var all: [Challenge] = []
        for field in ["from", "to"] {
            let docs = try await db.collection("challenges").whereField(field, isEqualTo: uid).limit(to: 200).getDocuments(source: .server).documents
            all += docs.compactMap { Self.challenge(id: $0.documentID, $0.data()) }
        }
        return all.sorted { $0.createdMs > $1.createdMs }
    }
    /// The challenges of the last ~52 hours, the only ones a notification can be about. The ids start
    /// with the time, so a cursor on the id keeps this to a few reads (no composite index needed).
    func recentChallenges(uid: String, nowMs: Int) async throws -> [Challenge] {
        var all: [Challenge] = []
        for field in ["from", "to"] {
            let docs = try await db.collection("challenges").whereField(field, isEqualTo: uid).order(by: FieldPath.documentID())
                .start(after: [ChallengeRules.recentFromId(nowMs: nowMs)]).limit(to: 50).getDocuments(source: .server).documents
            all += docs.compactMap { Self.challenge(id: $0.documentID, $0.data()) }
        }
        return all
    }
    /// One read: whether this player has at least one friend to be challenged by.
    func hasFriends(uid: String) async throws -> Bool {
        let docs = try await db.collection("users").document(uid).collection("friends").limit(to: 1).getDocuments(source: .server).documents
        return !docs.isEmpty
    }
    nonisolated static func challenge(id: String, _ d: [String: Any]) -> Challenge? {
        guard let from = d["from"] as? String, let to = d["to"] as? String, let ids = d["cardIds"] as? [String],
              let created = d["createdAt"] as? Timestamp else { return nil }
        func ms(_ key: String) -> Int? { (d[key] as? Timestamp).map(millis) }
        return Challenge(id: id, cardIds: ids, createdMs: millis(created),
                         from: .init(uid: from, name: d["fromName"] as? String ?? "Joueur", startedMs: ms("fromStartedAt"), finishedMs: ms("fromFinishedAt"),
                                     skips: d["fromSkips"] as? Int ?? 0, errors: d["fromErrors"] as? Int ?? 0),
                         to: .init(uid: to, name: d["toName"] as? String ?? "Joueur", startedMs: ms("toStartedAt"), finishedMs: ms("toFinishedAt"),
                                   skips: d["toSkips"] as? Int ?? 0, errors: d["toErrors"] as? Int ?? 0))
    }

    // MARK: Cards

    /// Version of the approved catalogue (`meta/cards`), moved by moderators: the cards are downloaded
    /// again only when it changed, which saves the free plan's daily reads. Nil when never set.
    func cardsVersion() async throws -> Int? {
        let doc = try await db.collection("meta").document("cards").getDocument(source: .server)
        return (doc.data()?["updatedAt"] as? Timestamp).map(Self.millis)
    }
    func cards() async throws -> [Card] {
        let snap = try await db.collection("cards").whereField("status",isEqualTo:"approved").limit(to:500).getDocuments(source: .server)
        return snap.documents.compactMap { decode($0.documentID,$0.data()) }
    }
    private func bumpCardsVersion(_ batch: WriteBatch) {
        batch.setData(["updatedAt": FieldValue.serverTimestamp()], forDocument: db.collection("meta").document("cards"))
    }
    /// Proposes a card under its normalized word, which makes duplicates impossible,
    /// and consumes the anti-spam quota (30 s apart, 10 per 24 h) in the same batch.
    func submit(card: Card, uid: String) async throws -> Card {
        let id = WordEngine.normalize(card.wordFull)
        let ref = db.collection("cards").document(id)
        do {
            if try await ref.getDocument(source: .server).exists { throw CloudError.duplicateWord }
        } catch where CloudError.code(error) == .permissionDenied {
            // Someone else's pending or refused proposal: it exists but is private.
            throw CloudError.duplicateWord
        }
        let userRef = db.collection("users").document(uid)
        let profile = try await userRef.getDocument(source: .server).data() ?? [:]
        var quota: [String: Any] = ["updatedAt": FieldValue.serverTimestamp(), "lastProposalAt": FieldValue.serverTimestamp()]
        if let last = (profile["lastProposalAt"] as? Timestamp)?.dateValue(), Date().timeIntervalSince(last) < 31 { throw CloudError.proposalTooSoon }
        if let window = profile["proposalWindowAt"] as? Timestamp, Date().timeIntervalSince(window.dateValue()) < 24 * 3600 - 60 {
            let count = (profile["proposalCount"] as? Int ?? 0) + 1
            guard count <= 10 else { throw CloudError.proposalQuota }
            quota["proposalWindowAt"] = window; quota["proposalCount"] = count
        } else {
            quota["proposalWindowAt"] = FieldValue.serverTimestamp(); quota["proposalCount"] = 1
        }
        let author = profile["username"] as? String ?? "Joueur"
        let batch = db.batch()
        batch.setData(["wordFull":card.wordFull,"wordNoVowels":card.wordNoVowels,"normalizedAnswer":id,"hint":card.hint,"category":card.category.rawValue,"difficulty":card.difficulty.rawValue,"createdBy":uid,"createdAt":FieldValue.serverTimestamp(),"status":"pending","authorName":author], forDocument: ref)
        batch.updateData(quota, forDocument: userRef)
        try await batch.commit()
        var stored = card; stored.id = id; stored.author = author
        return stored
    }
    func submissions(uid: String) async throws -> [Submission] {
        let snap = try await db.collection("cards").whereField("createdBy",isEqualTo:uid).order(by:"createdAt",descending:true).limit(to:100).getDocuments()
        return snap.documents.compactMap { doc in
            guard let card = decode(doc.documentID,doc.data()) else { return nil }
            var s = Submission(card:card); s.id = doc.documentID
            s.createdAt = (doc.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            return s
        }
    }
    func report(cardID: String, reason: String) async throws {
        guard let uid = auth.currentUser?.uid else { throw CloudError.authentication }
        do {
            try await db.collection("reports").document(uid+"_"+cardID).setData(["userId":uid,"cardId":cardID,"reason":reason,"createdAt":FieldValue.serverTimestamp(),"status":"pending"])
        } catch where CloudError.code(error) == .permissionDenied { throw CloudError.alreadyReported }
    }

    /// Reports an offensive pseudo seen on the leaderboard.
    func report(player: String, username: String) async throws {
        guard let uid = auth.currentUser?.uid else { throw CloudError.authentication }
        do {
            try await db.collection("playerReports").document(uid + "_" + player).setData(["userId": uid, "playerId": player, "username": username,
                "reason": "Pseudo inapproprié", "createdAt": FieldValue.serverTimestamp(), "status": "pending"])
        } catch where CloudError.code(error) == .permissionDenied { throw CloudError.alreadyReported }
    }

    // MARK: Moderation

    func isSuspended(uid: String) async throws -> Bool {
        try await db.collection("banned").document(uid).getDocument(source: .server).exists
    }
    /// Suspends a player and hides them from the rankings. Nothing is deleted: lifting the suspension
    /// gives back every result and total.
    func suspend(player: String, username: String, reason: String) async throws {
        guard let uid = auth.currentUser?.uid else { throw CloudError.authentication }
        let hide = try await hidingWrites(player: player, suspended: true)
        try await commit([.set(["username": username, "reason": reason, "bannedAt": FieldValue.serverTimestamp(), "bannedBy": uid], db.collection("banned").document(player))] + hide)
    }
    func unsuspend(player: String) async throws {
        let show = try await hidingWrites(player: player, suspended: false)
        try await commit([.delete(db.collection("banned").document(player))] + show)
    }
    /// Sets or clears the `suspended` flag on the player's totals and every daily result.
    private func hidingWrites(player: String, suspended: Bool) async throws -> [BatchWrite] {
        let flag: [String: Any] = ["suspended": suspended ? true : FieldValue.delete()]
        var refs = try await db.collection("dailyResults").whereField("userId", isEqualTo: player).getDocuments(source: .server).documents.map(\.reference)
        let board = db.collection("leaderboard").document(player)
        if try await board.getDocument(source: .server).exists { refs.append(board) }
        return refs.map { BatchWrite.update(flag, $0) }
    }
    func suspendedPlayers() async throws -> [SuspendedPlayer] {
        try await db.collection("banned").limit(to: 100).getDocuments(source: .server).documents.map {
            SuspendedPlayer(id: $0.documentID, username: $0.data()["username"] as? String ?? "Joueur", reason: $0.data()["reason"] as? String ?? "")
        }
    }
    func pendingPlayerReports() async throws -> [PlayerReport] {
        try await db.collection("playerReports").whereField("status", isEqualTo: "pending").limit(to: 50).getDocuments(source: .server).documents.compactMap { doc in
            let d = doc.data()
            guard let player = d["playerId"] as? String, let name = d["username"] as? String else { return nil }
            return PlayerReport(id: doc.documentID, playerID: player, username: name, reason: d["reason"] as? String ?? "")
        }
    }
    func resolve(playerReport: PlayerReport) async throws {
        guard let uid = auth.currentUser?.uid else { throw CloudError.authentication }
        try await db.collection("playerReports").document(playerReport.id).updateData(["status": "resolved", "reviewedBy": uid, "reviewedAt": FieldValue.serverTimestamp()])
    }

    func isAdmin() async throws -> Bool {
        guard let user = auth.currentUser else { return false }
        if try await user.getIDTokenResult(forcingRefresh:true).claims["admin"] as? Bool == true { return true }
        return try await db.collection("admins").document(user.uid).getDocument(source: .server).exists
    }
    func pendingCards() async throws -> [Card] {
        let snap = try await db.collection("cards").whereField("status",isEqualTo:"pending").limit(to:50).getDocuments(source: .server)
        var cards: [Card] = []
        for doc in snap.documents {
            guard var card = decode(doc.documentID, doc.data()) else { continue }
            // Proposals made before the author's pseudo was stored on the card.
            if card.author == nil, let uid = doc.data()["createdBy"] as? String {
                card.author = try? await db.collection("users").document(uid).getDocument().data()?["username"] as? String
            }
            cards.append(card)
        }
        return cards
    }
    /// Approves or refuses a proposal, optionally fixing its hint, category or difficulty.
    func review(card: Card, approved: Bool) async throws {
        guard let uid = auth.currentUser?.uid else { throw CloudError.authentication }
        var fields: [String: Any] = ["status":approved ? "approved":"rejected","reviewedBy":uid,"reviewedAt":FieldValue.serverTimestamp(),
            "wordNoVowels":WordEngine.consonants(card.wordFull),"hint":card.hint,"category":card.category.rawValue,"difficulty":card.difficulty.rawValue]
        // Older proposals carry no pseudo: the moderator's copy (read from the author's profile) fills it in.
        if let author = card.author { fields["authorName"] = author }
        let batch = db.batch()
        batch.updateData(fields, forDocument: db.collection("cards").document(card.id))
        bumpCardsVersion(batch)
        try await batch.commit()
    }
    func pendingReports() async throws -> [CardReport] {
        let snap = try await db.collection("reports").whereField("status",isEqualTo:"pending").limit(to:50).getDocuments(source: .server)
        var reports: [CardReport] = snap.documents.compactMap { doc in
            guard let cardID = doc.data()["cardId"] as? String, let reason = doc.data()["reason"] as? String else { return nil }
            return CardReport(id:doc.documentID,cardID:cardID,reason:reason)
        }
        for index in reports.indices {
            reports[index].word = try? await db.collection("cards").document(reports[index].cardID).getDocument().data()?["wordFull"] as? String
        }
        return reports
    }
    func withdraw(report: CardReport) async throws {
        guard let uid = auth.currentUser?.uid else { throw CloudError.authentication }
        let batch = db.batch()
        batch.updateData(["status": "rejected", "reviewedBy": uid, "reviewedAt": FieldValue.serverTimestamp()], forDocument: db.collection("cards").document(report.cardID))
        batch.updateData(["status": "resolved", "reviewedBy": uid, "reviewedAt": FieldValue.serverTimestamp()], forDocument: db.collection("reports").document(report.id))
        bumpCardsVersion(batch)
        try await batch.commit()
    }
    func resolve(report: CardReport) async throws {
        guard let uid = auth.currentUser?.uid else { throw CloudError.authentication }
        try await db.collection("reports").document(report.id).updateData(["status":"resolved","reviewedBy":uid,"reviewedAt":FieldValue.serverTimestamp()])
    }

    // MARK: Decoding

    private func decode(_ id: String, _ d: [String:Any]) -> Card? {
        guard let word = d["wordFull"] as? String, let hint = d["hint"] as? String,
        let category = CNSNNCore.Category(rawValue:d["category"] as? String ?? ""),
        let difficulty = Difficulty(rawValue:d["difficulty"] as? String ?? ""),
        let status = ReviewStatus(rawValue:d["status"] as? String ?? "") else { return nil }
        return Card(id:id,wordFull:word,hint:hint,category:category,difficulty:difficulty,status:status,author:d["authorName"] as? String)
    }
    private static func session(day: String, _ d: [String: Any]) -> DailySessionState? {
        guard let cardID = d["cardId"] as? String, let started = d["startedAt"] as? Timestamp else { return nil }
        return DailySessionState(day: day, cardID: cardID, startedAt: started.dateValue(), hintUsed: d["hintUsed"] as? Bool ?? false, finished: d["finishedAt"] != nil,
                                 guesses: d["guesses"] as? Int ?? 0)
    }
    private static func attempt(day: String, _ d: [String: Any]) -> Attempt? {
        guard let cardID = d["cardId"] as? String, let timeMs = d["timeMs"] as? Int, let points = d["points"] as? Int else { return nil }
        let date = (d["finishedAt"] as? Timestamp)?.dateValue() ?? Date()
        return Attempt(cardID: cardID, mode: .daily, correct: d["correct"] as? Bool ?? false, timeMs: timeMs, points: points, date: date, dailyKey: day)
    }
    private static func entry(uid: String, _ d: [String: Any]) -> LeaderboardEntry? {
        guard let points = d["points"] as? Int else { return nil }
        return LeaderboardEntry(uid: uid, username: d["username"] as? String ?? "Joueur", points: points, played: d["played"] as? Int ?? 0,
                                wins: d["wins"] as? Int ?? 0, streak: d["streak"] as? Int ?? 0, bestStreak: d["bestStreak"] as? Int ?? 0,
                                bestTimeMs: d["bestTimeMs"] as? Int, lastWinDay: d["lastWinDay"] as? String ?? "")
    }
    /// Same arithmetic as the `tallies` rule in Firebase/firestore.rules.
    static func tally(old: LeaderboardEntry?, uid: String, username: String, day: String, correct: Bool, timeMs: Int, points: Int) -> [String: Any] {
        let lastWin = old?.lastWinDay ?? "", oldStreak = old?.streak ?? 0
        let laterWin = correct && day > lastWin
        let previous = DailySchedule.dayNumber(forKey: day).map { $0 - 1 } == DailySchedule.dayNumber(forKey: lastWin)
        let streak = laterWin ? (previous ? oldStreak + 1 : 1) : (!correct && day > lastWin ? 0 : oldStreak)
        let best: Any = correct ? (min(old?.bestTimeMs ?? timeMs, timeMs) as Any) : (old?.bestTimeMs.map { $0 as Any } ?? NSNull())
        return ["uid":uid,"username":username,"points":(old?.points ?? 0) + points,"played":(old?.played ?? 0) + 1,
                "wins":(old?.wins ?? 0) + (correct ? 1 : 0),"streak":streak,"bestStreak":max(old?.bestStreak ?? 0, streak),
                "bestTimeMs":best,"lastWinDay":laterWin ? day : lastWin,"lastResult":day,"updatedAt":FieldValue.serverTimestamp()]
    }
    /// Milliseconds exactly as the rules' `timestamp.toMillis()`.
    nonisolated static func millis(_ t: Timestamp) -> Int { Int(t.seconds) * 1000 + Int(t.nanoseconds) / 1_000_000 }

    /// Waits for the server to confirm a write, up to `timeout`. Firestore keeps unconfirmed writes
    /// queued and sends them later, so a timeout is not a failure, only "not confirmed yet".
    /// Runs a Firestore transaction through its completion handler. The SDK's async overload, called from
    /// this main-actor class, runs the update block on Firestore's queue as if it were main-actor code,
    /// which crashes the app ("freed pointer was not the last allocation").
    nonisolated static func transact(_ db: Firestore, _ body: @escaping @Sendable (Transaction) throws -> Any?) async throws -> Any? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            db.runTransaction({ transaction, errorPointer -> Any? in
                do { return try body(transaction) } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }, completion: { value, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: value) }
            })
        }
    }
    static func awaitWrite(timeout: TimeInterval = 10, _ start: (@escaping (Error?) -> Void) -> Void) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            let gate = OnceGate()
            start { error in
                gate.run { if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: true) } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { gate.run { continuation.resume(returning: false) } }
        }
    }
}

private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true; body()
    }
}

enum CloudError: LocalizedError {
    case authentication
    case permanentAccountAlreadyConnected
    case offline
    case progressTooLarge
    case duplicateWord
    case proposalTooSoon
    case proposalQuota
    case alreadyReported
    case friendNotFound
    case friendIsYou
    case noGuessesLeft
    case suspended
    case challengeUnavailable

    /// The few Firebase error codes the app reacts to.
    enum Code { case emailInUse, wrongCredentials, weakPassword, invalidEmail, requiresRecentLogin, network, tooManyRequests, permissionDenied, unavailable, other }
    static func code(_ error: Error) -> Code {
        let error = error as NSError
        switch (error.domain, error.code) {
        case ("FIRAuthErrorDomain", 17007), ("FIRAuthErrorDomain", 17025), ("FIRAuthErrorDomain", 17012): return .emailInUse
        case ("FIRAuthErrorDomain", 17004), ("FIRAuthErrorDomain", 17009), ("FIRAuthErrorDomain", 17011): return .wrongCredentials
        case ("FIRAuthErrorDomain", 17026): return .weakPassword
        case ("FIRAuthErrorDomain", 17008): return .invalidEmail
        case ("FIRAuthErrorDomain", 17014): return .requiresRecentLogin
        case ("FIRAuthErrorDomain", 17020): return .network
        case ("FIRAuthErrorDomain", 17010): return .tooManyRequests
        case ("FIRFirestoreErrorDomain", 7): return .permissionDenied
        case ("FIRFirestoreErrorDomain", 14), ("FIRFirestoreErrorDomain", 4): return .unavailable
        default: return .other
        }
    }
    /// A short French explanation for any error shown to the player.
    static func message(_ error: Error) -> String {
        if let error = error as? CloudError { return error.errorDescription ?? "" }
        switch code(error) {
        case .emailInUse: return "Cette adresse a déjà un compte CNSNN. Activez « J’ai déjà un compte » pour vous y connecter."
        case .wrongCredentials: return "Adresse ou mot de passe incorrect."
        case .weakPassword: return "Choisissez un mot de passe d’au moins 8 caractères."
        case .invalidEmail: return "Cette adresse email n’est pas valide."
        case .requiresRecentLogin: return "Pour votre sécurité, saisissez à nouveau votre mot de passe."
        case .network, .unavailable: return CloudError.offline.errorDescription ?? ""
        case .tooManyRequests: return "Trop de tentatives. Réessayez dans quelques minutes."
        case .permissionDenied: return "Action refusée par le serveur. Mettez l’application à jour puis réessayez."
        case .other: return error.localizedDescription
        }
    }
    var errorDescription: String? {
        switch self {
        case .authentication: "Connectez-vous avant cette action."
        case .permanentAccountAlreadyConnected: "Un compte permanent est déjà connecté. Fermez cette fenêtre pour retrouver votre profil."
        case .offline: "Pas de connexion au serveur. Vérifiez le réseau puis réessayez."
        case .progressTooLarge: "Votre historique est trop volumineux pour être synchronisé."
        case .duplicateWord: "Ce mot a déjà été proposé. Essayez-en un autre."
        case .proposalTooSoon: "Patientez quelques secondes avant une nouvelle proposition."
        case .proposalQuota: "Vous avez atteint la limite de 10 propositions par jour. Revenez demain."
        case .alreadyReported: "Votre signalement est déjà envoyé. Merci !"
        case .friendNotFound: "Aucun joueur n’a ce code. Vérifiez les 6 caractères."
        case .friendIsYou: "C’est votre propre code. Envoyez-le à vos amis !"
        case .noGuessesLeft: "Vous avez utilisé vos 20 essais pour aujourd’hui."
        case .suspended: "Votre compte est suspendu : les défis ne sont pas disponibles."
        case .challengeUnavailable: "Ce défi n’est plus disponible. Mettez l’application à jour si le problème continue."
        }
    }
}
