package com.poupoutch.cnsnn.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.poupoutch.cnsnn.core.ChallengeFormat
import com.poupoutch.cnsnn.core.ChallengeGame
import com.poupoutch.cnsnn.core.ChallengeRules
import com.poupoutch.cnsnn.core.LiveDuel
import com.poupoutch.cnsnn.core.LiveDuelInvite
import com.poupoutch.cnsnn.core.LiveDuelRules
import com.poupoutch.cnsnn.share.Share
import com.poupoutch.cnsnn.state.AppViewModel
import com.poupoutch.cnsnn.state.LiveDuelViewModel
import kotlinx.coroutines.delay

// Duel en direct, the Android twin of the iPhone's LiveDuelView: looking for an opponent (or waiting for
// a friend with a link), the 3-2-1, the 5 words with the other player's progress on top, the result.

@Composable
fun LiveDuelScreen(state: AppViewModel, start: String, close: () -> Unit) {
    val duelVm: LiveDuelViewModel = viewModel()
    LaunchedEffect(Unit) { duelVm.loadOnce(start, state) }
    val haptics = rememberHaptics()
    var confirmQuit by remember { mutableStateOf(false) }
    // The clock moves the 3-2-1, the chrono and the result on its own: a new frame 4 times a second.
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(250); tick++ } }
    tick
    val uid = state.uid
    val duel = duelVm.duel
    val duelState = if (duel != null && uid != null && duelVm.phase == LiveDuelViewModel.Phase.Live) duel.state(uid, duelVm.nowMs) else null
    val leave = {
        if (duelState == LiveDuel.State.Countdown || duelState == LiveDuel.State.Playing) confirmQuit = true
        else { duelVm.leave(state); close() }
    }
    BackHandler(onBack = leave)
    LaunchedEffect(duelVm.mistakeTick) { if (duelVm.mistakeTick > 0) haptics.retry() }
    LaunchedEffect(duelVm.successTick) { if (duelVm.successTick > 0) haptics.success() }
    val opponent = if (duel != null && uid != null && !duel.isOpen) duel.theirs(uid) else null

    Box(Modifier.fillMaxSize()) {
        AmbientBackground(dimmed = duelVm.phase == LiveDuelViewModel.Phase.Live)
        Column(Modifier.readableWidth().fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 12.dp)) {
            Box(Modifier.fillMaxWidth().height(56.dp)) {
                IconButton(leave, Modifier.align(Alignment.CenterStart)) { Icon(Icons.Filled.Close, "Quitter") }
                Column(Modifier.align(Alignment.Center).semantics(mergeDescendants = true) { heading() }, horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Duel en direct", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                    if (opponent != null) Text("contre ${opponent.name}", fontSize = 12.sp, color = Palette.tertiary, maxLines = 1)
                }
                val game = duelVm.game
                if (duelState == LiveDuel.State.Playing && game != null) Box(Modifier.align(Alignment.CenterEnd).padding(end = 4.dp)) {
                    Pill(ChallengeFormat.time(game.scoreMs(duelVm.elapsedMs)), "Chrono")
                }
            }
            when (val phase = duelVm.phase) {
                LiveDuelViewModel.Phase.Connecting -> Centered { CircularProgressIndicator(color = Palette.secondary); Line("Connexion…") }
                is LiveDuelViewModel.Phase.Searching -> Centered {
                    val left = (LiveDuelRules.SEARCH_MS - (System.currentTimeMillis() - phase.sinceMs)).coerceAtLeast(0)
                    DuelGlyph(72)
                    Text("Recherche d’un adversaire…", fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 18.dp))
                    Text(ChallengeFormat.time(left), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Duel.soft, modifier = Modifier.padding(top = 6.dp))
                    Line("Le premier joueur qui cherche aussi un duel sera votre adversaire.")
                }
                LiveDuelViewModel.Phase.Nobody -> Centered {
                    DuelGlyph(72)
                    Text("Personne ne cherche en ce moment", fontSize = 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 18.dp))
                    Line("Réessayez dans un instant, ou invitez un ami : il vous rejoint avec le lien.")
                    DuelButton("Chercher encore", Modifier.padding(top = 22.dp)) { haptics.selection(); duelVm.searchAgain(state) }
                    TonalButton("Inviter un ami par lien", Modifier.padding(top = 10.dp)) { haptics.selection(); duelVm.restart("link", state) }
                }
                LiveDuelViewModel.Phase.Waiting -> Waiting(duelVm)
                LiveDuelViewModel.Phase.Live -> if (duel != null && uid != null && duelState != null) Live(state, duelVm, duel, uid, duelState, close)
                    else Centered { CircularProgressIndicator(color = Palette.secondary) }
                is LiveDuelViewModel.Phase.Failed -> Centered {
                    Text(phase.message, textAlign = TextAlign.Center, color = Palette.secondary, modifier = Modifier.padding(horizontal = 20.dp))
                    TonalButton("Réessayer", Modifier.padding(top = 20.dp)) { duelVm.restart(duelVm.start.ifEmpty { start }, state) }
                }
            }
        }
    }

    if (confirmQuit) AlertDialog({ confirmQuit = false },
        title = { Text("Quitter le duel ?") },
        text = { Text("Quitter maintenant fait perdre le duel.") },
        confirmButton = { TextButton({ confirmQuit = false; duelVm.leave(state); close() }) { Text("Abandonner", color = Palette.red) } },
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

@Composable
private fun Waiting(duelVm: LiveDuelViewModel) {
    val context = LocalContext.current
    val code = duelVm.duel?.code
    Centered {
        DuelGlyph(64)
        Text("Envoyez ce code à un ami", fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 16.dp))
        Text(code ?: "······", fontSize = 44.sp, fontWeight = FontWeight.Black, letterSpacing = 6.sp, color = Duel.text,
            modifier = Modifier.padding(top = 10.dp).semantics { contentDescription = "Code : " + (code?.toList()?.joinToString(" ") ?: "") })
        if (code != null) DuelButton("Envoyer le lien", Modifier.padding(top = 18.dp).testTag("shareLiveDuel")) { Share.plain(context, LiveDuelInvite.shareText(code)) }
        Row(Modifier.padding(top = 24.dp), verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Duel.soft)
            Spacer(Modifier.width(8.dp))
            Text("En attente de votre ami…", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Duel.soft)
        }
        Line("Il a 15 minutes pour ouvrir le lien ou taper le code dans « Défier un ami ». Gardez cet écran ouvert : le duel démarre dès qu’il arrive.")
    }
}

