package com.poupoutch.cnsnn.state

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.poupoutch.cnsnn.core.Attempt
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.DailyPool
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.GameMode
import com.poupoutch.cnsnn.core.Glance
import com.poupoutch.cnsnn.core.LeaderboardEntry
import com.poupoutch.cnsnn.core.NameFilter
import com.poupoutch.cnsnn.core.Progress
import com.poupoutch.cnsnn.core.SecretDaily
import com.poupoutch.cnsnn.core.SeedCards
import com.poupoutch.cnsnn.core.Submission
import com.poupoutch.cnsnn.core.WordEngine
import com.poupoutch.cnsnn.data.CloudError
import com.poupoutch.cnsnn.data.CloudProfile
import com.poupoutch.cnsnn.data.CloudRepository
import com.poupoutch.cnsnn.data.LocalStore
import com.poupoutch.cnsnn.reminders.Reminders
import com.poupoutch.cnsnn.widget.DailyWidget
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant

/** The player's state for the whole app, the Android twin of the iPhone's AppState. */
class AppViewModel(app: Application) : AndroidViewModel(app) {
    val local = LocalStore(app)
    val cloud = CloudRepository()

    var progress by mutableStateOf(Progress()); private set
    var cards by mutableStateOf(SeedCards.all); private set
    var error by mutableStateOf<String?>(null)
    var isBusy by mutableStateOf(false); private set
    var uid by mutableStateOf<String?>(null); private set
    var isAnonymous by mutableStateOf(true); private set
    var email by mutableStateOf<String?>(null); private set
    var isAdmin by mutableStateOf(false); private set
    /** A moderator suspended this account: no ranked daily, proposals or reports. */
    var isSuspended by mutableStateOf(false); private set
    /** Official totals from the leaderboard, when signed in. */
    var official by mutableStateOf<LeaderboardEntry?>(null); private set
    /** True while a returning player's profile is fetched at launch: onboarding stays hidden meanwhile. */
    var isRestoring by mutableStateOf(false); private set
    var avatar by mutableStateOf(local.avatar); private set
    var hiddenPlayers by mutableStateOf(local.hiddenPlayers); private set

    private var scope: String? = local.activeScope
    private var savingAllowed = true
    private var cloudSave: Job? = null

    init {
        val saved = local.load(scope)
        if (saved == null) { savingAllowed = false; error = "La sauvegarde locale est illisible. Elle n’a pas été écrasée." }
        else progress = saved
        isRestoring = progress.username.isEmpty() && cloud.hasCurrentUser
        viewModelScope.launch { connect() }
    }

    val streak: Int get() = official?.currentStreak() ?: progress.streak()

    // ---- Saving

    /** Saves on the phone at once, then online shortly after (grouping quick successive changes). */
    fun update(change: (Progress) -> Progress) { progress = change(progress); persist() }
    private fun persist() {
        if (!savingAllowed) return
        local.save(progress, scope)
        scheduleCloudSave()
        refreshGlance()
    }
    fun refreshGlance(force: Boolean = false) {
        val glance = Glance.of(progress, streak)
        if (force || glance != local.glance) {
            local.glance = glance
            DailyWidget.refresh(getApplication())
            Reminders.schedule(getApplication())
        }
    }
    private fun scheduleCloudSave() {
        val user = uid ?: return
        cloudSave?.cancel()
        cloudSave = viewModelScope.launch {
            delay(1500)
            if (uid == user) runCatching { cloud.saveCloudProgress(progress, user) }
        }
    }
    /** Brings the online copy and this phone together, so a reinstall or a second device finds everything. */
    private suspend fun syncProgress() {
        val user = uid ?: return
        try {
            cloud.cloudProgress(user)?.let { remote ->
                val merged = progress.merged(remote)
                progress = merged.copy(username = progress.username.ifEmpty { remote.username })
            }
            persist()
        } catch (_: Exception) { /* Offline: the next change or launch syncs again. */ }
    }

    // ---- Session

    fun setAvatar(index: Int) { avatar = index; local.avatar = index }

