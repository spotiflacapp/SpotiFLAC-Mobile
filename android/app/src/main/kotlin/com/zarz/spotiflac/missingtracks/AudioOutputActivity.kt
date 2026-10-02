package com.zarz.spotiflac.missingtracks

import android.app.Activity
import android.content.Intent
import android.media.MediaRouter2
import android.os.Build
import android.provider.Settings

/** A notification launches this activity directly, so output selection has a
 * visible foreground context even while the Flutter player is in the background.
 */
class AudioOutputActivity : Activity() {
    private var opened = false
    private var pickerTookFocus = false

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) {
            if (opened) pickerTookFocus = true
            return
        }
        if (opened) {
            if (pickerTookFocus) finish()
            return
        }
        opened = true
        try {
            if (Build.VERSION.SDK_INT >= 34 &&
                MediaRouter2.getInstance(this).showSystemOutputSwitcher()) {
                return
            }
            // Public output-switcher API is unavailable on older Android.
            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
        } catch (_: Exception) {
            // Do not leave a transparent activity over the notification shade.
        }
        finish()
    }
}
