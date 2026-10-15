package com.poupoutch.cnsnn

import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.poupoutch.cnsnn.ui.DailyFoundTitle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import androidx.compose.foundation.layout.Box

/** The found daily word stays whole and "✓ trouvé" on one line, even on a narrow phone (Galaxy S9 width and less). */
@RunWith(AndroidJUnit4::class)
class DailyCardLayoutTest {
    @get:Rule val rule = createComposeRule()

    private fun layout(tag: String): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action?.invoke(results)
        return results.first()
    }

    /** The text drawn wider than the space it was given (on one line, so cut on the right). */
    private fun overflowsWidth(layout: TextLayoutResult) = layout.multiParagraph.width > layout.size.width + 0.5f

    private fun check(word: String, width: Int) {
        rule.setContent { Box(Modifier.width(width.dp)) { DailyFoundTitle(word, correct = true) } }
        val found = layout("dailyFound")
        assertEquals("✓ trouvé sur une ligne", 1, found.lineCount)
        assertFalse("✓ trouvé coupé", overflowsWidth(found))
        val shown = layout("dailyWord")
        assertFalse("$word coupé à ${width}dp", overflowsWidth(shown))
        assertFalse("$word tronqué à ${width}dp", shown.isLineEllipsized(0))
    }

    @Test fun gyrophareOnGalaxyS9() = check("GYROPHARE", 284)
    @Test fun longWordOnSmallPhone() = check("ANTICONSTITUTION", 250)
}
