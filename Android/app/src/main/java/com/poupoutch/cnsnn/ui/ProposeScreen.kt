package com.poupoutch.cnsnn.ui

import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.Category
import com.poupoutch.cnsnn.core.Difficulty
import com.poupoutch.cnsnn.core.ReviewStatus
import com.poupoutch.cnsnn.core.WordEngine
import com.poupoutch.cnsnn.state.AppViewModel
import kotlinx.coroutines.launch
import java.util.UUID

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProposeScreen(state: AppViewModel) {
    var word by rememberSaveable { mutableStateOf("") }
    var hint by rememberSaveable { mutableStateOf("") }
    var category by rememberSaveable { mutableStateOf(Category.entries.first()) }
    var difficulty by rememberSaveable { mutableStateOf(Difficulty.entries.first()) }
    var busy by rememberSaveable { mutableStateOf(false) }
    var sent by rememberSaveable { mutableStateOf(false) }
    val trimmedHint = hint.trim()
    val canSend = !busy && WordEngine.validWord(word) && trimmedHint.length in 5..160 && !state.isSuspended
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    val haptics = rememberHaptics()
    LaunchedEffect(Unit) { state.refreshSubmissions() }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().imePadding().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ScreenTitle("Proposer un mot", Modifier.padding(top = 8.dp))
        Text("Les mots validés par l’équipe rejoignent le jeu.", color = Palette.secondary)
        SectionCard(radius = 30.dp) {
            Kicker("Aperçu en jeu")
            val consonants = WordEngine.consonants(word)
            FlowRow(Modifier.fillMaxWidth().padding(vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                consonants.ifEmpty { "···" }.forEach { letter ->
                    Box(Modifier.size(40.dp, 50.dp).border(1.dp, Palette.border, RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
                        Text(letter.toString(), fontSize = 24.sp, fontWeight = FontWeight.Bold, color = if (consonants.isEmpty()) Palette.tertiary else Palette.foreground)
                    }
                }
            }
            Text(if (trimmedHint.isEmpty()) "Votre indice apparaîtra ici" else "« $trimmedHint »", style = Type.serifItalic(19), color = Palette.secondary,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }
        OutlinedTextField(word, { word = it.take(40); sent = false }, Modifier.fillMaxWidth(), label = { Text("Votre mot") }, singleLine = true,
            shape = RoundedCornerShape(18.dp), keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false))
        OutlinedTextField(hint, { hint = it.take(200); sent = false }, Modifier.fillMaxWidth(), label = { Text("Votre indice") }, maxLines = 4,
            shape = RoundedCornerShape(18.dp), keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            supportingText = { Text("${trimmedHint.length}/160", color = if (trimmedHint.isEmpty() || trimmedHint.length in 5..160) Palette.tertiary else Palette.red) })
        ChipRow(Category.entries, category, { it.label }) { category = it }
        ChipRow(Difficulty.entries, difficulty, { it.label }) { difficulty = it }
        PrimaryButton(if (busy) "Envoi…" else "Envoyer pour validation", enabled = canSend) {
            busy = true; sent = false; focus.clearFocus()
            scope.launch {
                val card = Card(UUID.randomUUID().toString(), word.trim(), trimmedHint, category, difficulty, ReviewStatus.PENDING)
                if (state.submit(card)) { haptics.success(); word = ""; hint = ""; sent = true }
                busy = false
            }
        }
        Text(when {
            state.isSuspended -> AppViewModel.SUSPENDED_TEXT
            sent -> "✓ Proposition envoyée. Vous verrez son statut ci-dessous."
            else -> "Y compte comme une voyelle. Chaque mot n’existe qu’une fois dans le jeu. Jusqu’à 10 propositions par jour, privées jusqu’à leur validation."
        }, fontSize = 12.sp, color = if (sent) Palette.mint else Palette.tertiary)
        Text("Mes propositions", fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 10.dp))
        val submissions = state.progress.submissions.reversed()
        SectionCard(padding = 0.dp, radius = 24.dp) {
            if (submissions.isEmpty()) Text("Vos propositions et leur statut apparaîtront ici.", fontSize = 14.sp, color = Palette.tertiary, modifier = Modifier.padding(16.dp))
            submissions.forEachIndexed { index, submission ->
                if (index > 0) Divider()
                Row(Modifier.padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(submission.card.wordFull.uppercase(), fontWeight = FontWeight.Bold, letterSpacing = 0.8.sp)
                        Text(submission.card.wordNoVowels + " · " + submission.card.hint, fontSize = 13.sp, color = Palette.tertiary, maxLines = 1)
                    }
                    val (label, color) = when (submission.card.status) {
                        ReviewStatus.PENDING -> "En attente" to Palette.secondary
                        ReviewStatus.APPROVED -> "Validé" to Palette.mint
                        ReviewStatus.REJECTED -> "Refusé" to Palette.red
                    }
                    Surface(shape = RoundedCornerShape(50), color = color.copy(alpha = 0.16f)) {
                        Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = color, modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp))
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun <T> ChipRow(items: List<T>, selected: T, label: (T) -> String, select: (T) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items.forEach { item ->
            FilterChip(item == selected, { select(item) }, { Text(label(item)) }, shape = RoundedCornerShape(50),
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = Palette.foreground, selectedLabelColor = Palette.ink))
        }
    }
}
