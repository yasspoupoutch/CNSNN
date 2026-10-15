package com.poupoutch.cnsnn

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.poupoutch.cnsnn.core.ChallengeInvite
import com.poupoutch.cnsnn.state.AppViewModel
import com.poupoutch.cnsnn.ui.CnsnnTheme
import com.poupoutch.cnsnn.ui.RootScreen

class MainActivity : ComponentActivity() {
    private val state: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        enableEdgeToEdge(SystemBarStyle.dark(Color.TRANSPARENT), SystemBarStyle.dark(Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        setContent { CnsnnTheme { RootScreen(state) } }
        if (savedInstanceState == null) openInvite(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openInvite(intent)
    }

    /** A challenge link: the challenge sheet joins it as soon as the player is connected. */
    private fun openInvite(intent: Intent?) {
        val link = intent?.takeIf { it.action == Intent.ACTION_VIEW }?.dataString ?: return
        ChallengeInvite.code(link)?.let { state.inviteCode = it }
    }

    override fun onResume() {
        super.onResume()
        // The day may have changed while away: refresh the widget and the next reminder.
        state.refreshGlance(force = true)
        // Progress saved while offline, or played on another device, is synced again.
        state.onForeground()
    }
}
