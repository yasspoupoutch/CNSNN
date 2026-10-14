package com.poupoutch.cnsnn.data

import com.google.android.gms.tasks.Task
import com.google.firebase.Timestamp
import com.google.firebase.auth.EmailAuthProvider
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.AggregateSource
import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import com.poupoutch.cnsnn.core.Attempt
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.Category
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.DailyStanding
import com.poupoutch.cnsnn.core.Difficulty
import com.poupoutch.cnsnn.core.FriendCode
import com.poupoutch.cnsnn.core.FriendStanding
import com.poupoutch.cnsnn.core.GameMode
import com.poupoutch.cnsnn.core.LeaderboardEntry
import com.poupoutch.cnsnn.core.Progress
import com.poupoutch.cnsnn.core.ReviewStatus
import com.poupoutch.cnsnn.core.Scoring
import com.poupoutch.cnsnn.core.SecretDaily
import com.poupoutch.cnsnn.core.Submission
import com.poupoutch.cnsnn.core.WordEngine
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import java.time.Instant

data class CloudProfile(val uid: String, val anonymous: Boolean, val username: String, val email: String? = null)
data class CardReport(val id: String, val cardId: String, val reason: String, val word: String? = null)
/** A pseudo reported from the leaderboard. */
data class PlayerReport(val id: String, val playerId: String, val username: String, val reason: String)
/** A player a moderator suspended. */
data class SuspendedPlayer(val id: String, val username: String, val reason: String)
/** One line of the day's ranking. */
data class DailyRank(val uid: String, val username: String, val timeMs: Int, val points: Int, val usedHint: Boolean, val wrongAnswers: Int)
/** Server state of today's Mot du jour for the signed-in player. */
data class DailySession(val day: String, val cardId: String, val startedAt: Instant, val hintUsed: Boolean, val finished: Boolean)

/**
 * Everything the app reads and writes on Firebase. The documents and fields are exactly those of
 * the iPhone app (App/Firebase/FirebaseRepository.swift): Firebase/firestore.rules checks both.
 */
