package com.poupoutch.cnsnn.state

import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.poupoutch.cnsnn.core.DuoGame
import com.poupoutch.cnsnn.core.ModeRandom
import com.poupoutch.cnsnn.core.ModeRecords
import com.poupoutch.cnsnn.core.ModeStat
import com.poupoutch.cnsnn.core.PlayMode
import com.poupoutch.cnsnn.core.SprintGame
import com.poupoutch.cnsnn.core.SurvivalGame
import com.poupoutch.cnsnn.core.TypedAnswer
import com.poupoutch.cnsnn.core.WordEngine
import com.poupoutch.cnsnn.core.records
import com.poupoutch.cnsnn.data.ModeRun

/**
 * One Sprint, Survie or Double sens game on screen, the Android twin of the iPhone's ModeSession.
 * The rules live in the shared core; this class adds the clock, the saving after every move and
 * the personal records at the end.
 *
 * Leaving and coming back:
 * - Sprint: the clock never stops (elapsedRealtime counts deep sleep). A Sprint whose app is closed
 *   is over and counts as it stood at the next launch.
 * - Survie: no clock. The game is saved after every word and picks up where it was.
 * - Double sens: the clock keeps running, in the background too; a closed game picks up where it
 *   was, the time away included.
 */
class ModeViewModel : ViewModel() {
    var mode = PlayMode.SPRINT; private set
    var sprint: SprintGame? = null; private set
    var survival: SurvivalGame? = null; private set
    var duo: DuoGame? = null; private set
    var answer by mutableStateOf("")
    /** The last answer was wrong: it stays on screen in red, so a typo is fixed without retyping it all. */
    var answerWrong by mutableStateOf(false); private set
    /** The caret in the answer (TypedAnswer.cursor): null at the end. */
    var cursor by mutableStateOf<Int?>(null); private set
    /** The core games are plain objects: this counter tells the screen they changed. */
    var version by mutableIntStateOf(0); private set
    var mistakeTick by mutableIntStateOf(0); private set
    var successTick by mutableIntStateOf(0); private set
    var lifeLostTick by mutableIntStateOf(0); private set
    var lifeGainedTick by mutableIntStateOf(0); private set
    /** "+1" after a right Sprint answer. */
    var gain by mutableStateOf<String?>(null); private set
    /** The answer of the word just passed, shown for a moment (Sprint and Survie). */
    var passed by mutableStateOf<String?>(null); private set
    var passedTick by mutableIntStateOf(0); private set
    /** The Sprint word just found, for the word that flies up from the answer line. */
    var foundWord by mutableStateOf<String?>(null); private set
    /**
     * Sprint: the Sprint clock (ms) at each word found, and the same for the record game on this phone
     * (the ghost that runs along the bar).
     */
    private val foundTimes = mutableListOf<Int>()
    private var ghost: List<Int> = emptyList()
    var resumed by mutableStateOf(false); private set
    var over by mutableStateOf(false); private set
    var beaten by mutableStateOf<Set<String>>(emptySet()); private set
    var previous by mutableStateOf(ModeRecords()); private set
    private var start = SystemClock.elapsedRealtime()
    private var baseMs = 0
    private var recorded = false
    /** Sprint: the score already sent to the ranking during this game (when the app left the screen). */
    private var publishedFound = 0
    private var loaded = false

    val elapsedMs: Int get() = baseMs + (SystemClock.elapsedRealtime() - start).toInt()
    val finished: Boolean get() = sprint?.finished ?: survival?.finished ?: duo?.finished ?: false

    fun loadOnce(mode: PlayMode, state: AppViewModel) {
        if (loaded) return
        loaded = true; this.mode = mode
        begin(state)
    }

    /** Picks up the saved game of this mode, or starts a new one. */
    fun begin(state: AppViewModel) {
        answer = ""; answerWrong = false; gain = null; passed = null; over = false; beaten = emptySet(); recorded = false; publishedFound = 0
        previous = state.progress.records(mode)
        foundWord = null; foundTimes.clear()
        ghost = if (mode == PlayMode.SPRINT) SprintGhost.timeline(state.local.sprintGhost, previous.best(ModeStat.WORDS)) else emptyList()
        val run = if (mode != PlayMode.SPRINT) state.local.loadRun(mode) else null
        if (run != null && !run.finished) {
            sprint = null; survival = run.survival; duo = run.duo
            baseMs = run.resumedElapsedMs(); start = SystemClock.elapsedRealtime(); resumed = true
            version++
            return
        }
        resumed = false
        val seed = testSeed ?: ModeRandom.seed()
        val recent = state.local.recent(mode)
        sprint = if (mode == PlayMode.SPRINT) SprintGame(seed, recent) else null
        survival = if (mode == PlayMode.SURVIVAL) SurvivalGame(seed, recent) else null
        duo = if (mode == PlayMode.DUO) DuoGame(seed, recent) else null
        baseMs = 0; start = SystemClock.elapsedRealtime()
        if (mode == PlayMode.SPRINT) state.startSprintRun()
        version++
        save(state)
    }

    // ---- Typing

    fun press(letter: String) {
        if (finished) return
        edit { it.insert(letter) }
    }
    fun delete() = edit { it.deleteBackward() }
    /** Long press on ⌫. */
    fun clear() = edit { TypedAnswer("") }
    /** A slide on the space bar. */
    fun moveCursor(steps: Int) = edit { it.move(steps) }
    /** A touch on the answer. */
    fun placeCursor(index: Int) = edit { it.place(index) }
    private fun edit(change: (TypedAnswer) -> TypedAnswer) {
        val typed = change(TypedAnswer(answer, cursor))
        answer = typed.text; cursor = typed.cursor; answerWrong = false
    }

