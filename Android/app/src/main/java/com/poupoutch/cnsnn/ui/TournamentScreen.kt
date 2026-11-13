package com.poupoutch.cnsnn.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.poupoutch.cnsnn.core.ChallengeFormat
import com.poupoutch.cnsnn.core.ChallengeRules
import com.poupoutch.cnsnn.core.TournamentBracket
import com.poupoutch.cnsnn.core.TournamentFormat
import com.poupoutch.cnsnn.core.TournamentRules
import com.poupoutch.cnsnn.state.AppViewModel
import com.poupoutch.cnsnn.state.TournamentPlayViewModel
import com.poupoutch.cnsnn.state.TournamentStore
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

// Tournoi de la semaine, the Android twin of the iPhone's TournamentView: sign up until Monday 9 h, then
// one knockout round a day. My match of the day, next week's sign-ups and the whole bracket.

internal object TournamentText {
    /** "lundi 9 h", "mardi 9 h 30": in the phone's time zone. */
    fun day(ms: Long): String {
        val date = Date(ms)
        val minutes = Calendar.getInstance().apply { time = date }.get(Calendar.MINUTE)
        return SimpleDateFormat(if (minutes == 0) "EEEE H' h'" else "EEEE H' h 'mm", Locale.FRANCE).format(date)
    }
    fun name(slot: TournamentBracket.Slot): String = when (slot) {
        is TournamentBracket.Slot.Player -> slot.player.name
        TournamentBracket.Slot.Empty -> "personne"
        TournamentBracket.Slot.Pending -> "à venir"
    }
}

private fun TournamentBracket.Slot.uid(): String? = (this as? TournamentBracket.Slot.Player)?.player?.uid

/** The tournament block of the "Défier un ami" sheet: sign-up and my match, in short. */
@Composable
internal fun TournamentBox(state: AppViewModel, open: () -> Unit) {
    val store = state.tournament
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    LaunchedEffect(state.uid) { store.refresh(state) }
    Surface(Modifier.fillMaxWidth().padding(top = 6.dp), shape = RoundedCornerShape(22.dp), color = Color.Transparent, border = Duel.border) {
        Column(Modifier.background(Duel.surface).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.EmojiEvents, null, Modifier.size(16.dp), tint = Palette.accent)
                Kicker("Tournoi de la semaine", Palette.accent)
            }
            Text(summary(store), fontSize = 13.sp, color = Palette.secondary)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (!store.nextMine && store.nextWeek.isNotEmpty())
                    DuelButton("S’inscrire", Modifier.weight(1f).testTag("tournamentSignUp")) { haptics.selection(); scope.launch { store.signUp(state) } }
                DuelButton(if (store.currentMine) "Mon match" else "Voir le tableau", Modifier.weight(1f).testTag("tournamentOpen")) { haptics.selection(); open() }
            }
            store.message?.let { Text(it, fontSize = 12.sp, color = Palette.red) }
        }
    }
}

private fun summary(store: TournamentStore): String {
    val deadline = TournamentRules.deadlineMs(store.nextWeek)?.let(TournamentText::day) ?: "lundi 9 h"
    val count = when (store.nextCount) { 0 -> ""; 1 -> " 1 inscrit pour l’instant."; else -> " ${store.nextCount} inscrits pour l’instant." }
    if (store.nextMine) return "Vous êtes inscrit au prochain tournoi : il commence $deadline.$count"
    return "Un match par jour, les mêmes 5 mots pour les deux joueurs, 24 h pour jouer : le plus rapide passe au tour suivant. Inscriptions jusqu’à $deadline.$count"
}

