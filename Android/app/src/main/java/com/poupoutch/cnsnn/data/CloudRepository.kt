package com.poupoutch.cnsnn.data

import com.google.android.gms.tasks.Task
import com.google.firebase.Timestamp
import com.google.firebase.auth.EmailAuthProvider
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.AggregateSource
import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import com.google.firebase.firestore.WriteBatch
import com.poupoutch.cnsnn.core.Attempt
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.Category
import com.poupoutch.cnsnn.core.Challenge
import com.poupoutch.cnsnn.core.DailyScore
import com.poupoutch.cnsnn.core.ChallengeInvite
import com.poupoutch.cnsnn.core.ChallengeRules
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.DailyStanding
import com.poupoutch.cnsnn.core.Difficulty
import com.poupoutch.cnsnn.core.FriendCode
import com.poupoutch.cnsnn.core.FriendStanding
import com.poupoutch.cnsnn.core.GameMode
import com.poupoutch.cnsnn.core.Guesses
import com.poupoutch.cnsnn.core.LeaderboardEntry
import com.poupoutch.cnsnn.core.Progress
import com.poupoutch.cnsnn.core.ReviewStatus
import com.poupoutch.cnsnn.core.SecretDaily
import com.poupoutch.cnsnn.core.Submission
import com.poupoutch.cnsnn.core.WordEngine
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import java.time.Instant

data class CloudProfile(val uid: String, val anonymous: Boolean, val username: String, val email: String? = null,
                        /** Community rules version recorded on the profile, null when never accepted there. */
                        val rulesVersion: Int? = null)
data class CardReport(val id: String, val cardId: String, val reason: String, val word: String? = null)
/** A pseudo reported from the leaderboard. */
data class PlayerReport(val id: String, val playerId: String, val username: String, val reason: String)
/** A player a moderator suspended. */
data class SuspendedPlayer(val id: String, val username: String, val reason: String)
/** One line of the day's ranking. `scoreMs` is the official time: the hint minute included, 10 min for a lost day. */
data class DailyRank(val uid: String, val username: String, val timeMs: Int, val scoreMs: Int, val usedHint: Boolean, val wrongAnswers: Int, val correct: Boolean = true)
/** Server state of today's Mot du jour for the signed-in player. */
data class DailySession(val day: String, val cardId: String, val startedAt: Instant, val hintUsed: Boolean, val finished: Boolean,
                        /** Guesses the server has counted, and the last one (normalized). */
                        val guesses: Int = 0, val guess: String? = null)

/**
 * Everything the app reads and writes on Firebase. The documents and fields are exactly those of
 * the iPhone app (App/Firebase/FirebaseRepository.swift): Firebase/firestore.rules checks both.
 */
/** Pseudos are unique whatever the case: the same key as the iPhone app and the server rules (`lower()`). */
fun nameKey(name: String): String = name.lowercase()
/** A pseudo that cannot name a Firestore document (a slash, ".." or __x__) cannot be reserved. */
fun reservable(name: String): Boolean {
    val key = nameKey(name)
    return '/' !in key && key != "." && key != ".." && !(key.startsWith("__") && key.endsWith("__"))
}
/** The pseudo given to an account that signs in without a profile yet (made on the web, say). */
fun fallbackName(): String = "Joueur" + (1000..9999).random()

