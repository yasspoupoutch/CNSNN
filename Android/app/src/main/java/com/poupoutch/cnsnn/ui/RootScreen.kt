package com.poupoutch.cnsnn.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.SportsEsports
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.poupoutch.cnsnn.core.Category
import com.poupoutch.cnsnn.core.CommunityRules
import com.poupoutch.cnsnn.core.Difficulty
import com.poupoutch.cnsnn.core.GameMode
import com.poupoutch.cnsnn.core.PlayMode
import com.poupoutch.cnsnn.core.Site
import com.poupoutch.cnsnn.reminders.Reminders
import com.poupoutch.cnsnn.state.AppViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.poupoutch.cnsnn.data.CloudError
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.runtime.rememberCoroutineScope

private const val LAUNCH_WORD = "CONSONNE"

@Composable
fun RootScreen(state: AppViewModel) {
    var introDone by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) { if (!introDone) { delay(introDurationMs(LAUNCH_WORD)); introDone = true } }
    Box(Modifier.fillMaxSize()) {
        AmbientBackground()
        val screen = when {
            !introDone || state.isRestoring -> 0
            state.progress.username.isNotEmpty() -> 2
            else -> 1
        }
        AnimatedContent(screen, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "root") { page ->
            when (page) {
                0 -> LaunchScreen(loading = introDone)
                1 -> OnboardingScreen(state)
                else -> AppNavigation(state)
            }
        }
    }
    // Players from before the community rules accept them once before playing on.
    if (introDone && !state.isRestoring && CommunityRules.mustAccept(state.progress)) RulesAcceptance(state::acceptRules)
    state.error?.let { message ->
        AlertDialog(onDismissRequest = { state.error = null }, confirmButton = { TextButton({ state.error = null }) { Text("Compris") } },
            title = { Text("CNSNN") }, text = { Text(message) })
    }
    // A friend link: added once there is an account, then said in a dialog.
    LaunchedEffect(state.friendInviteCode, state.uid) { state.acceptFriendInvite() }
    state.friendInviteResult?.let { message ->
        AlertDialog(onDismissRequest = { state.friendInviteResult = null }, confirmButton = { TextButton({ state.friendInviteResult = null }) { Text("OK") } },
            title = { Text("Ami") }, text = { Text(message) })
    }
}

@Composable
private fun LaunchScreen(loading: Boolean) {
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        VowelWord(LAUNCH_WORD, Type.wordmark(50), once = true)
        Spacer(Modifier.height(24.dp))
        CircularProgressIndicator(Modifier.size(28.dp).alpha(if (loading) 1f else 0f), color = Palette.secondary, strokeWidth = 2.5.dp)
    }
}

// ---- Navigation: the four tabs, and the game in full screen over them.

@Composable
private fun AppNavigation(state: AppViewModel) {
    val nav = rememberNavController()
    NavHost(nav, startDestination = "main",
        enterTransition = { slideInHorizontally { it / 3 } + fadeIn() }, exitTransition = { fadeOut() },
        popEnterTransition = { fadeIn() }, popExitTransition = { slideOutHorizontally { it / 3 } + fadeOut() }) {
        composable("main") {
            MainShell(state, { mode, category, difficulty ->
                nav.navigate("game/${mode.name}?category=${category?.name ?: ""}&difficulty=${difficulty?.name ?: ""}")
            }, { mode -> nav.navigate("mode/${mode.key}") }, { id -> nav.navigate("challenge/$id") }, { day -> nav.navigate("catchup/$day") },
                { nav.navigate("tutorial") })
        }
        composable("tutorial") {
            // "À vous de jouer": the real daily game opens in its place.
            GameScreen(state, GameMode.DAILY, null, null, tutorial = { play ->
                state.local.tutorialSeen = true
                nav.popBackStack()
                if (play) nav.navigate("game/${GameMode.DAILY.name}?category=&difficulty=")
            }) { nav.popBackStack() }
        }
        composable("catchup/{day}", arguments = listOf(navArgument("day") { type = NavType.StringType })) { entry ->
            GameScreen(state, GameMode.DAILY, null, null, catchUpDay = entry.arguments?.getString("day")) { nav.popBackStack() }
        }
        composable("challenge/{id}", arguments = listOf(navArgument("id") { type = NavType.StringType })) { entry ->
            ChallengeScreen(state, entry.arguments?.getString("id") ?: "") { nav.popBackStack() }
        }
        composable("mode/{mode}", arguments = listOf(navArgument("mode") { type = NavType.StringType })) { entry ->
            val mode = PlayMode.of(entry.arguments?.getString("mode")) ?: PlayMode.SPRINT
            ModeScreen(state, mode) { nav.popBackStack() }
        }
        composable("game/{mode}?category={category}&difficulty={difficulty}", arguments = listOf(
            navArgument("mode") { type = NavType.StringType },
            navArgument("category") { type = NavType.StringType; defaultValue = "" },
            navArgument("difficulty") { type = NavType.StringType; defaultValue = "" },
        )) { entry ->
            val args = entry.arguments!!
            GameScreen(state, GameMode.valueOf(args.getString("mode")!!),
                Category.entries.firstOrNull { it.name == args.getString("category") },
                Difficulty.entries.firstOrNull { it.name == args.getString("difficulty") }) { nav.popBackStack() }
        }
    }
}

