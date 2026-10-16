package com.poupoutch.cnsnn.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.Gavel
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import com.poupoutch.cnsnn.BuildConfig
import com.poupoutch.cnsnn.core.CommunityRules
import com.poupoutch.cnsnn.core.Format
import com.poupoutch.cnsnn.core.Site
import com.poupoutch.cnsnn.data.CloudError
import com.poupoutch.cnsnn.reminders.Reminders
import com.poupoutch.cnsnn.state.AppViewModel
import kotlinx.coroutines.launch

const val SUPPORT_EMAIL = "jeucnsnn@gmail.com"

@Composable
fun ProfileScreen(state: AppViewModel) {
    var editingName by remember { mutableStateOf(false) }
    var account by rememberSaveable { mutableStateOf(false) }
    var addFriend by rememberSaveable { mutableStateOf(false) }
    var moderation by rememberSaveable { mutableStateOf(false) }
    var privacy by rememberSaveable { mutableStateOf(false) }
    var rules by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    LaunchedEffect(Unit) { state.refreshModeration() }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ScreenTitle("Profil", Modifier.padding(top = 8.dp))
        SectionCard(radius = 34.dp, padding = 22.dp) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Avatar(state.progress.username, state.avatar, 96.dp)
                Text(state.progress.username, style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(top = 16.dp))
                Text("Niveau ${state.progress.level} · ${Format.number(state.progress.correctAnswers)} mot${if (state.progress.correctAnswers > 1) "s" else ""} trouvé${if (state.progress.correctAnswers > 1) "s" else ""}", color = Palette.secondary, modifier = Modifier.padding(top = 4.dp))
                AvatarPicker(state.avatar, state::chooseAvatar, Modifier.padding(top = 14.dp))
                TonalButton("Modifier le pseudo", Modifier.fillMaxWidth().padding(top = 14.dp)) { editingName = true }
            }
        }
        SectionCard(padding = 0.dp, radius = 24.dp) {
            NavRow(if (state.isAnonymous) "Sauvegarder mon compte" else "Mon compte", Icons.Outlined.AccountCircle) { account = true }
            Divider()
            NavRow("Ajouter un ami", Icons.Outlined.PersonAdd) { addFriend = true }
            if (state.isAdmin) { Divider(); NavRow("Modération", Icons.Outlined.Shield) { moderation = true } }
        }
        if (state.isSuspended) SectionCard(radius = 24.dp) { Text(AppViewModel.SUSPENDED_TEXT, color = Palette.red, fontSize = 14.sp) }
        ReminderSettings(state)
        SectionCard(padding = 0.dp, radius = 24.dp) {
            NavRow("Contacter le support", Icons.Outlined.Email) {
                context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$SUPPORT_EMAIL?subject=CNSNN")))
            }
            Divider()
            NavRow(CommunityRules.TITLE, Icons.Outlined.Gavel) { rules = true }
            Divider()
            NavRow("Confidentialité", Icons.Outlined.PrivacyTip) { privacy = true }
        }
        Text(when {
            state.uid == null -> "Hors connexion : votre progression reste sur ce téléphone."
            state.isAnonymous -> "Compte invité sauvegardé en ligne. Créez un compte pour le retrouver sur un autre appareil."
            else -> "Compte permanent : votre progression vous suit sur tous vos appareils, iPhone compris."
        }, style = MaterialTheme.typography.bodySmall, color = Palette.tertiary)
        Column(Modifier.fillMaxWidth().padding(top = 18.dp, bottom = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(highlighted("CONSONNE"), style = Type.wordmark(20))
            Text("Une application créée par Poupoutch", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Palette.secondary, modifier = Modifier.padding(top = 6.dp))
            Text("Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", fontSize = 12.sp, color = Palette.tertiary)
        }
    }

    if (editingName) RenameDialog(state.progress.username, { editingName = false }) { state.rename(it); editingName = false }
    if (account) FullScreen("Votre compte", { account = false }) { AccountContent(state) { account = false } }
    if (addFriend) FullScreen("Ajouter un ami", { addFriend = false }) { AddFriendContent(state) }
    if (moderation) FullScreen("Modération", { moderation = false }) { ModerationContent(state) }
    if (privacy) FullScreen("Confidentialité", { privacy = false }) { PrivacyContent() }
    if (rules) FullScreen(CommunityRules.TITLE, { rules = false }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            CommunityRulesList()
            Spacer(Modifier.height(24.dp))
        }
    }
}

