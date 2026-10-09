package com.example.pyclean_mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class PycleanWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val ACTION_REFRESH =
            "com.example.pyclean_mobile.action.PYCLEAN_WIDGET_REFRESH"

        // shared_preferences' legacy API stores values in this Android file
        // and prefixes normal Flutter keys with "flutter.".
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val KEY_SERVER_URL = "flutter.pyclean.server_url"
        private const val KEY_DEVICE_NAME = "flutter.pyclean.device_name"
        private const val KEY_LAST_PATH = "flutter.pyclean.last_path"

        private const val WIDGET_STATE_PREFS = "pyclean_widget_state"
        private const val KEY_WIDGET_STATUS = "status"

        private const val STATUS_UNKNOWN = "unknown"
        private const val STATUS_CHECKING = "checking"
        private const val STATUS_ONLINE = "online"
        private const val STATUS_OFFLINE = "offline"
        private const val STATUS_NOT_CONNECTED = "not_connected"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)

        appWidgetIds.forEach { widgetId ->
            updateWidget(context, appWidgetManager, widgetId)
        }

        // When the widget is first placed (or Android asks it to update),
        // immediately perform a real status check as well.
        requestRefresh(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REFRESH) {
            val pendingResult = goAsync()
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, PycleanWidgetProvider::class.java)
            val widgetIds = appWidgetManager.getAppWidgetIds(component)

            saveStatus(context, STATUS_CHECKING)
            widgetIds.forEach { widgetId ->
                updateWidget(context, appWidgetManager, widgetId)
            }

            Thread {
                try {
                    val connection = readConnection(context)

                    val status = if (connection.serverUrl.isBlank()) {
                        STATUS_NOT_CONNECTED
                    } else if (isServerOnline(connection.serverUrl)) {
                        STATUS_ONLINE
                    } else {
                        STATUS_OFFLINE
                    }

                    saveStatus(context, status)
                    widgetIds.forEach { widgetId ->
                        updateWidget(context, appWidgetManager, widgetId)
                    }
                } finally {
                    pendingResult.finish()
                }
            }.start()

            return
        }

        super.onReceive(context, intent)
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
    ) {
        val connection = readConnection(context)
        val status = if (connection.serverUrl.isBlank()) {
            STATUS_NOT_CONNECTED
        } else {
            readStatus(context)
        }

        val views = RemoteViews(context.packageName, R.layout.widget_layout)

        views.setTextViewText(
            R.id.tv_pc_name,
            connection.deviceName.ifBlank { "PyClean PC" },
        )

        views.setTextViewText(
            R.id.tv_server_url,
            connection.serverUrl.ifBlank { "Belum ada PC tersimpan" },
        )

        views.setTextViewText(
            R.id.tv_last_folder,
            connection.lastPath.ifBlank { "Belum ada folder terakhir" },
        )

        when (status) {
            STATUS_ONLINE -> {
                views.setTextViewText(R.id.tv_status, "● ONLINE")
                views.setTextColor(R.id.tv_status, Color.parseColor("#A6E3A1"))
            }

            STATUS_OFFLINE -> {
                views.setTextViewText(R.id.tv_status, "● OFFLINE")
                views.setTextColor(R.id.tv_status, Color.parseColor("#F38BA8"))
            }

            STATUS_CHECKING -> {
                views.setTextViewText(R.id.tv_status, "● CHECKING")
                views.setTextColor(R.id.tv_status, Color.parseColor("#89B4FA"))
            }

            STATUS_NOT_CONNECTED -> {
                views.setTextViewText(R.id.tv_status, "● NO PC")
                views.setTextColor(R.id.tv_status, Color.parseColor("#FAB387"))
            }

            else -> {
                views.setTextViewText(R.id.tv_status, "● REFRESH")
                views.setTextColor(R.id.tv_status, Color.parseColor("#F9E2AF"))
            }
        }

        views.setOnClickPendingIntent(R.id.btn_open, openAppPendingIntent(context))
        views.setOnClickPendingIntent(R.id.btn_refresh, refreshPendingIntent(context))

        appWidgetManager.updateAppWidget(widgetId, views)
    }

    private fun requestRefresh(context: Context) {
        context.sendBroadcast(
            Intent(context, PycleanWidgetProvider::class.java).apply {
                action = ACTION_REFRESH
            },
        )
    }

    private fun openAppPendingIntent(context: Context): PendingIntent {
        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            ?: Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

        return PendingIntent.getActivity(
            context,
            1001,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun refreshPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, PycleanWidgetProvider::class.java).apply {
            action = ACTION_REFRESH
        }

        return PendingIntent.getBroadcast(
            context,
            1002,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun readConnection(context: Context): WidgetConnection {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)

        return WidgetConnection(
            serverUrl = prefs.getString(KEY_SERVER_URL, "")?.trim().orEmpty(),
            deviceName = prefs.getString(KEY_DEVICE_NAME, "PyClean PC")?.trim().orEmpty(),
            lastPath = prefs.getString(KEY_LAST_PATH, "")?.trim().orEmpty(),
        )
    }

    private fun readStatus(context: Context): String {
        return context
            .getSharedPreferences(WIDGET_STATE_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_WIDGET_STATUS, STATUS_UNKNOWN)
            ?: STATUS_UNKNOWN
    }

    private fun saveStatus(context: Context, status: String) {
        context
            .getSharedPreferences(WIDGET_STATE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_WIDGET_STATUS, status)
            .apply()
    }

    private fun isServerOnline(serverUrl: String): Boolean {
        var connection: HttpURLConnection? = null

        return try {
            val normalizedUrl = serverUrl.trim().trimEnd('/')
            connection = URL("$normalizedUrl/api/status").openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = 2500
            connection.readTimeout = 2500
            connection.useCaches = false

            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                false
            } else {
                val body = connection.inputStream.bufferedReader().use { it.readText() }

                if (body.isBlank()) {
                    true
                } else {
                    val json = JSONObject(body)
                    json.optBoolean("running", false) ||
                        json.optString("status").equals("online", ignoreCase = true)
                }
            }
        } catch (_: Exception) {
            false
        } finally {
            connection?.disconnect()
        }
    }

    private data class WidgetConnection(
        val serverUrl: String,
        val deviceName: String,
        val lastPath: String,
    )
}
