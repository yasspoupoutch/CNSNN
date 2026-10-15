package com.poupoutch.cnsnn.ui

import androidx.core.content.ContextCompat
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.rememberLauncherForActivityResult
import android.os.Build
import android.content.pm.PackageManager
import android.Manifest
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.SportsKabaddi
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.poupoutch.cnsnn.core.Challenge
import com.poupoutch.cnsnn.core.ChallengeFormat
import com.poupoutch.cnsnn.core.ChallengeInvite
import com.poupoutch.cnsnn.core.ChallengeRules
import com.poupoutch.cnsnn.core.Mistakes
import com.poupoutch.cnsnn.core.Site
import com.poupoutch.cnsnn.data.CloudError
import com.poupoutch.cnsnn.share.Share
import com.poupoutch.cnsnn.state.AppViewModel
import com.poupoutch.cnsnn.state.ChallengeViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Défi entre amis: the lilac tile on the home page, the sheet to challenge a friend, the game and its result.

object Duel {
    /** The challenge's lilac: only on challenge surfaces, so it never competes with the gold vowels. */
    val color = Color(0xFFC9A7FF)
    val text = Color(0xFFE6D8FF)
    val soft = Color(0xFFD9C8FF)
    val surface = Brush.linearGradient(listOf(color.copy(alpha = 0.26f), Color(0xFF785ADC).copy(alpha = 0.10f)))
    val border = BorderStroke(1.dp, Brush.verticalGradient(listOf(text.copy(alpha = 0.6f), color.copy(alpha = 0.42f))))
}

private fun nowMs() = System.currentTimeMillis()

@Composable
private fun DuelGlyph(size: Int = 46) {
    Box(Modifier.size(size.dp).background(Duel.color.copy(alpha = 0.22f), CircleShape).border(1.dp, Duel.color.copy(alpha = 0.5f), CircleShape),
        contentAlignment = Alignment.Center) {
        Icon(Icons.Filled.SportsKabaddi, null, Modifier.size((size * 0.48f).dp), tint = Duel.text)
    }
}

@Composable
private fun DuelButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, busy: Boolean = false, onClick: () -> Unit) {
    Button(onClick, modifier.heightIn(min = 40.dp), enabled = enabled, shape = RoundedCornerShape(50),
        colors = ButtonDefaults.buttonColors(containerColor = Duel.color.copy(alpha = 0.22f), contentColor = Duel.text,
            disabledContainerColor = Duel.color.copy(alpha = 0.1f), disabledContentColor = Duel.text.copy(alpha = 0.5f)),
        border = BorderStroke(1.dp, Duel.color.copy(alpha = 0.5f))) {
        if (busy) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Duel.text)
        else Text(text, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
    }
}

// ---- Home tile

/** "Défier un ami", or the challenge that needs the player: a friend's to play, mine to finish, or the one waiting for the friend. */
@Composable
fun ChallengeTile(state: AppViewModel, open: () -> Unit, play: (Challenge) -> Unit) {
    var now by remember { mutableLongStateOf(nowMs()) }
    LaunchedEffect(Unit) { while (true) { delay(60_000); now = nowMs() } }
    val featured = state.featuredChallenge(now)
    val uid = state.uid
    val haptics = rememberHaptics()
    val (title, subtitle) = tileText(state, featured, now)
    val actionable = featured != null && featured.second != Challenge.State.Waiting
    Surface({ haptics.selection(); if (featured != null && actionable) play(featured.first) else open() },
        Modifier.fillMaxWidth().testTag("challengeTile"), shape = RoundedCornerShape(26.dp), color = Color.Transparent, border = Duel.border) {
        Row(Modifier.background(Duel.surface).padding(horizontal = 16.dp, vertical = 14.dp).semantics(mergeDescendants = true) { contentDescription = "$title. $subtitle" },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            if (featured != null && uid != null && !featured.first.isOpen) {
                val other = featured.first.theirs(uid)
                Avatar(other.name, colorIndex(other.uid), 42.dp)
            } else DuelGlyph()
            Column(Modifier.weight(1f)) {
                Text(title, fontSize = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(subtitle, fontSize = 13.sp, color = Duel.soft, modifier = Modifier.padding(top = 2.dp))
            }
            if (actionable) {
                Text(if (featured?.second == Challenge.State.Playing) "Reprendre" else "Jouer", color = Duel.text, fontWeight = FontWeight.SemiBold, fontSize = 15.sp,
                    modifier = Modifier.background(Duel.color.copy(alpha = 0.22f), RoundedCornerShape(50)).border(1.dp, Duel.color.copy(alpha = 0.5f), RoundedCornerShape(50))
                        .padding(horizontal = 16.dp, vertical = 9.dp))
            } else Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Palette.tertiary)
        }
    }
}

