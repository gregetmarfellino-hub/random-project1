package com.example.pyclean_mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.widget.RemoteViews
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class PycleanWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val ACTION_REFRESH =
            "com.example.pyclean_mobile.action.PYCLEAN_WIDGET_REFRESH"

        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val KEY_SERVER_URL = "flutter.pyclean.server_url"
        private const val KEY_DEVICE_NAME = "flutter.pyclean.device_name"
        private const val KEY_LAST_PATH = "flutter.pyclean.last_path"

        private const val WIDGET_STATE_PREFS = "pyclean_widget_state"

        private const val KEY_PC_STATUS = "pc_status"

        private const val KEY_ESP_STATUS = "esp_status"
        private const val KEY_ESP_NAME = "esp_name"
        private const val KEY_ESP_TYPE = "esp_type"
        private const val KEY_ESP_IP = "esp_ip"
        private const val KEY_ESP_RSSI = "esp_rssi"
        private const val KEY_ESP_UPTIME_MS = "esp_uptime_ms"
        private const val KEY_ESP_FREE_HEAP = "esp_free_heap"
        private const val KEY_ESP_SERVICE_NAME = "esp_service_name"

        private const val SERVICE_TYPE = "_pyclean._tcp."
        private const val DISCOVERY_TIMEOUT_MS = 6000L

        private const val STATUS_UNKNOWN = "unknown"
        private const val STATUS_CHECKING = "checking"
        private const val STATUS_ONLINE = "online"
        private const val STATUS_OFFLINE = "offline"
        private const val STATUS_NOT_CONNECTED = "not_connected"
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)

        appWidgetIds.forEach { widgetId ->
            updateWidget(context, appWidgetManager, widgetId)
        }

        requestRefresh(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REFRESH) {
            val pendingResult = goAsync()
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, PycleanWidgetProvider::class.java)
            val widgetIds = appWidgetManager.getAppWidgetIds(component)

            savePcStatus(context, STATUS_CHECKING)
            saveEspStatus(context, STATUS_CHECKING)
            updateAllWidgets(context, appWidgetManager, widgetIds)

            // PC status and ESP32 discovery run independently.
            val remainingTasks = AtomicInteger(2)

            fun finishTask() {
                if (remainingTasks.decrementAndGet() == 0) {
                    pendingResult.finish()
                }
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

                    savePcStatus(context, status)
                    updateAllWidgets(context, appWidgetManager, widgetIds)
                } finally {
                    finishTask()
                }
            }.start()

            // NSD callbacks are safest when discovery is started from the main looper.
            mainHandler.post {
                refreshEsp32(
                    context = context,
                    appWidgetManager = appWidgetManager,
                    widgetIds = widgetIds,
                    onFinished = { finishTask() },
                )
            }

            return
        }

        super.onReceive(context, intent)
    }

    private fun refreshEsp32(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetIds: IntArray,
        onFinished: () -> Unit,
    ) {
        val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        val finished = AtomicBoolean(false)
        val resolving = AtomicBoolean(false)

        lateinit var discoveryListener: NsdManager.DiscoveryListener

        fun stopDiscovery() {
            try {
                nsdManager.stopServiceDiscovery(discoveryListener)
            } catch (_: Exception) {
                // It may already be stopped.
            }
        }

        fun complete(status: String, data: EspWidgetState? = null) {
            if (!finished.compareAndSet(false, true)) return

            mainHandler.removeCallbacksAndMessages(discoveryListener)
            stopDiscovery()

            if (data != null) {
                saveEspState(context, status, data)
            } else {
                saveEspStatus(context, status)
            }

            updateAllWidgets(context, appWidgetManager, widgetIds)
            onFinished()
        }

        val timeout = Runnable {
            complete(STATUS_OFFLINE)
        }

        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {
                mainHandler.removeCallbacks(timeout)
                mainHandler.postDelayed(timeout, DISCOVERY_TIMEOUT_MS)
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (finished.get()) return
                if (!serviceInfo.serviceType.contains("_pyclean._tcp")) return
                if (!resolving.compareAndSet(false, true)) return

                @Suppress("DEPRECATION")
                nsdManager.resolveService(
                    serviceInfo,
                    object : NsdManager.ResolveListener {
                        override fun onResolveFailed(
                            failedService: NsdServiceInfo,
                            errorCode: Int,
                        ) {
                            resolving.set(false)
                        }

                        override fun onServiceResolved(resolved: NsdServiceInfo) {
                            val host = resolvedHostAddress(resolved)
                            val port = resolved.port

                            if (host.isNullOrBlank() || port <= 0) {
                                resolving.set(false)
                                return
                            }

                            // We have the current address now; stop listening while
                            // /status is verified.
                            stopDiscovery()
                            mainHandler.removeCallbacks(timeout)

                            Thread {
                                val espState = fetchEspStatus(
                                    host = host,
                                    port = port,
                                    serviceName = resolved.serviceName,
                                )

                                mainHandler.post {
                                    if (espState != null) {
                                        complete(STATUS_ONLINE, espState)
                                    } else {
                                        complete(STATUS_OFFLINE)
                                    }
                                }
                            }.start()
                        }
                    },
                )
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit

            override fun onDiscoveryStopped(serviceType: String) = Unit

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                complete(STATUS_OFFLINE)
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
        }

        try {
            nsdManager.discoverServices(
                SERVICE_TYPE,
                NsdManager.PROTOCOL_DNS_SD,
                discoveryListener,
            )
        } catch (_: Exception) {
            complete(STATUS_OFFLINE)
        }
    }

    private fun fetchEspStatus(
        host: String,
        port: Int,
        serviceName: String,
    ): EspWidgetState? {
        var connection: HttpURLConnection? = null

        return try {
            connection = URL("http://$host:$port/status").openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = 2200
            connection.readTimeout = 2200
            connection.useCaches = false

            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                null
            } else {
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                val json = JSONObject(body)

                val type = json.optString("type", "")
                val isEsp = type.contains("esp32", ignoreCase = true) ||
                    json.optString("device_name", "").contains("ESP32", ignoreCase = true)

                if (!isEsp || !json.optBoolean("online", true)) {
                    null
                } else {
                    EspWidgetState(
                        name = json.optString("device_name", "PyClean ESP32"),
                        type = type.ifBlank { "esp32" },
                        ip = json.optString("ip", host).ifBlank { host },
                        rssi = json.optInt("rssi", 0),
                        uptimeMs = json.optLong("uptime_ms", 0L),
                        freeHeap = json.optLong("free_heap", 0L),
                        serviceName = serviceName,
                    )
                }
            }
        } catch (_: Exception) {
            null
        } finally {
            connection?.disconnect()
        }
    }

    private fun updateAllWidgets(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetIds: IntArray,
    ) {
        widgetIds.forEach { widgetId ->
            updateWidget(context, appWidgetManager, widgetId)
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
    ) {
        val pc = readConnection(context)
        val pcStatus = if (pc.serverUrl.isBlank()) {
            STATUS_NOT_CONNECTED
        } else {
            readPcStatus(context)
        }

        val esp = readEspState(context)

        val views = RemoteViews(context.packageName, R.layout.widget_layout)

        views.setTextViewText(
            R.id.tv_pc_name,
            if (pc.deviceName.isBlank()) "PC • PyClean PC" else "PC • ${pc.deviceName}",
        )

        views.setTextViewText(
            R.id.tv_pc_detail,
            when {
                pc.lastPath.isNotBlank() -> pc.lastPath
                pc.serverUrl.isNotBlank() -> pc.serverUrl
                else -> "No PC saved"
            },
        )

        applyStatus(
            views = views,
            viewId = R.id.tv_pc_status,
            status = pcStatus,
            noDeviceText = "● NO PC",
        )

        views.setTextViewText(
            R.id.tv_esp_name,
            "ESP32 • ${esp.name.ifBlank { "PyClean ESP32" }}",
        )

        views.setTextViewText(
            R.id.tv_esp_detail,
            when (esp.status) {
                STATUS_ONLINE -> buildEspDetail(esp)
                STATUS_CHECKING -> "Searching local network..."
                STATUS_OFFLINE -> if (esp.ip.isNotBlank()) {
                    "Last: ${esp.ip} • tap REFRESH"
                } else {
                    "Not found • tap REFRESH"
                }
                else -> "Tap REFRESH to find ESP32"
            },
        )

        applyStatus(
            views = views,
            viewId = R.id.tv_esp_status,
            status = esp.status,
            noDeviceText = "● OFFLINE",
        )

        views.setOnClickPendingIntent(R.id.btn_open, openAppPendingIntent(context))
        views.setOnClickPendingIntent(R.id.btn_refresh, refreshPendingIntent(context))

        appWidgetManager.updateAppWidget(widgetId, views)
    }

    private fun applyStatus(
        views: RemoteViews,
        viewId: Int,
        status: String,
        noDeviceText: String,
    ) {
        when (status) {
            STATUS_ONLINE -> {
                views.setTextViewText(viewId, "● ONLINE")
                views.setTextColor(viewId, Color.parseColor("#A6E3A1"))
            }

            STATUS_OFFLINE -> {
                views.setTextViewText(viewId, "● OFFLINE")
                views.setTextColor(viewId, Color.parseColor("#F38BA8"))
            }

            STATUS_CHECKING -> {
                views.setTextViewText(viewId, "● CHECKING")
                views.setTextColor(viewId, Color.parseColor("#89B4FA"))
            }

            STATUS_NOT_CONNECTED -> {
                views.setTextViewText(viewId, noDeviceText)
                views.setTextColor(viewId, Color.parseColor("#FAB387"))
            }

            else -> {
                views.setTextViewText(viewId, "● REFRESH")
                views.setTextColor(viewId, Color.parseColor("#F9E2AF"))
            }
        }
    }

    private fun buildEspDetail(esp: EspWidgetState): String {
        val signal = if (esp.rssi == 0) "RSSI ?" else "${esp.rssi} dBm"
        val uptime = formatUptime(esp.uptimeMs)
        val heap = if (esp.freeHeap <= 0L) {
            ""
        } else {
            " • ${String.format("%.0f KB", esp.freeHeap / 1024.0)}"
        }

        return "$signal • $uptime$heap"
    }

    private fun formatUptime(uptimeMs: Long): String {
        if (uptimeMs <= 0L) return "uptime ?"

        val totalSeconds = uptimeMs / 1000L
        val days = totalSeconds / 86400L
        val hours = (totalSeconds % 86400L) / 3600L
        val minutes = (totalSeconds % 3600L) / 60L
        val seconds = totalSeconds % 60L

        return when {
            days > 0 -> "${days}d ${hours}h"
            hours > 0 -> "${hours}h ${minutes}m"
            minutes > 0 -> "${minutes}m ${seconds}s"
            else -> "${seconds}s"
        }
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

    private fun readPcStatus(context: Context): String {
        return statePrefs(context)
            .getString(KEY_PC_STATUS, STATUS_UNKNOWN)
            ?: STATUS_UNKNOWN
    }

    private fun savePcStatus(context: Context, status: String) {
        statePrefs(context)
            .edit()
            .putString(KEY_PC_STATUS, status)
            .apply()
    }

    private fun readEspState(context: Context): EspWidgetState {
        val prefs = statePrefs(context)

        return EspWidgetState(
            status = prefs.getString(KEY_ESP_STATUS, STATUS_UNKNOWN) ?: STATUS_UNKNOWN,
            name = prefs.getString(KEY_ESP_NAME, "PyClean ESP32") ?: "PyClean ESP32",
            type = prefs.getString(KEY_ESP_TYPE, "esp32-s3") ?: "esp32-s3",
            ip = prefs.getString(KEY_ESP_IP, "") ?: "",
            rssi = prefs.getInt(KEY_ESP_RSSI, 0),
            uptimeMs = prefs.getLong(KEY_ESP_UPTIME_MS, 0L),
            freeHeap = prefs.getLong(KEY_ESP_FREE_HEAP, 0L),
            serviceName = prefs.getString(KEY_ESP_SERVICE_NAME, "") ?: "",
        )
    }

    private fun saveEspStatus(context: Context, status: String) {
        statePrefs(context)
            .edit()
            .putString(KEY_ESP_STATUS, status)
            .apply()
    }

    private fun saveEspState(
        context: Context,
        status: String,
        data: EspWidgetState,
    ) {
        statePrefs(context)
            .edit()
            .putString(KEY_ESP_STATUS, status)
            .putString(KEY_ESP_NAME, data.name)
            .putString(KEY_ESP_TYPE, data.type)
            .putString(KEY_ESP_IP, data.ip)
            .putInt(KEY_ESP_RSSI, data.rssi)
            .putLong(KEY_ESP_UPTIME_MS, data.uptimeMs)
            .putLong(KEY_ESP_FREE_HEAP, data.freeHeap)
            .putString(KEY_ESP_SERVICE_NAME, data.serviceName)
            .apply()
    }

    private fun statePrefs(context: Context) =
        context.getSharedPreferences(WIDGET_STATE_PREFS, Context.MODE_PRIVATE)

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

    @Suppress("DEPRECATION")
    private fun resolvedHostAddress(serviceInfo: NsdServiceInfo): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val addresses = serviceInfo.hostAddresses
            return addresses.firstOrNull { it is Inet4Address }?.hostAddress
                ?: addresses.firstOrNull()?.hostAddress
        }

        return serviceInfo.host?.hostAddress
    }

    private data class WidgetConnection(
        val serverUrl: String,
        val deviceName: String,
        val lastPath: String,
    )

    private data class EspWidgetState(
        val status: String = STATUS_UNKNOWN,
        val name: String = "PyClean ESP32",
        val type: String = "esp32-s3",
        val ip: String = "",
        val rssi: Int = 0,
        val uptimeMs: Long = 0L,
        val freeHeap: Long = 0L,
        val serviceName: String = "",
    )
}
