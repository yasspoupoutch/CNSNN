package com.poupoutch.cnsnn.state

import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.poupoutch.cnsnn.core.Attempt
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.DailyScore
import com.poupoutch.cnsnn.core.CardPicker
import com.poupoutch.cnsnn.core.Category
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.DailyStanding
import com.poupoutch.cnsnn.core.Difficulty
import com.poupoutch.cnsnn.core.GameMode
import com.poupoutch.cnsnn.core.Guesses
import com.poupoutch.cnsnn.core.SecretDaily
import com.poupoutch.cnsnn.core.WordEngine
import com.poupoutch.cnsnn.data.CloudError
import com.poupoutch.cnsnn.data.CloudRepository
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

/**
 * One game, the Android twin of the iPhone's GameSession. The Mot du jour is always the official,
 * server-timed game: the consonants appear once the server has recorded the start, each guess is
 * counted by the server (20 a day) then checked by the security rules, and the word is revealed
 * only once the game is over.
 */
class GameViewModel : ViewModel() {
    sealed interface Phase { data object Loading : Phase; data object Playing : Phase; data class Failed(val message: String) : Phase }

    var phase by mutableStateOf<Phase>(Phase.Playing); private set
    var card by mutableStateOf<Card?>(null); private set
    var answer by mutableStateOf("")
    var feedback by mutableStateOf<String?>(null); private set
    var usedHint by mutableStateOf(false); private set
    var result by mutableStateOf<Attempt?>(null); private set
    var wrongAnswers by mutableStateOf(0); private set
    val wrongGuesses = mutableStateListOf<String>()
    var ranked by mutableStateOf(false); private set
    /** The finish is recorded on this phone and waits for the network to become official. */
    var pendingOfficial by mutableStateOf(false); private set
    var standing by mutableStateOf<DailyStanding?>(null); private set
    /** A guess or the hint is on its way to the server. */
    var checking by mutableStateOf(false); private set
    /** Why the last check could not reach the server, shown under the board. */
    var notice by mutableStateOf<String?>(null); private set
    /** Bumped on each wrong guess, so the answer line shakes. */
    var mistakeTick by mutableStateOf(0); private set
    var finishedHere by mutableStateOf(false); private set
    /** "Plus que 3 essais" under the board once few guesses remain on the Mot du jour. */
    val remainingText: String? get() = if (ranked && result == null) Guesses.remainingText(wrongAnswers) else null

    var mode = GameMode.CLASSIC; private set
    /** Rattrapage: a missed daily word of the week, played later and counted with 5 minutes more (see CatchUp). */
    var catchUpDay by mutableStateOf<String?>(null); private set
    private var category: Category? = null
    private var difficulty: Difficulty? = null
    private var dailyKey: String? = null
    private var dailyStart: Instant? = null
    private var started = SystemClock.elapsedRealtime()
    private var elapsedBeforePause = 0L
    private var paused = false
    private var loaded = false
    /** The last guess the server counted, which a win must name. */
    private var lastGuess: String? = null

    fun loadOnce(mode: GameMode, category: Category?, difficulty: Difficulty?, state: AppViewModel, catchUp: String? = null) {
        if (loaded) return
        loaded = true; this.mode = mode; this.category = category; this.difficulty = difficulty; catchUpDay = catchUp
        load(state)
    }

    private fun load(state: AppViewModel) {
        answer = ""; feedback = null; result = null; usedHint = false; wrongAnswers = 0; wrongGuesses.clear()
        started = SystemClock.elapsedRealtime(); elapsedBeforePause = 0; paused = false; dailyKey = null; dailyStart = null; lastGuess = null
        ranked = false; pendingOfficial = false; standing = null; phase = Phase.Playing; checking = false; notice = null; finishedHere = false
        val catchUp = catchUpDay
        if (mode == GameMode.DAILY) {
            val key = catchUp ?: DailySchedule.key(); dailyKey = key
            ranked = true; phase = Phase.Loading
            viewModelScope.launch {
                if (state.uid == null) state.refreshAll()
                val uid = state.uid ?: run { phase = Phase.Failed(CloudError.Kind.OFFLINE.message); return@launch }
                if (state.isSuspended && runCatching { state.cloud.dailySession(uid, key) }.getOrNull() == null) {
                    phase = Phase.Failed(AppViewModel.SUSPENDED_TEXT); return@launch
                }
                loadRankedDaily(key, catchUp != null, state.cloud, uid, state)
            }
        } else {
            card = CardPicker.candidates(state.cards, category, difficulty, state.progress.recentCards).randomOrNull()
        }
    }