private fun tileText(state: AppViewModel, featured: Pair<Challenge, Challenge.State>?, now: Long): Pair<String, String> {
    val uid = state.uid
    if (featured == null || uid == null) {
        val tally = state.challengeTally().label
        return "Défier un ami" to ("Mêmes 5 mots. Le plus rapide gagne." + (tally?.let { "\n$it" } ?: ""))
    }
    val (c, status) = featured
    val name = c.theirs(uid).name
    return when (status) {
        Challenge.State.YourTurn -> "$name vous a défié !" to ("Son chrono : caché · plus que " + ChallengeFormat.left(c.startDeadlineMs - now))
        Challenge.State.Playing -> (if (c.isOpen) "Défi par lien en cours" else "Défi en cours contre $name") to "Votre chrono tourne · 5 mots"
        else -> {
            val left = if (c.theirs(uid).startedMs == null) c.startDeadlineMs else c.finishDeadlineMs
            (if (c.isOpen) "Défi par lien en attente" else "En attente de $name") to ("Votre chrono : " + ChallengeFormat.time(c.mine(uid).scoreMs ?: 0) + " · encore " + ChallengeFormat.left(left - now))
        }
    }
}

// ---- Sheet: challenge a friend

@Composable
fun ChallengeSheet(state: AppViewModel, play: (Challenge) -> Unit) {
    val uid = state.uid
    var friends by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var code by remember { mutableStateOf<String?>(null) }
    var sending by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var joinCode by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val haptics = rememberHaptics()
    val focus = LocalFocusManager.current
    // A code received from a friend, or the link the app was opened with.
    fun join(text: String) {
        val clean = ChallengeInvite.code(text) ?: return
        if (sending != null) return
        haptics.selection(); sending = "join"; message = null; focus.clearFocus()
        scope.launch {
            try { val c = state.joinChallenge(clean); joinCode = ""; play(c) }
            catch (e: Exception) { message = CloudError.message(e); haptics.retry() }
            finally { sending = null }
        }
    }
    LaunchedEffect(uid, state.inviteCode) {
        val invite = state.inviteCode
        if (uid != null && invite != null) { state.inviteCode = null; joinCode = invite; join(invite) }
    }
    LaunchedEffect(uid) {
        if (uid == null) { loading = false; return@LaunchedEffect }
        friends = runCatching { state.cloud.friends(uid) }.getOrDefault(emptyList())
        loading = false
        state.refreshChallenges()
        if (code == null) code = runCatching { state.cloud.friendCode(uid, state.progress.username.ifEmpty { "Joueur" }) }.getOrNull()
    }
    val now = nowMs()
    Column(Modifier.verticalScroll(rememberScrollState()).padding(start = 22.dp, end = 22.dp, bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            DuelGlyph(40)
            Column {
                Kicker("Défi entre amis", Duel.color)
                Text("Mêmes 5 mots. Le plus rapide gagne.", fontSize = 19.sp, fontWeight = FontWeight.Bold)
            }
        }
        Text("Votre chrono démarre dès que vous lancez le défi. Votre ami a 48 h pour jouer ; chaque mot passé ajoute 20 s.",
            fontSize = 13.sp, color = Palette.secondary)
        state.challengeTally().label?.let { Text("Votre bilan : $it", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Duel.soft) }
        if (uid == null) {
            SectionCard(radius = 22.dp, padding = 16.dp) { Text("Connectez-vous à Internet pour défier vos amis.", color = Palette.secondary) }
        } else {
            val open = state.challenges.filter { it.state(uid, now) !is Challenge.State.Over }
            if (open.isNotEmpty()) {
                Kicker("En cours", Palette.tertiary, Modifier.padding(top = 6.dp))
                SectionCard(padding = 0.dp, radius = 22.dp) {
                    open.forEachIndexed { index, c ->
                        if (index > 0) Divider()
                        val other = c.theirs(uid)
                        val status = c.state(uid, now)
                        val code = c.code
                        PersonRow(c.opponentName(uid), other.uid, openLine(c, status, uid, now), link = c.isOpen) {
                            if (status == Challenge.State.YourTurn || status == Challenge.State.Playing)
                                DuelButton(if (status == Challenge.State.Playing) "Reprendre" else "Jouer") { play(c) }
                            else if (c.isOpen && code != null) DuelButton("Partager") { Share.plain(context, ChallengeInvite.shareText(code)) }
                        }
                    }
                }
            }
            SectionCard(Modifier.padding(top = 6.dp), padding = 0.dp, radius = 22.dp) {
                Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 10.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(joinCode, { text -> joinCode = text.uppercase().filter { it in ChallengeInvite.ALPHABET }.take(6) },
                        Modifier.weight(1f).testTag("joinCode"), singleLine = true,
                        placeholder = { Text("Code d’un défi reçu", color = Palette.tertiary) },
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false, imeAction = ImeAction.Go),
                        keyboardActions = KeyboardActions(onGo = { join(joinCode) }),
                        colors = OutlinedTextFieldDefaults.colors(unfocusedBorderColor = Color.Transparent, focusedBorderColor = Color.Transparent))
                    DuelButton("Rejoindre", enabled = joinCode.length == 6 && sending == null, busy = sending == "join") { join(joinCode) }
                }
            }
            Kicker("Défier un ami", Palette.tertiary, Modifier.padding(top = 6.dp))
            SectionCard(padding = 0.dp, radius = 22.dp) {
                if (friends.isEmpty()) Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (loading) { CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Palette.secondary); Spacer(Modifier.width(10.dp)) }
                    Text(if (loading) "Chargement…" else "Ajoutez d’abord un ami avec son code (Stats › Classement › Amis), ou invitez-le ci-dessous.",
                        fontSize = 14.sp, color = Palette.tertiary)
                }
                friends.forEachIndexed { index, (friend, name) ->
                    if (index > 0) Divider()
                    PersonRow(name, friend, state.challengeTally(friend).label ?: "Aucun défi pour l’instant", detailColor = Duel.soft.copy(alpha = 0.85f)) {
                        DuelButton("Défier", Modifier.semantics { contentDescription = "Défier $name" }, enabled = sending == null, busy = sending == friend) {
                            haptics.selection(); sending = friend; message = null
                            scope.launch {
                                try { play(state.sendChallenge(friend, name)) }
                                catch (e: Exception) { message = CloudError.message(e); haptics.retry() }
                                finally { sending = null }
                            }
                        }
                    }
                }
            }
            // For someone who is not a friend yet: play first, then send the link with its code.
            Surface(Modifier.fillMaxWidth().padding(top = 6.dp), shape = RoundedCornerShape(22.dp), color = Color.Transparent, border = Duel.border) {
                Column(Modifier.background(Duel.surface).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Pas encore amis ? Jouez d’abord, puis envoyez le lien. Le premier qui l’ouvre a 48 h pour vous battre.",
                        fontSize = 13.sp, color = Palette.secondary)
                    DuelButton("Défier par lien", Modifier.fillMaxWidth().testTag("openChallenge"), enabled = sending == null, busy = sending == "link") {
                        haptics.selection(); sending = "link"; message = null
                        scope.launch {
                            try { play(state.sendOpenChallenge()) }
                            catch (e: Exception) { message = CloudError.message(e); haptics.retry() }
                            finally { sending = null }
                        }
                    }
                }
            }
            val done = state.challenges.mapNotNull { c -> c.result(uid, now)?.let { c to it } }.take(5)
            if (done.isNotEmpty()) {
                Kicker("Derniers défis", Palette.tertiary, Modifier.padding(top = 6.dp))
                SectionCard(padding = 0.dp, radius = 22.dp) {
                    done.forEachIndexed { index, (c, result) ->
                        if (index > 0) Divider()
                        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(if (c.isOpen) resultTitle(result) + " · défi par lien" else resultTitle(result) + " contre " + c.theirs(uid).name, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
                                color = when (result) { Challenge.Result.WON -> Palette.mint; Challenge.Result.LOST -> Palette.red; else -> Palette.secondary },
                                modifier = Modifier.weight(1f))
                            Text((c.mine(uid).scoreMs?.let(ChallengeFormat::time) ?: "—") + " / " + (c.theirs(uid).scoreMs?.let(ChallengeFormat::time) ?: "—"),
                                fontSize = 13.sp, color = Palette.tertiary)
                        }
                    }
                }
            }
        }
        message?.let { Text(it, fontSize = 13.sp, color = Palette.red) }
        OutlinedButton({
            Share.plain(context, "Je te défie sur CNSNN : 5 mots sans leurs voyelles, le plus rapide gagne !" + (code?.let { " Ajoute-moi avec mon code ami $it." } ?: "") + " " + Site.URL)
        }, Modifier.fillMaxWidth().height(50.dp), shape = RoundedCornerShape(25.dp)) {
            Icon(Icons.Filled.Share, null, Modifier.size(18.dp)); Text("Inviter par message", Modifier.padding(start = 8.dp), fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun PersonRow(name: String, id: String, detail: String, detailColor: Color = Palette.tertiary, link: Boolean = false, action: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        if (link) DuelGlyph(34) else Avatar(name, colorIndex(id), 34.dp)
        Column(Modifier.weight(1f)) {
            Text(name, fontWeight = FontWeight.SemiBold, maxLines = 1)
            Text(detail, fontSize = 12.sp, color = detailColor, maxLines = 2)
        }
        action()
    }
}

private fun openLine(c: Challenge, status: Challenge.State, uid: String, now: Long): String = when (status) {
    Challenge.State.YourTurn -> "Vous a défié · plus que " + ChallengeFormat.left(c.startDeadlineMs - now)
    Challenge.State.Playing -> "Votre chrono tourne"
    else -> if (c.isOpen) "Code ${c.code ?: ""} · personne n’a encore rejoint"
        else "Votre chrono : " + ChallengeFormat.time(c.mine(uid).scoreMs ?: 0) + if (c.theirs(uid).startedMs == null) " · pas encore joué" else " · en train de jouer"
}

private fun resultTitle(result: Challenge.Result) = when (result) {
    Challenge.Result.WON -> "Victoire"; Challenge.Result.LOST -> "Défaite"; Challenge.Result.DRAW -> "Égalité"; Challenge.Result.EXPIRED -> "Expiré"
}

// ---- After the daily word

@Composable
fun ChallengePrompt(correct: Boolean, action: () -> Unit) {
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(26.dp), color = Color.Transparent, border = Duel.border) {
        Column(Modifier.background(Duel.surface).padding(16.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                DuelGlyph(40)
                Column {
                    Text(if (correct) "Vous êtes en forme !" else "Prenez votre revanche !", fontSize = 17.sp, fontWeight = FontWeight.Bold)
                    Text("Défiez un ami sur 5 mots, le plus rapide gagne.", fontSize = 13.sp, color = Duel.soft)
                }
            }
            DuelButton("Défier un ami", Modifier.fillMaxWidth().padding(top = 14.dp).testTag("challengePrompt"), onClick = action)
        }
    }
}

