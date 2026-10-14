package com.poupoutch.cnsnn.core

import kotlinx.serialization.Serializable

// Sprint, Survie and Double sens: the same rules as Core/Modes.swift. They hold no clock of their
// own (the screen passes the elapsed time), and both apps replay the scenarios written by
// Scripts/generate_content.py (ModeVectors.kt), so they find the same words, points and lives.

enum class PlayMode(val key: String, val title: String) {
    SPRINT("sprint", "Sprint"), SURVIVAL("survival", "Survie"), DUO("duo", "Double sens");

    companion object {
        fun of(key: String?): PlayMode? = entries.firstOrNull { it.key == key }
    }
}

/** SplitMix64: the same numbers from the same seed on the iPhone, on Android and in the reference script. */
@Serializable
class ModeRandom private constructor(private var state: Long, @Suppress("unused") private val version: Int = 1) {
    constructor(seed: ULong) : this(seed.toLong(), 1)

    fun next(): ULong {
        var s = state.toULong() + 0x9E3779B97F4A7C15uL
        state = s.toLong()
        var z = s
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        s = z xor (z shr 31)
        return s
    }
    fun int(bound: Int): Int = (next() % bound.toULong()).toInt()

    companion object {
        /** A fresh seed for a new game. */
        fun seed(): ULong = kotlin.random.Random.nextLong().toULong()
    }
}

/** The verified built-in cards played in Sprint and Survie, in the same order as on the iPhone. */
object ModeCatalogue {
    val cards: List<Card> by lazy { (SeedCards.all + ExtraCards.all).sortedBy { it.id } }
}

object ModePicker {
    /**
     * Rolls a difficulty with the given weights (easy, medium, hard, out of 100), then draws a card of
     * that difficulty never played in this game, avoiding the player's recent cards when possible.
     * If the difficulty is used up, the nearest one is taken.
     */
    fun next(pool: List<Card>, weights: List<Int>, used: Set<String>, recent: Set<String>, random: ModeRandom): Card? {
        val roll = random.int(100)
        val target = when {
            roll < weights[0] -> Difficulty.EASY
            roll < weights[0] + weights[1] -> Difficulty.MEDIUM
            else -> Difficulty.HARD
        }
        val order = when (target) {
            Difficulty.EASY -> listOf(Difficulty.EASY, Difficulty.MEDIUM, Difficulty.HARD)
            Difficulty.MEDIUM -> listOf(Difficulty.MEDIUM, Difficulty.EASY, Difficulty.HARD)
            Difficulty.HARD -> listOf(Difficulty.HARD, Difficulty.MEDIUM, Difficulty.EASY)
        }
        for (avoidRecent in listOf(true, false)) {
            for (level in order) {
                val options = pool.filter { it.difficulty == level && it.id !in used && !(avoidRecent && it.id in recent) }
                if (options.isNotEmpty()) return options[random.int(options.size)]
            }
        }
        return null
    }
}

// ---- Sprint

/**
 * 90 seconds to find as many words as possible. Each right answer scores its difficulty times the
 * combo (consecutive right answers, up to ×5). A wrong answer or a pass breaks the combo, and a pass
 * costs 5 seconds. The clock never stops, even in the background.
 */