@Composable
fun TournamentScreen(state: AppViewModel, play: (Int) -> Unit, close: () -> Unit) {
    val store = state.tournament
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    var confirmWithdraw by remember { mutableStateOf(false) }
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(30_000); tick++ } }
    LaunchedEffect(Unit) { store.refresh(state); store.loadBracket(state, force = true) }
    BackHandler(onBack = close)
    tick
    val uid = state.uid

    Box(Modifier.fillMaxSize()) {
        AmbientBackground(dimmed = false)
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            Box(Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 12.dp)) {
                IconButton(close, Modifier.align(Alignment.CenterStart)) { Icon(Icons.Filled.Close, "Fermer") }
                Text("Tournoi de la semaine", fontWeight = FontWeight.SemiBold, fontSize = 16.sp,
                    modifier = Modifier.align(Alignment.Center).semantics { heading() })
            }
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp).widthIn(max = 560.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)) {
                if (uid != null && store.currentLoaded && store.currentMine) Mine(store, uid, play)
                // Next week.
                val deadline = TournamentRules.deadlineMs(store.nextWeek)?.let(TournamentText::day) ?: "lundi 9 h"
                DuelCard {
                    Kicker("Prochain tournoi", Palette.accent)
                    Text(if (store.nextMine) "Vous êtes inscrit. Premier match $deadline." else "Inscriptions ouvertes jusqu’à $deadline.",
                        fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    Text("${store.nextCount} inscrit${if (store.nextCount > 1) "s" else ""} · 64 places · un match par jour, 24 h pour le jouer. Chaque mot passé ajoute 20 s ; à égalité, le moins d’erreurs passe.",
                        fontSize = 13.sp, color = Palette.secondary)
                    if (store.nextMine) TonalButton("Se désinscrire", Modifier.fillMaxWidth()) { confirmWithdraw = true }
                    else DuelButton("S’inscrire", Modifier.fillMaxWidth()) { haptics.selection(); scope.launch { store.signUp(state) } }
                }
                Bracket(store, uid)
                store.message?.let { Text(it, fontSize = 13.sp, color = Palette.red) }
            }
        }
    }

    if (confirmWithdraw) AlertDialog({ confirmWithdraw = false },
        title = { Text("Se désinscrire ?") },
        confirmButton = { TextButton({ confirmWithdraw = false; scope.launch { store.withdraw(state) } }) { Text("Se désinscrire", color = Palette.red) } },
        dismissButton = { TextButton({ confirmWithdraw = false }) { Text("Rester inscrit") } })
}

@Composable
private fun DuelCard(content: @Composable ColumnScope.() -> Unit) {
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(22.dp), color = Color.Transparent, border = Duel.border) {
        Column(Modifier.background(Duel.surface).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
    }
}