/** Profil > Ajouter un ami: the player's code to share and the field for a friend's, as in Stats > Amis. */
@Composable
private fun AddFriendContent(state: AppViewModel) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Donnez votre code à un ami ou entrez le sien : vous apparaissez aussitôt dans les amis l’un de l’autre, pour comparer vos temps et vous défier.",
            fontSize = 14.sp, color = Palette.secondary, modifier = Modifier.padding(top = 4.dp))
        if (state.uid == null) SectionCard(radius = 22.dp) { Text("Connectez-vous à Internet pour ajouter vos amis.", color = Palette.secondary) }
        else FriendCodeCards(state)
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun NavRow(title: String, icon: ImageVector, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).heightIn(min = 58.dp).padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Palette.secondary)
        Text(title, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f).padding(start = 14.dp))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Palette.tertiary)
    }
}

@Composable
private fun RenameDialog(current: String, dismiss: () -> Unit, save: (String) -> Unit) {
    var name by remember { mutableStateOf(current) }
    AlertDialog(dismiss, title = { Text("Modifier le pseudo") },
        text = { OutlinedTextField(name, { name = it.take(20) }, singleLine = true, supportingText = { Text("Entre 2 et 20 caractères.") }) },
        confirmButton = { TextButton({ save(name) }, enabled = name.trim().length in 2..20) { Text("Enregistrer") } },
        dismissButton = { TextButton(dismiss) { Text("Annuler") } })
}

@Composable
fun FullScreen(title: String, close: () -> Unit, content: @Composable () -> Unit) {
    Dialog(close, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize()) {
            AmbientBackground(dimmed = true)
            Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(close) { Icon(Icons.Filled.Close, "Fermer") }
                    Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(start = 4.dp))
                }
                content()
            }
        }
    }
}