@Serializable
class SprintGame private constructor(
    val random: ModeRandom,
    val recent: List<String>,
) {
    constructor(seed: ULong, recent: List<String> = emptyList()) : this(ModeRandom(seed), recent) { draw() }

    var card: Card? = null; private set
    val used: MutableList<String> = mutableListOf()
    var found = 0; private set
    var score = 0; private set
    /** Right answers in a row. */
    var streak = 0; private set
    var bestCombo = 0; private set
    var wrong = 0; private set
    var skips = 0; private set
    var penaltyMs = 0; private set
    var finished = false; private set

    /** What the next right answer is worth: ×1, ×2… up to ×5. */
    val multiplier: Int get() = minOf(MAX_MULTIPLIER, streak + 1)
    fun remainingMs(elapsed: Int): Int = maxOf(0, DURATION_MS - elapsed - penaltyMs)
    /** Right answers out of all the answers checked, in percent. */
    val accuracy: Int get() = if (found + wrong == 0) 0 else found * 100 / (found + wrong)

    sealed interface Outcome { data class Right(val points: Int, val multiplier: Int) : Outcome; data object Wrong : Outcome; data object Over : Outcome }

    fun answer(text: String, elapsed: Int): Outcome {
        val shown = card
        if (finished || remainingMs(elapsed) <= 0 || shown == null) { finished = true; return Outcome.Over }
        if (!WordEngine.matches(text, shown.wordFull)) { wrong++; streak = 0; return Outcome.Wrong }
        streak++
        val multiplier = minOf(MAX_MULTIPLIER, streak)
        val points = basePoints(shown.difficulty) * multiplier
        score += points; found++; bestCombo = maxOf(bestCombo, streak)
        draw()
        return Outcome.Right(points, multiplier)
    }

    fun skip(elapsed: Int) {
        if (finished || remainingMs(elapsed) <= 0) { finished = true; return }
        skips++; streak = 0; penaltyMs += SKIP_PENALTY_MS
        if (remainingMs(elapsed) == 0) finished = true else draw()
    }

    /** Ends the game once the time is up. Returns true when it just ended. */
    fun tick(elapsed: Int): Boolean {
        if (finished || remainingMs(elapsed) > 0) return false
        finished = true
        return true
    }

    fun stop() { finished = true }

    private fun draw() {
        card = ModePicker.next(ModeCatalogue.cards, WEIGHTS, used.toSet(), recent.toSet(), random)
        card?.let { used += it.id } ?: run { finished = true }
    }

    val best: Map<String, Int> get() = mapOf(ModeStat.SCORE to score, ModeStat.WORDS to found, ModeStat.COMBO to bestCombo)
    val add: Map<String, Int> get() = mapOf(ModeStat.GAMES to 1)

    companion object {
        const val DURATION_MS = 90_000
        const val SKIP_PENALTY_MS = 5_000
        const val MAX_MULTIPLIER = 5
        val WEIGHTS = listOf(40, 40, 20)
        fun basePoints(difficulty: Difficulty): Int = when (difficulty) { Difficulty.EASY -> 10; Difficulty.MEDIUM -> 20; Difficulty.HARD -> 30 }
    }
}

// ---- Survie

/**
 * Three lives. A wrong answer or a pass costs one; every tenth word found gives one back (three at
 * most). Every five words the level rises and hard words come more often.
 */
@Serializable
class SurvivalGame private constructor(
    val random: ModeRandom,
    val recent: List<String>,
) {
    constructor(seed: ULong, recent: List<String> = emptyList()) : this(ModeRandom(seed), recent) { draw() }

    var card: Card? = null; private set
    val used: MutableList<String> = mutableListOf()
    var lives = MAX_LIVES; private set
    var found = 0; private set
    var wrong = 0; private set
    var skips = 0; private set
    var livesGained = 0; private set
    var finished = false; private set

    val level: Int get() = found / WORDS_PER_LEVEL + 1
    /** Lives lost: wrong answers and passes. */
    val mistakes: Int get() = wrong + skips

    sealed interface Outcome { data class Right(val lifeGained: Boolean) : Outcome; data class Wrong(val livesLeft: Int) : Outcome; data object Over : Outcome }

    fun answer(text: String): Outcome {
        val shown = card
        if (finished || shown == null) return Outcome.Over
        if (!WordEngine.matches(text, shown.wordFull)) {
            wrong++; lives--
            if (lives == 0) finished = true
            return Outcome.Wrong(lives)
        }
        found++
        val gained = found % BONUS_EVERY == 0 && lives < MAX_LIVES
        if (gained) { lives++; livesGained++ }
        draw()
        return Outcome.Right(gained)
    }

    /** Next word, for one life. */
    fun skip() {
        if (finished) return
        skips++; lives--
        if (lives == 0) finished = true else draw()
    }

    fun abandon() { finished = true }

    private fun draw() {
        card = ModePicker.next(ModeCatalogue.cards, weights(level), used.toSet(), recent.toSet(), random)
        card?.let { used += it.id } ?: run { finished = true }
    }

    val best: Map<String, Int> get() = mapOf(ModeStat.WORDS to found, ModeStat.LEVEL to level)
    val add: Map<String, Int> get() = mapOf(ModeStat.GAMES to 1)

    companion object {
        const val MAX_LIVES = 3
        const val WORDS_PER_LEVEL = 5
        const val BONUS_EVERY = 10
        /** Chances of an easy, medium and hard word at levels 1, 2, 3… (the last row repeats). */
        val LEVELS = listOf(listOf(100, 0, 0), listOf(70, 30, 0), listOf(40, 50, 10), listOf(20, 55, 25), listOf(10, 50, 40), listOf(5, 40, 55), listOf(0, 30, 70))
        fun weights(level: Int): List<Int> = LEVELS[level.coerceIn(1, LEVELS.size) - 1]
    }
}

