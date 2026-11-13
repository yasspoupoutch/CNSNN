package com.poupoutch.cnsnn.state

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.firebase.firestore.ListenerRegistration
import com.poupoutch.cnsnn.core.ChallengeGame
import com.poupoutch.cnsnn.core.ChallengeRules
import com.poupoutch.cnsnn.core.LiveDuel
import com.poupoutch.cnsnn.core.LiveDuelRules
import com.poupoutch.cnsnn.core.ModeRandom
import com.poupoutch.cnsnn.core.ServerClock
import com.poupoutch.cnsnn.core.TypedAnswer
import com.poupoutch.cnsnn.core.WordEngine
import com.poupoutch.cnsnn.data.CloudError
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * A live duel on screen, the Android twin of the iPhone's LiveDuelSession: looking for a random
 * opponent, or waiting for a friend with a link, then the 3-2-1, the 5 words and the result. The duel's
 * document is listened to the whole time (one read per change), so each player sees the other move
 * forward. Times are the server's (core LiveDuel.kt).
 */
class LiveDuelViewModel : ViewModel() {
    sealed interface Phase {
        data object Connecting : Phase
        /** Looking for a random opponent; since when (this phone's clock). */
        data class Searching(val sinceMs: Long) : Phase
        /** Nobody was looking at the same time. */
        data object Nobody : Phase
        /** The link is ready: waiting for the friend. */
        data object Waiting : Phase
        /** The duel itself: its state says countdown, playing, finished or over. */
        data object Live : Phase
        data class Failed(val message: String) : Phase
    }

    /** "random", "link" or "join:ID". */
    var start = ""; private set
    var phase by mutableStateOf<Phase>(Phase.Connecting); private set
    var duel by mutableStateOf<LiveDuel?>(null); private set
    var game: ChallengeGame? = null; private set
    val clock = ServerClock()
    var answer by mutableStateOf("")
    var answerWrong by mutableStateOf(false); private set
    var cursor by mutableStateOf<Int?>(null); private set
    /** The core game is a plain object: this counter tells the screen it changed. */
    var version by mutableIntStateOf(0); private set
    var mistakeTick by mutableIntStateOf(0); private set
    var successTick by mutableIntStateOf(0); private set
    var passed by mutableStateOf<String?>(null); private set
    var passedTick by mutableIntStateOf(0); private set
    private var duelListener: ListenerRegistration? = null
    private var queueListener: ListenerRegistration? = null
    private var searchJob: Job? = null
    private var counted = false
    private var loaded = false

    val nowMs: Long get() = clock.now()
    /** My time so far, since the start. */
    val elapsedMs: Long get() = duel?.startMs?.let { (nowMs - it).coerceAtLeast(0) } ?: 0

    fun loadOnce(start: String, state: AppViewModel) {
        if (loaded) return
        loaded = true
        begin(start, state)
    }

    fun begin(start: String, state: AppViewModel) {
        this.start = start
        viewModelScope.launch {
            val uid = state.uid ?: run { phase = Phase.Failed(CloudError.Kind.OFFLINE.message); return@launch }
            if (state.isSuspended) { phase = Phase.Failed(CloudError.Kind.SUSPENDED.message); return@launch }
            phase = Phase.Connecting
            try {
                when {
                    start == "link" -> {
                        val (made, learnt) = state.cloud.createLinkDuel(uid, state.progress.username, draw(state))
                        learnt?.let { clock.offsetMs = it.offsetMs }
                        watch(made, state)
                    }
                    start.startsWith("join:") -> {
                        val (joined, learnt) = state.cloud.joinDuel(start.removePrefix("join:"), uid, state.progress.username)
                        learnt?.let { clock.offsetMs = it.offsetMs }
                        watch(joined, state)
                    }
                    else -> search(state)
                }
            } catch (e: Exception) { phase = Phase.Failed(CloudError.message(e)) }
        }
    }
    private fun draw(state: AppViewModel) = LiveDuelRules.draw(ModeRandom.seed(), state.progress.recentCards)

    // ---- Random opponent

    private suspend fun search(state: AppViewModel) {
        val uid = state.uid ?: return
        val since = System.currentTimeMillis()
        phase = Phase.Searching(since)
        val username = state.progress.username
        try {
            state.cloud.takeOpponent(uid, username, draw(state), clock)?.let { (taken, learnt) ->
                learnt?.let { clock.offsetMs = it.offsetMs }
                watch(taken, state)
                return
            }
            state.cloud.enterDuelQueue(uid, username)?.let { clock.offsetMs = it.offsetMs }
        } catch (e: Exception) { phase = Phase.Failed(CloudError.message(e)); return }
        queueListener = state.cloud.listenDuelQueue(uid) { id -> taken(id, state) }
        // Someone may have come in at the same moment: a new look now and then, then give up.
        searchJob = viewModelScope.launch {
            while (System.currentTimeMillis() - since < LiveDuelRules.SEARCH_MS) {
                delay(LiveDuelRules.SEARCH_EVERY_MS)
                if (phase !is Phase.Searching) return@launch
                val found = runCatching { state.cloud.takeOpponent(uid, username, draw(state), clock) }.getOrNull()
                if (found != null) {
                    stopQueue()
                    found.second?.let { clock.offsetMs = it.offsetMs }
                    watch(found.first, state)
                    return@launch
                }
            }
            if (phase !is Phase.Searching) return@launch
            queueListener?.remove(); queueListener = null
            val id = state.cloud.leaveDuelQueue(uid)
            if (id != null) taken(id, state) else phase = Phase.Nobody
        }
    }

