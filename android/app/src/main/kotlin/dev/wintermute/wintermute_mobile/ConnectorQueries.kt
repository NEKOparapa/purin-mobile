package dev.wintermute.wintermute_mobile

import android.app.usage.UsageStatsManager
import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.CalendarContract.Instances
import android.provider.ContactsContract
import android.provider.Telephony
import androidx.core.location.LocationManagerCompat
import androidx.core.os.CancellationSignal
import java.util.Calendar
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

internal class ConnectorQueries(private val context: Context) {
    private val resolver = context.contentResolver

    fun execute(tool: String, args: ConnectorArgs): Map<String, Any?> = when (tool) {
        "android_app_usage" -> usage(args)
        "android_calendar_events" -> calendar(args)
        "android_contacts" -> contacts(args)
        "android_location" -> position()
        "android_sms" -> sms(args)
        else -> error("未知查询")
    }

    private fun usage(args: ConnectorArgs): Map<String, Any?> {
        val days = args.number("days", 1..7, 1)
        val start = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            add(Calendar.DATE, 1 - days)
        }.timeInMillis
        val now = System.currentTimeMillis()
        val manager = context.getSystemService(UsageStatsManager::class.java)
        val stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, now)
            ?: error("系统暂时无法提供使用统计")
        val totals = stats.filter { it.totalTimeInForeground > 0 && it.lastTimeUsed >= start }
            .groupBy { it.packageName }.mapValues { (_, buckets) -> buckets.sumOf { it.totalTimeInForeground } }
            .entries.sortedByDescending { it.value }
        val pm = context.packageManager
        val items = totals.take(args.limit).map { (pkg, time) ->
            val label = try { pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString() }
                catch (_: android.content.pm.PackageManager.NameNotFoundException) { pkg }
            mapOf("package" to pkg, "app" to label.take(150), "foreground_seconds" to time / 1000)
        }
        return mapOf("start_ms" to start, "end_ms" to now, "aggregation" to "系统日统计，时长为估算值",
            "items" to items, "truncated" to (totals.size > items.size))
    }

    private fun calendar(args: ConnectorArgs): Map<String, Any?> {
        val (start, end) = args.window()
        val builder = Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, start)
        ContentUris.appendId(builder, end)
        val columns = arrayOf(Instances.TITLE, Instances.BEGIN, Instances.END, Instances.ALL_DAY,
            Instances.EVENT_LOCATION, Instances.DESCRIPTION)
        val cursor = resolver.query(builder.build(), columns, "${Instances.VISIBLE} = 1", null, "${Instances.BEGIN} ASC")
        return page(cursor, args.limit) {
            mapOf("title" to it.field(0, 200), "start_ms" to it.getLong(1), "end_ms" to it.getLong(2),
                "all_day" to (it.getInt(3) == 1), "location" to it.field(4, 160), "notes" to it.field(5, 200))
        }
    }

    private fun contacts(args: ConnectorArgs): Map<String, Any?> {
        val query = args.text("query", 80, true)
        val uri = Uri.withAppendedPath(ContactsContract.Contacts.CONTENT_FILTER_URI, Uri.encode(query))
        val cursor = resolver.query(uri, arrayOf(ContactsContract.Contacts._ID, ContactsContract.Contacts.DISPLAY_NAME),
            null, null, ContactsContract.Contacts.DISPLAY_NAME)
        return page(cursor, args.limit) { row ->
            val phoneMime = ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE
            val emailMime = ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE
            val phones = linkedSetOf<String>()
            val emails = linkedSetOf<String>()
            resolver.query(ContactsContract.Data.CONTENT_URI, arrayOf("mimetype", "data1"),
                "contact_id = ? AND mimetype IN (?, ?)", arrayOf(row.getString(0), phoneMime, emailMime), null)?.use {
                while (it.moveToNext()) {
                    val field = if (it.getString(0) == phoneMime) phones else emails
                    if (field.size < 4) it.field(1, 160)?.let(field::add)
                }
            }
            mapOf("name" to row.field(1, 160), "phones" to phones.toList(), "emails" to emails.toList())
        }
    }

    private fun sms(args: ConnectorArgs): Map<String, Any?> {
        val query = args.text("query", 80, true)
        val escaped = query.replace("!", "!!").replace("%", "!%").replace("_", "!_")
        val pattern = "%$escaped%"
        val cursor = resolver.query(Telephony.Sms.CONTENT_URI, arrayOf("address", "date", "type", "body"),
            "type IN (1, 2) AND (address LIKE ? ESCAPE '!' OR body LIKE ? ESCAPE '!')",
            arrayOf(pattern, pattern), "date DESC")
        return page(cursor, args.limit) {
            val body = it.getString(3).orEmpty()
            val begin = (body.indexOf(query, ignoreCase = true) - 40).coerceAtLeast(0)
            mapOf("address" to it.field(0, 120), "time_ms" to it.getLong(1),
                "direction" to if (it.getInt(2) == Telephony.Sms.MESSAGE_TYPE_INBOX) "received" else "sent",
                "excerpt" to body.drop(begin).take(180))
        }
    }

    @Suppress("DEPRECATION")
    private fun position(): Map<String, Any?> {
        val manager = context.getSystemService(LocationManager::class.java)
        val providers = manager.getProviders(true)
        val precise = context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        val choices = listOfNotNull(if (Build.VERSION.SDK_INT >= 31) LocationManager.FUSED_PROVIDER else null,
            LocationManager.NETWORK_PROVIDER, if (precise) LocationManager.GPS_PROVIDER else null).filter { it in providers }
        check(choices.isNotEmpty()) { "系统没有可用的定位服务" }
        val cached = choices.mapNotNull(manager::getLastKnownLocation).filter {
            it.hasAccuracy() && SystemClock.elapsedRealtimeNanos() - it.elapsedRealtimeNanos in 0L..30_000_000_000L
        }.minByOrNull { it.accuracy }
        val fix = cached ?: run {
            val done = CountDownLatch(1)
            val ref = AtomicReference<Location?>()
            val remaining = AtomicInteger(choices.size)
            val requests = mutableListOf<CancellationSignal>()
            try {
                for (provider in choices) {
                    if (ref.get() != null) break
                    val cancel = CancellationSignal()
                    requests.add(cancel)
                    try {
                        LocationManagerCompat.getCurrentLocation(manager, provider, cancel, { it.run() }) { value ->
                            if (value != null && ref.compareAndSet(null, value)) done.countDown()
                            if (remaining.decrementAndGet() == 0) done.countDown()
                        }
                    } catch (_: IllegalArgumentException) {
                        // A provider can disappear between enumeration and request.
                        if (remaining.decrementAndGet() == 0) done.countDown()
                    }
                }
                check(done.await(12, TimeUnit.SECONDS)) { "定位超时，请检查系统定位后重试" }
                ref.get() ?: error("暂时没有可用的位置")
            } finally { requests.forEach { it.cancel() } }
        }
        return mapOf("latitude" to fix.latitude, "longitude" to fix.longitude, "time_ms" to fix.time,
            "accuracy_m" to if (fix.hasAccuracy()) fix.accuracy.toDouble() else null,
            "permission" to if (precise) "precise" else "approximate")
    }

    private fun Cursor.field(column: Int, max: Int) = getString(column)?.take(max)

    private fun page(cursor: Cursor?, limit: Int, row: (Cursor) -> Map<String, Any?>): Map<String, Any?> =
        (cursor ?: error("系统数据源不可用")).use {
            val items = mutableListOf<Map<String, Any?>>()
            while (items.size < limit && it.moveToNext()) items.add(row(it))
            mapOf("items" to items, "truncated" to it.moveToNext())
        }
}