private enum class Tab(val label: String, val icon: ImageVector, val selectedIcon: ImageVector) {
    PLAY("Jouer", Icons.Outlined.SportsEsports, Icons.Filled.SportsEsports),
    STATS("Stats", Icons.Outlined.BarChart, Icons.Filled.BarChart),
    FRIENDS("Amis", Icons.Outlined.Group, Icons.Filled.Group),
    PROFILE("Profil", Icons.Outlined.Person, Icons.Filled.Person),
}

@Composable
private fun MainShell(state: AppViewModel, play: (GameMode, Category?, Difficulty?) -> Unit, playMode: (PlayMode) -> Unit, playChallenge: (String) -> Unit,
                      playCatchUp: (String) -> Unit, playTutorial: () -> Unit) {
    var tab by rememberSaveable { mutableStateOf(Tab.PLAY) }
    // "Classement" on the home page.
    var seenRequest by rememberSaveable { mutableStateOf(state.leaderboardRequest) }
    LaunchedEffect(state.leaderboardRequest) { if (state.leaderboardRequest != seenRequest) { seenRequest = state.leaderboardRequest; tab = Tab.STATS } }
    // "Proposer un mot" on the daily result: the form lives in Profil.
    var seenPropose by rememberSaveable { mutableStateOf(state.proposeRequest) }
    LaunchedEffect(state.proposeRequest) { if (state.proposeRequest != seenPropose) { seenPropose = state.proposeRequest; tab = Tab.PROFILE } }
    // A challenge link opened the app: back to the home page, whose sheet joins it.
    LaunchedEffect(state.inviteCode) { if (state.inviteCode != null) tab = Tab.PLAY }
    val holder = rememberSaveableStateHolder()
    val haptics = rememberHaptics()
    // The first-launch tutorial, over the navigation bar, pointing at the daily card.
    val targets = remember { TutorialTargets() }
    var tutorial by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (!state.local.tutorialSeen && state.progress.attempts.isEmpty() && state.inviteCode == null) { delay(600); tab = Tab.PLAY; tutorial = true }
    }
    var seenTutorialRequest by rememberSaveable { mutableStateOf(state.tutorialRequest) }
    LaunchedEffect(state.tutorialRequest) { if (state.tutorialRequest != seenTutorialRequest) { seenTutorialRequest = state.tutorialRequest; tab = Tab.PLAY; tutorial = true } }
    Box(Modifier.fillMaxSize()) {
        CompositionLocalProvider(LocalTutorialTargets provides targets) {
            Scaffold(containerColor = androidx.compose.ui.graphics.Color.Transparent, bottomBar = {
                NavigationBar(containerColor = Palette.surface.copy(alpha = 0.94f), tonalElevation = 0.dp) {
                    Tab.entries.forEach { item ->
                        val selected = tab == item
                        NavigationBarItem(selected, onClick = { if (!selected) haptics.selection(); tab = item },
                            icon = { Icon(if (selected) item.selectedIcon else item.icon, contentDescription = null) },
                            label = { Text(item.label, fontWeight = FontWeight.SemiBold) },
                            colors = NavigationBarItemDefaults.colors(selectedIconColor = Palette.onAccent, indicatorColor = Palette.accent,
                                selectedTextColor = Palette.foreground, unselectedIconColor = Palette.tertiary, unselectedTextColor = Palette.tertiary))
                    }
                }
            }) { padding ->
                AnimatedContent(tab, Modifier.padding(padding), transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "tabs") { page ->
                    holder.SaveableStateProvider(page.name) {
                        when (page) {
                            Tab.PLAY -> HomeScreen(state, play, playMode, playChallenge, playCatchUp)
                            Tab.STATS -> StatsScreen(state)
                            Tab.FRIENDS -> FriendsScreen(state, playChallenge)
                            Tab.PROFILE -> ProfileScreen(state)
                        }
                    }
                }
            }
        }
        androidx.compose.animation.AnimatedVisibility(tutorial, enter = fadeIn(), exit = fadeOut()) {
            TutorialOverlay(targets, play = { tutorial = false; playTutorial() }, skip = { state.local.tutorialSeen = true; tutorial = false })
        }
    }
    ReminderOffer(state)
}

