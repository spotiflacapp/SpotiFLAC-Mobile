package com.zarz.spotiflac.missingtracks

import android.Manifest
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Bundle
import android.view.View
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Applies real RemoteViews through an Android widget host, including resizing. */
@RunWith(AndroidJUnit4::class)
class PlayerWidgetTest {
    @Test
    fun launcherRendersEverySizeAndAppearance() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val manager = AppWidgetManager.getInstance(context)
        val prefs = PlayerWidgetProvider.preferences(context)
        val previousState = prefs.getString("state", null)
        val title = "Widget rendering test"
        val state = JSONObject().apply {
            put("title", title)
            put("artist", "Test artist")
            put("canPlay", true)
            put("playing", true)
            put("canNext", true)
            put("canPrevious", false)
            put("background", 0xff6b3945L)
        }
        prefs.edit().putString("state", state.toString()).commit()
        instrumentation.uiAutomation.adoptShellPermissionIdentity(Manifest.permission.BIND_APPWIDGET)
        try {
            instrumentation.runOnMainSync {
                val host = AppWidgetHost(context, 595)
                val id = host.allocateAppWidgetId()
                try {
                    assertTrue(manager.bindAppWidgetIdIfAllowed(
                        id, ComponentName(context, PlayerWidgetProvider::class.java),
                    ))
                    val info = manager.getAppWidgetInfo(id)
                    assertNotNull(info)
                    for ((width, height) in listOf(140 to 156, 300 to 160, 320 to 350)) {
                        manager.updateAppWidgetOptions(id, Bundle().apply {
                            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, width)
                            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, width)
                            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, height)
                            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, height)
                        })
                        for (theme in listOf("artwork", "light", "dark")) {
                            prefs.edit().putString("theme_$id", theme).commit()
                            PlayerWidgetProvider.update(context, intArrayOf(id))
                            val view = host.createView(context, id, info)
                            val titleView = view.findViewById<TextView>(R.id.player_widget_title)
                            assertNotNull("RemoteViews failed at $width x $height, $theme", titleView)
                            assertEquals(title, titleView.text.toString())
                            assertTrue(view.findViewById<android.view.View>(R.id.player_widget_play).isEnabled)
                            assertTrue(!view.findViewById<android.view.View>(R.id.player_widget_previous).isEnabled)
                            val density = context.resources.displayMetrics.density
                            val pixelsWide = (width * density).toInt()
                            val pixelsHigh = (height * density).toInt()
                            view.measure(
                                View.MeasureSpec.makeMeasureSpec(pixelsWide, View.MeasureSpec.EXACTLY),
                                View.MeasureSpec.makeMeasureSpec(pixelsHigh, View.MeasureSpec.EXACTLY),
                            )
                            view.layout(0, 0, pixelsWide, pixelsHigh)
                            val bitmap = Bitmap.createBitmap(pixelsWide, pixelsHigh, Bitmap.Config.ARGB_8888)
                            view.draw(Canvas(bitmap))
                            File(context.cacheDir, "player-widget-$width-$height-$theme.png").outputStream().use {
                                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                            }
                            bitmap.recycle()
                        }
                    }
                } finally {
                    host.deleteHost()
                    prefs.edit().remove("theme_$id").remove("artist_$id").commit()
                }
            }
        } finally {
            instrumentation.uiAutomation.dropShellPermissionIdentity()
            prefs.edit().putString("state", previousState).commit()
            PlayerWidgetProvider.update(context)
        }
    }
}