// ---- The game

@Composable
fun ChallengeScreen(state: AppViewModel, id: String, close: () -> Unit) {
    val game: ChallengeViewModel = viewModel()
    LaunchedEffect(Unit) { game.loadOnce(id, state) }
    val haptics = rememberHaptics()
    var confirmQuit by remember { mutableStateOf(false) }
    val phase = game.phase
    val leave = { if (phase == ChallengeViewModel.Phase.Playing) confirmQuit = true else close() }
    BackHandler(onBack = leave)
    LaunchedEffect(game.mistakeTick) { if (game.mistakeTick > 0) haptics.retry() }
    LaunchedEffect(game.successTick) { if (game.successTick > 0) haptics.success() }
    val uid = state.uid ?: ""
    val opponent = game.challenge?.opponentName(uid) ?: ""
    val byLink = game.challenge?.isOpen == true

    Box(Modifier.fillMaxSize()) {
        AmbientBackground(dimmed = phase == ChallengeViewModel.Phase.Playing)
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 12.dp)) {
            Box(Modifier.fillMaxWidth().height(56.dp)) {
                IconButton(leave, Modifier.align(Alignment.CenterStart)) { Icon(Icons.Filled.Close, "Quitter") }
                Column(Modifier.align(Alignment.Center).semantics(mergeDescendants = true) { heading() }, horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Défi", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                    Text(if (byLink) opponent else "contre $opponent", fontSize = 12.sp, color = Palette.tertiary, maxLines = 1)
                }
                if (phase == ChallengeViewModel.Phase.Playing) Box(Modifier.align(Alignment.CenterEnd).padding(end = 4.dp)) {
                    var tick by remember { mutableIntStateOf(0) }
                    LaunchedEffect(Unit) { while (true) { delay(500); tick++ } }
                    tick
                    Pill(ChallengeFormat.time(game.game?.scoreMs(game.elapsedMs) ?: 0), "Chrono")
                }
            }
            when (phase) {
                ChallengeViewModel.Phase.Playing -> Board(state, game)
                ChallengeViewModel.Phase.Starting, ChallengeViewModel.Phase.Sending -> Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = Palette.secondary)
                    Text(if (phase == ChallengeViewModel.Phase.Starting) "Lancement du chrono…" else "Envoi de votre temps…", color = Palette.secondary, modifier = Modifier.padding(top = 12.dp))
                }
                is ChallengeViewModel.Phase.Failed -> Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(phase.message, textAlign = TextAlign.Center, color = Palette.secondary)
                    TonalButton("Réessayer", Modifier.padding(top = 20.dp)) { game.begin(id, state) }
                }
                ChallengeViewModel.Phase.Done -> {}
            }
        }
        val done = phase == ChallengeViewModel.Phase.Done
        AnimatedVisibility(done, enter = fadeIn(), exit = fadeOut()) { Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.42f))) }
        AnimatedVisibility(done, Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessMediumLow)) { it }, exit = slideOutVertically { it }) {
            ChallengeResult(state, game, close)
        }
    }

    if (confirmQuit) AlertDialog({ confirmQuit = false },
        title = { Text("Quitter le défi ?") },
        text = { Text("Le chrono continue pendant votre absence. Abandonner compte les mots restants comme passés (+20 s chacun).") },
        confirmButton = { TextButton({ confirmQuit = false; game.abandon(state) }) { Text("Abandonner", color = Palette.red) } },
        dismissButton = {
            Row {
                TextButton({ confirmQuit = false; close() }) { Text("Plus tard") }
                TextButton({ confirmQuit = false }) { Text("Continuer") }
            }
        })
}

