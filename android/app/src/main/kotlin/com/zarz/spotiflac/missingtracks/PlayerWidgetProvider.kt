package com.zarz.spotiflac.missingtracks

import android.app.ActivityOptions
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/** Native launcher rendering; audio remains in the app's shared Flutter engine. */
class PlayerWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        update(context, ids)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, intArrayOf(id))
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        val editor = preferences(context).edit()
        ids.forEach { editor.remove("theme_$it").remove("artist_$it") }
        editor.apply()
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION) return
        val command = intent.getStringExtra(COMMAND) ?: return
        if (command !in setOf("toggle", "next", "previous")) return
        val pending = goAsync()
        if (!PlayerWidgetBridge.command(command) { pending.finish() }) {
            // A killed process has no audio engine. A widget click may launch
            // the activity to restore the queue and then execute this command.
            val options = if (Build.VERSION.SDK_INT >= 34) {
                ActivityOptions.makeBasic().apply {
                    // Preserve the launch privilege from this widget tap when
                    // the sender is a receiver rather than a visible activity.
                    setPendingIntentBackgroundActivityStartMode(
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
                    )
                }.toBundle()
            } else null
            try {
                launchIntent(context, command).send(context, 0, null, null, null, null, options)
            } catch (error: PendingIntent.CanceledException) {
                Log.w("PlayerWidget", "Widget launch was cancelled", error)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        const val ACTION = "com.zarz.spotiflac.missingtracks.PLAYER_WIDGET_ACTION"
        const val COMMAND = "player_widget_command"
        fun preferences(context: Context) = context.getSharedPreferences("player_widget", Context.MODE_PRIVATE)

        fun launchIntent(context: Context, command: String): PendingIntent = PendingIntent.getActivity(
            context, 8100 + command.hashCode(),
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(COMMAND, command)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        fun update(context: Context, ids: IntArray? = null) {
            val manager = AppWidgetManager.getInstance(context)
            val widgets = ids ?: manager.getAppWidgetIds(ComponentName(context, PlayerWidgetProvider::class.java))
            if (widgets.isEmpty()) return
            val prefs = preferences(context)
            val state = runCatching { JSONObject(prefs.getString("state", "{}")!!) }.getOrDefault(JSONObject())
            val active = state.optBoolean("canPlay")
            val cover = if (state.optString("artworkKey").isNotEmpty()) {
                BitmapFactory.decodeFile(File(context.filesDir, "player-widget-cover.png").path)
            } else null
            for (id in widgets) {
                val options = manager.getAppWidgetOptions(id)
                val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 280)
                val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 150)
                val horizontal = width >= 240 && height < 240
                val views = RemoteViews(context.packageName, if (horizontal) R.layout.widget_player_wide else R.layout.widget_player)
                val theme = prefs.getString("theme_$id", "artwork")
                val light = theme == "light"
                val foreground = if (light) Color.rgb(26, 24, 31) else Color.WHITE
                val background = when (theme) {
                    "light" -> Color.rgb(246, 243, 248)
                    "dark" -> Color.rgb(28, 27, 33)
                    else -> state.optLong("background", 0xff292433).toInt()
                }
                views.setImageViewBitmap(R.id.player_widget_background, renderBackground(background, width, height))
                views.setTextViewText(R.id.player_widget_title, state.optString("title").ifEmpty { context.getString(R.string.player_widget_name) })
                views.setTextViewText(R.id.player_widget_artist, if (active) state.optString("artist") else context.getString(R.string.player_widget_empty))
                views.setTextColor(R.id.player_widget_title, foreground)
                views.setTextColor(R.id.player_widget_artist, (foreground and 0x00ffffff) or (0xb8 shl 24))
                views.setViewVisibility(R.id.player_widget_artist, if (prefs.getBoolean("artist_$id", true)) View.VISIBLE else View.GONE)
                views.setImageViewBitmap(R.id.player_widget_art, cover?.let(::roundedCover) ?: icon(context, R.drawable.ic_widget_music, foreground, false))
                val playing = state.optBoolean("playing")
                val buttons = listOf(
                    Triple(R.id.player_widget_previous, R.drawable.ic_widget_previous, "previous"),
                    Triple(R.id.player_widget_play, if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play, "toggle"),
                    Triple(R.id.player_widget_next, R.drawable.ic_widget_next, "next"),
                )
                for ((view, drawable, command) in buttons) {
                    val enabled = active && when (command) {
                        "previous" -> state.optBoolean("canPrevious")
                        "next" -> state.optBoolean("canNext")
                        else -> true
                    }
                    views.setImageViewBitmap(view, icon(context, drawable, foreground, command == "toggle"))
                    views.setFloat(view, "setAlpha", if (enabled) 1f else 0.4f)
                    views.setBoolean(view, "setEnabled", enabled)
                    views.setOnClickPendingIntent(view, PendingIntent.getBroadcast(
                        context, 8200 + command.hashCode(),
                        Intent(context, PlayerWidgetProvider::class.java).setAction(ACTION).putExtra(COMMAND, command),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    ))
                }
                views.setContentDescription(R.id.player_widget_play, context.getString(if (playing) R.string.player_widget_pause else R.string.player_widget_play))
                views.setOnClickPendingIntent(R.id.player_widget_root, launchIntent(context, "open"))
                manager.updateAppWidget(id, views)
            }
            cover?.recycle()
        }

        private fun roundedCover(source: Bitmap): Bitmap {
            val scaled = Bitmap.createScaledBitmap(source, 256, 256, true)
            val result = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888)
            Canvas(result).drawRoundRect(0f, 0f, 256f, 256f, 20f, 20f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = BitmapShader(scaled, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            })
            if (scaled !== source) scaled.recycle()
            return result
        }

        private fun renderBackground(color: Int, width: Int, height: Int): Bitmap {
            val w = width.coerceIn(120, 640)
            val h = height.coerceIn(100, 640)
            val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val highlight = Color.rgb((Color.red(color) + 12).coerceAtMost(255), (Color.green(color) + 12).coerceAtMost(255), (Color.blue(color) + 12).coerceAtMost(255))
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = LinearGradient(0f, 0f, w.toFloat(), h.toFloat(), highlight, color, Shader.TileMode.CLAMP)
            }
            Canvas(bitmap).drawRoundRect(0f, 0f, w.toFloat(), h.toFloat(), 26f, 26f, paint)
            return bitmap
        }

        private fun icon(context: Context, resource: Int, color: Int, circle: Boolean): Bitmap {
            val bitmap = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            if (circle) canvas.drawCircle(48f, 48f, 46f, Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color })
            val drawable = context.getDrawable(resource)!!.mutate()
            drawable.setTint(if (circle && color == Color.WHITE) Color.rgb(35, 30, 42) else if (circle) Color.WHITE else color)
            drawable.setBounds(25, 25, 71, 71)
            drawable.draw(canvas)
            return bitmap
        }
    }
}