/** Daily Mot du jour reminder: a notification set on this phone, nothing sent by a server. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReminderSettings(state: AppViewModel) {
    val context = LocalContext.current
    var enabled by remember { mutableStateOf(state.local.remindersEnabled) }
    var minutes by remember { mutableStateOf(state.local.reminderMinutes) }
    var refused by remember { mutableStateOf(false) }
    var picking by remember { mutableStateOf(false) }
    fun apply(on: Boolean) { enabled = on; state.local.remindersEnabled = on; state.refreshGlance(force = true) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> refused = !granted; apply(granted) }
    SectionCard(padding = 0.dp, radius = 24.dp) {
        Row(Modifier.fillMaxWidth().heightIn(min = 58.dp).padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.NotificationsActive, null, tint = Palette.secondary)
            Text("Rappel du mot du jour", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f).padding(start = 14.dp))
            Switch(enabled, { on ->
                if (on && Build.VERSION.SDK_INT >= 33 &&
                    ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                } else { refused = false; apply(on) }
            }, colors = SwitchDefaults.colors(checkedTrackColor = Palette.mint, checkedThumbColor = Palette.ink))
        }
        if (enabled) {
            Divider()
            Row(Modifier.fillMaxWidth().clickable { picking = true }.heightIn(min = 52.dp).padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Heure", color = Palette.secondary, modifier = Modifier.weight(1f))
                Text("%d:%02d".format(minutes / 60, minutes % 60), fontWeight = FontWeight.SemiBold)
            }
        }
        if (refused) Text("Les notifications sont désactivées pour CNSNN. Autorisez-les dans Paramètres > Applications > CNSNN.",
            fontSize = 12.sp, color = Palette.tertiary, modifier = Modifier.padding(start = 18.dp, end = 18.dp, bottom = 14.dp))
    }
    if (picking) {
        val picker = rememberTimePickerState(minutes / 60, minutes % 60, is24Hour = true)
        AlertDialog({ picking = false }, title = { Text("Heure du rappel") }, text = { TimePicker(picker) },
            confirmButton = { TextButton({
                minutes = picker.hour * 60 + picker.minute; state.local.reminderMinutes = minutes; picking = false; state.refreshGlance(force = true)
            }) { Text("OK") } },
            dismissButton = { TextButton({ picking = false }) { Text("Annuler") } })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AccountContent(state: AppViewModel, close: () -> Unit) {
    var email by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var login by rememberSaveable { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var deletePassword by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val trimmed = email.trim()
    fun perform(work: suspend () -> Unit) {
        if (busy) return
        busy = true; message = null
        scope.launch { try { work() } catch (e: Exception) { message = CloudError.message(e) } finally { busy = false } }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        when {
            state.uid == null -> SectionCard { Text("Le serveur est injoignable pour le moment. Réessayez une fois connecté à Internet.") }
            state.isAnonymous -> SectionCard {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    SegmentedButton(!login, { login = false }, SegmentedButtonDefaults.itemShape(0, 2)) { Text("Créer un compte") }
                    SegmentedButton(login, { login = true }, SegmentedButtonDefaults.itemShape(1, 2)) { Text("J’ai déjà un compte") }
                }
                OutlinedTextField(email, { email = it }, Modifier.fillMaxWidth().padding(top = 14.dp), label = { Text("Email") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, autoCorrectEnabled = false))
                OutlinedTextField(password, { password = it }, Modifier.fillMaxWidth().padding(top = 8.dp), singleLine = true,
                    label = { Text(if (login) "Mot de passe" else "Mot de passe (8 caractères minimum)") },
                    visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
                PrimaryButton(if (login) "Se connecter" else "Créer mon compte", Modifier.padding(top = 14.dp),
                    enabled = !busy && trimmed.isNotEmpty() && (if (login) password.isNotEmpty() else password.length >= 8)) {
                    perform {
                        try {
                            if (login) state.signIn(trimmed, password) else state.createAccount(trimmed, password)
                            close()
                        } catch (e: Exception) {
                            // The address already has an account: offer to sign in to it instead.
                            if (CloudError.code(e) == CloudError.Code.EMAIL_IN_USE) login = true
                            throw e
                        }
                    }
                }
                if (login) TextButton({ perform {
                    state.cloud.resetPassword(trimmed)
                    message = "Si cette adresse correspond à un compte, vous recevrez un lien pour choisir un nouveau mot de passe."
                } }, enabled = !busy && trimmed.isNotEmpty()) { Text("Mot de passe oublié ?") }
                Text(if (login) "Vos parties d’entraînement de ce téléphone rejoignent ce compte. Les Mots du jour joués en invité restent sur le profil invité."
                     else "Votre compte invité devient permanent : même profil, mêmes stats, mêmes propositions. Vous pourrez le retrouver sur un autre appareil (Android ou iPhone) ou après une réinstallation.",
                    fontSize = 12.sp, color = Palette.tertiary, modifier = Modifier.padding(top = 8.dp))
            }
            else -> SectionCard {
                Text(state.email ?: "Compte permanent", fontWeight = FontWeight.SemiBold)
                Text("Votre progression est sauvegardée en ligne et suit votre compte sur tous vos appareils.", fontSize = 13.sp, color = Palette.secondary, modifier = Modifier.padding(top = 4.dp))
                TonalButton("Se déconnecter", Modifier.fillMaxWidth().padding(top = 14.dp)) { state.signOut(); close() }
            }
        }
        message?.let { SectionCard { Text(it) } }
        if (state.uid != null) {
            TextButton({ confirmDelete = true }, enabled = !busy) { Text(if (state.isAnonymous) "Supprimer mes données" else "Supprimer mon compte", color = Palette.red) }
            Text("Supprime votre profil, vos résultats, votre place au classement, vos amis, vos signalements et vos propositions non publiées. Les cartes déjà publiées restent dans le jeu, sans votre nom. Cette action est définitive.",
                fontSize = 12.sp, color = Palette.tertiary)
        }
        if (busy) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        Spacer(Modifier.height(24.dp))
    }
    if (confirmDelete) AlertDialog({ confirmDelete = false; deletePassword = "" },
        title = { Text(if (state.isAnonymous) "Supprimer vos données ?" else "Supprimer votre compte ?") },
        text = {
            Column {
                Text(if (state.isAnonymous) "Toutes vos parties et propositions seront effacées." else "Saisissez votre mot de passe pour confirmer. Toutes vos données seront effacées.")
                if (!state.isAnonymous) OutlinedTextField(deletePassword, { deletePassword = it }, Modifier.padding(top = 10.dp), singleLine = true,
                    label = { Text("Mot de passe") }, visualTransformation = PasswordVisualTransformation())
            }
        },
        confirmButton = { TextButton({
            val pass = if (state.isAnonymous) null else deletePassword
            confirmDelete = false; deletePassword = ""
            perform { state.deleteAccount(pass); close() }
        }) { Text("Supprimer", color = Palette.red) } },
        dismissButton = { TextButton({ confirmDelete = false; deletePassword = "" }) { Text("Annuler") } })
}

@Composable
private fun PrivacyContent() {
    val sections = listOf(
        "Ce que nous enregistrons" to "Votre pseudo, vos parties (mots du jour, temps, séries), vos propositions de cartes, vos signalements et vos amis ajoutés par code. Si vous créez un compte, votre adresse email sert uniquement à vous connecter.",
        "Ce qui est public" to "Votre pseudo et vos résultats officiels apparaissent dans les classements. Les cartes que vous proposez ne montrent pas votre nom aux autres joueurs. Votre email n’est jamais affiché.",
        "Où sont les données" to "Sur les serveurs Firebase de Google (Authentication, Cloud Firestore et Crashlytics), et sur votre téléphone. Aucune publicité, aucun traceur, aucune revente de données.",
        "Rapports de plantage" to "Si l’application plante, un rapport technique (modèle et version du téléphone, version de l’app, détail de l’erreur) est envoyé à Firebase Crashlytics pour corriger le problème. Il ne contient ni votre pseudo ni votre email et ne sert jamais à la publicité ni au suivi.",
        "Notifications et widget" to "Le rappel du mot du jour et le widget sont calculés sur votre téléphone : rien n’est envoyé par un serveur.",
        "Supprimer vos données" to "Profil > Mon compte > Supprimer mon compte efface votre profil, vos résultats, votre place au classement, vos amis, vos signalements et vos propositions non publiées. Les cartes déjà publiées restent dans le jeu, sans votre nom.",
        "Nous contacter" to "Pour toute question ou demande sur vos données : $SUPPORT_EMAIL.",
    )
    val links = LocalUriHandler.current
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        sections.forEach { (title, body) ->
            SectionCard(radius = 22.dp, padding = 18.dp) {
                Text(title, fontWeight = FontWeight.SemiBold)
                Text(body, fontSize = 14.sp, color = Palette.secondary, modifier = Modifier.padding(top = 6.dp))
            }
        }
        TonalButton("Lire la politique complète", Modifier.fillMaxWidth()) { runCatching { links.openUri(Site.PRIVACY) } }
        Spacer(Modifier.height(24.dp))
    }
}

/** The community rules, numbered, as in the onboarding, the acceptance sheet and the site. */
@Composable
fun CommunityRulesList(modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        CommunityRules.items.forEachIndexed { index, rule ->
            SectionCard(radius = 22.dp, padding = 16.dp) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("${index + 1}", fontWeight = FontWeight.Black, color = Palette.accent, fontSize = 17.sp)
                    Text(rule, fontSize = 14.sp, color = Palette.secondary)
                }
            }
        }
    }
}

