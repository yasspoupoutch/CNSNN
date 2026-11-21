package com.poupoutch.cnsnn

import android.content.Context
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.poupoutch.cnsnn.ads.AdMeasurement
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The ad measurement question: shown to a new player on the first screen, "Non merci" is remembered. */
@RunWith(AndroidJUnit4::class)
class AdMeasurementTest {
    @get:Rule val rule = createEmptyComposeRule()
    private val context: Context = ApplicationProvider.getApplicationContext()

    @After fun tearDown() { AdMeasurement.askInTests = false }

    @Test fun questionOnFirstScreenThenRemembered() {
        context.getSharedPreferences("cnsnn", Context.MODE_PRIVATE).edit().remove(AdMeasurement.KEY).commit()
        AdMeasurement.askInTests = true
        ActivityScenario.launch(MainActivity::class.java).use {
            rule.waitUntil(15_000) { rule.onAllNodes(hasText("Continuer")).fetchSemanticsNodes().isNotEmpty() || rule.onAllNodes(hasText("Bonjour,")).fetchSemanticsNodes().isNotEmpty() }
            // A player who already has a pseudo never sees it: only new players are asked.
            if (rule.onAllNodes(hasText("Continuer")).fetchSemanticsNodes().isEmpty()) return
            rule.onNodeWithText(AdMeasurement.TITLE).assertExists()
            rule.onNodeWithText("Non merci").performClick()
            rule.waitUntil(5_000) { rule.onAllNodes(hasText(AdMeasurement.TITLE)).fetchSemanticsNodes().isEmpty() }
            assertEquals(false, AdMeasurement.answer(context))
            assertEquals(false, AdMeasurement.shouldAsk(context))
        }
    }
}
