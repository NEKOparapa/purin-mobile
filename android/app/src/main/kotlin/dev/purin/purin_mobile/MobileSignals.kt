package dev.purin.purin_mobile

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.content.Context
import android.os.Build
import android.provider.Settings
import java.util.concurrent.Executors

internal fun Context.systemDeviceName(): String? = try {
    Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
        ?.filterNot { it.isISOControl() }?.trim()?.takeIf { it.isNotEmpty() }
        ?.let { it.substring(0, it.offsetByCodePoints(0, minOf(80, it.codePointCount(0, it.length)))) }
} catch (_: SecurityException) {
    null
}

internal class MobileSignals private constructor(private val context: Context) {
    val store = SignalStore(context)
    val location = LocationCapture(context, store)
    val usage = UsageCapture(context, store)
    val screenshots = ScreenshotStore(context, store, usage)
    private val worker = Executors.newSingleThreadExecutor()

    init {
        // Clear the checkpoint immediately on revocation, including while Flutter
        // is paused in the system's usage-access settings.
        val ops = context.getSystemService(AppOpsManager::class.java)
        ops.startWatchingMode(AppOpsManager.OPSTR_GET_USAGE_STATS, context.packageName) { _, _ ->
            val allowed = usage.granted()
            execute {
                store.transaction {
                    if (!allowed) {
                        screenshots.stopAndClear()
                        UsageService.configure(context, false, locationAllowed())
                    }
                    if (store["usage"] == "true" && (!allowed || store["usageCursor"] == null)) {
                        usage.reset(allowed)
                    }
                }
            }
        }
    }

    fun execute(block: () -> Unit) = worker.execute(block)

    fun status(activity: Activity): Map<String, Any> {
        val locationStatus = when {
            location.granted() -> if (location.enabled()) "granted" else "disabled"
            store["askedLocation"] == "true" &&
                !activity.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_COARSE_LOCATION) &&
                !activity.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION) -> "blocked"
            else -> "denied"
        }
        return buildMap {
            context.systemDeviceName()?.let { put("systemDeviceName", it) }
            put("deviceModel", Build.MODEL)
            put("location", locationStatus)
            put("usage", if (usage.granted()) "granted" else "denied")
            put("backgroundLocation", location.background())
            if (locationAllowed()) store["locationLatest"]?.let { put("locationLatest", it) }
            if (usageAllowed()) {
                store["usageLatest"]?.let { put("usageLatest", it) }
                store["usageUploadedAt"]?.toLongOrNull()?.let { put("usageUploadedAt", it) }
                put("usageServiceRunning", UsageService.running)
                if (UsageService.running) put("usagePending", store.pendingUsage())
            }
        }
    }

    fun configure(scope: String, wantLocation: Boolean, wantUsage: Boolean, wantNetwork: Boolean) {
        require(scope.isNotBlank() || (!wantLocation && !wantUsage))
        store.transaction {
            val newScope = scope != store["scope"]
            if (newScope || !wantUsage) screenshots.stopAndClear()
            if (newScope || (store["usage"] == "true") != wantUsage) usage.reset(wantUsage)
            if (newScope || (store["location"] == "true") != wantLocation) {
                location.reset(wantLocation && location.granted())
            }
            store["network"] = (wantLocation && wantNetwork).toString()
            store["scope"] = scope
            store["location"] = wantLocation.toString()
            store["usage"] = wantUsage.toString()
            reconcile()
        }
        UsageService.configure(context, usageAllowed(), locationAllowed())
    }

    fun locationAllowed() = store["location"] == "true" && location.granted() && location.enabled()

    fun usageAllowed() = store["usage"] == "true" && usage.granted()

    private fun reconcile() {
        if (store["usage"] == "true") {
            val allowed = usage.granted()
            if ((store["usageCursor"] != null) != allowed) usage.reset(allowed)
        }
        if (store["location"] == "true") {
            val allowed = location.granted()
            if ((store["locationGeneration"] != null) != allowed) location.reset(allowed)
            if (allowed) location.register()
        }
    }

    fun read(scope: String): List<Map<String, Any>> = store.transaction {
        if (scope != store["scope"]) return@transaction emptyList()
        reconcile()
        // Keep new usage spans in SQLite until the service gets the HTTP receipt,
        // including when the Activity pauses or is destroyed mid-upload.
        if (UsageService.running) return@transaction emptyList()
        if (store["usage"] == "true" && usage.granted()) usage.collect(System.currentTimeMillis())
        store.batch()
    }

    fun ack(scope: String, ids: List<String>) = store.transaction {
        if (scope == store["scope"]) store.ack(ids)
    }

    companion object {
        @Volatile private var instance: MobileSignals? = null
        fun get(context: Context): MobileSignals = instance ?: synchronized(this) {
            instance ?: MobileSignals(context.applicationContext).also { instance = it }
        }
    }
}