// ---- Double sens

@Serializable
data class DuoWord(val word: String, val hint: String)

/** Two different words with exactly the same consonants (FRN: farine, frein). */
@Serializable
data class Duo(val id: String, val first: DuoWord, val second: DuoWord) {
    val consonants: String get() = WordEngine.consonants(first.word)
    val words: List<DuoWord> get() = listOf(first, second)
}

/**
 * Five rounds of two words. An answer fills the word it matches; a round can be passed. The time
 * counts while a round is open, not while its answer is shown.
 */
@Serializable
class DuoGame private constructor(val random: ModeRandom) {
    constructor(seed: ULong, recent: List<String> = emptyList()) : this(ModeRandom(seed)) {
        val bank = DuoBank.all.sortedBy { it.id }
        repeat(minOf(ROUNDS, bank.size)) {
            val picked = duos.map { it.id }.toSet()
            val options = bank.filter { it.id !in picked && it.id !in recent }.ifEmpty { bank.filter { it.id !in picked } }
            duos += options[random.int(options.size)]
        }
        duos.forEach { _ -> found += mutableListOf(false, false); skipped += false }
    }

    val duos: MutableList<Duo> = mutableListOf()
    var round = 0; private set
    val found: MutableList<MutableList<Boolean>> = mutableListOf()
    val skipped: MutableList<Boolean> = mutableListOf()
    var errors = 0; private set
    var finished = false; private set
    /** Time spent on the answers shown between rounds, left out of the clock. */
    var excludedMs = 0; private set
    var completedAt: Int? = null; private set
    var endMs: Int? = null; private set

    val duo: Duo? get() = duos.getOrNull(round)
    val roundComplete: Boolean get() = round in duos.indices && ((found[round][0] && found[round][1]) || skipped[round])
    val isLastRound: Boolean get() = round == duos.size - 1

    enum class Outcome { FIRST, SECOND, ALREADY, WRONG, OVER }

    fun answer(text: String, elapsed: Int): Outcome {
        val shown = duo
        if (finished || roundComplete || shown == null) return Outcome.OVER
        val key = WordEngine.normalize(text)
        val index = listOf(WordEngine.normalize(shown.first.word), WordEngine.normalize(shown.second.word)).indexOf(key)
        if (index < 0) { errors++; return Outcome.WRONG }
        if (found[round][index]) return Outcome.ALREADY
        found[round][index] = true
        if (roundComplete) close(elapsed)
        return if (index == 0) Outcome.FIRST else Outcome.SECOND
    }

    /** Gives up the words still hidden in this round. */
    fun skip(elapsed: Int) {
        if (finished || roundComplete) return
        skipped[round] = true
        close(elapsed)
    }

    private fun close(elapsed: Int) {
        completedAt = elapsed
        if (isLastRound) { finished = true; endMs = elapsed - excludedMs }
    }

    fun next(elapsed: Int) {
        val at = completedAt
        if (finished || !roundComplete || at == null) return
        excludedMs += elapsed - at
        completedAt = null
        round++
    }