    fun submit(state: AppViewModel) {
        if (finished) return
        if (WordEngine.normalize(answer).isEmpty()) { mistakeTick++; return }
        val text = answer; val now = elapsedMs
        when (mode) {
            PlayMode.SPRINT -> { val word = sprint?.card?.wordFull; when (val outcome = sprint?.answer(text, now)) {
                is SprintGame.Outcome.Right -> {
                    answer = ""; answerWrong = false; foundWord = word
                    sprint?.let { foundTimes += SprintGame.DURATION_MS - it.remainingMs(now) }
                    successTick++; gain = "+1"
                }
                SprintGame.Outcome.Wrong -> wrong()
                else -> Unit
            } }
            PlayMode.SURVIVAL -> when (val outcome = survival?.answer(text)) {
                is SurvivalGame.Outcome.Right -> { answer = ""; answerWrong = false; successTick++; if (outcome.lifeGained) lifeGainedTick++ }
                is SurvivalGame.Outcome.Wrong -> { wrong(); lifeLostTick++ }
                else -> Unit
            }
            PlayMode.DUO -> when (duo?.answer(text, now)) {
                DuoGame.Outcome.FIRST, DuoGame.Outcome.SECOND -> { answer = ""; answerWrong = false; successTick++ }
                DuoGame.Outcome.ALREADY -> { answer = ""; answerWrong = false }
                DuoGame.Outcome.WRONG -> wrong()
                else -> Unit
            }
        }
        afterMove(state)
    }
    private fun wrong() { answerWrong = true; mistakeTick++ }

    /** Sprint: next word for 5 seconds. Survie: next word for one life. Double sens: gives up the round. */
    fun skip(state: AppViewModel) {
        if (finished) return
        answer = ""; answerWrong = false
        (sprint?.card ?: survival?.card)?.let { passed = it.wordFull; passedTick++ }
        when (mode) {
            PlayMode.SPRINT -> { sprint?.skip(elapsedMs); gain = null }
            PlayMode.SURVIVAL -> { survival?.skip(); lifeLostTick++ }
            PlayMode.DUO -> duo?.skip(elapsedMs)
        }
        afterMove(state)
    }

    /** Double sens: on to the next round once the words are shown. */
    fun nextRound(state: AppViewModel) {
        if (finished) { over = true; return }
        duo?.next(elapsedMs)
        version++
        save(state)
    }

    /** Sprint: ends the game when the time is up (called by the screen's clock and on return). */
    fun tick(state: AppViewModel) {
        if (mode != PlayMode.SPRINT || sprint?.tick(elapsedMs) != true) return
        afterMove(state)
    }

    /**
     * Sprint: the app leaves the screen. Its clock keeps running and it may be closed while away, so the
     * score so far goes on the ranking now, while the game is still recent enough for the server
     * (otherwise a game ended in the background kept its record on the phone only).
     */
    fun leaveApp(state: AppViewModel) {
        val game = sprint ?: return
        if (mode != PlayMode.SPRINT || game.finished || game.found <= publishedFound) return
        publishedFound = game.found
        state.publishSprint(game.found)
    }

    /** Ends the game now and counts it. */
    fun quit(state: AppViewModel) {
        if (finished) return
        when (mode) {
            PlayMode.SPRINT -> sprint?.stop()
            PlayMode.SURVIVAL -> survival?.abandon()
            PlayMode.DUO -> duo?.abandon(elapsedMs)
        }
        afterMove(state)
        over = true
    }

    private fun afterMove(state: AppViewModel) {
        version++
        if (finished) finish(state) else save(state)
    }

    private fun save(state: AppViewModel) {
        if (finished) return
        state.local.saveRun(ModeRun(mode.key, sprint, survival, duo, elapsedMs, System.currentTimeMillis()))
    }

    private fun finish(state: AppViewModel) {
        if (recorded) return
        recorded = true
        state.local.clearRun(mode)
        val now = elapsedMs
        when (mode) {
            PlayMode.SPRINT -> sprint?.let {
                beaten = state.recordMode(mode, it.best, it.add); state.local.remember(it.used, mode)
                if (it.found > previous.best(ModeStat.WORDS)) state.local.sprintGhost = foundTimes.toList()
                if (it.found > publishedFound) state.publishSprint(it.found)
            }
            PlayMode.SURVIVAL -> survival?.let { beaten = state.recordMode(mode, it.best, it.add); state.local.remember(it.used, mode) }
            PlayMode.DUO -> duo?.let { beaten = state.recordMode(mode, it.best(now), it.add); state.local.remember(it.duos.map { d -> d.id }, mode) }
        }
        // The last Double sens round first shows its words; "Voir le résultat" opens the results.
        over = mode != PlayMode.DUO || duo?.roundComplete != true
    }

    /** Sprint: how many words the record game had found at this point of the clock (null: no record yet). */
    fun ghostCount(elapsed: Int): Int? {
        val game = sprint ?: return null
        if (ghost.isEmpty()) return null
        val clock = SprintGame.DURATION_MS - game.remainingMs(elapsed)
        return ghost.count { it <= clock }
    }

    /** A record beaten that existed before this game (the first game only sets them). */
    fun improved(key: String): Boolean = key in beaten && previous.best(key) > 0

    companion object {
        /** Fixed seed for the interface tests, so they know the words. */
        var testSeed: ULong? = null
    }
}

/**
 * The record game of this phone, word by word: the Sprint clock (ms) at each word found. When the record
 * was set elsewhere (another phone, an older version), the ghost runs at the record's even pace.
 */
internal object SprintGhost {
    fun timeline(saved: List<Int>, best: Int): List<Int> {
        if (best <= 0) return emptyList()
        if (saved.size == best) return saved
        return (1..best).map { (it * SprintGame.DURATION_MS.toDouble() / (best + 0.5)).toInt() }
    }
}
