package com.poupoutch.cnsnn.ui

import android.content.Intent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SecondaryTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.poupoutch.cnsnn.core.ClassicLevel
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.DuoGame
import com.poupoutch.cnsnn.core.DuoRecord
import com.poupoutch.cnsnn.core.Format
import com.poupoutch.cnsnn.core.ModeStat
import com.poupoutch.cnsnn.core.PlayMode
import com.poupoutch.cnsnn.core.records
import com.poupoutch.cnsnn.core.FriendCode
import com.poupoutch.cnsnn.core.FriendStanding
import com.poupoutch.cnsnn.core.LeaderboardEntry
import com.poupoutch.cnsnn.core.Mistakes
import com.poupoutch.cnsnn.core.Site
import com.poupoutch.cnsnn.data.CloudError
import com.poupoutch.cnsnn.reminders.ChallengeWatch
import com.poupoutch.cnsnn.data.DailyRank
import com.poupoutch.cnsnn.state.AppViewModel
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.foundation.text.KeyboardActions

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatsScreen(state: AppViewModel) {
    var page by rememberSaveable { mutableIntStateOf(0) }
    // "Classement" on the home page.
    var seenRequest by rememberSaveable { mutableIntStateOf(state.leaderboardRequest) }
    LaunchedEffect(state.leaderboardRequest) { if (state.leaderboardRequest != seenRequest) { seenRequest = state.leaderboardRequest; page = 1 } }
    var refreshToken by remember { mutableIntStateOf(0) }
    var refreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    PullToRefreshBox(refreshing, { scope.launch { refreshing = true; refreshToken++; state.refreshOfficial(); refreshing = false } }, Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            ScreenTitle("Statistiques", Modifier.padding(top = 8.dp))
            SecondaryTabRow(page, containerColor = androidx.compose.ui.graphics.Color.Transparent, divider = {}) {
                Tab(page == 0, { page = 0 }, text = { Text("Mes stats", fontWeight = FontWeight.SemiBold) })
                Tab(page == 1, { page = 1 }, text = { Text("Classement", fontWeight = FontWeight.SemiBold) })
            }
            if (page == 0) MyStats(state) else Leaderboard(state, refreshToken)
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun MyStats(state: AppViewModel) {
    val p = state.progress
    state.official?.let { entry ->
        SectionCard {
            Kicker("Mot du jour · officiel")
            // This month's total time: every day counts, 10 min for a day not found or not played.
            Row(verticalAlignment = Alignment.Bottom, modifier = Modifier.padding(top = 10.dp)) {
                val total = entry.monthTotalMs()
                if (total != null) {
                    Text(Format.clock(total), fontSize = 34.sp, fontWeight = FontWeight.Black)
                    Text("au total ce mois-ci", color = Palette.secondary, modifier = Modifier.padding(start = 8.dp, bottom = 6.dp))
                } else Text("Pas encore joué ce mois-ci", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Palette.secondary)
            }
            Row(Modifier.padding(top = 12.dp)) {
                listOf("${entry.currentStreak()}" to "série", "${entry.bestStreak}" to "record de série",
                    "${Math.round(entry.successRate * 100)} %" to "réussite", Format.seconds(entry.bestTimeMs) to "meilleur temps").forEach { (v, l) ->
                    Column(Modifier.weight(1f)) {
                        Text(v, fontWeight = FontWeight.Bold, fontSize = 17.sp, maxLines = 1)
                        Text(l, fontSize = 11.sp, color = Palette.tertiary, maxLines = 2)
                    }
                }
            }
        }
    }
    val level = p.level; val into = p.levelInto
    SectionCard {
        Text("Mots trouvés, entraînement compris", fontSize = 13.sp, color = Palette.secondary)
        Text(Format.number(p.correctAnswers), fontSize = 52.sp, fontWeight = FontWeight.Black, letterSpacing = (-1.5).sp)
        Row(Modifier.padding(top = 10.dp)) {
            Text("Niveau $level", fontSize = 13.sp, color = Palette.secondary, modifier = Modifier.weight(1f))
            val left = ClassicLevel.WORDS_PER_LEVEL - into
            Text("$left mot${if (left > 1) "s" else ""} avant le niveau ${level + 1}", fontSize = 13.sp, color = Palette.secondary)
        }
        LevelBar(into / ClassicLevel.WORDS_PER_LEVEL.toFloat(), Modifier.padding(top = 8.dp))
    }
    val tiles = listOf(
        "${p.attempts.size}" to "Cartes jouées", "${(p.successRate * 100).toInt()} %" to "Réussite · ${p.correctAnswers} trouvés",
        "${state.streak}" to "Série quotidienne", "${p.dailyWins}" to "Défis réussis",
        Format.seconds(p.bestTimeMs) to "Meilleur temps", Format.seconds(p.averageTimeMs) to "Temps moyen")
    tiles.chunked(2).forEach { pair ->
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) { pair.forEach { (v, l) -> StatTile(v, l, Modifier.weight(1f)) } }
    }
    SectionCard {
        Text("Mots du jour · 7 derniers jours", fontWeight = FontWeight.SemiBold)
        Row(Modifier.padding(top = 14.dp)) {
            val today = LocalDate.now(DailySchedule.zone)
            (6 downTo 0).forEach { offset ->
                val day = today.minusDays(offset.toLong())
                val attempt = p.attempts.firstOrNull { it.dailyKey == day.toString() }
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.size(36.dp).background(when (attempt?.correct) { true -> Palette.mint; false -> Palette.red; null -> Palette.fill1 }, RoundedCornerShape(12.dp)),
                        contentAlignment = Alignment.Center) {
                        when (attempt?.correct) {
                            true -> Icon(Icons.Filled.Check, "trouvé", Modifier.size(18.dp), tint = Palette.ink)
                            false -> Icon(Icons.Filled.Close, "raté", Modifier.size(18.dp), tint = Palette.ink)
                            null -> {}
                        }
                    }
                    Text(day.dayOfWeek.getDisplayName(TextStyle.NARROW, Locale.FRENCH).uppercase(), fontSize = 12.sp, color = Palette.tertiary, modifier = Modifier.padding(top = 8.dp))
                }
            }
        }
    }
    ModeRecordsCard(state)
    if (p.attempts.isEmpty()) Text("Votre première partie lance l’histoire.", color = Palette.secondary)
}

