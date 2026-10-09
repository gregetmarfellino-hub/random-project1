package com.example.pyclean_mobile

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "pyclean/nsd"
        private const val SERVICE_TYPE = "_pyclean._tcp."
        private const val DISCOVERY_TIMEOUT_MS = 6000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "discoverPyClean" -> discoverPyClean(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun discoverPyClean(result: MethodChannel.Result) {
        val nsdManager = getSystemService(Context.NSD_SERVICE) as NsdManager
        val finished = AtomicBoolean(false)
        val resolving = AtomicBoolean(false)

        lateinit var discoveryListener: NsdManager.DiscoveryListener

        fun stopDiscovery() {
            try {
                nsdManager.stopServiceDiscovery(discoveryListener)
            } catch (_: Exception) {
                // Discovery may already have stopped. Safe to ignore.
            }
        }

        fun complete(value: Map<String, Any?>?) {
            if (!finished.compareAndSet(false, true)) return
            stopDiscovery()
            mainHandler.post {
                result.success(value)
            }
        }

        val timeout = Runnable {
            complete(null)
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
                            errorCode: Int
                        ) {
                            resolving.set(false)
                        }

                        override fun onServiceResolved(resolved: NsdServiceInfo) {
                            val host = resolvedHostAddress(resolved)
                            if (host.isNullOrBlank() || resolved.port <= 0) {
                                resolving.set(false)
                                return
                            }

                            complete(
                                mapOf(
                                    "serviceName" to resolved.serviceName,
                                    "serviceType" to resolved.serviceType,
                                    "host" to host,
                                    "port" to resolved.port
                                )
                            )
                        }
                    }
                )
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit

            override fun onDiscoveryStopped(serviceType: String) {
                mainHandler.removeCallbacks(timeout)
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                if (!finished.compareAndSet(false, true)) return
                mainHandler.removeCallbacks(timeout)
                stopDiscovery()
                mainHandler.post {
                    result.error(
                        "NSD_START_FAILED",
                        "Android could not start PyClean device discovery.",
                        errorCode
                    )
                }
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
        }

        try {
            nsdManager.discoverServices(
                SERVICE_TYPE,
                NsdManager.PROTOCOL_DNS_SD,
                discoveryListener
            )
        } catch (e: Exception) {
            if (finished.compareAndSet(false, true)) {
                mainHandler.removeCallbacks(timeout)
                result.error(
                    "NSD_EXCEPTION",
                    e.message ?: "Unable to start PyClean device discovery.",
                    null
                )
            }
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
}
