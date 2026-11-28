package dev.purin.purin_mobile

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject

/** The event and its checkpoint commit together, before Flutter receives either. */
internal class SignalStore(context: Context) : SQLiteOpenHelper(context, "mobile-signals.db", null, 2) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE config (name TEXT PRIMARY KEY, value TEXT NOT NULL)")
        db.execSQL("CREATE TABLE records (id TEXT PRIMARY KEY, source TEXT NOT NULL, at INTEGER NOT NULL, body TEXT NOT NULL)")
        db.execSQL("CREATE INDEX record_time ON records(at)")
        db.execSQL(
            "CREATE TABLE screenshots (id TEXT PRIMARY KEY, at INTEGER NOT NULL, app TEXT NOT NULL, " +
                "package TEXT NOT NULL, start INTEGER NOT NULL, activity_id TEXT NOT NULL, jpeg BLOB NOT NULL)"
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        error("Unsupported signal database version $oldVersion, expected $newVersion")
    }

    fun <T> transaction(body: () -> T): T {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val result = body()
            db.setTransactionSuccessful()
            return result
        } finally {
            db.endTransaction()
        }
    }

    operator fun get(name: String): String? =
        readableDatabase.rawQuery("SELECT value FROM config WHERE name=?", arrayOf(name)).use {
            if (it.moveToFirst()) it.getString(0) else null
        }

    operator fun set(name: String, value: String?) {
        if (value == null) writableDatabase.delete("config", "name=?", arrayOf(name))
        else writableDatabase.execSQL("INSERT OR REPLACE INTO config(name,value) VALUES(?,?)", arrayOf(name, value))
    }

    fun clear(source: String) {
        writableDatabase.delete("records", "source=?", arrayOf(source))
    }

    fun append(record: JSONObject) {
        val row = ContentValues().apply {
            put("id", record.getString("id"))
            put("source", record.getString("source"))
            put("at", record.getLong("at"))
            put("body", record.toString())
        }
        writableDatabase.insertOrThrow("records", null, row)
    }

    fun pendingUsage(): Int = readableDatabase.rawQuery(
        "SELECT COUNT(*) FROM records WHERE source='usage'", null
    ).use { it.moveToFirst(); it.getInt(0) }

    fun batch(source: String? = null, limit: Int = 128): List<Map<String, Any>> {
        return readableDatabase.query("records", arrayOf("body",
            "EXISTS(SELECT 1 FROM screenshots s WHERE s.id='visit:' || records.id)"),
            source?.let { "source=?" }, source?.let { arrayOf(it) },
            null, null, "at,rowid", limit.toString()).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    val record = JSONObject(cursor.getString(0))
                    if (cursor.getInt(1) != 0) record.put("hasVisitScreenshot", true)
                    add(record.keys().asSequence().associateWith { record.get(it) })
                }
            }
        }
    }

    fun ack(ids: List<String>) {
        for (id in ids) {
            writableDatabase.delete("records", "id=?", arrayOf(id))
            writableDatabase.delete("screenshots", "id=?", arrayOf("visit:$id"))
        }
    }
}