/** Personal records of Sprint, Survie and Double sens. They never reach a leaderboard. */
@Composable
private fun ModeRecordsCard(state: AppViewModel) {
    SectionCard {
        Row(verticalAlignment = Alignment.Bottom) {
            Text("Records personnels", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text("hors classement", fontSize = 12.sp, color = Palette.tertiary)
        }
        PlayMode.entries.forEachIndexed { index, mode ->
            val r = state.progress.records(mode)
            val games = r.total(ModeStat.GAMES)
            val values = when (mode) {
                PlayMode.SPRINT -> listOf("${r.best(ModeStat.WORDS)}" to "mots max",
                    "${r.best(ModeStat.COMBO)}" to "meilleur combo", "$games" to if (games > 1) "parties" else "partie")
                PlayMode.SURVIVAL -> listOf("${maxOf(1, r.best(ModeStat.LEVEL))}" to "niveau max", "${r.best(ModeStat.WORDS)}" to "meilleur parcours",
                    "$games" to if (games > 1) "parties" else "partie")
                PlayMode.DUO -> {
                    val played = r.total(ModeStat.DUOS_PLAYED)
                    val best = r.best(ModeStat.DUO)
                    listOf((if (best == 0) "—" else "${DuoRecord.solved(best)}/${DuoGame.ROUNDS} · ${Format.clock(DuoRecord.seconds(best) * 1000)}") to "meilleure partie", "${r.total(ModeStat.PERFECT)}" to "parfaites",
                        "${if (played == 0) 0 else r.total(ModeStat.DUOS_SOLVED) * 100 / played} %" to "duos résolus", "$games" to if (games > 1) "parties" else "partie")
                }
            }
            if (index > 0) Box(Modifier.padding(top = 14.dp)) { Divider() }
            Row(Modifier.padding(top = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(mode.icon, null, Modifier.size(15.dp), tint = mode.tint)
                Text(mode.title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Palette.secondary, modifier = Modifier.padding(start = 6.dp))
            }
            Row(Modifier.padding(top = 8.dp)) {
                values.forEach { (v, l) ->
                    Column(Modifier.weight(1f)) {
                        Text(v, fontWeight = FontWeight.Bold, fontSize = 17.sp, maxLines = 1)
                        Text(l, fontSize = 11.sp, color = Palette.tertiary, maxLines = 2)
                    }
                }
            }
        }
    }
}

private enum class Board(val label: String) { TODAY("Aujourd’hui"), FRIENDS("Amis"), MONTH("Mois"), FASTEST("Records") }

/** "12 jours joués" this month. */
private fun monthDetail(entry: LeaderboardEntry): String = if (entry.monthPlayed > 1) "${entry.monthPlayed} jours joués" else "1 jour joué"
private data class Line(val id: String, val name: String, val value: String, val detail: String? = null)

@Composable
private fun Leaderboard(state: AppViewModel, refreshToken: Int) {
    if (state.uid == null) {
        SectionCard { Text("Connectez-vous à Internet pour voir le classement.", color = Palette.secondary) }; return
    }
    var board by rememberSaveable { mutableStateOf(Board.TODAY) }
    var seenToken by remember { mutableIntStateOf(refreshToken) }
    val today = state.rankings.today
    val players = state.rankings.players
    val fastest = state.rankings.fastest
    val myRank = state.rankings.myRank
    var loading by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var suspending by remember { mutableStateOf<Line?>(null) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    /** Reads only the ranking on screen, and only when the kept copy is old (see AppViewModel.rankings). */
    suspend fun refresh() {
        if (board == Board.FRIENDS) return
        // Every open, tab switch and return to the app reads again (at most every 10 s, see rankingIsStale).
        val force = true
        seenToken = refreshToken
        val day = DailySchedule.key()
        val key = when (board) { Board.TODAY -> "today-$day"; Board.MONTH -> "month-" + day.take(7); else -> board.name }
        val summary = state.rankingIsStale("summary", force)
        if (!summary && !state.rankingIsStale(key, force)) return
        loading = true; failed = false
        try {
            if (summary) {
                state.refreshOfficial()
                state.rankings = state.rankings.copy(myRank = state.official?.let { state.cloud.monthlyRank(it, day) })
                state.rankingRead("summary")
            }
            if (state.rankingIsStale(key, force)) {
                state.rankings = when (board) {
                    Board.TODAY -> state.rankings.copy(today = state.cloud.dailyRanking(day))
                    Board.MONTH -> state.rankings.copy(players = state.cloud.monthlyPlayers(day))
                    Board.FASTEST -> state.rankings.copy(fastest = state.cloud.fastestPlayers())
                    Board.FRIENDS -> state.rankings
                }
                state.rankingRead(key)
            }
        } catch (_: Exception) { failed = true } finally { loading = false }
    }
    val resumes = rememberResumeCount()
    LaunchedEffect(state.uid, refreshToken, board, resumes) { refresh() }

    val entry = state.official
    if (entry != null) Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        StatTile(myRank?.let { Format.ordinal(it.first) } ?: "—", myRank?.let { "du mois sur ${Format.number(it.second)}" } ?: "Rang du mois", Modifier.weight(1f))
        StatTile(entry.monthTotalMs()?.let { Format.clock(it) } ?: "—", "total du mois", Modifier.weight(1f))
        StatTile("${entry.currentStreak()}", "série en cours", Modifier.weight(1f))
    } else SectionCard { Text("Jouez le Mot du jour pour entrer au classement.", color = Palette.secondary) }

    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Board.entries.forEach { item ->
            FilterChip(board == item, { board = item }, { Text(item.label) }, shape = RoundedCornerShape(50),
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = Palette.foreground, selectedLabelColor = Palette.ink))
        }
    }
    if (board == Board.FRIENDS) { FriendsBoard(state, refreshToken); return }
    message?.let { Text(it, fontSize = 13.sp, color = Palette.secondary) }
    // The rankings show only their first lines: says how many, so nobody looks for a missing name.
    Text(when (board) { Board.TODAY -> "Top 25 des plus rapides du jour"; Board.MONTH -> "Top 50 du mois"; else -> "Top 25 des meilleurs temps" },
        fontSize = 13.sp, color = Palette.secondary, modifier = Modifier.padding(horizontal = 4.dp))
    val hidden = state.hiddenPlayers
    val rows = when (board) {
        // The official time: a hint adds a minute.
        Board.TODAY -> today.map { Line(it.uid, it.username, Format.clock(it.scoreMs), Mistakes.text(it.wrongAnswers) + if (it.usedHint) " · indice +1 min" else "") }
        // The month total: 10 min for every day not found or not played, so the lowest wins.
        Board.MONTH -> players.mapNotNull { p -> p.monthTotalMs()?.let { Line(p.uid, p.username, Format.clock(it), monthDetail(p)) } }
        Board.FASTEST -> fastest.map { Line(it.uid, it.username, Format.seconds(it.bestTimeMs)) }
        Board.FRIENDS -> emptyList()
    }.filter { it.id !in hidden }
    SectionCard(padding = 0.dp, radius = 24.dp) {
        if (rows.isEmpty()) EmptyLine(loading, if (failed) "Classement indisponible hors connexion." else
            when (board) { Board.TODAY -> "Personne n’a encore trouvé le mot du jour."; Board.MONTH -> "Personne n’a encore joué ce mois-ci."; else -> "Aucun résultat pour le moment." })
        rows.forEachIndexed { index, row ->
            if (index > 0) Divider()
            val mine = row.id == state.uid
            var menu by remember(row.id) { mutableStateOf(false) }
            Box {
                RankRow(index, row.name, row.id, mine, row.detail, row.value, onLongPress = { if (!mine) { haptics.selection(); menu = true } })
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem({ Text("Signaler ce pseudo") }, {
                        menu = false
                        scope.launch {
                            message = try { state.cloud.reportPlayer(row.id, row.name); "Merci, la modération va vérifier le pseudo de ${row.name}." }
                            catch (e: Exception) { CloudError.message(e) }
                        }
                    })
                    DropdownMenuItem({ Text("Masquer ce joueur") }, { menu = false; state.hide(row.id) })
                    if (state.isAdmin) DropdownMenuItem({ Text("Suspendre ce joueur", color = Palette.red) }, { menu = false; suspending = row })
                }
            }
        }
    }
    if (hidden.isNotEmpty()) TextButton(state::showAllPlayers) {
        Text((if (hidden.size == 1) "1 joueur masqué" else "${hidden.size} joueurs masqués") + " · Tout afficher", color = Palette.secondary)
    }
    Text("Appui long sur un joueur pour le signaler ou le masquer.", fontSize = 12.sp, color = Palette.tertiary)
    suspending?.let { row ->
        AlertDialog({ suspending = null }, title = { Text("Suspendre ${row.name} ?") },
            text = { Text("Le joueur disparaît des classements et ne peut plus jouer le mot du jour classé, proposer ni signaler. Ses résultats et ses stats sont conservés : en levant la suspension dans Modération, il retrouve tout.") },
            confirmButton = { TextButton({
                suspending = null
                scope.launch {
                    message = try { state.cloud.suspend(row.id, row.name, "Depuis le classement"); state.forgetRankings(); refresh(); "${row.name} est suspendu." } catch (e: Exception) { CloudError.message(e) }
                }
            }) { Text("Suspendre", color = Palette.red) } },
            dismissButton = { TextButton({ suspending = null }) { Text("Annuler") } })
    }
}

