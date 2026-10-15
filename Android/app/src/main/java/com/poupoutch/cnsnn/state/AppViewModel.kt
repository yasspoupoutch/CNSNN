package com.poupoutch.cnsnn.state

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.poupoutch.cnsnn.core.Attempt
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.Challenge
import com.poupoutch.cnsnn.core.ChallengeGame
import com.poupoutch.cnsnn.core.ChallengeRules
import com.poupoutch.cnsnn.core.ChallengeTally
import com.poupoutch.cnsnn.core.ModeRandom
import com.poupoutch.cnsnn.core.CommunityRules
import com.poupoutch.cnsnn.core.DailyPool
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.ExtraCards
import com.poupoutch.cnsnn.core.GameMode
import com.poupoutch.cnsnn.core.Glance
import com.poupoutch.cnsnn.core.LeaderboardEntry
import com.poupoutch.cnsnn.core.ModeCatalogue
import com.poupoutch.cnsnn.core.NameFilter
import com.poupoutch.cnsnn.core.PlayMode
import com.poupoutch.cnsnn.core.Progress
import com.poupoutch.cnsnn.core.recordingMode
import com.poupoutch.cnsnn.core.SecretDaily
import com.poupoutch.cnsnn.core.SeedCards
import com.poupoutch.cnsnn.core.Submission
import com.poupoutch.cnsnn.core.WordEngine
import com.poupoutch.cnsnn.data.CloudError
import com.poupoutch.cnsnn.data.CloudProfile
import com.poupoutch.cnsnn.data.CloudRepository
import com.poupoutch.cnsnn.data.LocalStore
import com.poupoutch.cnsnn.reminders.ChallengeWatch
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
    var cards by mutableStateOf(SeedCards.all + ExtraCards.all); private set
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
    /** Friend challenges sent and received (see core Challenge.kt). */
    var challenges by mutableStateOf<List<Challenge>>(emptyList()); private set
    /** Asks the home page to open the challenge sheet (from the daily result). */
    var challengeRequest by mutableStateOf(0)
    /** Asks the shell to show the leaderboard (from the home page). */
    var leaderboardRequest by mutableStateOf(0)

    private var scope: String? = local.activeScope
    private var savingAllowed = true
    private var cloudSave: Job? = null
    private var lastSync = 0L

    init {
        val saved = local.load(scope)
        if (saved == null) { savingAllowed = false; error = "La sauvegarde locale est illisible. Elle n’a pas été écrasée." }
        else progress = saved
        local.cachedCards?.let { cards = withCommunity(it) }
        isRestoring = progress.username.isEmpty() && cloud.hasCurrentUser
        if (saved != null) finishInterruptedSprint()
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
            if (uid == user) runCatching { saveOnline(user) }
        }
    }
    /**
     * Merges this phone's copy into the online one (a transaction: another device's games are never
     * overwritten), then takes back what the other devices added. Offline it fails and changes nothing.
     */
    private suspend fun saveOnline(user: String) {
        val saved = cloud.saveCloudProgress(progress, user)
        if (uid != user) return
        val merged = progress.merged(saved)
        if (merged != progress) {
            progress = merged
            if (savingAllowed) local.save(progress, scope)
            refreshGlance()
        }
    }
    /** Brings the online copy and this phone together, so a reinstall or a second device finds everything. */
    private suspend fun syncProgress() {
        val user = uid ?: return
        lastSync = System.currentTimeMillis()
        try {
            cloud.cloudProgress(user)?.let { remote ->
                val merged = progress.merged(remote)
                progress = merged.copy(username = progress.username.ifEmpty { remote.username })
                if (savingAllowed) local.save(progress, scope)
                refreshGlance()
            }
            cloudSave?.cancel()
            saveOnline(user)
        } catch (_: Exception) { /* Offline: the next change, launch or return to the app syncs again. */ }
    }
    /** Back in the app: anything saved while offline, or played on another device, is synced again. */
    fun onForeground() {
        if (uid == null || System.currentTimeMillis() - lastSync < 30_000) return
        viewModelScope.launch { syncProgress() }
    }

    // ---- Session

    fun chooseAvatar(index: Int) { avatar = index; local.avatar = index }

    /** First pseudo: the player accepted the community rules on the same screen. */
    fun start(username: String) = viewModelScope.launch {
        if (isBusy) return@launch
        val name = username.trim()
        if (name.length !in 2..20) { error = "Choisissez un pseudo de 2 à 20 caractères."; return@launch }
        if (!NameFilter.isAllowed(name)) { error = REFUSED_NAME; return@launch }
        isBusy = true
        try {
            progress = progress.copy(rulesVersion = maxOf(progress.rulesVersion ?: 0, CommunityRules.VERSION))
            activate(cloud.bootstrap(name, CommunityRules.VERSION), preservingGuest = true)
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
                if (e is CloudError && e.kind == CloudError.Kind.DELETION_PENDING) { resumeDeletion(); return }
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
        refreshChallenges()
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
        val accepted = listOfNotNull(progress.rulesVersion, profile.rulesVersion).maxOrNull()
        progress = progress.copy(username = profile.username, rulesVersion = accepted)
        persist()
        // Accepted on this phone (offline, or before the profile kept it): record it on the profile too.
        if (accepted != null && (profile.rulesVersion ?: 0) < accepted) {
            viewModelScope.launch { runCatching { cloud.acceptRules(profile.uid, accepted) } }
        }
    }

    /** The player accepted the current community rules (existing players, after an update). */
    fun acceptRules() {
        update { it.copy(rulesVersion = CommunityRules.VERSION) }
        val user = uid ?: return
        viewModelScope.launch { runCatching { cloud.acceptRules(user, CommunityRules.VERSION) } }
    }
    fun signOut() {
        persist(); cloudSave?.cancel()
        cloud.signOut()
        resetToGuest()
    }
    private fun resetToGuest() {
        uid = null; isAnonymous = true; email = null; isAdmin = false; isSuspended = false; official = null; challenges = emptyList()
        challengesReadAt = 0L; rankings = Rankings()
        ChallengeWatch.setActive(getApplication(), false)
        progress = Progress(); cards = SeedCards.all + ExtraCards.all
        local.clearRuns()
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
        val profile = try { cloud.signIn(email, password) } catch (e: CloudError) {
            if (e.kind == CloudError.Kind.DELETION_PENDING) { resumeDeletion(); return } else throw e
        }
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
        local.erase(user); local.erase(null); local.clearChallenges(user)
        chooseAvatar(0)
        resetToGuest()
    }

    /**
     * Finishes a deletion that was cut off halfway (the profile is gone, the tombstone is there): at
     * launch, or when the player signs in again. Nothing is brought back.
     */
    suspend fun resumeDeletion() {
        val user = cloud.currentUid ?: return
        try {
            cloud.deleteAccount(user, null)
            error = "La suppression de votre compte est terminée."
        } catch (e: Exception) {
            if (CloudError.code(e) != CloudError.Code.RECENT_LOGIN) {
                // Offline: still signed in, so the next launch tries again.
                error = "La suppression de votre compte n’est pas terminée. Elle reprendra au prochain lancement avec du réseau."
                return
            }
            // The data is gone; only the sign-in remains, and Firebase wants a fresh password for it.
            cloud.signOut()
            error = "Vos données sont supprimées. Reconnectez-vous une fois avec votre email pour supprimer aussi le compte."
        }
        local.erase(user); local.clearChallenges(user)
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
    /**
     * Classique plays the built-in cards plus every approved community card. The catalogue is
     * downloaded again only when its version (`meta/cards`) moved: one read instead of up to 500.
     */
    suspend fun refreshCards() {
        if (uid == null) return
        try {
            val version = cloud.cardsVersion()
            val cached = local.cachedCards
            val now = System.currentTimeMillis()
            val stale = when {
                cached == null -> true
                // No version on the server yet: download at most once a day.
                version == null -> local.cardsVersion != 0L || now - local.cardsFetchedAt > 24 * 3600 * 1000L
                else -> version != local.cardsVersion
            }
            val community = if (stale || cached == null) cloud.cards().also { local.storeCards(it, version ?: 0L, now) } else cached
            cards = withCommunity(community)
        } catch (_: Exception) { /* Offline: the built-in and cached cards remain. */ }
    }
    private fun withCommunity(community: List<Card>): List<Card> {
        val known = (SeedCards.all + ExtraCards.all + DailyPool.all).map { WordEngine.normalize(it.wordFull) }.toSet()
        return SeedCards.all + ExtraCards.all + community.filter { WordEngine.normalize(it.wordFull) !in known }
    }
    fun card(id: String): Card? {
        SecretDaily.day(id)?.let { return progress.dailyWords?.get(it) }
        return DailyPool.card(id) ?: cards.firstOrNull { it.id == id } ?: ModeCatalogue.cards.firstOrNull { it.id == id }
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
        if (attempt.dailyKey != null) forgetRankings()
        update { p ->
            p.copy(attempts = p.attempts + attempt, recentCards = (p.recentCards.filter { it != attempt.cardID } + attempt.cardID).takeLast(20))
        }
    }
    /** The server's result replaces this phone's measurement for that day. */
    fun recordOfficial(attempt: Attempt) {
        val day = attempt.dailyKey ?: return
        forgetRankings()
        val index = progress.attempts.indexOfFirst { it.dailyKey == day }
        if (index < 0) { record(attempt); return }
        update { p -> p.copy(attempts = p.attempts.toMutableList().also { it[index] = attempt.copy(id = p.attempts[index].id) }) }
    }

    // ---- Sprint, Survie, Double sens

    /** Adds a finished game to the personal records (synced like the rest; never on a leaderboard). */
    fun recordMode(mode: PlayMode, best: Map<String, Int>, add: Map<String, Int>): Set<String> {
        val (next, beaten) = progress.recordingMode(mode, best, add, local.deviceID)
        progress = next; persist()
        return beaten
    }
    /** A Sprint whose app was closed during play is over: it counts as it stood (its clock never stops). */
    fun finishInterruptedSprint() {
        val game = local.loadRun(PlayMode.SPRINT)?.sprint ?: return
        local.clearRun(PlayMode.SPRINT)
        game.stop()
        recordMode(PlayMode.SPRINT, game.best, game.add)
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

    // ---- Friend challenges

    fun refreshChallengesSoon() { viewModelScope.launch { refreshChallenges() } }
    /**
     * The public rankings, kept a few minutes: everybody reads the same lines, so opening the page
     * again (or switching tabs back and forth) costs nothing until they may have moved.
     */
    data class Rankings(
        val today: List<com.poupoutch.cnsnn.data.DailyRank> = emptyList(),
        val players: List<LeaderboardEntry> = emptyList(),
        val fastest: List<LeaderboardEntry> = emptyList(),
        val myRank: Pair<Int, Int>? = null,
        val friends: List<com.poupoutch.cnsnn.core.FriendStanding> = emptyList(),
        val friendCode: String? = null,
        val readAt: Map<String, Long> = emptyMap(),
    )
    var rankings by mutableStateOf(Rankings())
    /** Whether a ranking needs reading: after 5 minutes, or 30 seconds when the player pulls to refresh. */
    fun rankingIsStale(key: String, force: Boolean): Boolean {
        val at = rankings.readAt[key] ?: return true
        return System.currentTimeMillis() - at > if (force) 30_000 else 300_000
    }
    fun rankingRead(key: String) { rankings = rankings.copy(readAt = rankings.readAt + (key to System.currentTimeMillis())) }
    fun forgetRankings() { rankings = rankings.copy(readAt = emptyMap()) }

    private var challengesReadAt = 0L
    /**
     * Reads the challenges of the last two days only (a few documents) and keeps the older ones on
     * the phone, since a challenge never changes after its 50 hours. The whole list is read on the
     * first launch and then once a week. Back-to-back calls (home, return to the app) share one read.
     */
    suspend fun refreshChallenges(force: Boolean = false) {
        val user = uid ?: return
        val now = System.currentTimeMillis()
        if (!force && now - challengesReadAt < 30_000) return
        val cached = local.loadChallenges(user)
        var fullAt = cached?.second ?: 0L
        val list = if (cached != null && now - cached.second < ChallengeRules.FULL_REFRESH_MS) {
            val recent = runCatching { cloud.recentChallenges(user, now) }.getOrNull() ?: return
            ChallengeRules.merge(cached.first, recent, now)
        } else {
            val all = runCatching { cloud.challenges(user) }.getOrNull() ?: return
            fullAt = now
            all
        }
        if (uid != user) return
        challengesReadAt = now
        local.challengesReadAt = now
        local.saveChallenges(user, list, fullAt)
        challenges = list
        ChallengeWatch.markSeen(getApplication(), list, user)
        sendPendingChallenges(list, user)
        // Background checks only for players someone can challenge (one read, once a week at most).
        if (list.isNotEmpty()) ChallengeWatch.setActive(getApplication(), true)
        else if (fullAt == now) ChallengeWatch.setActive(getApplication(), runCatching { cloud.hasFriends(user) }.getOrDefault(local.challengeWatch))
    }
    /**
     * The challenge the home tile shows: a friend's challenge to play first (the closest deadline),
     * then one of mine left unfinished, then the latest one waiting for the friend.
     */
    fun featuredChallenge(now: Long = System.currentTimeMillis()): Pair<Challenge, Challenge.State>? {
        val user = uid ?: return null
        val open = challenges.mapNotNull { c ->
            val state = c.state(user, now)
            if (state is Challenge.State.Over || ChallengeRules.cards(c.cardIds) == null) null else c to state
        }
        return open.filter { it.second == Challenge.State.YourTurn }.minByOrNull { it.first.createdMs }
            ?: open.firstOrNull { it.second == Challenge.State.Playing }
            ?: open.firstOrNull { it.second == Challenge.State.Waiting }
    }
    fun challengeTally(friend: String? = null): ChallengeTally {
        val user = uid ?: return ChallengeTally()
        return ChallengeTally.of(challenges, user, friend, System.currentTimeMillis())
    }
    /** Draws 5 public words (avoiding the player's recent ones) and starts the challenger's clock. */
    suspend fun sendChallenge(friend: String, name: String): Challenge {
        val user = uid ?: throw CloudError(CloudError.Kind.OFFLINE)
        if (isSuspended) throw CloudError(CloudError.Kind.SUSPENDED)
        val ids = ChallengeRules.draw(ModeRandom.seed(), progress.recentCards)
        val challenge = cloud.createChallenge(user, progress.username, friend, name, ids)
        challenges = listOf(challenge) + challenges
        ChallengeWatch.setActive(getApplication(), true)
        return challenge
    }
    /** Starts (or resumes) my side of a challenge: the friend's clock starts on the server here. */
    suspend fun startChallenge(challenge: Challenge): Challenge {
        val user = uid ?: throw CloudError(CloudError.Kind.OFFLINE)
        val fresh = if (challenge.to.uid == user) cloud.startChallenge(challenge, user) else challenge
        replace(fresh)
        ChallengeWatch.setActive(getApplication(), true)
        return fresh
    }
    /** Stamps my finish on the server, then reads back the official times. */
    /** What the server made of a finished challenge game. */
    enum class ChallengeSend { CONFIRMED, PENDING, EXPIRED }
    /**
     * Sends the finish, then reads the challenge back: only the server's copy says it counts. Sending
     * twice is harmless (the rules accept one finish), so a retry after a lost answer is safe.
     */
    suspend fun finishChallenge(challenge: Challenge, skips: Int, errors: Int): Pair<Challenge, ChallengeSend> {
        val user = uid ?: return challenge to ChallengeSend.PENDING
        val refused = runCatching { cloud.finishChallenge(challenge, user, skips, errors) }
            .exceptionOrNull()?.let { CloudError.code(it) == CloudError.Code.PERMISSION_DENIED } ?: false
        val fresh = runCatching { cloud.challenge(challenge.id) }.getOrNull() ?: return challenge to ChallengeSend.PENDING
        replace(fresh)
        return fresh to when {
            fresh.mine(user).finished -> ChallengeSend.CONFIRMED
            refused && System.currentTimeMillis() >= fresh.finishDeadlineMs -> ChallengeSend.EXPIRED
            else -> ChallengeSend.PENDING
        }
    }
    /** Finished games the server has not confirmed yet (network lost, app closed): sent again. */
    private suspend fun sendPendingChallenges(list: List<Challenge>, user: String) {
        for (challenge in list) {
            if (challenge.mine(user).finished) continue
            val saved = local.loadChallengeRun(challenge.id) ?: continue
            val cards = ChallengeRules.cards(challenge.cardIds) ?: continue
            val game = ChallengeGame.restore(cards, saved.first)?.takeIf { it.finished } ?: continue
            if (finishChallenge(challenge, game.skips, game.errors).second != ChallengeSend.PENDING) local.clearChallengeRun(challenge.id)
        }
    }
    private fun replace(challenge: Challenge) {
        challenges = if (challenges.any { it.id == challenge.id }) challenges.map { if (it.id == challenge.id) challenge else it } else listOf(challenge) + challenges
    }

    fun hide(player: String) { hiddenPlayers = hiddenPlayers + player; local.hiddenPlayers = hiddenPlayers }
    fun showAllPlayers() { hiddenPlayers = emptySet(); local.hiddenPlayers = emptySet() }

    companion object {
        const val REFUSED_NAME = "Ce pseudo n’est pas autorisé. Choisissez-en un autre."
        const val SUSPENDED_TEXT = "Votre compte est suspendu par la modération : le mot du jour classé, les propositions et les signalements ne sont plus disponibles. Contactez le support depuis votre profil."
    }
}