class CloudRepository(
    private val auth: FirebaseAuth = com.poupoutch.cnsnn.Cloud.auth,
    private val db: FirebaseFirestore = com.poupoutch.cnsnn.Cloud.db,
) {
    val hasCurrentUser: Boolean get() = auth.currentUser != null
    val currentUid: String? get() = auth.currentUser?.uid
    val currentEmail: String? get() = auth.currentUser?.email

    // ---- Profile

    suspend fun bootstrap(username: String): CloudProfile {
        val user = auth.currentUser ?: auth.signInAnonymously().await().user ?: throw CloudError(CloudError.Kind.AUTHENTICATION)
        val ref = db.collection("users").document(user.uid)
        // Falls back to the cached profile offline, so a returning player keeps their identity.
        val doc = ref.get().await()
        if (!doc.exists()) {
            if (doc.metadata.isFromCache) throw CloudError(CloudError.Kind.OFFLINE)
            ref.set(mapOf("uid" to user.uid, "username" to username, "createdAt" to FieldValue.serverTimestamp(), "updatedAt" to FieldValue.serverTimestamp(),
                "score" to 0, "gamesPlayed" to 0, "correctAnswers" to 0, "bestTimeMs" to null, "currentStreak" to 0)).await()
        }
        return CloudProfile(user.uid, user.isAnonymous, doc.getString("username") ?: username, user.email)
    }

    /** Renames the profile and, in the same batch, the public leaderboard line. */
    suspend fun rename(uid: String, username: String) {
        val batch = db.batch()
        batch.update(db.collection("users").document(uid), mapOf("username" to username, "updatedAt" to FieldValue.serverTimestamp()))
        if (leaderboardEntry(uid) != null) {
            batch.update(db.collection("leaderboard").document(uid), mapOf("username" to username, "updatedAt" to FieldValue.serverTimestamp()))
        }
        batch.commit().await()
    }

    // ---- Accounts

    /** Turns the guest into a permanent account. Linking keeps the UID, so nothing is lost. */
    suspend fun createPermanentAccount(email: String, password: String): CloudProfile {
        val address = email.trim()
        val current = auth.currentUser
        if (current != null) {
            if (!current.isAnonymous) throw CloudError(CloudError.Kind.PERMANENT_ACCOUNT_CONNECTED)
            current.linkWithCredential(EmailAuthProvider.getCredential(address, password)).await()
        } else {
            auth.createUserWithEmailAndPassword(address, password).await()
        }
        return bootstrap("Joueur")
    }
    suspend fun signIn(email: String, password: String): CloudProfile {
        auth.signInWithEmailAndPassword(email.trim(), password).await()
        return bootstrap("Joueur")
    }
    suspend fun resetPassword(email: String) { auth.sendPasswordResetEmail(email.trim()).await() }
    fun signOut() = auth.signOut()

    /** Deletes every document of the player, then the Firebase account itself. */
    suspend fun deleteAccount(uid: String, password: String?) {
        val user = auth.currentUser?.takeIf { it.uid == uid } ?: throw CloudError(CloudError.Kind.AUTHENTICATION)
        val email = user.email
        if (password != null && email != null) user.reauthenticate(EmailAuthProvider.getCredential(email, password)).await()
        val refs = mutableListOf<DocumentReference>(
            db.collection("users").document(uid),
            db.collection("users").document(uid).collection("private").document("progress"),
            db.collection("leaderboard").document(uid),
        )
        refs += db.collection("users").document(uid).collection("friends").get(Source.SERVER).await().documents.map { it.reference }
        refs += db.collection("friendCodes").whereEqualTo("uid", uid).get(Source.SERVER).await().documents.map { it.reference }
        for (collection in listOf("dailyResults", "dailySessions", "reports", "playerReports")) {
            refs += db.collection(collection).whereEqualTo("userId", uid).get(Source.SERVER).await().documents.map { it.reference }
        }
        // Approved cards stay in the game without the author's name or id; the other proposals go.
        val authored = db.collection("cards").whereEqualTo("createdBy", uid).get(Source.SERVER).await().documents
        refs += authored.filter { it.getString("status") != "approved" }.map { it.reference }
        val live = authored.filter { it.getString("status") == "approved" }.map { it.reference }
        // The profile goes first: the rules only let the daily history go once it is gone.
        // The first batch also leaves the tombstone that lets friends drop this account.
        refs.chunked(400).forEachIndexed { index, chunk ->
            val batch = db.batch()
            chunk.forEach { batch.delete(it) }
            if (index == 0) {
                batch.set(db.collection("deletedUsers").document(uid), mapOf("deletedAt" to FieldValue.serverTimestamp()))
                live.take(80).forEach { batch.update(it, mapOf("createdBy" to "deleted", "authorName" to FieldValue.delete())) }
            }
            batch.commit().await()
        }
        try {
            user.delete().await()
        } catch (error: Exception) {
            // A guest cannot sign in again: its data is already gone, so simply leave the account.
            if (CloudError.code(error) == CloudError.Code.RECENT_LOGIN && user.isAnonymous) auth.signOut() else throw error
        }
    }

    // ---- Synced progress (practice, not official), shared with the iPhone app

    private fun progressRef(uid: String) = db.collection("users").document(uid).collection("private").document("progress")
    suspend fun cloudProgress(uid: String): Progress? =
        progressRef(uid).get().await().getString("json")?.let { Progress.fromJson(it) }
    /** Queued by Firestore when offline and sent once the network is back. */
    fun saveCloudProgress(progress: Progress, uid: String) {
        val json = progress.toJson()
        if (json.length > 900_000) throw CloudError(CloudError.Kind.PROGRESS_TOO_LARGE)
        progressRef(uid).set(mapOf("json" to json, "schema" to 1, "updatedAt" to FieldValue.serverTimestamp()))
    }

    // ---- Mot du jour (secret word: consonants first, hint once used, word once finished)

    private fun sessionRef(uid: String, day: String) = db.collection("dailySessions").document("${uid}_$day")
    private fun resultRef(uid: String, day: String) = db.collection("dailyResults").document("${uid}_$day")

    suspend fun dailyPuzzle(day: String): Card? {
        val d = db.collection("dailyPuzzles").document(day).get().await()
        val consonants = d.getString("consonants")?.takeIf { it.isNotEmpty() } ?: return null
        val category = Category.of(d.getString("category")) ?: return null
        val difficulty = Difficulty.of(d.getString("difficulty")) ?: return null
        return Card(SecretDaily.cardId(day), "", "", category, difficulty, masked = consonants)
    }
    suspend fun dailyHint(day: String): String? = db.collection("dailyHints").document(day).get().await().getString("hint")
    suspend fun dailySecret(day: String): Card? {
        val d = db.collection("dailySecrets").document(day).get().await()
        val word = d.getString("word") ?: return null
        val hint = d.getString("hint") ?: return null
        val category = Category.of(d.getString("category")) ?: return null
        val difficulty = Difficulty.of(d.getString("difficulty")) ?: return null
        return Card(SecretDaily.cardId(day), word, hint, category, difficulty)
    }
    suspend fun dailySession(uid: String, day: String): DailySession? {
        val d = sessionRef(uid, day).get(Source.SERVER).await()
        val cardId = d.getString("cardId") ?: return null
        val started = d.getTimestamp("startedAt") ?: return null
        return DailySession(day, cardId, started.toInstant(), d.getBoolean("hintUsed") ?: false, d.contains("finishedAt"))
    }
    /** Starts today's clock on the server. Returns only once the server has recorded the start. */
    suspend fun startDaily(uid: String, day: String, cardId: String): DailySession {
        val ok = awaitWrite(sessionRef(uid, day).set(mapOf("userId" to uid, "day" to day, "cardId" to cardId, "startedAt" to FieldValue.serverTimestamp(), "hintUsed" to false)))
        if (!ok) throw CloudError(CloudError.Kind.OFFLINE)
        return dailySession(uid, day) ?: throw CloudError(CloudError.Kind.OFFLINE)
    }
    /** Records the hint on the server first, since the rules open the hint only after that. */
    suspend fun revealSecretHint(uid: String, day: String): String? {
        if (!awaitWrite(sessionRef(uid, day).update("hintUsed", true))) return null
        return dailyHint(day)
    }
    /**
     * Stamps the finish with the server time. False if the network did not confirm in time: the write
     * stays queued. For a secret word, `answer` is the normalized guess: a wrong one is refused.
     */
    suspend fun finishDaily(uid: String, day: String, correct: Boolean, wrongAnswers: Int, answer: String? = null): Boolean {
        val data = mutableMapOf<String, Any>("finishedAt" to FieldValue.serverTimestamp(), "correct" to correct, "wrongAnswers" to wrongAnswers)
        if (answer != null) data["answer"] = answer
        return awaitWrite(sessionRef(uid, day).update(data))
    }
    suspend fun dailyResult(uid: String, day: String): Pair<Attempt, Int>? {
        val d = resultRef(uid, day).get(Source.SERVER).await()
        return attempt(day, d.data ?: return null)?.let { it to ((d.getLong("wrongAnswers") ?: 0).toInt()) }
    }
    /**
     * Publishes the official result of a finished session together with the leaderboard tally,
     * exactly as the security rules recompute them. Returns the existing result if already published.
     */
    suspend fun publishDailyResult(uid: String, day: String): Attempt? {
        dailyResult(uid, day)?.let { return it.first }
        val s = sessionRef(uid, day).get(Source.SERVER).await()
        val started = s.getTimestamp("startedAt") ?: return null
        val finished = s.getTimestamp("finishedAt") ?: return null
        val cardId = s.getString("cardId") ?: return null
        val correct = s.getBoolean("correct") ?: false
        val usedHint = s.getBoolean("hintUsed") ?: false
        val wrong = (s.getLong("wrongAnswers") ?: 0).toInt()
        val timeMs = (millis(finished) - millis(started)).toInt()
        val difficulty = DailySchedule.difficulty(day) ?: return null
        val points = Scoring.points(difficulty, timeMs, usedHint, correct)
        val username = db.collection("users").document(uid).get(Source.SERVER).await().getString("username") ?: "Joueur"
        val old = leaderboardEntry(uid, Source.SERVER)
        val tally = LeaderboardEntry.tally(old, uid, username, day, correct, timeMs, points) + ("updatedAt" to FieldValue.serverTimestamp())
        val result = mapOf("userId" to uid, "username" to username, "day" to day, "cardId" to cardId, "correct" to correct, "usedHint" to usedHint,
            "wrongAnswers" to wrong, "timeMs" to timeMs, "points" to points, "startedAt" to started, "finishedAt" to finished)
        val batch = db.batch()
        batch.set(resultRef(uid, day), result)
        batch.set(db.collection("leaderboard").document(uid), tally)
        awaitWrite(batch.commit())
        return Attempt(cardID = cardId, mode = GameMode.DAILY, correct = correct, timeMs = timeMs, points = points, date = finished.toInstant(), dailyKey = day)
    }

    // ---- Leaderboard

    suspend fun leaderboardEntry(uid: String, source: Source = Source.DEFAULT): LeaderboardEntry? =
        db.collection("leaderboard").document(uid).get(source).await().data?.let { entry(uid, it) }
    suspend fun topPlayers(limit: Long = 50): List<LeaderboardEntry> =
        db.collection("leaderboard").orderBy("points", Query.Direction.DESCENDING).limit(limit).get().await().documents.mapNotNull { d -> d.data?.let { entry(d.id, it) } }
    suspend fun fastestPlayers(limit: Long = 50): List<LeaderboardEntry> =
        db.collection("leaderboard").whereGreaterThan("bestTimeMs", 0).orderBy("bestTimeMs").limit(limit).get().await().documents.mapNotNull { d -> d.data?.let { entry(d.id, it) } }
    /** Rank by official points among every player. */
    suspend fun rank(points: Int): Pair<Int, Int> {
        val board = db.collection("leaderboard")
        return (count(board.whereGreaterThan("points", points)) + 1) to count(board)
    }
    suspend fun dailyRanking(day: String, limit: Long = 50): List<DailyRank> =
        db.collection("dailyResults").whereEqualTo("day", day).whereEqualTo("correct", true).orderBy("timeMs").limit(limit).get().await().documents.mapNotNull { d ->
            val uid = d.getString("userId") ?: return@mapNotNull null
            val timeMs = d.getLong("timeMs")?.toInt() ?: return@mapNotNull null
            DailyRank(uid, d.getString("username") ?: "Joueur", timeMs, (d.getLong("points") ?: 0).toInt(), d.getBoolean("usedHint") ?: false, (d.getLong("wrongAnswers") ?: 0).toInt())
        }
    /** Players who were slower or did not find the word, among everyone else who played today. */
    suspend fun standing(day: String, timeMs: Int, correct: Boolean): DailyStanding {
        val today = db.collection("dailyResults").whereEqualTo("day", day)
        val players = count(today)
        if (!correct) return DailyStanding(null, players, null)
        val missed = count(today.whereEqualTo("correct", false))
        val slower = count(today.whereEqualTo("correct", true).whereGreaterThan("timeMs", timeMs))
        val faster = count(today.whereEqualTo("correct", true).whereLessThan("timeMs", timeMs))
        val others = players - 1
        return DailyStanding(faster + 1, players, if (others > 0) minOf(100, (slower + missed) * 100 / others) else null)
    }
    private suspend fun count(query: Query): Int = query.count().get(AggregateSource.SERVER).await().count.toInt()

    // ---- Friends

    /** The player's friend code, created on first use. The code is the document id, so it is unique. */
    suspend fun friendCode(uid: String, username: String): String {
        db.collection("friendCodes").whereEqualTo("uid", uid).limit(1).get(Source.SERVER).await().documents.firstOrNull()?.let { return it.id }
        repeat(5) {
            val code = FriendCode.random()
            try {
                if (!awaitWrite(db.collection("friendCodes").document(code).set(mapOf("uid" to uid, "username" to username, "createdAt" to FieldValue.serverTimestamp())))) {
                    throw CloudError(CloudError.Kind.OFFLINE)
                }
                return code
            } catch (error: Exception) {
                if (CloudError.code(error) != CloudError.Code.PERMISSION_DENIED) throw error // Taken: draw another code.
            }
        }
        throw CloudError(CloudError.Kind.OFFLINE)
    }
    /** Adds the owner of a friend code to the player's friends. Returns the friend's pseudo. */
    suspend fun addFriend(code: String, uid: String): String {
        val clean = FriendCode.normalize(code)
        if (clean.length != 6) throw CloudError(CloudError.Kind.FRIEND_NOT_FOUND)
        val doc = db.collection("friendCodes").document(clean).get(Source.SERVER).await()
        val friend = doc.getString("uid") ?: throw CloudError(CloudError.Kind.FRIEND_NOT_FOUND)
        if (friend == uid) throw CloudError(CloudError.Kind.FRIEND_IS_YOU)
        val name = leaderboardEntry(friend, Source.SERVER)?.username ?: doc.getString("username") ?: "Joueur"
        val saved = awaitWrite(db.collection("users").document(uid).collection("friends").document(friend)
            .set(mapOf("username" to name, "addedAt" to FieldValue.serverTimestamp())))
        if (!saved) throw CloudError(CloudError.Kind.OFFLINE)
        return name
    }
    suspend fun removeFriend(uid: String, friend: String) {
        db.collection("users").document(uid).collection("friends").document(friend).delete().await()
    }
    /** The player and their friends, with today's Mot du jour result for each. */
    suspend fun friendsBoard(uid: String, username: String, day: String): List<FriendStanding> {
        val friends = db.collection("users").document(uid).collection("friends").limit(100).get(Source.SERVER).await().documents
        val players = listOf(uid to username) + friends.map { it.id to (it.getString("username") ?: "Joueur") }
        val rows = mutableListOf<FriendStanding>()
        for ((player, name) in players) {
            // A friend who deleted their account leaves the list for good.
            if (player != uid && db.collection("deletedUsers").document(player).get(Source.SERVER).await().exists()) {
                runCatching { removeFriend(uid, player) }
                continue
            }
            val entry = leaderboardEntry(player, Source.SERVER)
            val result = resultRef(player, day).get(Source.SERVER).await()
            val today = result.data?.let { attempt(day, it) }
            rows += FriendStanding(player, entry?.username ?: name, entry?.points ?: 0, entry?.currentStreak() ?: 0, today, result.getLong("wrongAnswers")?.toInt())
        }
        return FriendStanding.ordered(rows)
    }

    // ---- Community cards

    suspend fun cards(): List<Card> =
        db.collection("cards").whereEqualTo("status", "approved").limit(500).get().await().documents.mapNotNull { d -> d.data?.let { decode(d.id, it) } }

    /**
     * Proposes a card under its normalized word, which makes duplicates impossible, and consumes
     * the anti-spam quota (30 s apart, 10 per 24 h) in the same batch.
     */
    suspend fun submit(card: Card, uid: String): Card {
        val id = WordEngine.normalize(card.wordFull)
        val ref = db.collection("cards").document(id)
        val exists = try {
            ref.get(Source.SERVER).await().exists()
        } catch (error: Exception) {
            // Someone else's pending or refused proposal: it exists but is private.
            if (CloudError.code(error) == CloudError.Code.PERMISSION_DENIED) true else throw error
        }
        if (exists) throw CloudError(CloudError.Kind.DUPLICATE_WORD)
        val userRef = db.collection("users").document(uid)
        val profile = userRef.get(Source.SERVER).await()
        val now = Instant.now()
        val quota = mutableMapOf<String, Any>("updatedAt" to FieldValue.serverTimestamp(), "lastProposalAt" to FieldValue.serverTimestamp())
        profile.getTimestamp("lastProposalAt")?.let { if (now.epochSecond - it.seconds < 31) throw CloudError(CloudError.Kind.PROPOSAL_TOO_SOON) }
        val window = profile.getTimestamp("proposalWindowAt")
        if (window != null && now.epochSecond - window.seconds < 24 * 3600 - 60) {
            val count = (profile.getLong("proposalCount") ?: 0).toInt() + 1
            if (count > 10) throw CloudError(CloudError.Kind.PROPOSAL_QUOTA)
            quota["proposalWindowAt"] = window; quota["proposalCount"] = count
        } else {
            quota["proposalWindowAt"] = FieldValue.serverTimestamp(); quota["proposalCount"] = 1
        }
        val author = profile.getString("username") ?: "Joueur"
        val batch = db.batch()
        batch.set(ref, mapOf("wordFull" to card.wordFull, "wordNoVowels" to card.wordNoVowels, "normalizedAnswer" to id, "hint" to card.hint,
            "category" to card.category.label, "difficulty" to card.difficulty.label, "createdBy" to uid, "createdAt" to FieldValue.serverTimestamp(),
            "status" to "pending", "authorName" to author))
        batch.update(userRef, quota)
        batch.commit().await()
        return card.copy(id = id, author = author, status = ReviewStatus.PENDING)
    }
    suspend fun submissions(uid: String): List<Submission> =
        db.collection("cards").whereEqualTo("createdBy", uid).orderBy("createdAt", Query.Direction.DESCENDING).limit(100).get().await().documents.mapNotNull { d ->
            val card = d.data?.let { decode(d.id, it) } ?: return@mapNotNull null
            Submission(id = d.id, card = card, createdAt = d.getTimestamp("createdAt")?.toInstant() ?: Instant.now())
        }
    suspend fun report(cardId: String, reason: String) {
        val uid = currentUid ?: throw CloudError(CloudError.Kind.AUTHENTICATION)
        try {
            db.collection("reports").document("${uid}_$cardId").set(mapOf("userId" to uid, "cardId" to cardId, "reason" to reason,
                "createdAt" to FieldValue.serverTimestamp(), "status" to "pending")).await()
        } catch (error: Exception) {
            if (CloudError.code(error) == CloudError.Code.PERMISSION_DENIED) throw CloudError(CloudError.Kind.ALREADY_REPORTED) else throw error
        }
    }
    /** Reports an offensive pseudo seen on the leaderboard. */
    suspend fun reportPlayer(player: String, username: String) {
        val uid = currentUid ?: throw CloudError(CloudError.Kind.AUTHENTICATION)
        try {
            db.collection("playerReports").document("${uid}_$player").set(mapOf("userId" to uid, "playerId" to player, "username" to username,
                "reason" to "Pseudo inapproprié", "createdAt" to FieldValue.serverTimestamp(), "status" to "pending")).await()
        } catch (error: Exception) {
            if (CloudError.code(error) == CloudError.Code.PERMISSION_DENIED) throw CloudError(CloudError.Kind.ALREADY_REPORTED) else throw error
        }
    }

    // ---- Moderation (the rules check the admin role on every write)

    suspend fun isAdmin(): Boolean {
        val user = auth.currentUser ?: return false
        if (user.getIdToken(true).await().claims["admin"] == true) return true
        return db.collection("admins").document(user.uid).get(Source.SERVER).await().exists()
    }
    suspend fun isSuspended(uid: String): Boolean = db.collection("banned").document(uid).get(Source.SERVER).await().exists()
    /** Suspends a player and takes them off the leaderboards; their games stay recorded. */
    suspend fun suspend(player: String, username: String, reason: String) {
        val uid = currentUid ?: throw CloudError(CloudError.Kind.AUTHENTICATION)
        val results = db.collection("dailyResults").whereEqualTo("userId", player).get(Source.SERVER).await().documents
        val batch = db.batch()
        batch.set(db.collection("banned").document(player), mapOf("username" to username, "reason" to reason, "bannedAt" to FieldValue.serverTimestamp(), "bannedBy" to uid))
        batch.delete(db.collection("leaderboard").document(player))
        results.take(400).forEach { batch.delete(it.reference) }
        batch.commit().await()
    }
    suspend fun unsuspend(player: String) { db.collection("banned").document(player).delete().await() }
    suspend fun suspendedPlayers(): List<SuspendedPlayer> =
        db.collection("banned").limit(100).get(Source.SERVER).await().documents.map { SuspendedPlayer(it.id, it.getString("username") ?: "Joueur", it.getString("reason") ?: "") }
    suspend fun pendingCards(): List<Card> {
        val docs = db.collection("cards").whereEqualTo("status", "pending").limit(50).get(Source.SERVER).await().documents
        return docs.mapNotNull { d ->
            val card = d.data?.let { decode(d.id, it) } ?: return@mapNotNull null
            if (card.author != null) card
            else card.copy(author = d.getString("createdBy")?.let { runCatching { db.collection("users").document(it).get().await().getString("username") }.getOrNull() })
        }
    }
    suspend fun review(card: Card, approved: Boolean) {
        val uid = currentUid ?: throw CloudError(CloudError.Kind.AUTHENTICATION)
        val fields = mutableMapOf<String, Any>("status" to if (approved) "approved" else "rejected", "reviewedAt" to FieldValue.serverTimestamp(), "reviewedBy" to uid,
            "hint" to card.hint, "category" to card.category.label, "difficulty" to card.difficulty.label)
        card.author?.let { fields["authorName"] = it }
        db.collection("cards").document(card.id).update(fields).await()
    }
    suspend fun pendingReports(): List<CardReport> =
        db.collection("reports").whereEqualTo("status", "pending").limit(50).get(Source.SERVER).await().documents.mapNotNull { d ->
            val cardId = d.getString("cardId") ?: return@mapNotNull null
            val word = runCatching { db.collection("cards").document(cardId).get().await().getString("wordFull") }.getOrNull()
            CardReport(d.id, cardId, d.getString("reason") ?: "", word)
        }
    suspend fun withdraw(report: CardReport) {
        val uid = currentUid ?: throw CloudError(CloudError.Kind.AUTHENTICATION)
        val batch = db.batch()
        batch.update(db.collection("cards").document(report.cardId), mapOf("status" to "rejected", "reviewedBy" to uid, "reviewedAt" to FieldValue.serverTimestamp()))
        batch.update(db.collection("reports").document(report.id), mapOf("status" to "resolved", "reviewedBy" to uid, "reviewedAt" to FieldValue.serverTimestamp()))
        batch.commit().await()
    }
    suspend fun resolve(report: CardReport) = resolve("reports", report.id)
    suspend fun resolve(report: PlayerReport) = resolve("playerReports", report.id)
    private suspend fun resolve(collection: String, id: String) {
        val uid = currentUid ?: throw CloudError(CloudError.Kind.AUTHENTICATION)
        db.collection(collection).document(id).update(mapOf("status" to "resolved", "reviewedBy" to uid, "reviewedAt" to FieldValue.serverTimestamp())).await()
    }
    suspend fun pendingPlayerReports(): List<PlayerReport> =
        db.collection("playerReports").whereEqualTo("status", "pending").limit(50).get(Source.SERVER).await().documents.mapNotNull { d ->
            val player = d.getString("playerId") ?: return@mapNotNull null
            PlayerReport(d.id, player, d.getString("username") ?: return@mapNotNull null, d.getString("reason") ?: "")
        }

    // ---- Decoding

    private fun decode(id: String, d: Map<String, Any>): Card? {
        val word = d["wordFull"] as? String ?: return null
        val hint = d["hint"] as? String ?: return null
        val category = Category.of(d["category"] as? String) ?: return null
        val difficulty = Difficulty.of(d["difficulty"] as? String) ?: return null
        val status = when (d["status"]) { "approved" -> ReviewStatus.APPROVED; "pending" -> ReviewStatus.PENDING; "rejected" -> ReviewStatus.REJECTED; else -> return null }
        return Card(id, word, hint, category, difficulty, status, author = d["authorName"] as? String)
    }
    private fun attempt(day: String, d: Map<String, Any>): Attempt? {
        val cardId = d["cardId"] as? String ?: return null
        val timeMs = (d["timeMs"] as? Number)?.toInt() ?: return null
        val points = (d["points"] as? Number)?.toInt() ?: return null
        val date = (d["finishedAt"] as? Timestamp)?.toInstant() ?: Instant.now()
        return Attempt(cardID = cardId, mode = GameMode.DAILY, correct = d["correct"] as? Boolean ?: false, timeMs = timeMs, points = points, date = date, dailyKey = day)
    }
    private fun entry(uid: String, d: Map<String, Any>): LeaderboardEntry? {
        val points = (d["points"] as? Number)?.toInt() ?: return null
        fun int(key: String) = (d[key] as? Number)?.toInt() ?: 0
        return LeaderboardEntry(uid, d["username"] as? String ?: "Joueur", points, int("played"), int("wins"), int("streak"), int("bestStreak"),
            (d["bestTimeMs"] as? Number)?.toInt(), d["lastWinDay"] as? String ?: "")
    }

    companion object {
        /** Milliseconds exactly as the rules' `timestamp.toMillis()`. */
        fun millis(t: Timestamp): Long = t.seconds * 1000 + t.nanoseconds / 1_000_000
        private fun Timestamp.toInstant(): Instant = Instant.ofEpochSecond(seconds, nanoseconds.toLong())

        /**
         * Waits for the server to confirm a write, up to `timeoutMs`. Firestore keeps unconfirmed writes
         * queued and sends them later, so a timeout is not a failure, only "not confirmed yet".
         */
        suspend fun awaitWrite(task: Task<*>, timeoutMs: Long = 10_000): Boolean =
            withTimeoutOrNull(timeoutMs) { task.await(); true } ?: false
    }
}
