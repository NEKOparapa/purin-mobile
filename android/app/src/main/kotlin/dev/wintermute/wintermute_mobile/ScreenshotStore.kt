package dev.wintermute.wintermute_mobile

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import java.util.UUID

/** Configuration, image bytes and attribution are committed in the same local database. */
internal class ScreenshotStore(
    private val context: Context, private val store: SignalStore, private val usage: UsageCapture
) {
    @Volatile var channel: MethodChannel? = null
    @Volatile var activeGeneration: String? = null
    private val main = Handler(Looper.getMainLooper())

    fun changed() { main.post { channel?.invokeMethod("changed", null) } }

    val generation: String? get() = store["shotGeneration"]
    val intervalMs: Long get() = (store["shotInterval"]?.toLongOrNull() ?: 300L) * 1000L

    fun allowed(scope: String?) = scope != null && scope.isNotEmpty() && scope == store["scope"] &&
        scope == store["shotScope"] && store["shotEnabled"] == "true" &&
        store["usage"] == "true" && usage.granted()

    fun configure(scope: String, enabled: Boolean, seconds: Int): Map<String, Any> = store.transaction {
        require(seconds in setOf(60, 300, 900))
        if (scope != store["shotScope"] || !enabled || !usage.granted() || store["usage"] != "true") {
            stopAndClear()
        }
        store["shotScope"] = scope
        store["shotEnabled"] = enabled.toString()
        store["shotInterval"] = seconds.toString()
        status(scope)
    }

    fun status(scope: String): Map<String, Any> {
        val access = when {
            !usage.granted() || store["usage"] != "true" -> "usageRequired"
            allowed(scope) && generation != null && activeGeneration == generation -> "active"
            store["shotDenied"] == "true" -> "denied"
            else -> "ready"
        }
        val count = if (allowed(scope)) store.readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM screenshots", null
        ).use { it.moveToFirst(); it.getInt(0) } else 0
        return mapOf("access" to access, "pending" to count)
    }

    fun beginConsent(): String {
        check(allowed(store["shotScope"])) { "请先开启截图并授权其他 App 使用时段" }
        check(activeGeneration == null) { "正在共享屏幕" }
        val token = UUID.randomUUID().toString()
        store["shotGeneration"] = token
        store["shotDenied"] = null
        return token
    }

    fun denied(token: String) {
        if (token == generation) {
            store["shotDenied"] = "true"
            store["shotGeneration"] = null
            changed()
        }
    }

    fun stopAndClear() {
        if (generation != null || activeGeneration != null) {
            store["shotGeneration"] = null
            activeGeneration = null
            context.stopService(Intent(context, ScreenshotService::class.java))
            changed()
        }
        if (store["shotEnabled"] == "true") {
            store.writableDatabase.delete("screenshots", null, null)
            store["shotEnabled"] = "false"
        }
        if (store["shotDenied"] != null) store["shotDenied"] = null
    }

    fun ended(token: String) = store.transaction {
        if (token == generation) {
            store["shotGeneration"] = null
            activeGeneration = null
            changed()
        }
    }

    fun append(token: String, at: Long, app: UsageCapture.Foreground, jpeg: ByteArray) {
        if (generation != token || activeGeneration != token || !allowed(store["shotScope"])) return
        store.transaction {
            // Retain the first 32 frames until acknowledged. A paused uploader never overwrites them.
            val full = store.readableDatabase.rawQuery(
                "SELECT 1 FROM screenshots LIMIT 1 OFFSET 31", null
            ).use { it.moveToFirst() }
            if (full) return@transaction
            val values = ContentValues().apply {
                put("id", UUID.randomUUID().toString())
                put("at", at)
                put("app", app.label)
                put("package", app.pkg)
                put("start", app.start)
                put("activity_id", app.id)
                put("jpeg", jpeg)
            }
            store.writableDatabase.insertOrThrow("screenshots", null, values)
        }
        changed()
    }

    fun read(scope: String): List<Map<String, Any>> {
        if (!allowed(scope)) return emptyList()
        return store.readableDatabase.rawQuery(
            "SELECT id,at,app,package,start,activity_id FROM screenshots ORDER BY at,rowid LIMIT 8", null
        ).use { c -> buildList {
            while (c.moveToNext()) add(mapOf("id" to c.getString(0), "at" to c.getLong(1),
                "app" to c.getString(2), "package" to c.getString(3), "start" to c.getLong(4),
                "activity_id" to c.getString(5)))
        } }
    }

    fun bytes(scope: String, id: String): ByteArray? {
        if (!allowed(scope)) return null
        return store.readableDatabase.rawQuery("SELECT jpeg FROM screenshots WHERE id=?", arrayOf(id)).use {
            if (it.moveToFirst()) it.getBlob(0) else null
        }
    }

    fun ack(scope: String, ids: List<String>) {
        if (scope != store["shotScope"]) return
        store.transaction { for (id in ids) store.writableDatabase.delete("screenshots", "id=?", arrayOf(id)) }
    }
}
