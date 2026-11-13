package com.poupoutch.cnsnn.state

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.poupoutch.cnsnn.core.ChallengeGame
import com.poupoutch.cnsnn.core.ChallengeRules
import com.poupoutch.cnsnn.core.ServerClock
import com.poupoutch.cnsnn.core.TournamentBracket
import com.poupoutch.cnsnn.core.TournamentPlayer
import com.poupoutch.cnsnn.core.TournamentRules
import com.poupoutch.cnsnn.core.TournamentRun
import com.poupoutch.cnsnn.core.TypedAnswer
import com.poupoutch.cnsnn.core.WordEngine
import com.poupoutch.cnsnn.data.CloudError
import kotlinx.coroutines.launch

/**
 * The weekly tournament as this phone knows it, the Android twin of the iPhone's TournamentStore:
 * next week's sign-ups (a count and my place, 2 reads), and the week under way, its players once, its
 * runs from the round not yet settled. Read only when the tournament is on screen, at most once a minute.
 */
class TournamentStore {
    private var uid: String? = null
    var nextWeek by mutableStateOf(""); private set
    var nextCount by mutableIntStateOf(0); private set
    var nextMine by mutableStateOf(false); private set
    var currentWeek by mutableStateOf(""); private set
    var currentMine by mutableStateOf(false); private set
    var current by mutableStateOf<List<TournamentPlayer>>(emptyList()); private set
    var currentLoaded by mutableStateOf(false); private set
    var runs by mutableStateOf<List<TournamentRun>>(emptyList()); private set
    var loading by mutableStateOf(false); private set
    var message by mutableStateOf<String?>(null)
    private var readAt = 0L
    private var runsReadAt = 0L
    /** The last round whose runs can no longer change (its 24 hours were over when they were read). */
    private var settled = 0

    val nowMs: Long get() = System.currentTimeMillis()
    fun bracket(): TournamentBracket = TournamentBracket(currentWeek, current, runs, nowMs)

    /** The light look: next week's sign-ups and whether I play this week. */
    suspend fun refresh(state: AppViewModel, force: Boolean = false) {
        val me = state.uid ?: return
        val now = nowMs
        val next = TournamentRules.nextWeek(now)
        val week = TournamentRules.currentWeek(now)
        if (me != uid || week != currentWeek) {
            uid = me; currentWeek = week; current = emptyList(); currentLoaded = false; runs = emptyList(); settled = 0; runsReadAt = 0; readAt = 0
        }
        if (!force && next == nextWeek && now - readAt < 60_000) return
        loading = true
        try {
            nextWeek = next
            nextMine = state.cloud.isSignedUp(next, me)
            nextCount = state.cloud.tournamentCount(next)
            if (!currentLoaded) currentMine = state.cloud.isSignedUp(week, me)
            readAt = now
            if (currentMine || currentLoaded) loadBracket(state, force)
        } catch (e: Exception) {
            message = CloudError.message(e)
        } finally { loading = false }
    }

    /** The week under way: its players (once: they no longer change) and the runs still moving. */
    suspend fun loadBracket(state: AppViewModel, force: Boolean = false) {
        if (!force && nowMs - runsReadAt < 60_000) return
        try {
            if (!currentLoaded) {
                current = state.cloud.tournamentPlayers(currentWeek)
                currentLoaded = true
                uid?.let { me -> currentMine = current.any { it.uid == me } }
            }
            val now = nowMs
            val total = TournamentRules.rounds(minOf(current.size, TournamentRules.MAX_PLAYERS))
            val start = TournamentRules.deadlineMs(currentWeek) ?: return
            if (total == 0 || now < start) return
            val from = settled + 1
            if (from > total) return
            val fresh = state.cloud.tournamentRuns(currentWeek, from)
            runs = runs.filter { it.round < from } + fresh
            runsReadAt = now
            settled = maxOf(settled, (1..total).lastOrNull { (TournamentRules.roundEndMs(currentWeek, it) ?: Long.MAX_VALUE) <= now } ?: 0)
        } catch (e: Exception) {
            message = CloudError.message(e)
        }
    }

    suspend fun signUp(state: AppViewModel) {
        val me = state.uid ?: return
        if (nextWeek.isEmpty()) return
        if (state.isSuspended) { message = CloudError.Kind.SUSPENDED.message; return }
        try {
            state.cloud.signUp(nextWeek, me, state.progress.username)
            nextMine = true; nextCount += 1; message = null
        } catch (e: Exception) { message = CloudError.message(e) }
    }
    suspend fun withdraw(state: AppViewModel) {
        val me = state.uid ?: return
        if (nextWeek.isEmpty()) return
        try {
            state.cloud.withdraw(nextWeek, me)
            nextMine = false; nextCount = maxOf(0, nextCount - 1); message = null
        } catch (e: Exception) { message = CloudError.message(e) }
    }

    /** My run of a round, just finished: no need to read everything again. */
    fun note(run: TournamentRun) { runs = runs.filterNot { it.round == run.round && it.uid == run.uid } + run }
    fun run(round: Int, uid: String): TournamentRun? = runs.firstOrNull { it.round == round && it.uid == uid }
}

/**
 * One tournament match on screen, the twin of the iPhone's TournamentPlaySession: my clock starts on
 * the server when I begin, the 5 words of the round, then my time is stamped by the server. A game left
 * halfway resumes where it was (its moves are kept on the phone; the clock kept going).
 */
class TournamentPlayViewModel : ViewModel() {
    sealed interface Phase {
        data object Ready : Phase
        data object Starting : Phase
        data object Playing : Phase
        data object Sending : Phase
        data object Done : Phase
        data class Failed(val message: String) : Phase
    }

