package com.poupoutch.cnsnn

import android.graphics.Bitmap
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.poupoutch.cnsnn.core.ExtraCards
import com.poupoutch.cnsnn.core.PlayMode
import com.poupoutch.cnsnn.core.SprintGame
import com.poupoutch.cnsnn.core.WordEngine
import com.poupoutch.cnsnn.data.LocalStore
import com.poupoutch.cnsnn.state.GameViewModel
import com.poupoutch.cnsnn.state.ModeViewModel
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * The longest expressions (« Qu’est-ce qu’on a fait au Bon Dieu », or « La Communauté de l’anneau ») on a small phone
 * (Galaxy S9, set up by tools/small-screen.sh, after SmallScreenTest made the profile): the board on several lines,
 * the typed answer, the answer passed and the word revealed at the end, all whole, never cut. Pictures go to
 * files/shots. Runs only when asked (`-e smallScreen true`).
 */
@RunWith(AndroidJUnit4::class)
class LongWordsTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun has(text: String, substring: Boolean = false) = rule.onAllNodes(hasText(text, substring = substring)).fetchSemanticsNodes().isNotEmpty()
    private fun waitFor(text: String, timeout: Long = 15_000) = rule.waitUntil(timeout) { has(text) }

    /** Every text holding `part` is laid out whole: no letter cut on the right or at the bottom. */
    private fun assertWhole(where: String, part: String) {
        rule.waitForIdle()
        val nodes = rule.onAllNodes(hasText(part, substring = true)).fetchSemanticsNodes()
        assertTrue("$where : « $part » n’est pas à l’écran", nodes.isNotEmpty())
        nodes.forEach { node ->
            val layouts = mutableListOf<TextLayoutResult>()
            node.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action?.invoke(layouts)
            // hasVisualOverflow is not enough: a one-line text (softWrap = false) is laid out on the whole width it may
            // take, so it reports an overflow even when every letter is in. Each line must end inside the text instead.
            layouts.forEach { layout ->
                val widest = (0 until layout.lineCount).maxOf { layout.getLineRight(it) }
                assertFalse("$where : « $part » est coupé (${layout.lineCount} lignes, ${layout.size}, ligne la plus longue $widest)",
                    widest > layout.size.width + 1f || layout.didOverflowHeight || (0 until layout.lineCount).any { layout.isLineEllipsized(it) })
            }
        }
    }

    /** Lit vowels read « U, voyelle du mot » once the first hint is taken. */
    private fun type(word: String) = WordEngine.normalize(word).forEach { letter ->
        val key = if (rule.onAllNodes(hasContentDescription(letter.toString())).fetchSemanticsNodes().isNotEmpty()) letter.toString() else "$letter, voyelle du mot"
        rule.onNodeWithContentDescription(key).performClick()
    }

    @Test fun longExpressionsShowWhole() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("smallScreen") == "true")
        val bonDieu = ExtraCards.all.first { it.id == "seed-questcequonafaitaubondieu" }
        waitFor("Bonjour,", 30_000)
        if (has("Non merci")) rule.onNodeWithText("Non merci").performClick()

        // Classique with « Qu’est-ce qu’on a fait au Bon Dieu »: the board, the hints, two vowels placed, the answer, the end.
        GameViewModel.testCardId = bonDieu.id
        rule.onNodeWithText("Classique").performScrollTo().performClick()
        waitFor("Lancer une partie")
        rule.onNodeWithText("Lancer une partie").performClick()
        waitFor("votre réponse")
        WordEngine.lines(bonDieu.wordNoVowels).forEach { assertWhole("Classique, consonnes", it) }
        shot("20-classique-expression")
        rule.onNodeWithText("Indice").performClick(); rule.waitForIdle()
        if (has("Indice 2")) rule.onNodeWithText("Indice 2").performClick()
        rule.waitUntil(5_000) { has("« ", substring = true) }
        repeat(2) { if (has("Lettre", substring = true)) { rule.onNodeWithText("Lettre", substring = true).performClick(); rule.waitForIdle(); Thread.sleep(800) } }
        val placed = WordEngine.placedVowels(bonDieu.wordFull).steps[1]
        WordEngine.lines(placed).forEach { assertWhole("Classique, lettres placées", it) }
        shot("21-classique-expression-lettres")
        type(bonDieu.wordFull)
        assertWhole("Classique, réponse tapée", WordEngine.normalize(bonDieu.wordFull))
        shot("22-classique-expression-reponse")
        rule.onNodeWithText("Valider").performClick()
        Thread.sleep(3_500)
        shot("23-classique-expression-trouvee")
        GameViewModel.testCardId = null
        rule.onNodeWithContentDescription("Fermer").performClick()
        waitFor("Bonjour,")

        // Sprint dealing a long expression first, then « Passer »: « C’était : … » is whole too.
        val store = LocalStore(context)
        store.clearRun(PlayMode.SPRINT)
        val recent = store.recent(PlayMode.SPRINT)
        val seed = (1uL..20_000uL).first { (SprintGame(it, recent).card?.wordNoVowels?.length ?: 0) >= 16 }
        ModeViewModel.testSeed = seed
        val first = SprintGame(seed, recent).card!!
        rule.onNodeWithText("Sprint").performScrollTo().performClick()
        waitFor("90 secondes")
        WordEngine.lines(first.wordNoVowels).forEach { assertWhole("Sprint, consonnes", it) }
        shot("24-sprint-expression")
        rule.onNodeWithText("Passer · −5 s").performClick()
        rule.waitUntil(3_000) { has("C’était", substring = true) }
        shot("25-sprint-cetait")
        assertWhole("Sprint, réponse passée", "C’était")
        ModeViewModel.testSeed = null
        rule.onNodeWithContentDescription("Quitter").performClick()
        rule.onNodeWithText("Arrêter").performClick()
        waitFor("Accueil")
        rule.onNodeWithText("Accueil").performClick()
        waitFor("Bonjour,")
    }

    private fun shot(name: String) {
        rule.waitForIdle()
        Thread.sleep(700)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: return
        val dir = File(context.filesDir, "shots").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
