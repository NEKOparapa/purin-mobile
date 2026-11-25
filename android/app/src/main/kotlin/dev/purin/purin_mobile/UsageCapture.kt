package dev.purin.purin_mobile

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Process
import java.util.UUID
import org.json.JSONObject

internal class UsageCapture(private val context: Context, private val store: SignalStore) {
    private val manager = context.getSystemService(UsageStatsManager::class.java)
    private val appOps = context.getSystemService(AppOpsManager::class.java)

    @Suppress("DEPRECATION")
    fun granted(): Boolean =
        appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName
        ) == AppOpsManager.MODE_ALLOWED

    fun reset(enabled: Boolean) {
        store.clear("usage")
        store.writableDatabase.delete("screenshots", "id LIKE 'visit:%'", null)
        store["usageLatest"] = null
        store["usageUploadedAt"] = null
        store["usageCursor"] = if (enabled && granted()) System.currentTimeMillis().toString() else null
        store["usageOpen"] = null
    }

    private fun label(pkg: String): String = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString().take(256)
    } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
        pkg
    }

    private fun spanId(pkg: String, start: Long): String =
        UUID.nameUUIDFromBytes(("${store["scope"]}\u0000$pkg\u0000$start").toByteArray(Charsets.UTF_8)).toString()

    data class Foreground(val pkg: String, val label: String, val start: Long, val id: String)

    // Use precisely the same checkpoint and span ID as the eventual usage slice.
    fun foreground(now: Long): Foreground? {
        if (!granted() || store["usage"] != "true") return null
        collect(now)
        if (store["usageCursor"] != now.toString()) return null
        val open = JSONObject(store["usageOpen"] ?: "{}")
        val packages = open.keys().asSequence().filter { !open.getJSONObject(it).has("paused") }.toList()
        val pkg = packages.singleOrNull() ?: return null // Ambiguous in split screen.
        if (pkg == context.packageName || pkg == "com.android.systemui") return null
        val start = open.getJSONObject(pkg).getLong("start")
        return Foreground(pkg, label(pkg), start, spanId(pkg, start))
    }

    // Some app-internal navigation pauses one Activity before resuming another.
    // Finalize its package interval after a short gap, or when another app opens.
    fun collect(now: Long) {
        val cursor = store["usageCursor"]?.toLongOrNull()
        if (cursor == null || cursor > now) {
            reset(true)
            return
        }
        val from = maxOf(cursor, now - 7 * DAY)
        val endExclusive = minOf(now, from + DAY)
        if (from == endExclusive) return
        val events = manager.queryEvents(from, endExclusive) ?: return // User may still be locked.
        val open = if (from == cursor) JSONObject(store["usageOpen"] ?: "{}") else JSONObject()
        // Record Android's HOME role alongside the span; the server decides what to filter.
        val homePackages by lazy {
            val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            context.packageManager.queryIntentActivities(home, 0).map { it.activityInfo.packageName }.toSet()
        }
        val deviceName by lazy { context.systemDeviceName() }
        fun finish(pkg: String, at: Long) {
            val session = open.remove(pkg) as? JSONObject ?: return
            if (pkg == context.packageName) return
            val start = session.getLong("start")
            val id = spanId(pkg, start)
            store.writableDatabase.delete("screenshots", "id=? AND at>?", arrayOf("visit:$id", at.toString()))
            if (at <= start) return
            val record = JSONObject()
                .put("id", id)
                .put("source", "usage").put("at", at)
                .put("package", pkg).put("label", label(pkg)).put("start", start).put("end", at)
                .put("isHomeApp", pkg in homePackages).putOpt("deviceName", deviceName)
            store.append(record)
            store["usageLatest"] = record.toString()
        }
        fun flushPaused(at: Long, nextPackage: String? = null) {
            for (pkg in open.keys().asSequence().toList()) {
                val paused = open.getJSONObject(pkg).optLong("paused", 0)
                if (paused != 0L && (paused + 1500 <= at || (nextPackage != null && pkg != nextPackage))) {
                    finish(pkg, paused)
                }
            }
        }
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val at = event.timeStamp
            if (at !in from until endExclusive) continue
            val pkg = event.packageName
            // ACTIVITY_RESUMED and ACTIVITY_PAUSED use the same values as
            // MOVE_TO_FOREGROUND and MOVE_TO_BACKGROUND on pre-Android 10.
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    flushPaused(at, pkg)
                    if (pkg == null) continue
                    val session = open.optJSONObject(pkg) ?: JSONObject().put("start", at)
                    session.remove("paused")
                    val classes = session.optJSONObject("classes") ?: JSONObject()
                    classes.put(event.className.orEmpty(), true)
                    open.put(pkg, session.put("classes", classes))
                }
                UsageEvents.Event.ACTIVITY_PAUSED -> {
                    if (pkg == null) continue
                    val session = open.optJSONObject(pkg) ?: continue
                    val classes = session.getJSONObject("classes")
                    classes.remove(event.className.orEmpty())
                    if (classes.length() == 0) session.put("paused", at)
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE, UsageEvents.Event.KEYGUARD_SHOWN,
                UsageEvents.Event.DEVICE_SHUTDOWN -> {
                    for (name in open.keys().asSequence().toList()) {
                        finish(name, open.getJSONObject(name).optLong("paused", at))
                    }
                }
                UsageEvents.Event.DEVICE_STARTUP -> {
                    // After an unclean shutdown the missing end time is unknown.
                    for (name in open.keys().asSequence().toList()) {
                        val start = open.getJSONObject(name).getLong("start")
                        store.writableDatabase.delete("screenshots", "id=?", arrayOf("visit:${spanId(name, start)}"))
                        open.remove(name)
                    }
                }
            }
        }
        flushPaused(endExclusive)
        store["usageCursor"] = endExclusive.toString()
        store["usageOpen"] = open.toString()
    }

    companion object { private const val DAY = 86_400_000L }
}