@Composable
private fun EmptyLine(loading: Boolean, text: String) {
    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        if (loading) { CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Palette.secondary); Spacer(Modifier.width(10.dp)) }
        Text(if (loading) "Chargement…" else text, fontSize = 14.sp, color = Palette.tertiary)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RankRow(index: Int, name: String, id: String, mine: Boolean, detail: String?, value: String, valueColor: androidx.compose.ui.graphics.Color = Palette.foreground,
                    extra: String? = null, onLongPress: () -> Unit) {
    Row(Modifier.fillMaxWidth().background(if (mine) Palette.fill1 else androidx.compose.ui.graphics.Color.Transparent)
        .combinedClickable(onClick = {}, onLongClick = onLongPress, onLongClickLabel = "Options").heightIn(min = 56.dp).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(Format.ordinal(index + 1), fontWeight = FontWeight.Bold, fontSize = 14.sp, color = if (index < 3) Palette.foreground else Palette.tertiary, modifier = Modifier.width(36.dp))
        Avatar(name, colorIndex(id), 32.dp)
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(name, fontWeight = if (mine) FontWeight.Bold else FontWeight.Medium, maxLines = 1)
                if (mine) Text("vous", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Palette.secondary, modifier = Modifier.padding(start = 6.dp))
            }
            if (!detail.isNullOrEmpty()) Text(detail, fontSize = 12.sp, color = Palette.tertiary, maxLines = 1)
            if (!extra.isNullOrEmpty()) Text(extra, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = Duel.soft, maxLines = 1)
        }
        Text(value, fontWeight = FontWeight.SemiBold, color = valueColor)
    }
}