    fun start(username: String) = viewModelScope.launch {
        if (isBusy) return@launch
        val name = username.trim()
        if (name.length !in 2..20) { error = "Choisissez un pseudo de 2 à 20 caractères."; return@launch }
        if (!NameFilter.isAllowed(name)) { error = REFUSED_NAME; return@launch }
        isBusy = true
        try {
            activate(cloud.bootstrap(name), preservingGuest = true)
        } catch (e: Exception) {
            error = "Connexion impossible : " + CloudError.message(e); return@launch
        } finally { isBusy = false }
        refreshAll()
    }
    private suspend fun connect() {
        try {
            if (progress.username.isEmpty() && !cloud.hasCurrentUser) return
            isBusy = true
            try {
                activate(cloud.bootstrap(progress.username.ifEmpty { "Joueur" }), preservingGuest = true)
            } catch (e: Exception) {
                // Offline launches stay quiet: Classique works and the home screen says it is offline.
                val code = CloudError.code(e)
                if (code != CloudError.Code.NETWORK && code != CloudError.Code.UNAVAILABLE && e !is CloudError) error = CloudError.message(e)
                return
            } finally { isBusy = false }
            refreshAll()
        } finally { isRestoring = false }
    }
    /** Everything that follows a successful sign-in. */
    suspend fun refreshAll() {
        syncProgress()
        refreshCards()
        finishPendingDaily()
        refreshOfficial()
        isAdmin = runCatching { cloud.isAdmin() }.getOrDefault(false)
        uid?.let { user -> isSuspended = runCatching { cloud.isSuspended(user) }.getOrDefault(isSuspended) }
    }
    fun refreshModeration() = viewModelScope.launch {
        isAdmin = runCatching { cloud.isAdmin() }.getOrDefault(isAdmin)
        uid?.let { user -> isSuspended = runCatching { cloud.isSuspended(user) }.getOrDefault(isSuspended) }
    }

    private fun activate(profile: CloudProfile, preservingGuest: Boolean) {
        if (uid != profile.uid) {
            val restored = local.load(profile.uid) ?: throw IllegalStateException("La sauvegarde locale est illisible.")
            if (restored.username.isNotEmpty()) progress = if (preservingGuest) restored.merged(progress) else restored
            else if (!preservingGuest) progress = Progress()
            scope = profile.uid; local.activeScope = profile.uid
        }
        uid = profile.uid; isAnonymous = profile.anonymous; email = profile.email
        progress = progress.copy(username = profile.username)
        persist()
    }
    fun signOut() {
        persist(); cloudSave?.cancel()
        cloud.signOut()
        resetToGuest()
    }
    private fun resetToGuest() {
        uid = null; isAnonymous = true; email = null; isAdmin = false; isSuspended = false; official = null
        progress = Progress(); cards = SeedCards.all
        scope = null; local.activeScope = null; persist()
    }

    // ---- Accounts

    /** Saves the guest as a permanent account (same UID, nothing moves). */
    suspend fun createAccount(email: String, password: String) {
        activate(cloud.createPermanentAccount(email, password), preservingGuest = true)
        refreshAll()
    }
    /** Switches to an existing account. Practice games on this phone join it; official results stay with their profile. */
    suspend fun signIn(email: String, password: String) {
        val guestPractice = progress.copy(attempts = progress.attempts.filter { it.mode == GameMode.CLASSIC },
            dailyStarted = emptyMap(), dailyStartedAt = emptyMap(), submissions = emptyList())
        persist()
        val profile = cloud.signIn(email, password)
        activate(profile, preservingGuest = false)
        progress = progress.merged(guestPractice).copy(username = profile.username)
        persist()
        refreshAll()
    }
    /** Deletes the account and everything stored for it, online and on this phone. */
    suspend fun deleteAccount(password: String?) {
        val user = uid ?: return
        cloudSave?.cancel()
        cloud.deleteAccount(user, password)
        local.erase(user); local.erase(null)
        setAvatar(0)
        resetToGuest()
    }

    // ---- Profile and catalogue

