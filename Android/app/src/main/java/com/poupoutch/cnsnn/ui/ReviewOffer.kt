package com.poupoutch.cnsnn.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import com.google.android.play.core.review.ReviewManagerFactory
import com.poupoutch.cnsnn.BuildConfig
import com.poupoutch.cnsnn.state.AppViewModel
import kotlinx.coroutines.delay

/**
 * When to show Google Play's rating prompt, like the iPhone: once a game is closed after a found
 * daily word, from the third found daily word on, at most once per app version. Google Play itself
 * decides whether the sheet really appears (quota, app installed from Play).
 */
object ReviewPrompt {
    const val MINIMUM_DAILY_WINS = 3

    fun isDue(dailyWins: Int, version: String, askedVersion: String?): Boolean =
        dailyWins >= MINIMUM_DAILY_WINS && askedVersion != version
}

/** Back on the home page after a found daily word: Google Play's in-app rating sheet, nothing if it fails. */
@Composable
fun ReviewOffer(state: AppViewModel) {
    val context = LocalContext.current
    LaunchedEffect(state.reviewPending) {
        if (!state.reviewPending) return@LaunchedEffect
        delay(800)
        // Cleared only after the pause: clearing the key first would cancel this effect at once.
        state.reviewPending = false
        state.local.reviewAskedVersion = BuildConfig.VERSION_NAME
        val activity = context.findActivity() ?: return@LaunchedEffect
        runCatching {
            val manager = ReviewManagerFactory.create(activity)
            manager.requestReviewFlow().addOnCompleteListener { request ->
                if (request.isSuccessful && !activity.isFinishing) manager.launchReviewFlow(activity, request.result)
            }
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