    /** Ends the game now; the rounds not played count as not found. */
    fun abandon(elapsed: Int) {
        if (finished) return
        endMs = playMs(elapsed); finished = true
    }

    fun playMs(elapsed: Int): Int = endMs ?: (elapsed - excludedMs - (completedAt?.let { elapsed - it } ?: 0))
    val wordsFound: Int get() = found.sumOf { pair -> pair.count { it } }
    val solved: Int get() = found.count { it[0] && it[1] }
    val perfect: Boolean get() = wordsFound == duos.size * 2 && errors == 0
    /** 100 per word, 50 per complete duo, −20 per error, plus a time bonus that grows with the words found. */
    fun score(elapsed: Int): Int {
        val bonus = maxOf(0, TIME_BONUS_SECONDS - playMs(elapsed) / 1000) * wordsFound / 10
        return maxOf(0, wordsFound * WORD_POINTS + solved * DUO_BONUS - errors * ERROR_PENALTY + bonus)
    }

    fun best(elapsed: Int): Map<String, Int> = mapOf(ModeStat.SCORE to score(elapsed))
    val add: Map<String, Int> get() = mapOf(ModeStat.GAMES to 1, ModeStat.PERFECT to (if (perfect) 1 else 0), ModeStat.DUOS_SOLVED to solved, ModeStat.DUOS_PLAYED to duos.size)

    companion object {
        const val ROUNDS = 5
        const val WORD_POINTS = 100
        const val DUO_BONUS = 50
        const val ERROR_PENALTY = 20
        /** Seconds under which the remaining time adds a bonus, shared by the words found. */
        const val TIME_BONUS_SECONDS = 300
    }
}

// ---- Personal records

object ModeStat {
    const val SCORE = "score"; const val WORDS = "words"; const val COMBO = "combo"; const val LEVEL = "level"
    const val GAMES = "games"; const val PERFECT = "perfect"; const val DUOS_SOLVED = "duosSolved"; const val DUOS_PLAYED = "duosPlayed"
}

/**
 * One mode's personal records, merged safely between devices: a best only grows (the highest wins),
 * and each counter keeps one total per device, so two phones playing offline never lose a game.
 * Encoded like the iPhone's ModeRecords.
 */
@Serializable
data class ModeRecords(
    val best: Map<String, Int> = emptyMap(),
    /** Counter name → device id → games counted on that device. */
    val counts: Map<String, Map<String, Int>> = emptyMap(),
) {
    fun total(key: String): Int = counts[key]?.values?.sum() ?: 0
    fun best(key: String): Int = best[key] ?: 0

    fun merged(other: ModeRecords): ModeRecords {
        val bests = best.toMutableMap()
        for ((key, value) in other.best) bests[key] = maxOf(bests[key] ?: value, value)
        val all = counts.mapValues { it.value.toMutableMap() }.toMutableMap()
        for ((key, devices) in other.counts) {
            val mine = all.getOrPut(key) { mutableMapOf() }
            for ((device, value) in devices) mine[device] = maxOf(mine[device] ?: value, value)
        }
        return ModeRecords(bests, all)
    }
}

fun Progress.records(mode: PlayMode): ModeRecords = modes?.get(mode.key) ?: ModeRecords()

/** Adds one finished game. Returns the new progress and the records it beat (its first game sets them). */
fun Progress.recordingMode(mode: PlayMode, best: Map<String, Int>, add: Map<String, Int>, device: String): Pair<Progress, Set<String>> {
    val records = records(mode)
    val beaten = mutableSetOf<String>()
    val bests = records.best.toMutableMap()
    for ((key, value) in best) if (value > records.best(key) && value > 0) { bests[key] = value; beaten += key }
    val counts = records.counts.mapValues { it.value.toMutableMap() }.toMutableMap()
    for ((key, value) in add) if (value > 0) {
        val devices = counts.getOrPut(key) { mutableMapOf() }
        devices[device] = (devices[device] ?: 0) + value
    }
    val all = (modes ?: emptyMap()) + (mode.key to ModeRecords(bests, counts))
    return copy(modes = all) to beaten
}