@Composable
private fun androidx.compose.foundation.layout.ColumnScope.Board(state: AppViewModel, game: ChallengeViewModel) {
    game.version // The core game is a plain object: re-read after every move.
    val current = game.game ?: return
    Row(Modifier.fillMaxWidth().padding(top = 10.dp, start = 30.dp, end = 30.dp)
        .semantics(mergeDescendants = true) { contentDescription = "Mot ${minOf(current.index + 1, current.cards.size)} sur ${current.cards.size}" },
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        current.cards.indices.forEach { index ->
            Box(Modifier.weight(1f).height(5.dp).background(when {
                index < current.index -> Duel.color; index == current.index -> Palette.foreground; else -> Palette.fill2
            }, RoundedCornerShape(50)))
        }
    }
    current.card?.let {
        Text("Mot ${current.index + 1} sur ${ChallengeRules.WORDS}", fontSize = 12.sp, color = Palette.tertiary,
            modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 14.dp))
        Clue(it)
    }
    AnswerLine(game.answer, game.mistakeTick, true)
    SkipChip("Passer · +20 s", "Passer ce mot, 20 secondes de pénalité") { game.skip(state) }
    LetterKeyboard(press = { game.press(it) }, delete = { game.delete() }, submit = { game.submit(state) }, enabled = true)
}

