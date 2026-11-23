package com.poupoutch.cnsnn.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Dp
import com.poupoutch.cnsnn.core.TournamentLayout
import kotlinx.coroutines.flow.first
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
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.material.icons.filled.CheckCircle
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
    /** "Gagnant de Léa / Sam" in a sentence: "le gagnant de Léa / Sam". */
    fun lower(name: String): String = if (name.startsWith("Gagnant")) "le g" + name.drop(1) else name
}

private fun TournamentBracket.Slot.uid(): String? = (this as? TournamentBracket.Slot.Player)?.player?.uid

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
        Column(Modifier.readableWidth().fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
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
                val others = match.opponents(uid).mapNotNull { (it as? TournamentBracket.Slot.Player)?.player?.name }
                val other = if (others.isEmpty()) "personne" else others.joinToString(" et ")
                val end = TournamentRules.roundEndMs(store.currentWeek, round) ?: 0
                val run = store.run(round, uid)
                Kicker(TournamentFormat.roundName(round, total), Duel.text)
                Text("Contre $other", fontSize = 19.sp, fontWeight = FontWeight.Bold)
                if (others.size > 1) Text("Match à 3 : le plus rapide des trois passe.", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Duel.soft)
                val score = run?.scoreMs
                if (match.decided) {
                    val won = match.winner?.uid == uid
                    Text(if (won) "Gagné ! Le tour suivant ouvre ${TournamentText.day(end)}." else "Perdu…",
                        fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = if (won) Palette.mint else Palette.red)
                } else if (score != null) {
                    Text("Votre temps : ${ChallengeFormat.time(score)}", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Text("Résultat dès que $other ${if (others.size > 1) "ont" else "a"} joué, au plus tard ${TournamentText.day(end)}.", fontSize = 13.sp, color = Palette.secondary)
                } else {
                    Text(if (run == null) "5 mots, une seule partie : votre chrono démarre dès que vous commencez. Vous avez jusqu’à ${TournamentText.day(end)}."
                        else "Votre partie est commencée : le chrono tourne. Finissez avant ${TournamentText.day(end)}.", fontSize = 13.sp, color = Palette.secondary)
                    DuelButton(if (run == null) "Jouer mon match" else "Reprendre", Modifier.fillMaxWidth().testTag("tournamentPlay")) { play(round) }
                }
                // What comes next: "Si vous gagnez : contre le gagnant de Léa / Sam".
                val index = bracket.rounds[round - 1].indexOf(match)
                val next = if (match.winner == null || match.winner?.uid == uid) bracket.following(round, index) else null
                if (next != null) {
                    val names = next.second.map { TournamentText.lower(TournamentFormat.slotName(bracket, round + 1, next.first, it)) }
                    Text((if (match.decided) "Prochain match : contre " else "Si vous gagnez : contre ") + names.joinToString(" et "),
                        fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Duel.text)
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
    if (bracket.players.size < 2) {
        Text(if (bracket.players.isEmpty()) "Pas de tournoi cette semaine : inscrivez-vous au prochain !" else "Un seul inscrit cette semaine : pas de tournoi. Rendez-vous au prochain !",
            fontSize = 14.sp, color = Palette.secondary)
        return
    }
    Text("Résultats au fil de la journée : les temps s’affichent quand le match est fini.", fontSize = 12.sp, color = Palette.tertiary)
    TournamentTree(store, bracket, uid)
}

/** Sizes of the bracket drawn like a football one (same as the iPhone's TournamentTree). */
private object Tree {
    val cardWidth = 136.dp
    val columnGap = 28.dp
    val slotHeight = 26.dp
    val pad = 7.dp
    val gap = 14.dp
    val header = 34.dp
    val trophy = 78.dp
    val margin = 20.dp
    fun height(slots: Int): Dp = pad * 2 + slotHeight * slots
    fun x(column: Int): Dp = margin + (cardWidth + columnGap) * column
    /** "Finale", "Demies", "Quarts", "8es", "16es", "Tour 1". */
    fun shortName(round: Int, total: Int) = when (total - round) {
        0 -> "Finale"; 1 -> "Demies"; 2 -> "Quarts"; 3 -> "8es"; 4 -> "16es"; else -> "Tour $round"
    }
}

/** The 20 dp margins of the page given back to a wide child, so it scrolls from edge to edge. */
private fun Modifier.bleed(side: Dp) = layout { measurable, constraints ->
    val extra = side.roundToPx()
    val placeable = measurable.measure(constraints.copy(minWidth = constraints.minWidth + 2 * extra, maxWidth = constraints.maxWidth + 2 * extra))
    layout(placeable.width - 2 * extra, placeable.height) { placeable.place(-extra, 0) }
}

/**
 * The bracket drawn like a football one ([TournamentLayout]): the first rounds on both sides, the final in
 * the middle under the trophy, lines from each match to the next. It scrolls sideways and opens on my match.
 */
@Composable
private fun TournamentTree(store: TournamentStore, bracket: TournamentBracket, me: String?) {
    val layout = remember(bracket) { TournamentLayout(bracket, { Tree.height(it).value.toDouble() }, Tree.gap.value.toDouble()) }
    val total = bracket.rounds.size
    val width = Tree.x(layout.columns) - Tree.columnGap + Tree.margin
    val top = Tree.header + Tree.trophy
    val height = top + layout.height.dp + 8.dp
    val scroll = rememberScrollState()
    val density = LocalDensity.current
    val target = me?.let { uid -> layout.nodes.lastOrNull { bracket.rounds[it.round - 1][it.index].has(uid) } } ?: layout.node(total, 0)
    LaunchedEffect(target?.round, target?.index) {
        val node = target ?: return@LaunchedEffect
        val viewport = snapshotFlow { scroll.viewportSize }.first { it > 0 }
        val centre = with(density) { (Tree.x(node.column) + Tree.cardWidth / 2).toPx() }
        scroll.scrollTo((centre - viewport / 2f).toInt().coerceIn(0, scroll.maxValue))
    }
    Box(Modifier.fillMaxWidth().bleed(20.dp).horizontalScroll(scroll).testTag("tournamentTree")) {
        Box(Modifier.size(width, height).drawBehind {
            // The lines from each match to the next one: into the slot its winner takes, lit once it is known.
            for (node in layout.nodes) {
                if (node.round < 2) continue
                val match = bracket.rounds[node.round - 1][node.index]
                val parentTop = top.toPx() + (node.y - node.height / 2).toFloat() * density.density
                match.from.forEachIndexed { position, source ->
                    val child = layout.node(node.round - 1, source) ?: return@forEachIndexed
                    val fromLeft = node.side == TournamentLayout.Side.Left || (node.side == TournamentLayout.Side.Center && child.side == TournamentLayout.Side.Left)
                    val childEdge = (if (fromLeft) Tree.x(child.column) + Tree.cardWidth else Tree.x(child.column)).toPx()
                    val parentEdge = (if (fromLeft) Tree.x(node.column) else Tree.x(node.column) + Tree.cardWidth).toPx()
                    val mid = (childEdge + parentEdge) / 2
                    val childY = top.toPx() + child.y.toFloat() * density.density
                    val slotY = parentTop + (Tree.pad + Tree.slotHeight * (position + 0.5f)).toPx()
                    val before = bracket.rounds[node.round - 2][source]
                    val lit = before.decided && before.winner != null
                    val path = Path().apply { moveTo(childEdge, childY); lineTo(mid, childY); lineTo(mid, slotY); lineTo(parentEdge, slotY) }
                    drawPath(path, if (lit) Palette.mint.copy(alpha = 0.75f) else Color.White.copy(alpha = 0.16f),
                        style = Stroke(width = (if (lit) 2.dp else 1.5.dp).toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
                }
            }
        }) {
            for (column in 0 until layout.columns) {
                val round = if (column < total) column + 1 else layout.columns - column
                Text(Tree.shortName(round, total).uppercase(), fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.1.sp,
                    color = if (round == total) Palette.accent else Palette.tertiary, textAlign = TextAlign.Center, maxLines = 1,
                    modifier = Modifier.offset(Tree.x(column), 8.dp).width(Tree.cardWidth))
            }
            layout.node(total, 0)?.let { final ->
                val champion = bracket.champion
                Column(Modifier.offset(Tree.x(final.column), top + (final.y - final.height / 2).dp - Tree.trophy + 4.dp).size(Tree.cardWidth, Tree.trophy - 8.dp)
                    .semantics(mergeDescendants = true) { contentDescription = champion?.let { "Champion : ${it.name}" } ?: "Le vainqueur n’est pas encore connu" },
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically)) {
                    Icon(if (champion == null) Icons.Filled.EmojiEvents else CrownIcon, null, Modifier.size(32.dp), tint = Palette.accent)
                    Text(champion?.name ?: "Vainqueur ?", fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        color = if (champion == null) Palette.tertiary else Palette.accent)
                }
            }
            for (node in layout.nodes) {
                val match = bracket.rounds[node.round - 1][node.index]
                TreeCard(store, match, node.round, node.round == total, me,
                    Modifier.offset(Tree.x(node.column), top + (node.y - node.height / 2).dp).size(Tree.cardWidth, node.height.dp))
            }
        }
    }
}

@Composable
private fun TreeCard(store: TournamentStore, match: TournamentBracket.Match, round: Int, final: Boolean, me: String?, modifier: Modifier) {
    val shape = RoundedCornerShape(14.dp)
    val mine = me != null && match.has(me)
    Column(modifier.clip(shape).background(Palette.surface.copy(alpha = 0.92f))
        .background(Brush.linearGradient(listOf(Duel.color.copy(alpha = if (mine) 0.34f else 0.2f), Color.White.copy(alpha = 0.03f))))
        .border(if (final || mine) 1.5.dp else 1.dp, if (final) Palette.accent.copy(alpha = 0.8f) else if (mine) Duel.text.copy(alpha = 0.9f) else Color.White.copy(alpha = 0.12f), shape)
        .padding(horizontal = 10.dp, vertical = Tree.pad)
        .semantics(mergeDescendants = true) {}) {
        match.slots.forEach { slot -> TreeSlot(store, match, round, slot, me) }
    }
}

@Composable
private fun TreeSlot(store: TournamentStore, match: TournamentBracket.Match, round: Int, slot: TournamentBracket.Slot, me: String?) {
    val id = slot.uid()
    val won = match.decided && id != null && match.winner?.uid == id
    val lost = match.decided && id != null && !won
    val mine = id != null && id == me
    val run = id?.let { store.run(round, it) }
    val opened = (TournamentRules.roundStartMs(store.currentWeek, round) ?: 0) <= store.nowMs
    val status = when {
        id == null -> ""
        match.decided -> run?.scoreMs?.let(ChallengeFormat::time) ?: "—"
        !opened -> ""
        run?.finishedMs != null -> "✓"
        run != null -> "en jeu"
        else -> ""
    }
    val name = when (slot) {
        is TournamentBracket.Slot.Player -> slot.player.name
        TournamentBracket.Slot.Empty -> "personne"
        TournamentBracket.Slot.Pending -> "…"
    }
    Row(Modifier.fillMaxWidth().height(Tree.slotHeight), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(name, fontSize = 13.sp, fontWeight = if (won || mine) FontWeight.Bold else FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis,
            textDecoration = if (lost) TextDecoration.LineThrough else null, modifier = Modifier.weight(1f),
            color = when { id == null || lost -> Palette.tertiary; won -> Palette.mint; mine -> Duel.text; else -> Palette.foreground })
        if (won) Icon(Icons.Filled.CheckCircle, null, Modifier.size(12.dp), tint = Palette.mint)
        Text(status, fontSize = 11.sp, fontWeight = if (status == "✓") FontWeight.Bold else FontWeight.Normal, maxLines = 1,
            color = if (status == "✓") Palette.mint else Palette.tertiary)
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
    val now = vm.nowMs // read here: inside Centered { } it would not move (that part is skipped)
    val leave = { if (vm.phase == TournamentPlayViewModel.Phase.Playing) confirmQuit = true else close() }
    BackHandler(onBack = leave)
    LaunchedEffect(vm.mistakeTick) { if (vm.mistakeTick > 0) haptics.retry() }
    LaunchedEffect(vm.successTick) { if (vm.successTick > 0) haptics.success() }

    Box(Modifier.fillMaxSize()) {
        AmbientBackground(dimmed = vm.phase == TournamentPlayViewModel.Phase.Playing)
        Column(Modifier.readableWidth().fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 12.dp)) {
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
                    if (now < vm.endMs) DuelButton("C’est parti", Modifier.padding(top = 24.dp).testTag("tournamentGo")) { haptics.selection(); vm.start(state) }
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
