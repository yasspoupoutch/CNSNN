package com.poupoutch.cnsnn.state

import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.poupoutch.cnsnn.core.Challenge
import com.poupoutch.cnsnn.core.ChallengeGame
import com.poupoutch.cnsnn.core.ChallengeRules
import com.poupoutch.cnsnn.core.TypedAnswer
import com.poupoutch.cnsnn.core.WordEngine
import com.poupoutch.cnsnn.data.CloudError
import kotlinx.coroutines.launch

/**
 * One side of a friend challenge on screen, the Android twin of the iPhone's ChallengeSession. The
 * official time is the server's (start and finish stamped in Firestore); the chrono shown while
 * playing is this phone's. The game is saved after every word, so a closed app picks up at the same
 * word, the time away included.
 */
class ChallengeViewModel : ViewModel() {
    sealed interface Phase {
        data object Starting : Phase
        data object Playing : Phase
        data object Sending : Phase
        data object Done : Phase
        data class Failed(val message: String) : Phase
    }

    var challenge by mutableStateOf<Challenge?>(null); private set
    var game: ChallengeGame? = null; private set
    var phase by mutableStateOf<Phase>(Phase.Starting); private set
    var answer by mutableStateOf("")
    /** The last answer was wrong: it stays on screen in red, so a typo is fixed without retyping it all. */
    var answerWrong by mutableStateOf(false); private set
    /** The caret in the answer (TypedAnswer.cursor): null at the end. */
    var cursor by mutableStateOf<Int?>(null); private set
    /** The core game is a plain object: this counter tells the screen it changed. */
    var version by mutableIntStateOf(0); private set
    var mistakeTick by mutableIntStateOf(0); private set
    var successTick by mutableIntStateOf(0); private set
    /** The answer of the word just passed, shown for a moment. */
    var passed by mutableStateOf<String?>(null); private set
    var passedTick by mutableIntStateOf(0); private set
    private var start = SystemClock.elapsedRealtime()
    private var baseMs = 0L
    private var loaded = false

    val elapsedMs: Long get() = baseMs + (SystemClock.elapsedRealtime() - start)

    fun loadOnce(id: String, state: AppViewModel) {
        if (loaded) return
        loaded = true
        begin(id, state)
    }

    /** Starts the friend's clock on the server (the challenger's started with the challenge), then plays. */
    fun begin(id: String, state: AppViewModel) = viewModelScope.launch {
        phase = Phase.Starting
        val uid = state.uid
        val known = state.challenges.firstOrNull { it.id == id } ?: runCatching { state.cloud.challenge(id) }.getOrNull()
        if (uid == null || known == null) { phase = Phase.Failed(CloudError.Kind.OFFLINE.message); return@launch }
        challenge = known
        if (known.mine(uid).finished) { state.local.clearChallengeRun(id); phase = Phase.Done; return@launch }
        if (System.currentTimeMillis() >= known.finishDeadlineMs) { state.local.clearChallengeRun(id); phase = Phase.Failed(EXPIRED); return@launch }
        val cards = ChallengeRules.cards(known.cardIds) ?: run { phase = Phase.Failed(CloudError.Kind.CHALLENGE_UNAVAILABLE.message); return@launch }
        val started = try { state.startChallenge(known) } catch (e: Exception) { phase = Phase.Failed(CloudError.message(e)); return@launch }
        challenge = started
        // A result sent earlier may have reached the server after all.
        if (started.mine(uid).finished) { state.local.clearChallengeRun(id); phase = Phase.Done; return@launch }
        val saved = state.local.loadChallengeRun(id)
        val restored = saved?.let { ChallengeGame.restore(cards, it.first) }
        if (saved != null && restored != null) {
            game = restored
            baseMs = saved.second + maxOf(0L, System.currentTimeMillis() - saved.third)
        } else {
            game = ChallengeGame(cards); baseMs = 0
        }
        start = SystemClock.elapsedRealtime()
        version++
        phase = Phase.Playing
        if (game?.finished == true) finish(state)
    }

    fun press(letter: String) {
        if (phase != Phase.Playing) return
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
        val current = game
        if (phase != Phase.Playing || current == null || WordEngine.normalize(answer).isEmpty()) { mistakeTick++; return }
        when (current.answer(answer)) {
            ChallengeGame.Outcome.RIGHT -> { answer = ""; answerWrong = false; successTick++ }
            ChallengeGame.Outcome.WRONG -> { answerWrong = true; mistakeTick++ }
            ChallengeGame.Outcome.OVER -> {}
        }
        afterMove(state)
    }

    /** Next word, for 20 seconds. */
    fun skip(state: AppViewModel) {
        val current = game ?: return
        if (phase != Phase.Playing) return
        answer = ""; answerWrong = false
        current.card?.let { passed = it.wordFull; passedTick++ }
        current.skip()
        afterMove(state)
    }

    /** Gives up: the words left count as skipped. */
    fun abandon(state: AppViewModel) {
        val current = game ?: return
        if (phase != Phase.Playing) return
        while (!current.finished) current.skip()
        afterMove(state)
    }

    private fun afterMove(state: AppViewModel) {
        version++
        val current = game ?: return
        val id = challenge?.id ?: return
        if (current.finished) viewModelScope.launch { finish(state) }
        else state.local.saveChallengeRun(id, current.saved(), elapsedMs)
    }

    /**
     * The game is kept on the phone until the server confirms the finish: a lost connection never
     * loses a result, and "Réessayer" (or the next launch) sends it again.
     */
    private suspend fun finish(state: AppViewModel) {
        val current = game ?: return
        val playing = challenge ?: return
        if (phase != Phase.Playing) return
        phase = Phase.Sending
        state.local.saveChallengeRun(playing.id, current.saved(), elapsedMs)
        val (fresh, outcome) = state.finishChallenge(playing, current.skips, current.errors)
        challenge = fresh
        phase = when (outcome) {
            AppViewModel.ChallengeSend.CONFIRMED -> { state.local.clearChallengeRun(playing.id); Phase.Done }
            AppViewModel.ChallengeSend.EXPIRED -> { state.local.clearChallengeRun(playing.id); Phase.Failed(EXPIRED) }
            AppViewModel.ChallengeSend.PENDING -> Phase.Failed(PENDING)
        }
    }

    companion object {
        const val PENDING = "Résultat en attente de validation. Votre partie est gardée sur ce téléphone : vérifiez le réseau puis réessayez. Le chrono officiel s’arrête quand le serveur reçoit votre résultat."
        const val EXPIRED = "Le délai de ce défi est dépassé : ce résultat n’a pas pu être enregistré."
    }

    /** My time as the server measured it, or this phone's while the server has not confirmed. */
    fun myScoreMs(uid: String): Long = challenge?.mine(uid)?.scoreMs ?: game?.scoreMs(elapsedMs) ?: 0L
}
