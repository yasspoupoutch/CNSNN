package com.poupoutch.cnsnn.ads

import android.content.Context
import com.facebook.FacebookSdk
import com.poupoutch.cnsnn.BuildConfig
import com.poupoutch.cnsnn.R

/**
 * Ad measurement for Meta (Facebook, Instagram) ads, only if the player says yes.
 * The Meta SDK stays off by default (AutoInitEnabled, AutoLogAppEventsEnabled and
 * AdvertiserIDCollectionEnabled are false in the manifest): nothing is sent before the answer.
 * Only Meta's automatic events (install, opening) are sent, never the pseudo or the email.
 * Google Play counts installs from Google Ads by itself, so no Google SDK is needed here.
 */
object AdMeasurement {
    const val KEY = "adMeasurement"
    const val TITLE = "Aider CNSNN à se faire connaître ?"
    const val QUESTION = "CNSNN fait un peu de publicité. Pour savoir si elle amène de nouveaux joueurs, l’app peut prévenir Meta (Facebook, Instagram) quand elle est installée et ouverte, avec l’identifiant publicitaire du téléphone. Ni pseudo, ni email. Vous pourrez changer d’avis dans Profil."

    /** Instrumented tests only: show the question even though the app talks to the emulators. */
    @Volatile var askInTests = false

    private fun prefs(context: Context) = context.getSharedPreferences("cnsnn", Context.MODE_PRIVATE)

    /** null until the player answered. */
    fun answer(context: Context): Boolean? = prefs(context).let { if (it.contains(KEY)) it.getBoolean(KEY, false) else null }
    fun isOn(context: Context) = answer(context) == true
    fun shouldAsk(context: Context) = answer(context) == null && (BuildConfig.EMULATOR_HOST.isEmpty() || askInTests)

    private fun configured(context: Context) = context.getString(R.string.facebook_app_id).isNotBlank() && context.getString(R.string.facebook_client_token).isNotBlank()

    fun set(context: Context, on: Boolean) {
        prefs(context).edit().putBoolean(KEY, on).apply()
        apply(context)
    }

    /** At launch and after each answer: turns Meta's SDK on or off. */
    fun apply(context: Context) {
        if (BuildConfig.EMULATOR_HOST.isNotEmpty() || !configured(context)) return
        val on = isOn(context)
        runCatching {
            FacebookSdk.setAutoInitEnabled(on)
            if (on) FacebookSdk.fullyInitialize()
            FacebookSdk.setAutoLogAppEventsEnabled(on)
            FacebookSdk.setAdvertiserIDCollectionEnabled(on)
        }
    }
}
