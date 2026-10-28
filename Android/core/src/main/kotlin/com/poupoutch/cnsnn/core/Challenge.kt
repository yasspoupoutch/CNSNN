package com.poupoutch.cnsnn.core

import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.ZoneId

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

    /**
     * Document ids start with the sending phone's clock (13 digits, then a random part), so the
     * background check can ask for the latest challenges with a cursor on the id: no composite index.
     */
    fun newId(nowMs: Long, random: String): String = nowMs.coerceAtLeast(0).toString().padStart(13, '0') + "-" + random
    /** Ids above this one cover the challenges still open, with 2 h of slack for a wrong phone clock. */
    fun recentFromId(nowMs: Long): String = (nowMs - FINISH_WINDOW_MS - 2 * 3_600_000L).coerceAtLeast(0).toString().padStart(13, '0')

    /**
     * The whole list is read again once a week (to drop the challenges of deleted accounts);
     * otherwise only the recent ones, since a challenge never changes after its 50 hours.
     */
    const val FULL_REFRESH_MS = 7 * 24 * 3_600_000L
    /** The list kept on the phone, brought up to date with the recent challenges just read. */
    fun merge(cached: List<Challenge>, recent: List<Challenge>, nowMs: Long): List<Challenge> {
        val cursor = recentFromId(nowMs)
        val fresh = recent.map { it.id }.toSet()
        val frozen = cached.filter { it.id <= cursor && it.id !in fresh }
        return (frozen + recent).sortedByDescending { it.createdMs }
    }

    /**
     * Background checks for notifications: every 30 minutes at most, none at night (midnight to
     * 7 am, local time), and none soon after the app itself read the challenges.
     */
    const val CHECK_EVERY_MS = 30 * 60_000L
    fun nextCheckMs(afterMs: Long, zone: ZoneId = ZoneId.systemDefault()): Long {
        val next = Instant.ofEpochMilli(afterMs + CHECK_EVERY_MS).atZone(zone)
        if (next.hour >= 7) return next.toInstant().toEpochMilli()
        return next.withHour(7).withMinute(0).withSecond(0).withNano(0).toInstant().toEpochMilli()
    }
    fun shouldCheck(nowMs: Long, lastReadMs: Long?, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        if (Instant.ofEpochMilli(nowMs).atZone(zone).hour < 7) return false
        return lastReadMs == null || nowMs - lastReadMs >= CHECK_EVERY_MS / 2
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
    /** Positions of the words passed. */
    private val skipped: MutableList<Int> = mutableListOf()
    /** The words passed, shown at the end. */
    val missed: List<String> get() = skipped.mapNotNull { cards.getOrNull(it)?.wordFull }
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
        skips++; skipped += index; index++
    }

    /** The time shown and compared: play time plus 20 s per skipped word. */
    fun scoreMs(elapsed: Long): Long = elapsed + skips * ChallengeRules.SKIP_PENALTY_MS

    /** "index,found,skips,errors,passed;positions", to pick a closed game up at the same word. */
    fun saved(): String = "$index,$found,$skips,$errors," + skipped.joinToString(";")

    companion object {
        fun restore(cards: List<Card>, saved: String): ChallengeGame? {
            val raw = saved.split(",")
            // Older versions saved the first four numbers only.
            val parts = raw.take(4).mapNotNull { it.toIntOrNull() }
            if (parts.size != 4 || raw.size > 5 || parts[0] !in 0..cards.size) return null
            return ChallengeGame(cards).apply {
                index = parts[0]; found = parts[1]; skips = parts[2]; errors = parts[3]
                raw.getOrNull(4)?.split(";")?.mapNotNull { it.toIntOrNull() }?.let { skipped += it }
            }
        }
    }
}