class CloudRepository(
    private val auth: FirebaseAuth = com.poupoutch.cnsnn.Cloud.auth,
    private val db: FirebaseFirestore = com.poupoutch.cnsnn.Cloud.db,
) {
    val hasCurrentUser: Boolean get() = auth.currentUser != null
    val currentUid: String? get() = auth.currentUser?.uid
    val currentEmail: String? get() = auth.currentUser?.email

    // ---- Profile

    /** Signs in (as a guest if needed) and creates the profile once. `rulesVersion`: community rules accepted at creation. */
    suspend fun bootstrap(username: String, rulesVersion: Int? = null): CloudProfile {
        val user = auth.currentUser ?: auth.signInAnonymously().await().user ?: throw CloudError(CloudError.Kind.AUTHENTICATION)
        val ref = db.collection("users").document(user.uid)
        // Falls back to the cached profile offline, so a returning player keeps their identity.
        val doc = ref.get().await()
        if (!doc.exists()) {
            if (doc.metadata.isFromCache) throw CloudError(CloudError.Kind.OFFLINE)
            // A deletion cut off halfway (network, app closed) must finish, never bring the profile back.
            if (db.collection("deletedUsers").document(user.uid).get(Source.SERVER).await().exists()) throw CloudError(CloudError.Kind.DELETION_PENDING)
            val data = mutableMapOf<String, Any?>("uid" to user.uid, "username" to username, "createdAt" to FieldValue.serverTimestamp(), "updatedAt" to FieldValue.serverTimestamp(),
                "score" to 0, "gamesPlayed" to 0, "correctAnswers" to 0, "bestTimeMs" to null, "currentStreak" to 0)
            if (rulesVersion != null) { data["rulesVersion"] = rulesVersion; data["rulesAcceptedAt"] = FieldValue.serverTimestamp() }
            // The pseudo is reserved in the same batch: the server refuses a profile whose pseudo is taken.
            val batch = db.batch()
            reserve(username, user.uid, batch)
            batch.set(ref, data)
            batch.commit().await()
            return CloudProfile(user.uid, user.isAnonymous, username, user.email, rulesVersion)
        }
        return CloudProfile(user.uid, user.isAnonymous, doc.getString("username") ?: username, user.email, doc.getLong("rulesVersion")?.toInt())
    }

    /** Records on the profile that the player accepted the community rules (allowed even while suspended). */
    suspend fun acceptRules(uid: String, version: Int) {
        db.collection("users").document(uid).update(mapOf("rulesVersion" to version, "rulesAcceptedAt" to FieldValue.serverTimestamp())).await()
    }

    /** Renames the profile and, in the same batch, the public leaderboard line. The new pseudo is reserved and the player's other reservations freed. */
    suspend fun rename(uid: String, username: String) {
        val batch = db.batch()
        reserve(username, uid, batch)
        db.collection("usernames").whereEqualTo("uid", uid).get(Source.SERVER).await().documents
            .filter { it.id != nameKey(username) }.forEach { batch.delete(it.reference) }
        batch.update(db.collection("users").document(uid), mapOf("username" to username, "updatedAt" to FieldValue.serverTimestamp()))
        if (leaderboardEntry(uid) != null) {
            batch.update(db.collection("leaderboard").document(uid), mapOf("username" to username, "updatedAt" to FieldValue.serverTimestamp()))
        }
        batch.commit().await()
    }

    // ---- Unique pseudos: usernames/{pseudo in lower case} names the player holding it, whatever the case.

    /** Adds the reservation of `name` to the batch, unless the player already holds it. */
    private suspend fun reserve(name: String, uid: String, batch: WriteBatch) {
        if (!reservable(name)) throw CloudError(CloudError.Kind.USERNAME_INVALID)
        val ref = db.collection("usernames").document(nameKey(name))
        val held = ref.get(Source.SERVER).await()
        if (held.exists()) {
            if (held.getString("uid") != uid) throw CloudError(CloudError.Kind.USERNAME_TAKEN)
        } else {
            batch.set(ref, mapOf("uid" to uid, "createdAt" to FieldValue.serverTimestamp()))
        }
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
        return bootstrap(fallbackName())
    }
    suspend fun signIn(email: String, password: String): CloudProfile {
        auth.signInWithEmailAndPassword(email.trim(), password).await()
        return bootstrap(fallbackName())
    }
    suspend fun resetPassword(email: String) { auth.sendPasswordResetEmail(email.trim()).await() }
    fun signOut() = auth.signOut()

    /** Deletes every document of the player, then the Firebase account itself. */
    suspend fun deleteAccount(uid: String, password: String?) {
        val user = auth.currentUser?.takeIf { it.uid == uid } ?: throw CloudError(CloudError.Kind.AUTHENTICATION)
        val email = user.email
        if (password != null && email != null) user.reauthenticate(EmailAuthProvider.getCredential(email, password)).await()
        val users = db.collection("users").document(uid)
        val refs = mutableListOf<DocumentReference>(users.collection("private").document("progress"), db.collection("leaderboard").document(uid))
        refs += users.collection("friends").get(Source.SERVER).await().documents.map { it.reference }
        refs += db.collection("friendCodes").whereEqualTo("uid", uid).get(Source.SERVER).await().documents.map { it.reference }
        refs += db.collection("usernames").whereEqualTo("uid", uid).get(Source.SERVER).await().documents.map { it.reference }
        refs += db.collection("challengeInvites").whereEqualTo("from", uid).get(Source.SERVER).await().documents.map { it.reference }
        for (collection in listOf("dailyResults", "dailySessions", "reports", "playerReports")) {
            refs += db.collection(collection).whereEqualTo("userId", uid).get(Source.SERVER).await().documents.map { it.reference }
        }
        // Friend challenges, sent or received: they carry the player's name.
        for (field in listOf("from", "to")) {
            refs += db.collection("challenges").whereEqualTo(field, uid).get(Source.SERVER).await().documents.map { it.reference }
        }
        // Approved cards stay in the game without the author's name or id; the other proposals go.
        val authored = db.collection("cards").whereEqualTo("createdBy", uid).get(Source.SERVER).await().documents
        refs += authored.filter { it.getString("status") != "approved" }.map { it.reference }
        val writes = refs.map { deleting(it) }.toMutableList()
        authored.filter { it.getString("status") == "approved" }.forEach { card ->
            writes.add { it.update(card.reference, mapOf("createdBy" to "deleted", "authorName" to FieldValue.delete())) }
        }
        // The profile goes first, with the tombstone that lets friends drop this account and any
        // suspension: the rules only let the daily history and the reports go once the profile is gone.
        // The tombstone can only be created once, so a deletion cut off halfway resumes without it.
        val tombstoneRef = db.collection("deletedUsers").document(uid)
        val tombstone: (WriteBatch) -> Unit = { it.set(tombstoneRef, mapOf("deletedAt" to FieldValue.serverTimestamp())) }
        val first = listOfNotNull(deleting(users), tombstone.takeUnless { tombstoneRef.get(Source.SERVER).await().exists() },
            deleting(db.collection("banned").document(uid)))
        commitInBatches(first + writes)
        // Reports naming this player can only be read once the profile is gone.
        val aboutMe = db.collection("playerReports").whereEqualTo("playerId", uid).get(Source.SERVER).await().documents
        commitInBatches(aboutMe.map { deleting(it.reference) })
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
    /**
     * Merges this copy into the online one in a transaction, so two devices saving at once never lose
     * a game. Returns what was saved. Needs the network: offline it fails and overwrites nothing.
     */
    suspend fun saveCloudProgress(progress: Progress, uid: String): Progress {
        val ref = progressRef(uid)
        return db.runTransaction { transaction ->
            val json = transaction.get(ref).getString("json")
            // An online copy this version cannot read is never overwritten.
            val merged = if (json == null) progress else progress.merged(Progress.fromJson(json))
            val encoded = merged.toJson()
            if (encoded.length > 900_000) throw CloudError(CloudError.Kind.PROGRESS_TOO_LARGE)
            transaction.set(ref, mapOf("json" to encoded, "schema" to 1, "updatedAt" to FieldValue.serverTimestamp()))
            merged
        }.await()
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
        // A query, not a direct read: the rules refuse to read a session that does not exist yet
        // (they check its owner), so the first game of the day would be refused.
        val d = db.collection("dailySessions").whereEqualTo("userId", uid).whereEqualTo("day", day).limit(1)
            .get(Source.SERVER).await().documents.firstOrNull() ?: return null
        val cardId = d.getString("cardId") ?: return null
        val started = d.getTimestamp("startedAt") ?: return null
        return DailySession(day, cardId, started.toInstant(), d.getBoolean("hintUsed") ?: false, d.contains("finishedAt"),
            (d.getLong("guesses") ?: 0).toInt(), d.getString("guess"))
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
     * Counts one more guess on the server before it can be checked (at most 20 a day, one per second),
     * in a transaction. Returns the number of guesses so far, this one included.
     */
    suspend fun registerGuess(uid: String, day: String, guess: String): Int {
        val ref = sessionRef(uid, day)
        val count = try {
            withTimeoutOrNull(15_000) {
                db.runTransaction { transaction ->
                    val session = transaction.get(ref)
                    if (!session.exists() || session.contains("finishedAt")) -1L
                    else {
                        val next = (session.getLong("guesses") ?: 0L) + 1
                        if (next > Guesses.MAX) 0L
                        else {
                            transaction.update(ref, mapOf("guesses" to next, "guess" to guess, "guessAt" to FieldValue.serverTimestamp()))
                            next
                        }
                    }
                }.await()
            } ?: throw CloudError(CloudError.Kind.OFFLINE)
        } catch (error: FirebaseFirestoreException) {
            // The rules refuse a guess less than a second after the previous one.
            throw CloudError(if (error.code == FirebaseFirestoreException.Code.PERMISSION_DENIED) CloudError.Kind.GUESS_TOO_SOON else CloudError.Kind.OFFLINE)
        }
        return when (count) {
            -1L -> throw CloudError(CloudError.Kind.DAILY_FINISHED)
            0L -> throw CloudError(CloudError.Kind.GUESS_LIMIT)
            else -> count.toInt()
        }
    }
    /**
     * Stamps the finish with the server time. False if the network did not confirm in time: the write
     * stays queued. A win names the last registered guess (`answer`, normalized) with
     * `wrongAnswers` = guesses - 1; a loss has no answer and `wrongAnswers` = guesses. Anything else is refused.
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
        val scoreMs = DailyScore.scoreMs(timeMs, usedHint, correct)
        val rank = DailyScore.rank(day, scoreMs, correct) ?: return null
        val username = db.collection("users").document(uid).get(Source.SERVER).await().getString("username") ?: "Joueur"
        val old = leaderboardEntry(uid, Source.SERVER)
        // The whole line is replaced: an old `points` field goes, as the rules require.
        val tally = LeaderboardEntry.tally(old, uid, username, day, correct, timeMs, scoreMs) + ("updatedAt" to FieldValue.serverTimestamp())
        val result = mapOf("userId" to uid, "username" to username, "day" to day, "cardId" to cardId, "correct" to correct, "usedHint" to usedHint,
            "wrongAnswers" to wrong, "timeMs" to timeMs, "scoreMs" to scoreMs, "rank" to rank, "startedAt" to started, "finishedAt" to finished)
        val batch = db.batch()
        batch.set(resultRef(uid, day), result)
        batch.set(db.collection("leaderboard").document(uid), tally)
        awaitWrite(batch.commit())
        return Attempt(cardID = cardId, mode = GameMode.DAILY, correct = correct, timeMs = timeMs, date = finished.toInstant(), dailyKey = day)
    }

    // ---- Leaderboard

    suspend fun leaderboardEntry(uid: String, source: Source = Source.DEFAULT): LeaderboardEntry? =
        db.collection("leaderboard").document(uid).get(source).await().data?.let { entry(uid, it) }
    /** This month's ranking: the most time saved first, so the lowest month total (single-field `monthRank`). */
    suspend fun monthlyPlayers(today: String = DailySchedule.key(), limit: Int = 25): List<LeaderboardEntry> {
        val month = DailyScore.monthIndex(today) ?: return emptyList()
        return visible(monthRange(month).orderBy("monthRank", Query.Direction.DESCENDING), limit).mapNotNull { d -> d.data?.let { entry(d.id, it) } }
    }
    suspend fun fastestPlayers(limit: Int = 25): List<LeaderboardEntry> =
        visible(db.collection("leaderboard").whereGreaterThan("bestTimeMs", 0).orderBy("bestTimeMs"), limit).mapNotNull { d -> d.data?.let { entry(d.id, it) } }
    /** A few more than needed, so the list stays full once suspended players are left out. */
    private suspend fun visible(query: Query, limit: Int): List<DocumentSnapshot> =
        query.limit(limit + 10L).get().await().documents.filter { it.getBoolean("suspended") != true }.take(limit)
    private fun monthRange(month: Int): Query = db.collection("leaderboard")
        .whereGreaterThanOrEqualTo("monthRank", DailyScore.monthRank(month, 0))
        .whereLessThan("monthRank", DailyScore.monthRank(month + 1, 0))
    /** My place in this month's ranking and the players this month; null without a result this month. */
    suspend fun monthlyRank(entry: LeaderboardEntry, today: String = DailySchedule.key()): Pair<Int, Int>? {
        val month = DailyScore.monthIndex(today) ?: return null
        if (!entry.playedMonth(today)) return null
        val mine = DailyScore.monthRank(month, entry.monthSaved)
        val range = monthRange(month)
        return (count(range.whereGreaterThan("monthRank", mine)) + 1) to count(range)
    }
    /** Today's found words, fastest first (the hint minute included): one range on the single-field `rank`. */
    suspend fun dailyRanking(day: String, limit: Int = 25): List<DailyRank> {
        val base = DailyScore.dayBase(day) ?: return emptyList()
        return visible(db.collection("dailyResults").whereGreaterThanOrEqualTo("rank", base).whereLessThanOrEqualTo("rank", base + DailyScore.MISSED_MS)
            .orderBy("rank"), limit).mapNotNull { dailyRank(it) }
    }
    private fun dailyRank(d: DocumentSnapshot): DailyRank? {
        val uid = d.getString("userId") ?: return null
        val timeMs = d.getLong("timeMs")?.toInt() ?: return null
        val usedHint = d.getBoolean("usedHint") ?: false
        val correct = d.getBoolean("correct") ?: false
        val scoreMs = d.getLong("scoreMs")?.toInt() ?: DailyScore.scoreMs(timeMs, usedHint, correct)
        return DailyRank(uid, d.getString("username") ?: "Joueur", timeMs, scoreMs, usedHint, (d.getLong("wrongAnswers") ?: 0).toInt(), correct)
    }
    /**
     * Where my result stands among everyone who played today (`rank` from DailyScore.rank): faster
     * players, then slower or lost ones, counted on the single-field `rank`.
     */
    suspend fun standing(day: String, rank: Long, correct: Boolean): DailyStanding {
        val base = DailyScore.dayBase(day) ?: return DailyStanding(null, 0, null)
        val results = db.collection("dailyResults")
        val players = count(results.whereGreaterThanOrEqualTo("rank", base).whereLessThanOrEqualTo("rank", base + DailyScore.LOST_RANK))
        if (!correct) return DailyStanding(null, players, null)
        val faster = count(results.whereGreaterThanOrEqualTo("rank", base).whereLessThan("rank", rank))
        val slower = count(results.whereGreaterThan("rank", rank).whereLessThanOrEqualTo("rank", base + DailyScore.LOST_RANK))
        val others = players - 1
        return DailyStanding(faster + 1, players, if (others > 0) minOf(100, slower * 100 / others) else null)
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
    /**
     * Adds the owner of a friend code to the player's friends, and the player to theirs, so both
     * see each other at once. Returns the friend's pseudo.
     */
    suspend fun addFriendByCode(code: String, uid: String, username: String): String {
        val clean = FriendCode.normalize(code)
        if (clean.length != 6) throw CloudError(CloudError.Kind.FRIEND_NOT_FOUND)
        val doc = db.collection("friendCodes").document(clean).get(Source.SERVER).await()
        val friend = doc.getString("uid") ?: throw CloudError(CloudError.Kind.FRIEND_NOT_FOUND)
        if (friend == uid) throw CloudError(CloudError.Kind.FRIEND_IS_YOU)
        val name = leaderboardEntry(friend, Source.SERVER)?.username ?: doc.getString("username") ?: "Joueur"
        val saved = awaitWrite(db.collection("users").document(uid).collection("friends").document(friend)
            .set(mapOf("username" to name, "addedAt" to FieldValue.serverTimestamp())))
        if (!saved) throw CloudError(CloudError.Kind.OFFLINE)
        // Their side: the code proves they gave it (see firestore.rules). Best effort, theirs is a bonus.
        runCatching {
            awaitWrite(db.collection("users").document(friend).collection("friends").document(uid)
                .set(mapOf("username" to username, "addedAt" to FieldValue.serverTimestamp(), "code" to clean)))
        }
        return name
    }
    /** One read: how many friends the player has, to notice one added from their phone. */
    suspend fun friendCount(uid: String): Int = count(db.collection("users").document(uid).collection("friends"))
    suspend fun removeFriend(uid: String, friend: String) {
        db.collection("users").document(uid).collection("friends").document(friend).delete().await()
    }
    /** The player and their friends, with today's Mot du jour result for each. */
    suspend fun friendsBoard(uid: String, username: String, day: String): List<FriendStanding> {
        val friends = db.collection("users").document(uid).collection("friends").limit(100).get(Source.SERVER).await().documents
        val players = listOf(uid to username) + friends.map { it.id to (it.getString("username") ?: "Joueur") }
        val rows = mutableListOf<FriendStanding>()
        for ((player, name) in players) {
            val board = db.collection("leaderboard").document(player).get(Source.SERVER).await()
            val entry = board.data?.let { entry(player, it) }
            if (player != uid) {
                // A suspended friend is hidden like on the public rankings.
                if (board.getBoolean("suspended") == true) continue
                // A friend who deleted their account leaves the list for good (no totals left, so check only then).
                if (entry == null && db.collection("deletedUsers").document(player).get(Source.SERVER).await().exists()) {
                    runCatching { removeFriend(uid, player) }
                    continue
                }
            }
            val result = resultRef(player, day).get(Source.SERVER).await()
            val today = result.data?.let { attempt(day, it) }
            val hint = result.getBoolean("usedHint") ?: false
            val score = today?.let { result.getLong("scoreMs")?.toInt() ?: DailyScore.scoreMs(it.timeMs, hint, it.correct) }
            rows += FriendStanding(player, entry?.username ?: name, entry?.monthTotalMs(day), entry?.currentStreak() ?: 0, today,
                result.getLong("wrongAnswers")?.toInt(), score, hint)
        }
        return FriendStanding.ordered(rows)
    }

    /** The friends' ids and names only (one read each, for the challenge list). */
    suspend fun friends(uid: String): List<Pair<String, String>> =
        db.collection("users").document(uid).collection("friends").limit(100).get(Source.SERVER).await().documents
            .map { it.id to (it.getString("username") ?: "Joueur") }.sortedBy { it.second.lowercase() }

    // ---- Friend challenges (same documents as the iPhone app, see Firebase/firestore.rules)

    /** Sends a challenge to a friend and starts the challenger's clock on the server at once. */
    suspend fun createChallenge(uid: String, username: String, friend: String, friendName: String, cardIds: List<String>): Challenge {
        val random = java.util.UUID.randomUUID().toString().replace("-", "").take(12)
        val ref = db.collection("challenges").document(ChallengeRules.newId(System.currentTimeMillis(), random))
        val data = mapOf("from" to uid, "fromName" to username, "to" to friend, "toName" to friendName, "cardIds" to cardIds,
            "createdAt" to FieldValue.serverTimestamp(), "fromStartedAt" to FieldValue.serverTimestamp())
        if (!awaitWrite(ref.set(data))) throw CloudError(CloudError.Kind.OFFLINE)
        return challenge(ref.id) ?: throw CloudError(CloudError.Kind.OFFLINE)
    }
    /**
     * A challenge by link: nobody named yet, a 6-character code to share. The challenger's clock starts
     * at once, as for a friend. The code is the invite's id, so a code already taken is refused: new one.
     */
    suspend fun createOpenChallenge(uid: String, username: String, cardIds: List<String>): Challenge {
        val random = java.util.UUID.randomUUID().toString().replace("-", "").take(12)
        val ref = db.collection("challenges").document(ChallengeRules.newId(System.currentTimeMillis(), random))
        for (attempt in 1..3) {
            val code = ChallengeInvite.newCode()
            val batch = db.batch()
            batch.set(ref, mapOf("from" to uid, "fromName" to username, "to" to "", "toName" to "", "code" to code, "cardIds" to cardIds,
                "createdAt" to FieldValue.serverTimestamp(), "fromStartedAt" to FieldValue.serverTimestamp()))
            batch.set(db.collection("challengeInvites").document(code),
                mapOf("challenge" to ref.id, "from" to uid, "createdAt" to FieldValue.serverTimestamp()))
            val written = try { awaitWrite(batch.commit()) } catch (e: Exception) {
                if (CloudError.code(e) == CloudError.Code.PERMISSION_DENIED && attempt < 3) continue
                throw e
            }
            if (!written) throw CloudError(CloudError.Kind.OFFLINE)
            return challenge(ref.id) ?: throw CloudError(CloudError.Kind.OFFLINE)
        }
        throw CloudError(CloudError.Kind.OFFLINE)
    }
    /** Takes the empty place of a challenge by link, then adds its author to the player's friends. */
    suspend fun joinChallenge(code: String, uid: String, username: String): Challenge {
        val id = db.collection("challengeInvites").document(code).get(Source.SERVER).await().getString("challenge")
            ?: throw CloudError(CloudError.Kind.INVITE_NOT_FOUND)
        // Once someone joined, only the two players may read it.
        val open = try { challenge(id) } catch (e: Exception) {
            if (CloudError.code(e) == CloudError.Code.PERMISSION_DENIED) throw CloudError(CloudError.Kind.INVITE_TAKEN)
            throw e
        } ?: throw CloudError(CloudError.Kind.INVITE_NOT_FOUND)
        if (open.to.uid == uid) return open
        if (open.from.uid == uid) throw CloudError(CloudError.Kind.INVITE_IS_YOURS)
        if (!open.isOpen) throw CloudError(CloudError.Kind.INVITE_TAKEN)
        if (System.currentTimeMillis() >= open.startDeadlineMs) throw CloudError(CloudError.Kind.INVITE_EXPIRED)
        val ref = db.collection("challenges").document(id)
        if (!awaitWrite(ref.update(mapOf("to" to uid, "toName" to username)))) throw CloudError(CloudError.Kind.OFFLINE)
        runCatching { addFriend(uid, open.from.uid, open.from.name) }
        return challenge(id) ?: throw CloudError(CloudError.Kind.OFFLINE)
    }
    /** Adds a player met through a challenge to the friends, once (no write when already there). */
    suspend fun addFriend(uid: String, friend: String, name: String) {
        val ref = db.collection("users").document(uid).collection("friends").document(friend)
        if (!ref.get(Source.SERVER).await().exists()) {
            ref.set(mapOf("username" to name, "addedAt" to FieldValue.serverTimestamp())).await()
        }
    }
    /** Starts the friend's clock (once), and adds the challenger to their friends so the scores show up. */
    suspend fun startChallenge(challenge: Challenge, uid: String): Challenge {
        if (challenge.to.startedMs == null) {
            val ref = db.collection("challenges").document(challenge.id)
            if (!awaitWrite(ref.update("toStartedAt", FieldValue.serverTimestamp()))) throw CloudError(CloudError.Kind.OFFLINE)
            runCatching { addFriend(uid, challenge.from.uid, challenge.from.name) }
        }
        return challenge(challenge.id) ?: throw CloudError(CloudError.Kind.OFFLINE)
    }
    /** Stamps the finish with the server time. False if the network did not confirm in time (the write stays queued). */
    suspend fun finishChallenge(challenge: Challenge, uid: String, skips: Int, errors: Int): Boolean {
        val side = if (challenge.from.uid == uid) "from" else "to"
        return awaitWrite(db.collection("challenges").document(challenge.id)
            .update(mapOf(side + "FinishedAt" to FieldValue.serverTimestamp(), side + "Skips" to skips, side + "Errors" to errors)))
    }
    suspend fun challenge(id: String): Challenge? =
        db.collection("challenges").document(id).get(Source.SERVER).await().data?.let { challenge(id, it) }
    /**
     * The challenges of the last ~52 hours, the only ones a notification can be about. The ids start
     * with the time, so a cursor on the id keeps this to a few reads (no composite index needed).
     */
    suspend fun recentChallenges(uid: String, nowMs: Long): List<Challenge> {
        val all = mutableListOf<Challenge>()
        for (field in listOf("from", "to")) {
            all += db.collection("challenges").whereEqualTo(field, uid).orderBy(FieldPath.documentId())
                .startAfter(ChallengeRules.recentFromId(nowMs)).limit(50).get(Source.SERVER).await().documents
                .mapNotNull { doc -> doc.data?.let { challenge(doc.id, it) } }
        }
        return all
    }
    /** One read: whether this player has at least one friend to be challenged by. */
    suspend fun hasFriends(uid: String): Boolean =
        !db.collection("users").document(uid).collection("friends").limit(1).get(Source.SERVER).await().isEmpty

    /** The challenges sent and received, newest first (equality queries only: no composite index needed). */
    suspend fun challenges(uid: String): List<Challenge> {
        val all = mutableListOf<Challenge>()
        for (field in listOf("from", "to")) {
            all += db.collection("challenges").whereEqualTo(field, uid).limit(200).get(Source.SERVER).await().documents
                .mapNotNull { doc -> doc.data?.let { challenge(doc.id, it) } }
        }
        return all.sortedByDescending { it.createdMs }
    }

    // ---- Community cards

    /**
     * Version of the approved catalogue (`meta/cards`, moved by moderators), in milliseconds: one read
     * instead of the whole catalogue. Null while the document does not exist yet.
     */
    suspend fun cardsVersion(): Long? =
        db.collection("meta").document("cards").get().await().getTimestamp("updatedAt")?.let { millis(it) }
    private fun bumpCards(batch: WriteBatch) {
        batch.set(db.collection("meta").document("cards"), mapOf("updatedAt" to FieldValue.serverTimestamp()))
    }
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
        batch.set(ref, mapOf("wordFull" to card.wordFull, "wordNoVowels" to WordEngine.consonants(card.wordFull), "normalizedAnswer" to id, "hint" to card.hint,
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
    /** Suspends a player and hides them from the rankings. Results and totals are kept, so lifting it gives everything back. */
    suspend fun suspend(player: String, username: String, reason: String) {
        val uid = currentUid ?: throw CloudError(CloudError.Kind.AUTHENTICATION)
        val ban = db.collection("banned").document(player)
        val record: (WriteBatch) -> Unit = {
            it.set(ban, mapOf("username" to username.take(40), "reason" to reason.take(300), "bannedAt" to FieldValue.serverTimestamp(), "bannedBy" to uid))
        }
        commitInBatches(listOf(record) + markSuspended(player, true))
    }
    suspend fun unsuspend(player: String) {
        val ban = db.collection("banned").document(player)
        commitInBatches(listOf(deleting(ban)) + markSuspended(player, false))
    }
    /** The `suspended` flag on the player's leaderboard line (when there is one) and on every daily result. */
    private suspend fun markSuspended(player: String, suspended: Boolean): List<(WriteBatch) -> Unit> {
        val value: Any = if (suspended) true else FieldValue.delete()
        val refs = mutableListOf<DocumentReference>()
        val board = db.collection("leaderboard").document(player)
        if (board.get(Source.SERVER).await().exists()) refs += board
        refs += db.collection("dailyResults").whereEqualTo("userId", player).get(Source.SERVER).await().documents.map { it.reference }
        return refs.map { ref -> updating(ref, value) }
    }
    /** Today's wins under 5 seconds, fastest first, for a moderator to check. Suspended players are left out. */
    /** Words found today in under 5 seconds (a hint adds a minute, so these never used one). */
    suspend fun suspiciousTimes(day: String): List<DailyRank> {
        val base = DailyScore.dayBase(day) ?: return emptyList()
        return db.collection("dailyResults").whereGreaterThanOrEqualTo("rank", base).whereLessThan("rank", base + 5000).orderBy("rank").limit(20)
            .get(Source.SERVER).await().documents.filter { it.getBoolean("suspended") != true }.mapNotNull { dailyRank(it) }
    }
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
        val batch = db.batch()
        batch.update(db.collection("cards").document(card.id), fields)
        bumpCards(batch)
        batch.commit().await()
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
        bumpCards(batch)
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

    private fun deleting(ref: DocumentReference): (WriteBatch) -> Unit = { it.delete(ref) }
    private fun updating(ref: DocumentReference, suspended: Any): (WriteBatch) -> Unit = { it.update(ref, "suspended", suspended) }
    /** Commits the writes in order, at most 400 per batch (Firestore allows 500). */
    private suspend fun commitInBatches(writes: List<(WriteBatch) -> Unit>) {
        for (chunk in writes.chunked(400)) {
            val batch = db.batch()
            chunk.forEach { it(batch) }
            batch.commit().await()
        }
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
        val date = (d["finishedAt"] as? Timestamp)?.toInstant() ?: Instant.now()
        return Attempt(cardID = cardId, mode = GameMode.DAILY, correct = d["correct"] as? Boolean ?: false, timeMs = timeMs, date = date, dailyKey = day)
    }
    /** A leaderboard line; an old one may still carry `points` (ignored) or lack the month fields (zeros). */
    private fun entry(uid: String, d: Map<String, Any>): LeaderboardEntry? {
        if (d["played"] !is Number) return null
        fun int(key: String) = (d[key] as? Number)?.toInt() ?: 0
        return LeaderboardEntry(uid, d["username"] as? String ?: "Joueur", int("played"), int("wins"), int("streak"), int("bestStreak"),
            (d["bestTimeMs"] as? Number)?.toInt(), d["lastWinDay"] as? String ?: "", int("month"), int("monthSaved"), int("monthPlayed"))
    }

    companion object {
        fun challenge(id: String, d: Map<String, Any?>): Challenge? {
            val from = d["from"] as? String ?: return null
            val to = d["to"] as? String ?: return null
            val ids = (d["cardIds"] as? List<*>)?.filterIsInstance<String>() ?: return null
            val created = d["createdAt"] as? Timestamp ?: return null
            fun ms(key: String) = (d[key] as? Timestamp)?.let { millis(it) }
            fun int(key: String) = (d[key] as? Number)?.toInt() ?: 0
            return Challenge(id, ids, millis(created),
                Challenge.Side(from, d["fromName"] as? String ?: "Joueur", ms("fromStartedAt"), ms("fromFinishedAt"), int("fromSkips"), int("fromErrors")),
                Challenge.Side(to, d["toName"] as? String ?: "Joueur", ms("toStartedAt"), ms("toFinishedAt"), int("toSkips"), int("toErrors")),
                d["code"] as? String)
        }

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