@Composable
private fun ChallengeResult(state: AppViewModel, game: ChallengeViewModel, close: () -> Unit) {
    val uid = state.uid ?: ""
    val c = game.challenge ?: return
    val me = c.mine(uid); val other = c.theirs(uid)
    val result = c.result(uid, nowMs())
    val byLink = c.isOpen
    val otherName = if (byLink) "Adversaire" else other.name
    val context = LocalContext.current
    val haptics = rememberHaptics()
    LaunchedEffect(result) { if (result == Challenge.Result.WON) haptics.success() }
    // After a challenge, the natural moment to ask: "tell me when my friend has played".
    val askNotifications = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            askNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
    Surface(Modifier.fillMaxWidth().padding(horizontal = 8.dp).navigationBarsPadding().padding(bottom = 8.dp), shape = RoundedCornerShape(40.dp),
        color = Palette.surfaceHigh, border = BorderStroke(1.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.3f), Palette.border)))) {
        Column(Modifier.padding(horizontal = 22.dp, vertical = 26.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(when (result) {
                Challenge.Result.WON -> "Victoire contre ${other.name} !"
                Challenge.Result.LOST -> "${other.name} a été plus rapide…"
                Challenge.Result.DRAW -> "Égalité parfaite !"
                Challenge.Result.EXPIRED -> "Défi expiré"
                null -> if (byLink) "Défi prêt à partager" else "Défi envoyé à ${other.name}"
            }, style = Type.serifItalic(24), textAlign = TextAlign.Center,
                color = when (result) { Challenge.Result.WON -> Palette.mint; Challenge.Result.LOST -> Palette.red; else -> Duel.soft })
            val mine = ChallengeFormat.time(game.myScoreMs(uid))
            Text(mine, fontSize = 60.sp, fontWeight = FontWeight.Black, letterSpacing = (-1.5).sp, modifier = Modifier.padding(top = 4.dp)
                .semantics { contentDescription = "Votre temps : $mine" })
            Text(if (me.skips > 0) "votre temps, dont ${me.skips * 20} s de pénalité" else "votre temps", fontSize = 13.sp, color = Palette.tertiary)
            Row(Modifier.padding(top = 18.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                listOf((other.scoreMs?.let(ChallengeFormat::time) ?: if (result == null) "caché" else "—") to otherName,
                    "${ChallengeRules.WORDS - me.skips}/${ChallengeRules.WORDS}" to "mots trouvés",
                    Mistakes.text(me.errors) to "réponses").forEach { (v, l) ->
                    Surface(Modifier.weight(1f), shape = RoundedCornerShape(20.dp), color = Palette.fill1) {
                        Column(Modifier.padding(vertical = 12.dp).semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(v, fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                            Text(l, fontSize = 12.sp, color = Palette.tertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
            Text(when {
                result != null -> "Le temps officiel est mesuré par le serveur."
                byLink -> "Envoyez le lien : le premier qui l’ouvre a 48 h pour battre votre temps, qui reste caché jusque-là."
                other.startedMs == null -> "Votre chrono reste caché jusqu’à ce que ${other.name} joue. Il a 48 h pour relever le défi."
                else -> "${other.name} est en train de jouer. Le résultat apparaîtra sur l’accueil."
            }, fontSize = 13.sp, color = Palette.secondary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 14.dp))
            Row(Modifier.padding(top = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                val code = c.code
                if (result == null && byLink && code != null) TonalButton("Envoyer le lien", Modifier.weight(1f).testTag("shareChallengeLink")) {
                    Share.plain(context, ChallengeInvite.shareText(code))
                } else if (result == null) TonalButton("Prévenir ${other.name}", Modifier.weight(1f)) {
                    Share.plain(context, "Je t’ai défié sur CNSNN : 5 mots, mon chrono est caché jusqu’à ce que tu joues. Ouvre l’app pour relever le défi ! ${Site.URL}")
                }
                PrimaryButton("Terminer", Modifier.weight(1f), onClick = close)
            }
            if (!byLink) state.challengeTally(other.uid).label?.let {
                Text("Contre ${other.name} : $it", fontSize = 12.sp, color = Palette.tertiary, modifier = Modifier.padding(top = 12.dp))
            }
        }
    }
}
