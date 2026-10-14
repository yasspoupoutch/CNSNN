package com.poupoutch.cnsnn.ui

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalView

/** Light taps like the system keyboard, and clear confirm/reject feedback. */
class Haptics(private val view: View) {
    fun key() = view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
    fun selection() = view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    fun success() = view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.CONTEXT_CLICK)
    fun retry() = view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS)
}

@Composable
fun rememberHaptics(): Haptics = Haptics(LocalView.current)