    /**
     * One server session per day. A finished day always shows its official result. A caught-up day
     * ([catchUp]) runs the same way: its answer stays secret until the week is over.
     */
    private suspend fun loadRankedDaily(key: String, catchUp: Boolean, cloud: CloudRepository, uid: String, state: AppViewModel) {
        try {
            val session = cloud.dailySession(uid, key)
            if (session != null) {
                usedHint = session.hintUsed
                card = state.card(session.cardId)
                if (session.finished) cloud.dailySecret(key)?.let { state.storeDailyWord(it, key); card = it }
                else if (card == null) cloud.dailyPuzzle(key)?.let { state.storeDailyWord(it, key); card = it }
                val masked = card
                if (session.hintUsed && !session.finished && masked != null && masked.hint.isEmpty()) {
                    card = masked.copy(hint = cloud.dailyHint(key) ?: ""); state.storeDailyWord(card!!, key)
                }
                if (session.finished) {
                    val official = cloud.publishDailyResult(uid, key)
                    if (official != null) {
                        state.recordOfficial(official); result = official; loadStanding(cloud, official)
                    } else state.progress.attempts.firstOrNull { it.dailyKey == key }?.let { result = it; pendingOfficial = true }
                    phase = Phase.Playing
                    return
                }
                usedHint = session.hintUsed
                dailyStart = session.startedAt
                // Every guess counted so far was wrong (a right one ends the game).
                wrongAnswers = session.guesses; lastGuess = session.guess
                state.progress.attempts.firstOrNull { it.dailyKey == key }?.let { local ->
                    // Finished on this phone but the finish never reached the server: send it again.
                    if (local.correct) wrongAnswers = maxOf(0, session.guesses - 1)
                    result = local; pendingOfficial = true; phase = Phase.Playing
                    makeOfficial(cloud, uid, key, local.correct, state)
                    return
                }
            } else {
                state.progress.attempts.firstOrNull { it.dailyKey == key }?.let { local ->
                    // Already played on this phone before the account existed: no second try.
                    result = local; card = state.card(local.cardID); ranked = false; phase = Phase.Playing
                    return
                }
                val puzzle = cloud.dailyPuzzle(key) ?: run { phase = Phase.Failed("Le mot du jour est indisponible."); return }
                val started = cloud.startDaily(uid, key, puzzle.id, catchUp)
                card = puzzle; dailyStart = started.startedAt
                state.storeDailyWord(puzzle, key)
            }
            card?.let { c ->
                state.update { it.copy(dailyStarted = it.dailyStarted + (key to c.id), dailyStartedAt = it.dailyStartedAt + (key to dailyStart!!)) }
            }
            phase = if (card == null) Phase.Failed("Cette carte n’existe pas dans cette version. Mettez l’application à jour.") else Phase.Playing
        } catch (e: Exception) {
            phase = Phase.Failed(CloudError.message(e))
        }
    }

    fun retry(state: AppViewModel) = load(state)
    fun next(state: AppViewModel) = load(state)

    val secret: Boolean get() = card?.id?.let { SecretDaily.day(it) } != null
    /** The Mot du jour's official time: the hint adds a minute, a lost day counts ten. */
    fun officialMs(attempt: Attempt): Int = DailyScore.scoreMs(attempt.timeMs, usedHint, attempt.correct)

