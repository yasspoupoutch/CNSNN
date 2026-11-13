package com.poupoutch.cnsnn.core

import kotlinx.serialization.Serializable

// Duel en direct: two players on the same 5 words at the same moment, each one seeing the other move
// forward. The server stamps the start and every finish (duels/{id}, see Firebase/firestore.rules);
// the same rules as Core/LiveDuel.swift. The words and the skip penalty are those of the friend challenges.

object LiveDuelRules {
    /** Between the moment both players are there and the first word: a 3-2-1 for everyone. */
    const val COUNTDOWN_MS = 5_000L
    /** A duel lasts 10 minutes at most: whoever has not finished by then loses. */
    const val MAX_MS = 10 * 60_000L
    /** A friend has 15 minutes to open the link of a duel. */
    const val JOIN_WINDOW_MS = 15 * 60_000L
    /** Looking for a random opponent: one minute at most, a new look every few seconds. */
    const val SEARCH_MS = 60_000L
    const val SEARCH_EVERY_MS = 8_000L
    /** Players in the waiting line for longer than this are not taken any more (closed app). */
    const val QUEUE_FRESH_MS = 90_000L

    /** The words of a new duel: same draw as a friend challenge. */
    fun draw(seed: ULong, recent: List<String> = emptyList()): List<String> = ChallengeRules.draw(seed, recent)
}

/** A duel as stored in Firestore, with the server's times in milliseconds. */
@Serializable
data class LiveDuel(
    val id: String,
    val cardIds: List<String>,
    val createdMs: Long,
    /** The first word's moment, once both players are there (null while a link waits for a friend). */
    val startMs: Long? = null,
    val from: Side,
    val to: Side,
    /** The code of a duel by link; null for a random opponent. */
    val code: String? = null,
) {
    @Serializable
    data class Side(
        val uid: String,
        val name: String,
        /** Words behind the player: found or passed. */
        val done: Int = 0,
        val skips: Int = 0,
        val finishedMs: Long? = null,
        /** Left the duel before the end: it is lost. */
        val quit: Boolean = false,
    ) {
        val finished: Boolean get() = finishedMs != null
    }

    fun involves(uid: String) = from.uid == uid || to.uid == uid
    fun mine(uid: String) = if (from.uid == uid) from else to
    fun theirs(uid: String) = if (from.uid == uid) to else from
    /** A duel by link that nobody has joined yet. */
    val isOpen: Boolean get() = to.uid.isEmpty()
    /** Nobody can join any more. */
    fun joinClosed(now: Long) = now >= createdMs + LiveDuelRules.JOIN_WINDOW_MS

    /** Finish minus start, plus 20 s per word passed. */
    fun scoreMs(side: Side): Long? {
        val start = startMs ?: return null
        val finished = side.finishedMs ?: return null
        return finished - start + side.skips * ChallengeRules.SKIP_PENALTY_MS
    }
    /** The best time a player still on the words can make: the clock only goes up. */
    fun boundMs(side: Side, now: Long): Long? {
        scoreMs(side)?.let { return it }
        val start = startMs ?: return null
        return (now - start).coerceAtLeast(0) + side.skips * ChallengeRules.SKIP_PENALTY_MS
    }
    fun endMs(): Long? = startMs?.let { it + LiveDuelRules.MAX_MS }

    enum class Result { WON, LOST, DRAW }

    sealed interface State {
        /** A link waiting for a friend. */
        data object Waiting : State
        /** Both are there: the 3-2-1 before the first word. */
        data object Countdown : State
        data object Playing : State
        /** I finished; the other one can still beat my time. */
        data object Finished : State
        data class Over(val result: Result) : State
    }

    fun state(uid: String, now: Long): State {
        result(uid, now)?.let { return State.Over(it) }
        val start = startMs
        if (start == null || isOpen) return State.Waiting
        if (now < start) return State.Countdown
        return if (mine(uid).finished) State.Finished else State.Playing
    }

    /** Null while the duel is still on. `now` is the server's time, as well as this phone can tell it. */
    fun result(uid: String, now: Long): Result? {
        if (startMs == null || isOpen) return null
        val me = mine(uid)
        val other = theirs(uid)
        // Leaving is only possible before finishing (see the rules): it loses.
        if (me.quit || other.quit) return if (me.quit && other.quit) Result.DRAW else if (me.quit) Result.LOST else Result.WON
        val over = now >= (endMs() ?: Long.MAX_VALUE)
        val mine = scoreMs(me)
        val theirs = scoreMs(other)
        return when {
            mine != null && theirs != null -> if (mine == theirs) Result.DRAW else if (mine < theirs) Result.WON else Result.LOST
            mine != null -> if (over || (boundMs(other, now) ?: 0) > mine) Result.WON else null
            theirs != null -> if (over || (boundMs(me, now) ?: 0) > theirs) Result.LOST else null
            else -> if (over) Result.DRAW else null
        }
    }

    /** While I wait after finishing: the time the other one has left to beat me. */
    fun leftToBeatMs(uid: String, now: Long): Long? {
        val mine = scoreMs(mine(uid)) ?: return null
        val bound = boundMs(theirs(uid), now) ?: return null
        val end = endMs() ?: return null
        return minOf(mine - bound, end - now).coerceAtLeast(0)
    }
}

/**
 * The server's time on this phone: each write stamped by the server tells how far the phone's
 * clock is (half the round trip is taken as the way back).
 */
class ServerClock(var offsetMs: Long = 0) {
    fun learn(serverMs: Long, sentMs: Long, receivedMs: Long) { offsetMs = serverMs - (sentMs + receivedMs) / 2 }
    fun now(localMs: Long = System.currentTimeMillis()): Long = localMs + offsetMs
}

object LiveDuelInvite {
    fun shareText(code: String) =
        "Duel en direct sur CNSNN : mêmes 5 mots, au même moment, le plus rapide gagne ! Je t’attends, rejoins-moi avec le code $code : ${ChallengeInvite.link(code)}"
}