/**
 * Back on the home page after a found daily word, the 12h reminder is offered once: Android's
 * permission prompt alone when it is needed (a yes turns it on), else CNSNN asks in its own words.
 * Accepted or not, it is never asked again; it stays in Profil.
 */
@Composable
private fun ReminderOffer(state: AppViewModel) {
    val context = LocalContext.current
    var asking by remember { mutableStateOf(false) }
    fun turnOn() { state.local.reminderMinutes = Reminders.DEFAULT_MINUTES; state.local.remindersEnabled = true; state.refreshGlance(force = true) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> if (granted) turnOn() }
    LaunchedEffect(state.reminderPending) {
        if (!state.reminderPending) return@LaunchedEffect
        state.reminderPending = false
        state.local.reminderOffered = true
        delay(800)
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            permission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else asking = true
    }
    if (asking) AlertDialog({ asking = false },
        title = { Text("Un rappel à 12h ?") },
        text = { Text("Chaque jour à midi : « N’oubliez pas le mot du jour », sauf si vous l’avez déjà joué. Vous pourrez changer l’heure dans Profil.") },
        confirmButton = { TextButton({ asking = false; turnOn() }) { Text("Oui, me le rappeler") } },
        dismissButton = { TextButton({ asking = false }) { Text("Non merci") } })
}

// ---- Onboarding

@Composable
private fun OnboardingScreen(state: AppViewModel) {
    var step by rememberSaveable { mutableStateOf(0) }
    AnimatedContent(step, transitionSpec = {
        if (targetState > initialState) (slideInHorizontally { it } + fadeIn()) togetherWith (slideOutHorizontally { -it } + fadeOut())
        else (slideInHorizontally { -it } + fadeIn()) togetherWith (slideOutHorizontally { it } + fadeOut())
    }, label = "onboarding") { page ->
        if (page == 0) Rules { step = 1 } else Pseudo(state) { step = 0 }
    }
}

@Composable
private fun Rules(next: () -> Unit) {
    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 26.dp)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.height(50.dp))
            VowelWord("CONSONNE", Type.wordmark(52))
            Text("Retrouvez le mot. Sans ses voyelles.", style = Type.serifItalic(22), color = Palette.secondary, textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 14.dp))
            SectionCard(Modifier.padding(top = 38.dp), padding = 22.dp, radius = 30.dp) {
                Kicker("Exemple")
                Text("SRR", style = Type.serif(64), letterSpacing = 3.sp, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 12.dp))
                Text("Indice : « On le voit sur mon visage. »", color = Palette.secondary, textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 14.dp))
                Box(Modifier.padding(vertical = 18.dp)) { Divider() }
                VowelWord("SOURIRE", MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Black, letterSpacing = 2.4.sp),
                    Modifier.align(Alignment.CenterHorizontally), delayMs = 600)
            }
            Column(Modifier.padding(top = 28.dp, start = 6.dp, end = 6.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Bullet("Tapez le mot complet, les accents sont ignorés")
                Bullet("Un chrono tourne. Un indice si vous séchez, contre 1 minute de pénalité")
                Bullet("Un mot du jour commun, et le mode Classique sans limite")
            }
            Spacer(Modifier.height(16.dp))
        }
        PrimaryButton("Continuer", onClick = next, modifier = Modifier.padding(bottom = 12.dp))
    }
}