    fun revealHint(state: AppViewModel) {
        if (usedHint || result != null || checking) return
        val uid = state.uid; val day = dailyKey
        if (!ranked || uid == null || day == null) { usedHint = true; return }
        // The server opens the hint only once it has recorded its use.
        checking = true; notice = null
        viewModelScope.launch {
            try {
                val hint = state.cloud.revealSecretHint(uid, day)
                val shown = card
                if (hint == null || shown == null) { notice = CloudError.Kind.OFFLINE.message; return@launch }
                card = shown.copy(hint = hint); usedHint = true
                state.storeDailyWord(card!!, day)
            } catch (e: Exception) { notice = CloudError.message(e) } finally { checking = false }
        }
    }

    fun pause() { if (!paused && result == null) { elapsedBeforePause += SystemClock.elapsedRealtime() - started; paused = true } }
    fun resume() { if (paused) { started = SystemClock.elapsedRealtime(); paused = false } }
    val elapsedMs: Int get() {
        dailyStart?.let { return maxOf(0, Duration.between(it, Instant.now()).toMillis().toInt()) }
        return (elapsedBeforePause + if (paused) 0 else SystemClock.elapsedRealtime() - started).toInt()
    }

    fun press(letter: String) {
        if (result != null || answer.length >= 40) return
        // No leading or double spaces.
        if (letter == " " && (answer.isEmpty() || answer.endsWith(" "))) return
        answer += letter
    }
    fun delete() { if (answer.isNotEmpty()) answer = answer.dropLast(1) }

    fun submit(state: AppViewModel) {
        val shown = card ?: return
        if (result != null || checking) return
        if (WordEngine.normalize(answer).isEmpty()) { mistakeTick++; return }
        if (ranked && state.uid != null && dailyKey != null) { submitRanked(state); return }
        if (!WordEngine.matches(answer, shown.wordFull)) { missed(); return }
        finishedHere = true
        finish(true, state)
    }
    private fun missed(counted: Int? = null) {
        wrongAnswers = counted ?: (wrongAnswers + 1); wrongGuesses += answer; feedback = "Pas encore. Essayez une autre idée."; mistakeTick++; answer = ""
    }
    /**
     * The server counts the guess first (20 a day, one per second), then the guess goes as the finish
     * of the session: the rules accept it only if it is the word. A refused finish is a wrong guess.
     */
    private fun submitRanked(state: AppViewModel) {
        val uid = state.uid ?: return; val day = dailyKey ?: return; val shown = card ?: return
        val guess = WordEngine.normalize(answer)
        checking = true; notice = null
        viewModelScope.launch {
            try {
                val count = state.cloud.registerGuess(uid, day, guess)
                lastGuess = guess
                // A secret word is checked by the server only; a known one is checked here first.
                if (secret || WordEngine.matches(answer, shown.wordFull)) {
                    val confirmed = try { state.cloud.finishDaily(uid, day, true, count - 1, guess) } catch (e: Exception) {
                        if (CloudError.code(e) != CloudError.Code.PERMISSION_DENIED) throw e
                        null
                    }
                    if (confirmed == false) {
                        // Not confirmed in time. If it was right, the server keeps it and the next opening shows the result.
                        wrongAnswers = count - 1
                        notice = "Connexion trop lente. Vérifiez le réseau puis réessayez."; return@launch
                    }
                    if (confirmed == true) {
                        wrongAnswers = count - 1
                        if (secret) reveal(state, day)
                        finishedHere = true
                        finish(true, state, alreadyFinished = true)
                        return@launch
                    }
                }
                missed(count)
                // The 20th wrong guess ends the game as lost.
                if (count >= Guesses.MAX) outOfGuesses(state, uid, day)
            } catch (e: Exception) {
                when ((e as? CloudError)?.kind) {
                    CloudError.Kind.GUESS_LIMIT -> { wrongAnswers = Guesses.MAX; outOfGuesses(state, uid, day) }
                    // Finished on another device: show the official result.
                    CloudError.Kind.DAILY_FINISHED -> { checking = false; load(state) }
                    else -> notice = CloudError.message(e)
                }
            } finally { checking = false }
        }
    }
    private suspend fun outOfGuesses(state: AppViewModel, uid: String, day: String) {
        finishedHere = true
        if (secret) loseSecret(state, uid, day)
        else { checking = false; finish(false, state) }
    }
    /** Records the loss on the server, then reveals the word and shows the result. */
    private suspend fun loseSecret(state: AppViewModel, uid: String, day: String) {
        val ok = runCatching { recordLoss(state.cloud, uid, day) }.getOrDefault(false)
        if (!ok) { notice = CloudError.Kind.OFFLINE.message; return }
        reveal(state, day)
        finish(false, state, alreadyFinished = true)
    }
    /**
     * A loss carries the server's count of guesses as its wrong answers. If the server counted
     * differently (another device, a lost reply), the session is read again and the finish retried once.
     */
    private suspend fun recordLoss(cloud: CloudRepository, uid: String, day: String): Boolean = try {
        cloud.finishDaily(uid, day, false, wrongAnswers)
    } catch (e: Exception) {
        if (CloudError.code(e) != CloudError.Code.PERMISSION_DENIED) throw e
        val session = cloud.dailySession(uid, day) ?: throw e
        if (session.finished) true
        else { wrongAnswers = session.guesses; cloud.finishDaily(uid, day, false, session.guesses) }
    }
    private suspend fun reveal(state: AppViewModel, day: String) {
        runCatching { state.cloud.dailySecret(day) }.getOrNull()?.let { card = it; state.storeDailyWord(it, day) }
    }

