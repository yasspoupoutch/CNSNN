package com.poupoutch.cnsnn

import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
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
    }

    override fun onResume() {
        super.onResume()
        // The day may have changed while away: refresh the widget and the next reminder.
        state.refreshGlance(force = true)
    }
}