@Composable
private fun Bullet(text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.padding(top = 8.dp).size(6.dp).background(Palette.tertiary, CircleShape))
        Text(text, color = Palette.secondary)
    }
}

@Composable
private fun Pseudo(state: AppViewModel, back: () -> Unit) {
    var name by rememberSaveable { mutableStateOf("") }
    var accepted by rememberSaveable { mutableStateOf(false) }
    var signingIn by rememberSaveable { mutableStateOf(false) }
    val trimmed = name.trim()
    val valid = trimmed.length in 2..20
    val haptics = rememberHaptics()
    val links = LocalUriHandler.current
    val start = { if (valid && accepted && !state.isBusy) { haptics.success(); state.start(name) } }
    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding().padding(horizontal = 26.dp)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            IconButton(back, Modifier.padding(top = 6.dp)) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Retour") }
            Text("Choisissez un pseudo", style = MaterialTheme.typography.headlineLarge, modifier = Modifier.padding(top = 16.dp))
            Text("Pas d’inscription, pas d’email. Juste un nom pour jouer.", color = Palette.secondary, modifier = Modifier.padding(top = 8.dp))
            Avatar(trimmed.ifEmpty { "?" }, state.avatar, 104.dp, Modifier.align(Alignment.CenterHorizontally).padding(top = 34.dp))
            AvatarPicker(state.avatar, state::chooseAvatar, Modifier.align(Alignment.CenterHorizontally).padding(top = 20.dp))
            OutlinedTextField(name, { name = it.take(20) }, Modifier.fillMaxWidth().padding(top = 30.dp),
                placeholder = { Text("ex. voyelle_hunter") }, singleLine = true, shape = RoundedCornerShape(20.dp),
                label = { Text("Pseudo") }, supportingText = {
                    when {
                        trimmed.isEmpty() -> Text("Entre 2 et 20 caractères")
                        valid -> Text("✓ Parfait", color = Palette.mint)
                        else -> Text("Entre 2 et 20 caractères")
                    }
                },
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = { start() }),
                colors = TextFieldDefaults.colors(focusedContainerColor = Palette.fill1, unfocusedContainerColor = Palette.fill1))
            Row(Modifier.fillMaxWidth().padding(top = 10.dp).clip(RoundedCornerShape(16.dp))
                .toggleable(accepted, role = Role.Checkbox) { haptics.selection(); accepted = it }.padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Checkbox(accepted, onCheckedChange = null, modifier = Modifier.padding(horizontal = 8.dp),
                    colors = CheckboxDefaults.colors(checkedColor = Palette.accent, checkmarkColor = Palette.onAccent, uncheckedColor = Palette.tertiary))
                Text("J’accepte les règles de la communauté et la politique de confidentialité", fontSize = 14.sp, modifier = Modifier.padding(end = 8.dp))
            }
            Row(Modifier.padding(start = 44.dp)) {
                TextButton({ runCatching { links.openUri(Site.RULES) } }) { Text("Lire les règles", fontSize = 13.sp) }
                TextButton({ runCatching { links.openUri(Site.PRIVACY) } }) { Text("Confidentialité", fontSize = 13.sp) }
            }
        }
        Column(Modifier.padding(bottom = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            PrimaryButton(if (state.isBusy) "Un instant…" else "C’est parti", enabled = valid && accepted && !state.isBusy, onClick = start)
            Text("Modifiable à tout moment depuis votre profil.", style = MaterialTheme.typography.bodySmall, color = Palette.tertiary,
                modifier = Modifier.padding(top = 12.dp))
            TextButton({ signingIn = true }, Modifier.padding(top = 4.dp)) { Text("J’ai déjà un compte", fontWeight = FontWeight.SemiBold) }
        }
    }
    if (signingIn) SignInDialog(state) { signingIn = false }
}