    var week = ""; private set
    var round = 0; private set
    var phase by mutableStateOf<Phase>(Phase.Ready); private set
    var myRun by mutableStateOf<TournamentRun?>(null); private set
    var game: ChallengeGame? = null; private set
    private val clock = ServerClock()
    var answer by mutableStateOf("")
    var answerWrong by mutableStateOf(false); private set
    var cursor by mutableStateOf<Int?>(null); private set
    var version by mutableIntStateOf(0); private set
    var mistakeTick by mutableIntStateOf(0); private set
    var successTick by mutableIntStateOf(0); private set
    var passed by mutableStateOf<String?>(null); private set
    var passedTick by mutableIntStateOf(0); private set
    /** R (found), S (passed), W (wrong answer): replayed to resume a game. */
    private var moves = ""
    private var loaded = false

    val nowMs: Long get() = clock.now()
    val endMs: Long get() = TournamentRules.roundEndMs(week, round) ?: 0
    val elapsedMs: Long get() = myRun?.let { (nowMs - it.startedMs).coerceAtLeast(0) } ?: 0
    private val saveKey get() = "tournament.$week.$round"
    private fun prefs(state: AppViewModel) = state.getApplication<android.app.Application>().getSharedPreferences("cnsnn", Context.MODE_PRIVATE)

    /** A run already started (the app was closed): straight back into it. */
    fun loadOnce(week: String, round: Int, state: AppViewModel) {
        if (loaded) return
        loaded = true
        this.week = week; this.round = round
        val me = state.uid ?: return
        viewModelScope.launch {
            val known = state.tournament.run(round, me) ?: runCatching { state.cloud.tournamentRun(week, round, me) }.getOrNull()?.also { state.tournament.note(it) }
            if (known != null) {
                myRun = known
                if (known.finishedMs != null) phase = Phase.Done else start(state)
            }
        }
    }

    fun start(state: AppViewModel) {
        val me = state.uid ?: run { phase = Phase.Failed(CloudError.Kind.OFFLINE.message); return }
        if (state.isSuspended) { phase = Phase.Failed(CloudError.Kind.SUSPENDED.message); return }
        phase = Phase.Starting
        viewModelScope.launch {
            try {
                val (started, ids, learnt) = state.cloud.startTournamentRound(week, round, me)
                learnt?.let { clock.offsetMs = it.offsetMs }
                myRun = started
                val cards = ChallengeRules.cards(ids) ?: run { phase = Phase.Failed(CloudError.Kind.OFFLINE.message); return@launch }
                val fresh = ChallengeGame(cards)
                val saved = prefs(state).getString(saveKey, null)
                if (saved != null) {
                    for (move in saved) when (move) {
                        'R' -> fresh.card?.let { fresh.answer(it.wordFull) }
                        'S' -> fresh.skip()
                        'W' -> fresh.answer("")
                    }
                    moves = saved
                } else state.noteLiveDuelPlayed()
                game = fresh; version++
                if (fresh.finished) finish(state) else phase = Phase.Playing
            } catch (e: Exception) { phase = Phase.Failed(CloudError.message(e)) }
        }
    }

    val playing: Boolean get() = phase == Phase.Playing && game?.finished == false && nowMs < endMs

    fun press(letter: String) { if (playing) edit { it.insert(letter) } }
    fun delete() = edit { it.deleteBackward() }
    fun clear() = edit { TypedAnswer("") }
    fun moveCursor(steps: Int) = edit { it.move(steps) }
    fun placeCursor(index: Int) = edit { it.place(index) }
    private fun edit(change: (TypedAnswer) -> TypedAnswer) {
        val typed = change(TypedAnswer(answer, cursor))
        answer = typed.text; cursor = typed.cursor; answerWrong = false
    }

    fun submit(state: AppViewModel) {
        val current = game
        if (!playing || current == null || WordEngine.normalize(answer).isEmpty()) { mistakeTick++; return }
        when (current.answer(answer)) {
            ChallengeGame.Outcome.RIGHT -> { answer = ""; answerWrong = false; successTick++; moved("R", state) }
            ChallengeGame.Outcome.WRONG -> { answerWrong = true; mistakeTick++; moved("W", state) }
            ChallengeGame.Outcome.OVER -> {}
        }
        version++
    }

    fun skip(state: AppViewModel) {
        val current = game ?: return
        if (!playing) return
        answer = ""; answerWrong = false
        current.card?.let { passed = it.wordFull; passedTick++ }
        current.skip()
        version++
        moved("S", state)
    }

    private fun moved(move: String, state: AppViewModel) {
        moves += move
        prefs(state).edit().putString(saveKey, moves).apply()
        if (game?.finished == true) finish(state)
    }

    /** The server stamps the end; a failed send (network) can be tried again. */
    fun finish(state: AppViewModel) {
        val me = state.uid ?: return
        val current = game ?: return
        phase = Phase.Sending
        viewModelScope.launch {
            val sent = runCatching { state.cloud.finishTournamentRound(week, round, me, current.skips, current.errors) }
            // Read back in any case: a finish sent twice is refused, but the first one counts.
            val fresh = runCatching { state.cloud.tournamentRun(week, round, me) }.getOrNull()
            if (fresh?.finishedMs != null) {
                myRun = fresh; state.tournament.note(fresh)
                prefs(state).edit().remove(saveKey).apply()
                phase = Phase.Done
            } else {
                phase = Phase.Failed(sent.exceptionOrNull()?.let { CloudError.message(it) } ?: CloudError.Kind.OFFLINE.message)
            }
        }
    }
}