/** The player and the friends added with a 6-character code, ranked on today's Mot du jour. */
@Composable
private fun FriendsBoard(state: AppViewModel, refreshToken: Int) {
    var seenToken by remember { mutableIntStateOf(refreshToken) }
    var reload by remember { mutableIntStateOf(0) }
    val rows = state.rankings.friends
    var loading by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val uid = state.uid ?: return
    val name = state.progress.username.ifEmpty { "Joueur" }
    /** Two reads per friend: kept a few minutes like the other rankings (see AppViewModel.rankings). */
    suspend fun refresh() {
        // Every open, tab switch and return to the app reads again (at most every 10 s, see rankingIsStale).
        val force = true
        seenToken = refreshToken
        val key = "friends-" + DailySchedule.key()
        // A friend who typed my code since the last read: one count, then the list at once.
        if (!state.rankingIsStale(key, force)) {
            val count = runCatching { state.cloud.friendCount(uid) }.getOrNull()
            if (count == null || count == state.rankings.friendCount) return
        }
        loading = true; failed = false
        try {
            state.rankings = state.rankings.copy(friends = state.cloud.friendsBoard(uid, name, DailySchedule.key()))
            state.rankings = state.rankings.copy(friendCount = runCatching { state.cloud.friendCount(uid) }.getOrNull())
            state.rankingRead(key)
            state.refreshChallenges(force)
        } catch (_: Exception) { failed = true } finally { loading = false }
    }
    // A friend added here: the ranking was marked to read again, so this reads it at once.
    val resumes = rememberResumeCount()
    LaunchedEffect(uid, refreshToken, reload, resumes) { refresh() }

    FriendCodeCards(state) { reload++ }
    message?.let { Text(it, fontSize = 13.sp, color = Palette.secondary, modifier = Modifier.padding(horizontal = 4.dp)) }
    SectionCard(padding = 0.dp, radius = 24.dp) {
        if (rows.size <= 1) EmptyLine(loading, if (failed) "Classement indisponible hors connexion." else "Ajoutez un ami avec son code pour comparer vos temps chaque jour.")
        else rows.forEachIndexed { index, row ->
            if (index > 0) Divider()
            val mine = row.uid == uid
            var menu by remember(row.uid) { mutableStateOf(false) }
            val today = row.today
            Box {
                RankRow(index, row.username, row.uid, mine,
                    listOfNotNull(row.monthTotalMs?.let { "mois " + Format.clock(it) } ?: "pas joué ce mois", if (row.streak > 0) "série ${row.streak}" else null,
                        if (today?.correct == true) Mistakes.text(row.todayWrong ?: 0) else null, if (today?.correct == true && row.todayHint) "indice" else null).joinToString(" · "),
                    when { today == null -> "pas joué"; today.correct -> Format.clock(row.todayScoreMs ?: today.timeMs); else -> "raté" },
                    if (today?.correct == true) Palette.foreground else Palette.tertiary,
                    // Friend challenges: "2 victoires · 1 défaite" against this friend.
                    extra = if (mine) null else state.challengeTally(row.uid).label) { if (!mine) menu = true }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem({ Text("Retirer de mes amis", color = Palette.red) }, {
                        menu = false
                        scope.launch {
                            try { state.cloud.removeFriend(uid, row.uid); state.rankings = state.rankings.copy(friends = rows.filter { it.uid != row.uid }, friendCount = state.rankings.friendCount?.minus(1)) } catch (e: Exception) { message = CloudError.message(e) }
                        }
                    })
                }
            }
        }
    }
}

