package com.zarz.spotiflac.missingtracks

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.TextView

class PlayerWidgetConfigurationActivity : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        setResult(RESULT_CANCELED)
        val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) { finish(); return }
        val prefs = PlayerWidgetProvider.preferences(this)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val padding = (24 * resources.displayMetrics.density).toInt()
            setPadding(padding, padding, padding, padding)
        }
        layout.addView(TextView(this).apply { setText(R.string.player_widget_name); textSize = 24f })
        val group = RadioGroup(this)
        val themes = listOf("artwork" to R.string.player_widget_artwork, "light" to R.string.player_widget_light, "dark" to R.string.player_widget_dark)
        themes.forEachIndexed { index, (key, label) ->
            group.addView(RadioButton(this).apply {
                this.id = index + 1
                setText(label)
                isChecked = prefs.getString("theme_$widgetId", "artwork") == key
            })
        }
        layout.addView(group)
        val artist = CheckBox(this).apply {
            setText(R.string.player_widget_show_artist)
            isChecked = prefs.getBoolean("artist_$widgetId", true)
        }
        layout.addView(artist)
        layout.addView(Button(this).apply {
            setText(R.string.player_widget_save)
            setOnClickListener {
                prefs.edit().putString("theme_$widgetId", themes[(group.checkedRadioButtonId - 1).coerceIn(0, 2)].first)
                    .putBoolean("artist_$widgetId", artist.isChecked).apply()
                PlayerWidgetProvider.update(this@PlayerWidgetConfigurationActivity, intArrayOf(widgetId))
                setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
                finish()
            }
        })
        setContentView(layout)
    }
}