    private fun taken(id: String, state: AppViewModel) {
        if (duel != null) return
        stopQueue()
        viewModelScope.launch {
            val found = runCatching { state.cloud.duel(id) }.getOrNull()
                ?: run { phase = Phase.Failed(CloudError.Kind.OFFLINE.message); return@launch }
            state.uid?.let { state.cloud.leaveDuelQueue(it) }
            watch(found, state)
        }
    }
    private fun stopQueue() {
        searchJob?.cancel(); searchJob = null
        queueListener?.remove(); queueListener = null
    }
    /** Looks again (after "personne pour l'instant"). */
    fun searchAgain(state: AppViewModel) {
        if (start != "random") return
        viewModelScope.launch { search(state) }
    }

    // ---- The duel

    private fun watch(found: LiveDuel, state: AppViewModel) {
        apply(found, state)
        if (duelListener != null) return
        duelListener = state.cloud.listenDuel(found.id) { fresh ->
            if (fresh != null) apply(fresh, state)
            else if (duel?.isOpen == true) phase = Phase.Failed(CloudError.Kind.DUEL_GONE.message)
        }
    }
    private fun apply(fresh: LiveDuel, state: AppViewModel) {
        duel = fresh
        if (fresh.isOpen) { phase = Phase.Waiting; return }
        phase = Phase.Live
        if (game == null) ChallengeRules.cards(fresh.cardIds)?.let {
            game = ChallengeGame(it); version++
            if (!counted) { counted = true; state.noteLiveDuelPlayed() }
        }
    }

    fun playing(uid: String?): Boolean {
        val d = duel ?: return false
        if (phase != Phase.Live || uid == null) return false
        return d.state(uid, nowMs) == LiveDuel.State.Playing && game?.finished == false
    }

    fun press(letter: String, uid: String?) { if (playing(uid)) edit { it.insert(letter) } }
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
        if (!playing(state.uid) || current == null || WordEngine.normalize(answer).isEmpty()) { mistakeTick++; return }
        when (current.answer(answer)) {
            ChallengeGame.Outcome.RIGHT -> { answer = ""; answerWrong = false; successTick++ }
            ChallengeGame.Outcome.WRONG -> { answerWrong = true; mistakeTick++ }
            ChallengeGame.Outcome.OVER -> {}
        }
        version++
        send(state)
    }

    fun skip(state: AppViewModel) {
        val current = game ?: return
        if (!playing(state.uid)) return
        answer = ""; answerWrong = false
        current.card?.let { passed = it.wordFull; passedTick++ }
        current.skip()
        version++
        send(state)
    }

    /** My total so far, after each word: the other player sees it at once. */
    private fun send(state: AppViewModel) {
        val uid = state.uid ?: return
        val d = duel ?: return
        val current = game ?: return
        if (current.index <= d.mine(uid).done) return
        state.cloud.moveInDuel(d, uid, current.index, current.skips)
    }
    /** A finish the server did not take (network): sent again. */
    fun resend(state: AppViewModel) = send(state)

    /** Leaving before the end loses the duel; a link nobody joined is withdrawn. */
    fun leave(state: AppViewModel) {
        stopQueue()
        val uid = state.uid
        if (uid != null) {
            // On the app's scope: this screen's own ends as it closes.
            if (phase is Phase.Searching) state.viewModelScope.launch { state.cloud.leaveDuelQueue(uid) }
            duel?.let { d ->
                if (d.isOpen && d.from.uid == uid) state.viewModelScope.launch { state.cloud.cancelLinkDuel(d) }
                else if (!d.isOpen && d.result(uid, nowMs) == null && !d.mine(uid).finished) state.cloud.quitDuel(d, uid)
            }
        }
        duelListener?.remove(); duelListener = null
    }

    /** "Rejouer", or a link after nobody was found: everything starts again. */
    fun restart(start: String, state: AppViewModel) {
        leave(state)
        duel = null; game = null; answer = ""; answerWrong = false; cursor = null; counted = false; version++
        begin(start, state)
    }

    override fun onCleared() {
        stopQueue()
        duelListener?.remove()
    }
}
