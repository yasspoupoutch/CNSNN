package com.poupoutch.cnsnn.ui

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import com.poupoutch.cnsnn.R

/**
 * The "match found" sound of a live duel (res/raw/duel_found.m4a, the same file as the iPhone's
 * App/Resources/duel-found.m4a): a rising pad, four quick notes and a "gling". Silent when the phone is
 * on vibrate or silent.
 */
object DuelSound {
    fun found(context: Context) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        runCatching {
            val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
            val player = MediaPlayer.create(context, R.raw.duel_found, attributes, audio.generateAudioSessionId()) ?: return
            player.setOnCompletionListener { it.release() }
            player.start()
        }
    }
}