object PlayerWidgetBridge : FlutterEngine.EngineLifecycleListener {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready = false
    private var pendingCommand: String? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun attach(context: Context, flutterEngine: FlutterEngine) {
        if (engine !== flutterEngine) {
            engine?.removeEngineLifecycleListener(this)
            engine = flutterEngine
            flutterEngine.addEngineLifecycleListener(this)
            ready = false
        }
        val app = context.applicationContext
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.zarz.spotiflac.missingtracks/player_widget").also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        ready = true
                        result.success(null)
                        pendingCommand?.let { command(it) {} }
                        pendingCommand = null
                    }
                    "update" -> {
                        val data = call.arguments as? Map<*, *>
                        if (data == null) { result.error("bad_state", "Missing widget state", null); return@setMethodCallHandler }
                        worker.execute {
                            try {
                                val prefs = PlayerWidgetProvider.preferences(app)
                                val bytes = data["artwork"] as? ByteArray
                                val old = JSONObject(prefs.getString("state", "{}")!!)
                                if (bytes != null && old.optString("artworkKey") != data["artworkKey"]) {
                                    val temp = File(app.filesDir, "player-widget-cover.tmp")
                                    temp.writeBytes(bytes)
                                    check(temp.renameTo(File(app.filesDir, "player-widget-cover.png")))
                                }
                                val state = JSONObject()
                                data.forEach { (key, value) -> if (key is String && key != "artwork") state.put(key, value) }
                                prefs.edit().putString("state", state.toString()).commit()
                                PlayerWidgetProvider.update(app)
                                main.post { result.success(null) }
                            } catch (error: Exception) {
                                main.post { result.error("widget_update", error.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onPreEngineRestart() {
        ready = false
    }

    override fun onEngineWillDestroy() {
        ready = false
        channel = null
        pendingCommand = null
        engine = null
    }

    fun handleIntent(intent: Intent?) {
        val action = intent?.getStringExtra(PlayerWidgetProvider.COMMAND) ?: return
        intent.removeExtra(PlayerWidgetProvider.COMMAND)
        if (!command(action) {}) pendingCommand = action
    }

    fun command(action: String, completion: () -> Unit): Boolean {
        val bridge = channel ?: return false
        if (!ready) return false
        var finished = false
        fun finish() { if (!finished) { finished = true; completion() } }
        main.postDelayed({ finish() }, 8500)
        bridge.invokeMethod("command", action, object : MethodChannel.Result {
            override fun success(result: Any?) = finish()
            override fun error(code: String, message: String?, details: Any?) = finish()
            override fun notImplemented() = finish()
        })
        return true
    }
}