/** Signs in to an existing account from the first launch, so a returning player (new phone, reinstall) finds their profile instead of creating a second one. */
@Composable
private fun SignInDialog(state: AppViewModel, close: () -> Unit) {
    var email by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val trimmed = email.trim()
    fun perform(work: suspend () -> Unit) {
        if (busy) return
        busy = true; message = null
        scope.launch {
            try { work() } catch (e: Exception) { message = CloudError.message(e) } finally { busy = false }
        }
    }
    AlertDialog(
        onDismissRequest = close,
        title = { Text("J’ai déjà un compte") },
        text = {
            Column {
                Text("Retrouvez votre pseudo, vos stats et votre série, comme sur votre ancien téléphone.", fontSize = 14.sp, color = Palette.secondary)
                OutlinedTextField(email, { email = it }, Modifier.fillMaxWidth().padding(top = 14.dp), label = { Text("Email") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, autoCorrectEnabled = false))
                OutlinedTextField(password, { password = it }, Modifier.fillMaxWidth().padding(top = 8.dp), label = { Text("Mot de passe") }, singleLine = true,
                    visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
                TextButton({ perform {
                    state.cloud.resetPassword(trimmed)
                    message = "Si cette adresse correspond à un compte, vous recevrez un lien pour choisir un nouveau mot de passe."
                } }, enabled = !busy && trimmed.isNotEmpty()) { Text("Mot de passe oublié ?") }
                message?.let { Text(it, fontSize = 13.sp, color = Palette.secondary) }
            }
        },
        confirmButton = {
            TextButton({ perform { state.signIn(trimmed, password); close() } }, enabled = !busy && trimmed.isNotEmpty() && password.isNotEmpty()) {
                Text(if (busy) "Un instant…" else "Se connecter")
            }
        },
        dismissButton = { TextButton(close) { Text("Fermer") } },
    )
}

/** Blocking sheet: the rules, and a single way on. */
@Composable
private fun RulesAcceptance(accept: () -> Unit) {
    val haptics = rememberHaptics()
    Dialog({}, DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false, usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize()) {
            AmbientBackground(dimmed = true)
            Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 20.dp)) {
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                    Text(CommunityRules.TITLE, style = MaterialTheme.typography.headlineLarge, modifier = Modifier.padding(top = 28.dp))
                    Text("Pour que CNSNN reste agréable pour tous, merci de lire et d’accepter ces règles.", color = Palette.secondary,
                        modifier = Modifier.padding(top = 8.dp, bottom = 18.dp))
                    CommunityRulesList()
                    Spacer(Modifier.height(16.dp))
                }
                PrimaryButton("J’accepte", Modifier.padding(vertical = 12.dp)) { haptics.success(); accept() }
            }
        }
    }
}

@Composable
fun AvatarPicker(selection: Int, select: (Int) -> Unit, modifier: Modifier = Modifier) {
    val haptics = rememberHaptics()
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Palette.avatars.indices.forEach { index ->
            Box(Modifier.size(44.dp).clickable(onClickLabel = "Couleur ${index + 1}") { haptics.selection(); select(index) }, contentAlignment = Alignment.Center) {
                Box(Modifier.size(32.dp).background(Palette.avatars[index], CircleShape)
                    .then(if (selection == index) Modifier.border(3.dp, Palette.foreground, CircleShape) else Modifier))
            }
        }
    }
}

@Composable
fun PrimaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Button(onClick, modifier.fillMaxWidth().height(56.dp), enabled = enabled, shape = RoundedCornerShape(28.dp)) {
        Text(text, fontWeight = FontWeight.Bold, fontSize = 17.sp)
    }
}

@Composable
fun TonalButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    androidx.compose.material3.FilledTonalButton(onClick, modifier.height(52.dp), enabled = enabled, shape = RoundedCornerShape(26.dp)) {
        Text(text, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
    }
}