@Composable
private fun ColumnScope.Live(state: AppViewModel, duelVm: LiveDuelViewModel, duel: LiveDuel, uid: String, duelState: LiveDuel.State, close: () -> Unit) {
    duelVm.version // The core game is a plain object: re-read after every move.
    val game = duelVm.game ?: return
    when (duelState) {
        LiveDuel.State.Countdown -> Centered {
            val left = (((duel.startMs ?: 0) - duelVm.nowMs + 999) / 1000).coerceIn(1, 5)
            Text("Duel contre", fontSize = 15.sp, color = Palette.secondary)
            Text(duel.theirs(uid).name, fontSize = 26.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 2.dp))
            Text("$left", fontSize = 120.sp, fontWeight = FontWeight.Black, color = Duel.text, modifier = Modifier.padding(top = 20.dp))
            Line("Mêmes 5 mots, au même moment. Chaque mot passé ajoute 20 s.")
        }
        LiveDuel.State.Playing -> {
            Tracks(duel, uid, game)
            val card = game.card
            if (card == null) Centered { CircularProgressIndicator(color = Palette.secondary); Line("Envoi de votre temps…") }
            else {
                Text("Mot ${game.index + 1} sur ${ChallengeRules.WORDS}", fontSize = 12.sp, color = Palette.tertiary,
                    modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 10.dp))
                Clue(card, duelVm.passed, duelVm.passedTick)
                AnswerLine(duelVm.answer, duelVm.mistakeTick, true, duelVm.answerWrong, duelVm.cursor) { duelVm.placeCursor(it) }
                SkipChip("Passer · +20 s", "Passer ce mot, 20 secondes de pénalité") { duelVm.skip(state) }
                LetterKeyboard(press = { duelVm.press(it, state.uid) }, delete = { duelVm.delete() }, clear = { duelVm.clear() },
                    moveCursor = { duelVm.moveCursor(it) }, submit = { duelVm.submit(state) }, enabled = true)
            }
        }
        LiveDuel.State.Finished -> {
            Tracks(duel, uid, game)
            Centered {
                Text("Votre temps", fontSize = 14.sp, color = Palette.tertiary)
                Text(ChallengeFormat.time(duel.scoreMs(duel.mine(uid)) ?: game.scoreMs(duelVm.elapsedMs)), fontSize = 60.sp, fontWeight = FontWeight.Black)
                val left = duel.leftToBeatMs(uid, duelVm.nowMs) ?: 0
                Line("${duel.theirs(uid).name} doit finir en moins de ${ChallengeFormat.time(left)} pour vous battre.")
            }
        }
        LiveDuel.State.Waiting -> Centered { CircularProgressIndicator(color = Palette.secondary) }
        is LiveDuel.State.Over -> {
            Tracks(duel, uid, game)
            Spacer(Modifier.weight(1f))
            Result(state, duelVm, duel, uid, duelState.result, game, close)
        }
    }
}

