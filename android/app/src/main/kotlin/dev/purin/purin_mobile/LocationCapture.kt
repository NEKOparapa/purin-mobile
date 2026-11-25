package dev.purin.purin_mobile

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.location.LocationRequest
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import org.json.JSONObject
import java.util.UUID

internal class LocationCapture(private val context: Context, private val store: SignalStore) {
    private val manager = context.getSystemService(LocationManager::class.java)
    private var registration: String? = null
    private var nextFixRequest = 0L

    fun permitted(permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    fun granted() = permitted(Manifest.permission.ACCESS_COARSE_LOCATION) ||
        permitted(Manifest.permission.ACCESS_FINE_LOCATION)

    fun background() = granted() && (Build.VERSION.SDK_INT < 29 ||
        permitted(Manifest.permission.ACCESS_BACKGROUND_LOCATION))

    @Suppress("DEPRECATION")
    fun enabled() = if (Build.VERSION.SDK_INT >= 28) manager.isLocationEnabled
        else manager.getProviders(true).any { it != LocationManager.PASSIVE_PROVIDER }

    private fun delivery(generation: String): PendingIntent {
        val mutableFlag = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        val intent = Intent(context, LocationReceiver::class.java)
            .setData(Uri.fromParts("purin-location", generation, null))
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag)
    }

    fun reset(enabled: Boolean) {
        store["locationGeneration"]?.let {
            val intent = delivery(it)
            try {
                manager.removeUpdates(intent)
            } catch (_: SecurityException) {
                // A revoked grant invalidates the subscription as well.
            } finally {
                intent.cancel()
            }
        }
        store.clear("location")
        registration = null
        nextFixRequest = 0L
        store["locationGeneration"] = if (enabled) UUID.randomUUID().toString() else null
        store["locationSince"] = if (enabled) System.currentTimeMillis().toString() else null
        store["lastFix"] = null
        store["locationLatest"] = null
    }

    fun register() {
        val generation = store["locationGeneration"] ?: return
        if (!granted() || !enabled()) return
        val providers = manager.getProviders(true)
        val provider = when {
            Build.VERSION.SDK_INT >= 31 && LocationManager.FUSED_PROVIDER in providers -> LocationManager.FUSED_PROVIDER
            LocationManager.NETWORK_PROVIDER in providers -> LocationManager.NETWORK_PROVIDER
            permitted(Manifest.permission.ACCESS_FINE_LOCATION) && LocationManager.GPS_PROVIDER in providers ->
                LocationManager.GPS_PROVIDER
            else -> LocationManager.PASSIVE_PROVIDER
        }
        val key = generation + ":" + provider
        if (key == registration) return
        val intent = delivery(generation)
        if (registration != null) manager.removeUpdates(intent)
        if (Build.VERSION.SDK_INT >= 31) {
            val request = LocationRequest.Builder(INTERVAL_MS)
                .setQuality(LocationRequest.QUALITY_BALANCED_POWER_ACCURACY)
                .setMinUpdateIntervalMillis(INTERVAL_MS)
                .setMinUpdateDistanceMeters(0f)
                .build()
            manager.requestLocationUpdates(provider, request, intent)
        } else {
            @Suppress("DEPRECATION")
            manager.requestLocationUpdates(provider, INTERVAL_MS, 0f, intent)
        }
        registration = key
    }

    fun requestDueFix(now: Long) {
        if (Build.VERSION.SDK_INT < 30 || !granted() || !enabled()) return
        val generation = store["locationGeneration"] ?: return
        val last = store["lastFix"]?.toLongOrNull()
        if (last != null && now - last < INTERVAL_MS) return
        val elapsed = SystemClock.elapsedRealtime()
        if (elapsed < nextFixRequest) return
        if (registration == null) register()
        val provider = registration?.substringAfter(':') ?: return
        nextFixRequest = elapsed + 60_000L
        manager.getCurrentLocation(provider, null, context.mainExecutor) { fix ->
            if (fix != null) {
                val signals = MobileSignals.get(context)
                signals.execute { store.transaction { accept(generation, fix) } }
            }
        }
    }

    fun accept(generation: String?, location: Location) {
        if (generation != store["locationGeneration"] || !granted() ||
            store["location"] != "true" || !enabled()) return
        val since = store["locationSince"]?.toLongOrNull() ?: return
        val last = store["lastFix"]?.toLongOrNull()
        if (location.time < since || (last != null && location.time - last < INTERVAL_MS)) return
        if (!location.hasAccuracy() || !location.accuracy.isFinite() || location.accuracy < 0 ||
            location.latitude !in -90.0..90.0 || location.longitude !in -180.0..180.0) return
        val record = JSONObject().put("id", UUID.randomUUID().toString())
            .put("source", "location").put("kind", "fix").put("at", location.time)
            .put("lat", location.latitude).put("lon", location.longitude)
            .put("accuracy", location.accuracy.toDouble())
        if (store["network"] == "true") addWifi(record)
        store.append(record)
        store["locationLatest"] = record.toString()
        store["lastFix"] = location.time.toString()
    }

    @Suppress("DEPRECATION")
    private fun addWifi(record: JSONObject) {
        try {
            val networks = context.getSystemService(ConnectivityManager::class.java)
            val connected = networks.allNetworks.any {
                networks.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
            }
            record.put("wifiState", if (connected) "connected" else "disconnected")
            if (connected) {
                val name = context.getSystemService(WifiManager::class.java).connectionInfo?.ssid
                    ?.removeSurrounding("\"")?.takeIf { it.isNotBlank() && it != WifiManager.UNKNOWN_SSID }
                record.putOpt("wifiSsid", name)
            }
        } catch (_: SecurityException) {
            if (!record.has("wifiState")) record.put("wifiState", "unknown")
        }
    }

    companion object { private const val INTERVAL_MS = 20 * 60_000L }
}

class LocationReceiver : BroadcastReceiver() {
    @Suppress("DEPRECATION")
    override fun onReceive(context: Context, intent: Intent) {
        // A single location is supplied when no batched request was made.
        val fix = intent.getParcelableExtra<Location>(LocationManager.KEY_LOCATION_CHANGED) ?: return
        val generation = intent.data?.schemeSpecificPart ?: return
        val signals = MobileSignals.get(context)
        val result = goAsync()
        signals.execute {
            try {
                signals.store.transaction { signals.location.accept(generation, fix) }
            } finally {
                result.finish()
            }
        }
    }
}