    /** Ends the card. Giving up on a secret word records the loss on the server first, then reveals the word. */
    fun giveUp(state: AppViewModel) { finishedHere = true; finish(false, state) }

    private fun finish(correct: Boolean, state: AppViewModel, alreadyFinished: Boolean = false) {
        if (result != null || (checking && !alreadyFinished)) return
        val uid = state.uid; val day = dailyKey
        if (secret && !correct && !alreadyFinished && uid != null && day != null) {
            checking = true; notice = null
            viewModelScope.launch {
                try { loseSecret(state, uid, day) } finally { checking = false }
            }
            return
        }
        val shown = card ?: return
        val ms = elapsedMs
        val attempt = Attempt(cardID = shown.id, mode = mode, correct = correct, timeMs = ms, date = Instant.now(), dailyKey = day,
            catchUp = if (catchUpDay != null) true else null)
        result = attempt
        state.record(attempt)
        if (ranked && uid != null && day != null) {
            pendingOfficial = true
            viewModelScope.launch { makeOfficial(state.cloud, uid, day, correct, state, finished = alreadyFinished) }
        }
    }
    /** Stamps the finish on the server, then shows the server's time instead of the local one. */
    private suspend fun makeOfficial(cloud: CloudRepository, uid: String, day: String, correct: Boolean, state: AppViewModel, finished: Boolean = false) {
        try {
            if (!finished) {
                val ok = if (correct) cloud.finishDaily(uid, day, true, wrongAnswers, lastGuess ?: return) else recordLoss(cloud, uid, day)
                if (!ok) return
            }
            val official = cloud.publishDailyResult(uid, day) ?: return
            state.recordOfficial(official)
            result = official.copy(id = result?.id ?: official.id)
            pendingOfficial = false
            state.refreshOfficial()
            loadStanding(cloud, official)
        } catch (_: Exception) {
            // Stays pending: the next launch publishes it.
        }
    }
    private suspend fun loadStanding(cloud: CloudRepository, attempt: Attempt) {
        // A caught-up day is out of the day's ranking.
        if (catchUpDay != null) return
        val day = attempt.dailyKey ?: return
        val rank = DailyScore.rank(day, officialMs(attempt), attempt.correct) ?: return
        standing = runCatching { cloud.standing(day, rank, attempt.correct) }.getOrNull()
    }
}