/** A challenge as stored in Firestore, with times in milliseconds. */
@Serializable
data class Challenge(
    val id: String,
    val cardIds: List<String>,
    val createdMs: Long,
    val from: Side,
    val to: Side,
    /** The invite code of a challenge by link (null for a challenge sent to a friend). */
    val code: String? = null,
) {
    @Serializable
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
    /** A challenge by link that nobody has joined yet. */
    val isOpen: Boolean get() = to.uid.isEmpty()
    /** The other player's name, or what stands for it while nobody has joined. */
    fun opponentName(uid: String): String = if (isOpen && from.uid == uid) "Défi par lien" else theirs(uid).name
    /**
     * The same challenge under the players' current pseudos: the names are saved when it is made,
     * so a player who renamed since would otherwise keep their old pseudo here.
     */
    fun renaming(names: Map<String, String>): Challenge = copy(
        from = names[from.uid]?.takeIf { it.isNotEmpty() }?.let { from.copy(name = it) } ?: from,
        to = names[to.uid]?.takeIf { it.isNotEmpty() }?.let { to.copy(name = it) } ?: to,
    )
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

/**
 * Challenges by link: a 6-character code (the friend-code alphabet, no 0/O or 1/I) and its web page,
 * which opens the app (App Link, or cnsnn://d/CODE) or tells how to get it. Same as Challenge.swift.
 */
object ChallengeInvite {
    const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    const val HOST = "cnsnn-9ctosy.web.app"
    fun link(code: String) = "https://$HOST/d/$code"
    fun newCode(random: java.util.Random = java.security.SecureRandom()): String =
        (1..6).map { ALPHABET[random.nextInt(ALPHABET.length)] }.joinToString("")
    /** The code in a typed text, a pasted link or an opened URL; null when there is none. */
    fun code(text: String): String? {
        var part = text.trim()
        val slash = part.lastIndexOf("/d/")
        if (slash >= 0) part = part.substring(slash + 3)
        else if (part.lowercase().startsWith("cnsnn://")) part = part.substring("cnsnn://".length)
        val letters = part.uppercase().takeWhile { it != '?' && it != '#' && it != '/' }.filter { it.isLetterOrDigit() }
        return letters.takeIf { it.length == 6 && it.all { c -> c in ALPHABET } }
    }
    fun shareText(code: String) =
        "Je te défie sur CNSNN : 5 mots sans leurs voyelles, le plus rapide gagne ! Rejoins mon défi avec le code $code : ${link(code)}"
}

/**
 * Friend links: https://…/a/CODE (or cnsnn://a/CODE from the web page) opens the app and adds the
 * player whose friend code it is. Same alphabet and length as the friend codes. Same as Challenge.swift.
 */
object FriendInvite {
    fun link(code: String) = "https://${ChallengeInvite.HOST}/a/$code"
    /** The friend code in an opened URL; null when it is not a friend link. */
    fun code(url: String): String? {
        val slash = url.lastIndexOf("/a/")
        if (slash < 0) return null
        val letters = url.substring(slash + 3).uppercase().takeWhile { it != '?' && it != '#' && it != '/' }.filter { it.isLetterOrDigit() }
        return letters.takeIf { it.length == 6 && it.all { c -> c in ChallengeInvite.ALPHABET } }
    }
    fun shareText(code: String) =
        "Ajoute-moi en ami sur CNSNN, le jeu de mots sans voyelles : on pourra se défier et comparer nos temps ! Mon code ami : $code. ${link(code)}"
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

/**
 * The notifications a background check shows: a friend's new challenge, and the result once the
 * friend finished after you. Each one has a key, remembered so it is shown only once.
 */
object ChallengeAlerts {
    data class Alert(val key: String, val challengeId: String, val title: String, val body: String)

    fun all(challenges: List<Challenge>, uid: String, now: Long): List<Alert> = challenges.mapNotNull { c -> alert(c, uid, now) }

    fun pending(challenges: List<Challenge>, uid: String, now: Long, seen: Set<String>): List<Alert> =
        all(challenges, uid, now).filter { it.key !in seen }

    private fun alert(c: Challenge, uid: String, now: Long): Alert? {
        if (!c.involves(uid)) return null
        val mine = c.mine(uid); val theirs = c.theirs(uid)
        if (c.state(uid, now) == Challenge.State.YourTurn && c.to.uid == uid)
            return Alert("${c.id}.new", c.id, "${theirs.name} vous a défié !",
                "Mêmes 5 mots, le plus rapide gagne. Plus que ${ChallengeFormat.left(c.startDeadlineMs - now)} pour jouer.")
        val result = c.result(uid, now) ?: return null
        val mineAt = mine.finishedMs ?: return null
        val theirsAt = theirs.finishedMs ?: return null
        if (theirsAt <= mineAt || result == Challenge.Result.EXPIRED) return null
        val title = when (result) {
            Challenge.Result.WON -> "Victoire contre ${theirs.name} !"
            Challenge.Result.LOST -> "Défaite contre ${theirs.name}"
            else -> "Égalité avec ${theirs.name}"
        }
        val body = "Votre chrono : ${ChallengeFormat.time(mine.scoreMs ?: 0)} · ${theirs.name} : ${ChallengeFormat.time(theirs.scoreMs ?: 0)}"
        return Alert("${c.id}.done", c.id, title, body)
    }
}