/** Both players' progress, one bar per word: the other one's moves come in live. */
@Composable
private fun Tracks(duel: LiveDuel, uid: String, game: ChallengeGame) {
    val other = duel.theirs(uid)
    Surface(Modifier.fillMaxWidth().padding(top = 8.dp), shape = RoundedCornerShape(20.dp), color = Color.Transparent, border = Duel.border) {
        Column(Modifier.background(Duel.surface).padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Track("Vous", uid, maxOf(game.index, duel.mine(uid).done), game.finished, false)
            Track(other.name, other.uid, other.done, other.finished, other.quit)
        }
    }
}

@Composable
private fun Track(name: String, id: String, done: Int, finished: Boolean, quit: Boolean) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {
        contentDescription = if (quit) "$name a quitté" else "$name : $done mots sur ${ChallengeRules.WORDS}"
    }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Avatar(name, colorIndex(id), 24.dp)
        Text(name, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.width(86.dp))
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            repeat(ChallengeRules.WORDS) { index ->
                Box(Modifier.weight(1f).height(6.dp).background(if (index < done) Duel.color else Palette.fill2, RoundedCornerShape(50)))
            }
        }
        Text(if (quit) "parti" else if (finished) "fini" else "$done/${ChallengeRules.WORDS}", fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
            color = Palette.tertiary, textAlign = TextAlign.End, modifier = Modifier.width(34.dp))
    }
}

@Composable
private fun Result(state: AppViewModel, duelVm: LiveDuelViewModel, duel: LiveDuel, uid: String, result: LiveDuel.Result, game: ChallengeGame, close: () -> Unit) {
    val haptics = rememberHaptics()
    val me = duel.mine(uid)
    val other = duel.theirs(uid)
    LaunchedEffect(result) {
        if (result == LiveDuel.Result.WON) haptics.success() else if (result == LiveDuel.Result.LOST) haptics.retry()
        duelVm.resend(state)
    }
    Surface(Modifier.fillMaxWidth().padding(horizontal = 4.dp).padding(bottom = 12.dp), shape = RoundedCornerShape(40.dp), color = Color.Transparent, border = Duel.border) {
        Column(Modifier.background(Duel.surface).padding(horizontal = 22.dp, vertical = 26.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(when (result) {
                LiveDuel.Result.WON -> if (other.quit) "${other.name} a abandonné : victoire !" else "Victoire contre ${other.name} !"
                LiveDuel.Result.LOST -> "${other.name} a été plus rapide…"
                LiveDuel.Result.DRAW -> "Égalité !"
            }, style = Type.serifItalic(26), textAlign = TextAlign.Center,
                color = when (result) { LiveDuel.Result.WON -> Palette.mint; LiveDuel.Result.LOST -> Palette.red; else -> Duel.soft })
            Row(Modifier.padding(top = 18.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                listOf((duel.scoreMs(me)?.let(ChallengeFormat::time) ?: if (me.quit) "abandon" else "—") to "vous",
                    (duel.scoreMs(other)?.let(ChallengeFormat::time) ?: if (other.quit) "abandon" else "—") to other.name).forEach { (v, l) ->
                    Surface(Modifier.weight(1f), shape = RoundedCornerShape(20.dp), color = Palette.fill1, border = BorderStroke(1.dp, Palette.line)) {
                        Column(Modifier.padding(vertical = 12.dp).semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(v, fontSize = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                            Text(l, fontSize = 12.sp, color = Palette.tertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
            missedSentence(game.missed)?.let {
                Text(it, fontSize = 13.sp, color = Palette.tertiary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp))
            }
            Text("Le temps officiel est mesuré par le serveur. Chaque mot passé compte 20 s.", fontSize = 12.sp, color = Palette.tertiary,
                textAlign = TextAlign.Center, modifier = Modifier.padding(top = 12.dp))
            Row(Modifier.padding(top = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TonalButton("Rejouer", Modifier.weight(1f).testTag("liveDuelAgain")) {
                    haptics.selection(); duelVm.restart(if (duelVm.start == "random") "random" else "link", state)
                }
                PrimaryButton("Terminer", Modifier.weight(1f), onClick = close)
            }
        }
    }
}
