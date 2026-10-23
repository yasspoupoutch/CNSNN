package com.poupoutch.cnsnn

import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick

/** The first-launch tutorial comes up just after the home page: skip it when it does, so the test can go on. */
fun ComposeTestRule.skipTutorial() {
    runCatching { waitUntil(2_000) { onAllNodes(hasTestTag("tutorial.skip")).fetchSemanticsNodes().isNotEmpty() } }
    if (onAllNodes(hasTestTag("tutorial.skip")).fetchSemanticsNodes().isNotEmpty()) {
        onNodeWithTag("tutorial.skip").performClick()
        waitUntil(5_000) { onAllNodes(hasTestTag("tutorial")).fetchSemanticsNodes().isEmpty() }
    }
}