    fun rename(name: String) = viewModelScope.launch {
        val clean = name.trim()
        if (clean.length !in 2..20) { error = "Le pseudo doit contenir 2 à 20 caractères."; return@launch }
        if (!NameFilter.isAllowed(clean)) { error = REFUSED_NAME; return@launch }
        try {
            uid?.let { cloud.rename(it, clean) }
            update { it.copy(username = clean) }
            refreshOfficial()
        } catch (e: Exception) { error = CloudError.message(e) }
    }
    /** Classique plays the built-in cards plus every approved community card. */
    suspend fun refreshCards() {
        if (uid == null) return
        try {
            val community = cloud.cards()
            val known = (SeedCards.all + DailyPool.all).map { WordEngine.normalize(it.wordFull) }.toSet()
            cards = SeedCards.all + community.filter { WordEngine.normalize(it.wordFull) !in known }
        } catch (_: Exception) { /* Offline: the built-in cards remain. */ }
    }
    fun card(id: String): Card? {
        SecretDaily.day(id)?.let { return progress.dailyWords?.get(it) }
        return DailyPool.card(id) ?: cards.firstOrNull { it.id == id } ?: SeedCards.all.firstOrNull { it.id == id }
    }

    // ---- Mot du jour

    /** Keeps a secret daily word on this phone: masked while playing, revealed once the game is over. */
    fun storeDailyWord(card: Card, day: String) {
        val known = progress.dailyWords?.get(day)
        if (known != null && known.wordFull.isNotEmpty() && card.wordFull.isEmpty()) return
        val oldest = DailySchedule.key(Instant.now().minusSeconds(400L * 86_400))
        update { p -> p.copy(dailyWords = ((p.dailyWords ?: emptyMap()) + (day to card)).filterKeys { it >= oldest }) }
    }
    /** Publishes results whose finish reached the server but whose result did not (app closed, network lost). */
    private suspend fun finishPendingDaily() {
        val user = uid ?: return
        val today = DailySchedule.key()
        for (day in listOf(DailySchedule.shift(today, -1), today)) {
            val session = runCatching { cloud.dailySession(user, day) }.getOrNull() ?: continue
            if (!session.finished) continue
            runCatching { cloud.publishDailyResult(user, day) }.getOrNull()?.let { recordOfficial(it) }
        }
    }
    suspend fun refreshOfficial() {
        val user = uid ?: return
        runCatching { cloud.leaderboardEntry(user) }.getOrNull()?.let { official = it; refreshGlance() }
    }

    // ---- Results

    fun record(attempt: Attempt) {
        if (attempt.dailyKey != null && progress.attempts.any { it.dailyKey == attempt.dailyKey }) return
        update { p ->
            p.copy(attempts = p.attempts + attempt, recentCards = (p.recentCards.filter { it != attempt.cardID } + attempt.cardID).takeLast(20))
        }
    }
    /** The server's result replaces this phone's measurement for that day. */
    fun recordOfficial(attempt: Attempt) {
        val day = attempt.dailyKey ?: return
        val index = progress.attempts.indexOfFirst { it.dailyKey == day }
        if (index < 0) { record(attempt); return }
        update { p -> p.copy(attempts = p.attempts.toMutableList().also { it[index] = attempt.copy(id = p.attempts[index].id) }) }
    }

    // ---- Community

    suspend fun submit(card: Card): Boolean = try {
        val word = WordEngine.normalize(card.wordFull)
        if ((cards + DailyPool.all).any { WordEngine.normalize(it.wordFull) == word }) throw CloudError(CloudError.Kind.DUPLICATE_WORD)
        val user = uid ?: throw CloudError(CloudError.Kind.OFFLINE)
        val stored = cloud.submit(card, user)
        update { it.copy(submissions = it.submissions + Submission(card = stored)) }
        true
    } catch (e: Exception) { error = CloudError.message(e); false }
    fun refreshSubmissions() = viewModelScope.launch {
        val user = uid ?: return@launch
        runCatching { cloud.submissions(user) }.onSuccess { list -> update { it.copy(submissions = list) } }
    }

    fun hide(player: String) { hiddenPlayers = hiddenPlayers + player; local.hiddenPlayers = hiddenPlayers }
    fun showAllPlayers() { hiddenPlayers = emptySet(); local.hiddenPlayers = emptySet() }

    companion object {
        const val REFUSED_NAME = "Ce pseudo n’est pas autorisé. Choisissez-en un autre."
        const val SUSPENDED_TEXT = "Votre compte est suspendu par la modération : le mot du jour classé, les propositions et les signalements ne sont plus disponibles. Contactez le support depuis votre profil."
    }
}