/** The player's friend code to share, and the field to type a friend's: in Stats > Amis and in Profil. */
@Composable
fun FriendCodeCards(state: AppViewModel, added: () -> Unit = {}) {
    val code = state.rankings.friendCode
    var friendCode by rememberSaveable { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val haptics = rememberHaptics()
    val focus = LocalFocusManager.current
    val uid = state.uid ?: return
    val name = state.progress.username.ifEmpty { "Joueur" }
    // One read the first time (the code is kept with the rankings), one write if the player has none yet.
    LaunchedEffect(uid) {
        if (state.rankings.friendCode == null) runCatching { state.cloud.friendCode(uid, name) }.onSuccess { state.rankings = state.rankings.copy(friendCode = it) }
    }
    fun add() {
        if (friendCode.length != 6 || busy) return
        busy = true; message = null; focus.clearFocus()
        scope.launch {
            try {
                val friend = state.cloud.addFriendByCode(friendCode, uid, name)
                friendCode = ""; message = "$friend fait partie de vos amis."; haptics.success()
                ChallengeWatch.setActive(context, true); state.forgetFriendsRanking(); added()
            } catch (e: Exception) { message = CloudError.message(e); haptics.retry() } finally { busy = false }
        }
    }

    SectionCard(radius = 24.dp, padding = 18.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Votre code ami", fontSize = 13.sp, color = Palette.secondary)
                Text(code ?: "······", fontSize = 26.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, letterSpacing = 3.sp)
            }
            code?.let { c ->
                IconButton({
                    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_TEXT, Site.friendInvite(c)), null))
                }) { Icon(Icons.Filled.Share, "Partager mon code") }
            }
        }
    }
    SectionCard(radius = 24.dp, padding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedTextField(friendCode, { friendCode = FriendCode.normalize(it) }, Modifier.weight(1f).testTag("friend-code-field"), singleLine = true,
                placeholder = { Text("Code d’un ami") }, textStyle = MaterialTheme.typography.titleMedium.copy(fontFamily = FontFamily.Monospace),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { add() }), shape = RoundedCornerShape(14.dp))
            Button(::add, enabled = friendCode.length == 6 && !busy, shape = RoundedCornerShape(24.dp)) { Text("Ajouter") }
        }
        message?.let { Text(it, fontSize = 13.sp, color = Palette.secondary, modifier = Modifier.padding(top = 8.dp)) }
    }
}

/** Counts the returns to the app while this screen is shown, so the ranking on screen reads again. */
@Composable
private fun rememberResumeCount(): Int {
    var count by remember { mutableIntStateOf(0) }
    val lifecycle = androidx.compose.ui.platform.LocalLifecycleOwner.current.lifecycle
    androidx.compose.runtime.DisposableEffect(lifecycle) {
        var started = false
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            // The first resume is the screen opening, already read.
            if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) { if (started) count++ else started = true }
        }
        lifecycle.addObserver(observer); onDispose { lifecycle.removeObserver(observer) }
    }
    return count
}