@Composable
private fun Mine(store: TournamentStore, uid: String, play: (Int) -> Unit) {
    val bracket = store.bracket()
    val total = bracket.rounds.size
    DuelCard {
        when (val standing = bracket.standing(uid, store.nowMs)) {
            TournamentBracket.Standing.Out -> Text("Le tableau de cette semaine est complet (64 joueurs).", fontSize = 15.sp)
            is TournamentBracket.Standing.InMatch -> {
                val round = standing.round
                val match = standing.match
                val other = match.opponent(uid)
                val end = TournamentRules.roundEndMs(store.currentWeek, round) ?: 0
                val run = store.run(round, uid)
                Kicker(TournamentFormat.roundName(round, total), Duel.text)
                Text("Contre ${TournamentText.name(other)}", fontSize = 19.sp, fontWeight = FontWeight.Bold)
                val score = run?.scoreMs
                if (match.decided) {
                    val won = match.winner?.uid == uid
                    Text(if (won) "Gagné ! Le tour suivant ouvre ${TournamentText.day(end)}." else "Perdu…",
                        fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = if (won) Palette.mint else Palette.red)
                    val a = match.a.uid()?.let { store.run(round, it)?.scoreMs }
                    val b = match.b.uid()?.let { store.run(round, it)?.scoreMs }
                    Text("${TournamentText.name(match.a)} ${a?.let(ChallengeFormat::time) ?: "—"} · ${TournamentText.name(match.b)} ${b?.let(ChallengeFormat::time) ?: "—"}",
                        fontSize = 13.sp, color = Palette.secondary)
                } else if (score != null) {
                    Text("Votre temps : ${ChallengeFormat.time(score)}", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Text("Résultat dès que ${TournamentText.name(other)} a joué, au plus tard ${TournamentText.day(end)}.", fontSize = 13.sp, color = Palette.secondary)
                } else {
                    Text(if (run == null) "5 mots, une seule partie : votre chrono démarre dès que vous commencez. Vous avez jusqu’à ${TournamentText.day(end)}."
                        else "Votre partie est commencée : le chrono tourne. Finissez avant ${TournamentText.day(end)}.", fontSize = 13.sp, color = Palette.secondary)
                    DuelButton(if (run == null) "Jouer mon match" else "Reprendre", Modifier.fillMaxWidth().testTag("tournamentPlay")) { play(round) }
                }
            }
            is TournamentBracket.Standing.Through -> {
                Kicker(TournamentFormat.roundName(standing.round, total), Duel.text)
                Text("Qualifié ! Votre prochain match ouvre ${TournamentText.day(TournamentRules.roundStartMs(store.currentWeek, standing.round + 1) ?: 0)}.",
                    fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
            is TournamentBracket.Standing.Eliminated -> {
                Kicker(TournamentFormat.roundName(standing.round, total), Duel.text)
                Text("Éliminé cette semaine. Revanche au prochain tournoi !", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
            TournamentBracket.Standing.Champion -> {
                Kicker("Finale", Palette.accent)
                Text("Champion de la semaine 🏆", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Palette.accent)
            }
        }
    }
}

@Composable
private fun Bracket(store: TournamentStore, uid: String?) {
    if (!store.currentLoaded) {
        if (store.loading) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Palette.secondary) }
        return
    }
    val bracket = store.bracket()
    val total = bracket.rounds.size
    if (bracket.players.size < 2) {
        Text(if (bracket.players.isEmpty()) "Pas de tournoi cette semaine : inscrivez-vous au prochain !" else "Un seul inscrit cette semaine : pas de tournoi. Rendez-vous au prochain !",
            fontSize = 14.sp, color = Palette.secondary)
        return
    }
    bracket.champion?.let { Text("Champion : ${it.name} 🏆", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Palette.accent) }
    bracket.rounds.withIndex().reversed().forEach { (index, matches) ->
        val round = index + 1
        if (round == 1 || (TournamentRules.roundStartMs(store.currentWeek, round) ?: 0) <= store.nowMs) {
            Kicker(TournamentFormat.roundName(round, total), Palette.tertiary, Modifier.padding(top = 6.dp))
            SectionCard(padding = 0.dp, radius = 20.dp) {
                matches.forEachIndexed { k, match ->
                    if (k > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(Palette.line))
                    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Side(store, round, match.a, match, uid, Modifier.weight(1f), TextAlign.Start)
                        Text("vs", fontSize = 11.sp, color = Palette.tertiary)
                        Side(store, round, match.b, match, uid, Modifier.weight(1f), TextAlign.End)
                    }
                }
            }
        }
    }
}

@Composable
private fun Side(store: TournamentStore, round: Int, slot: TournamentBracket.Slot, match: TournamentBracket.Match, uid: String?, modifier: Modifier, align: TextAlign) {
    val id = slot.uid()
    val won = match.decided && id != null && match.winner?.uid == id
    val mine = id != null && id == uid
    // Times are shown once the match is decided, so nobody knows the time to beat.
    val time = if (match.decided) id?.let { store.run(round, it)?.scoreMs }?.let(ChallengeFormat::time) else null
    Column(modifier, horizontalAlignment = if (align == TextAlign.Start) Alignment.Start else Alignment.End) {
        Text(TournamentText.name(slot), fontSize = 14.sp, fontWeight = if (won || mine) FontWeight.Bold else FontWeight.Normal, maxLines = 1, overflow = TextOverflow.Ellipsis,
            color = when { id == null -> Palette.tertiary; match.decided && !won -> Palette.tertiary; mine -> Duel.text; else -> Palette.foreground })
        if (time != null) Text(time, fontSize = 11.sp, color = Palette.tertiary)
    }
}

/** One match: the start screen, then the 5 words with my clock, then my time. */
@Composable
fun TournamentPlayScreen(state: AppViewModel, round: Int, close: () -> Unit) {
    val vm: TournamentPlayViewModel = viewModel()
    LaunchedEffect(Unit) { vm.loadOnce(state.tournament.currentWeek, round, state) }
    val haptics = rememberHaptics()
    var confirmQuit by remember { mutableStateOf(false) }
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(250); tick++ } }
    tick
    val leave = { if (vm.phase == TournamentPlayViewModel.Phase.Playing) confirmQuit = true else close() }
    BackHandler(onBack = leave)
    LaunchedEffect(vm.mistakeTick) { if (vm.mistakeTick > 0) haptics.retry() }
    LaunchedEffect(vm.successTick) { if (vm.successTick > 0) haptics.success() }

    Box(Modifier.fillMaxSize()) {
        AmbientBackground(dimmed = vm.phase == TournamentPlayViewModel.Phase.Playing)
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 12.dp)) {
            Box(Modifier.fillMaxWidth().height(56.dp)) {
                IconButton(leave, Modifier.align(Alignment.CenterStart)) { Icon(Icons.Filled.Close, "Quitter") }
                Text("Match du tournoi", fontWeight = FontWeight.SemiBold, fontSize = 16.sp, modifier = Modifier.align(Alignment.Center).semantics { heading() })
                val game = vm.game
                if (vm.phase == TournamentPlayViewModel.Phase.Playing && game != null) Box(Modifier.align(Alignment.CenterEnd).padding(end = 4.dp)) {
                    Pill(ChallengeFormat.time(game.scoreMs(vm.elapsedMs)), "Chrono")
                }
            }
            vm.version
            when (val phase = vm.phase) {
                TournamentPlayViewModel.Phase.Ready -> Centered {
                    Icon(Icons.Filled.EmojiEvents, null, Modifier.size(54.dp), tint = Palette.accent)
                    Text("Prêt pour votre match ?", fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 16.dp))
                    Line("5 mots, une seule partie. Le chrono démarre dès que vous appuyez et continue même si vous quittez. Chaque mot passé ajoute 20 s.")
                    if (vm.nowMs < vm.endMs) DuelButton("C’est parti", Modifier.padding(top = 24.dp).testTag("tournamentGo")) { haptics.selection(); vm.start(state) }
                    else Line("Ce tour est terminé.")
                }
                TournamentPlayViewModel.Phase.Starting -> Centered { CircularProgressIndicator(color = Palette.secondary) }
                TournamentPlayViewModel.Phase.Playing -> {
                    val game = vm.game
                    val card = game?.card
                    if (game == null || card == null) Centered { CircularProgressIndicator(color = Palette.secondary) }
                    else if (vm.nowMs >= vm.endMs) Centered { Line("Le tour est terminé : ce match n’a pas été fini à temps.") }
                    else {
                        Text("Mot ${game.index + 1} sur ${ChallengeRules.WORDS}", fontSize = 12.sp, color = Palette.tertiary,
                            modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 10.dp))
                        Clue(card, vm.passed, vm.passedTick)
                        AnswerLine(vm.answer, vm.mistakeTick, true, vm.answerWrong, vm.cursor) { vm.placeCursor(it) }
                        SkipChip("Passer · +20 s", "Passer ce mot, 20 secondes de pénalité") { vm.skip(state) }
                        LetterKeyboard(press = { vm.press(it) }, delete = { vm.delete() }, clear = { vm.clear() },
                            moveCursor = { vm.moveCursor(it) }, submit = { vm.submit(state) }, enabled = true)
                    }
                }
                TournamentPlayViewModel.Phase.Sending -> Centered { CircularProgressIndicator(color = Palette.secondary); Line("Envoi de votre temps…") }
                TournamentPlayViewModel.Phase.Done -> Centered {
                    Text("Votre temps", fontSize = 14.sp, color = Palette.tertiary)
                    Text(vm.myRun?.scoreMs?.let(ChallengeFormat::time) ?: "—", fontSize = 60.sp, fontWeight = FontWeight.Black)
                    val missed = vm.game?.missed.orEmpty()
                    if (missed.isNotEmpty()) Line((if (missed.size > 1) "Les réponses manquées : " else "La réponse manquée : ") + missed.joinToString(", ") { "« $it »" } + ".")
                    Line("Le temps officiel est mesuré par le serveur. Le résultat s’affiche dès que votre adversaire a joué, au plus tard ${TournamentText.day(vm.endMs)}.")
                    PrimaryButton("Terminer", Modifier.padding(top = 24.dp)) { close() }
                }
                is TournamentPlayViewModel.Phase.Failed -> Centered {
                    Text(phase.message, textAlign = TextAlign.Center, color = Palette.secondary, modifier = Modifier.padding(horizontal = 20.dp))
                    TonalButton("Réessayer", Modifier.padding(top = 20.dp)) { if (vm.game?.finished == true) vm.finish(state) else vm.start(state) }
                }
            }
        }
    }

    if (confirmQuit) AlertDialog({ confirmQuit = false },
        title = { Text("Quitter le match ?") },
        text = { Text("Votre chrono continue de tourner : revenez vite finir vos mots.") },
        confirmButton = { TextButton({ confirmQuit = false; close() }) { Text("Quitter", color = Palette.red) } },
        dismissButton = { TextButton({ confirmQuit = false }) { Text("Continuer à jouer") } })
}

@Composable
private fun Centered(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().padding(horizontal = 12.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally, content = content)
}

@Composable
private fun Line(text: String) {
    Text(text, fontSize = 14.sp, color = Palette.secondary, textAlign = TextAlign.Center, modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 10.dp))
}
