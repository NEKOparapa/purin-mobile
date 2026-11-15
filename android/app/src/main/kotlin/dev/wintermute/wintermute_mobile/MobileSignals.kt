package dev.wintermute.wintermute_mobile

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.content.Context
import java.util.concurrent.Executors

internal class MobileSignals private constructor(context: Context) {
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
                    if (!allowed) screenshots.stopAndClear()
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
        return mapOf("location" to locationStatus, "usage" to if (usage.granted()) "granted" else "denied",
            "backgroundLocation" to location.background())
    }

    fun configure(scope: String, wantLocation: Boolean, wantUsage: Boolean) {
        require(scope.isNotBlank() || (!wantLocation && !wantUsage))
        store.transaction {
            val newScope = scope != store["scope"]
            if (newScope || !wantUsage) screenshots.stopAndClear()
            if (newScope || (store["usage"] == "true") != wantUsage) usage.reset(wantUsage)
            if (newScope || (store["location"] == "true") != wantLocation) {
                location.reset(wantLocation && location.granted())
            }
            store["scope"] = scope
            store["location"] = wantLocation.toString()
            store["usage"] = wantUsage.toString()
            reconcile()
        }
    }

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
