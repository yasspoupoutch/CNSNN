package com.poupoutch.cnsnn.core

// Défi entre amis: the same 5 words for two friends, the best time wins. Firestore times both players
// (challenges/{id}, see Firebase/firestore.rules); the same rules as Core/Challenge.swift.

object ChallengeRules {
    const val WORDS = 5
    /** A skipped word adds 20 s to the time. */
    const val SKIP_PENALTY_MS = 20_000L
    /** The friend has 48 h to start, and everyone must finish before the 50th hour. */
    const val START_WINDOW_MS = 48 * 3_600_000L
    const val FINISH_WINDOW_MS = 50 * 3_600_000L
    /** 2 easy, 2 medium and 1 hard word, in that order. */
    val LEVELS = listOf(listOf(100, 0, 0), listOf(100, 0, 0), listOf(0, 100, 0), listOf(0, 100, 0), listOf(0, 0, 100))

    /** The words of a new challenge, drawn from the public catalogue (never the secret daily words). */
    fun draw(seed: ULong, recent: List<String> = emptyList()): List<String> {
        val random = ModeRandom(seed)
        val used = mutableListOf<String>()
        for (weights in LEVELS) {
            val card = ModePicker.next(ModeCatalogue.cards, weights, used.toSet(), recent.toSet(), random) ?: break
            used += card.id
        }
        return used
    }

    fun cards(ids: List<String>): List<Card>? {
        val found = ids.mapNotNull { id -> ModeCatalogue.cards.firstOrNull { it.id == id } }
        return if (found.size == ids.size && found.size == WORDS) found else null
    }
}

/** One player's run through the 5 words. The clock is the server's: the screen passes the elapsed time. */
class ChallengeGame(val cards: List<Card>) {
    var index = 0; private set
    var found = 0; private set
    var skips = 0; private set
    var errors = 0; private set
    val finished: Boolean get() = index >= cards.size
    val card: Card? get() = if (finished) null else cards[index]

    enum class Outcome { RIGHT, WRONG, OVER }

    fun answer(text: String): Outcome {
        val shown = card ?: return Outcome.OVER
        if (!WordEngine.matches(text, shown.wordFull)) { errors++; return Outcome.WRONG }
        found++; index++
        return Outcome.RIGHT
    }

    fun skip() {
        if (finished) return
        skips++; index++
    }

    /** The time shown and compared: play time plus 20 s per skipped word. */
    fun scoreMs(elapsed: Long): Long = elapsed + skips * ChallengeRules.SKIP_PENALTY_MS
}

/** A challenge as stored in Firestore, with times in milliseconds. */
data class Challenge(val id: String, val cardIds: List<String>, val createdMs: Long, val from: Side, val to: Side) {
    data class Side(
        val uid: String,
        val name: String,
        val startedMs: Long? = null,
        val finishedMs: Long? = null,
        val skips: Int = 0,
        val errors: Int = 0,
    ) {
        val finished: Boolean get() = finishedMs != null
        /** Finish minus start, plus the skip penalty. */
        val scoreMs: Long? get() = if (startedMs != null && finishedMs != null) finishedMs - startedMs + skips * ChallengeRules.SKIP_PENALTY_MS else null
    }

    fun involves(uid: String) = from.uid == uid || to.uid == uid
    fun mine(uid: String) = if (from.uid == uid) from else to
    fun theirs(uid: String) = if (from.uid == uid) to else from
    val startDeadlineMs: Long get() = createdMs + ChallengeRules.START_WINDOW_MS
    val finishDeadlineMs: Long get() = createdMs + ChallengeRules.FINISH_WINDOW_MS

    enum class Result { WON, LOST, DRAW, EXPIRED }

    sealed interface State {
        /** The friend challenged me and I have not played yet. */
        data object YourTurn : State
        /** I started but did not finish (the app was closed): the clock kept running. */
        data object Playing : State
        /** I finished; the other player has not. */
        data object Waiting : State
        data class Over(val result: Result) : State
    }

    fun state(uid: String, now: Long): State {
        result(uid, now)?.let { return State.Over(it) }
        val me = mine(uid)
        return when {
            me.startedMs == null -> State.YourTurn
            me.finished -> State.Waiting
            else -> State.Playing
        }
    }

    /** Null while the challenge is still open. */
    fun result(uid: String, now: Long): Result? {
        val me = mine(uid)
        val other = theirs(uid)
        val mine = me.scoreMs
        val theirs = other.scoreMs
        if (mine != null && theirs != null) {
            if (mine != theirs) return if (mine < theirs) Result.WON else Result.LOST
            if (me.errors != other.errors) return if (me.errors < other.errors) Result.WON else Result.LOST
            return Result.DRAW
        }
        val closed = now >= finishDeadlineMs || (to.startedMs == null && now >= startDeadlineMs)
        if (!closed) return null
        // The friend never started: nobody wins. Someone who started and gave up loses.
        return when {
            to.startedMs == null -> Result.EXPIRED
            me.finished -> Result.WON
            other.finished -> Result.LOST
            else -> Result.EXPIRED
        }
    }
}

data class ChallengeTally(val wins: Int = 0, val losses: Int = 0, val draws: Int = 0) {
    /** "2 victoires · 1 défaite", or null before the first finished challenge. */
    val label: String?
        get() {
            if (wins + losses + draws == 0) return null
            val parts = mutableListOf("$wins victoire${if (wins > 1) "s" else ""}", "$losses défaite${if (losses > 1) "s" else ""}")
            if (draws > 0) parts += "$draws égalité${if (draws > 1) "s" else ""}"
            return parts.joinToString(" · ")
        }

    companion object {
        /** Wins and losses against one friend (or everyone when [friend] is null). */
        fun of(challenges: List<Challenge>, me: String, friend: String? = null, now: Long): ChallengeTally {
            var wins = 0; var losses = 0; var draws = 0
            for (c in challenges) {
                if (!c.involves(me) || (friend != null && c.theirs(me).uid != friend)) continue
                when (c.result(me, now)) {
                    Challenge.Result.WON -> wins++
                    Challenge.Result.LOST -> losses++
                    Challenge.Result.DRAW -> draws++
                    else -> {}
                }
            }
            return ChallengeTally(wins, losses, draws)
        }
    }
}

object ChallengeFormat {
    /** 1:58, or 12:04 past ten minutes; the hour is folded into minutes. */
    fun time(ms: Long): String {
        val seconds = maxOf(0L, ms) / 1000
        return "${seconds / 60}:" + (seconds % 60).toString().padStart(2, '0')
    }
    /** "31 h" or "45 min" left. */
    fun left(ms: Long): String {
        val minutes = maxOf(0L, ms) / 60_000
        return if (minutes >= 60) "${minutes / 60} h" else "${maxOf(1L, minutes)} min"
    }
}
