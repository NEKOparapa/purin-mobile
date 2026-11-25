package dev.purin.purin_mobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document

internal class ConnectorFiles(context: Context) {
    private val resolver = context.contentResolver
    private val prefs = context.getSharedPreferences("connector_folders", Context.MODE_PRIVATE)
    private val readFlag = Intent.FLAG_GRANT_READ_URI_PERMISSION

    fun root(scope: String): Uri? {
        val uri = prefs.getString(scope, null)?.let(Uri::parse) ?: return null
        return uri.takeIf { resolver.persistedUriPermissions.any { grant -> grant.uri == it && grant.isReadPermission } }
    }

    fun remember(scope: String, uri: Uri) {
        require(DocumentsContract.isTreeUri(uri)) { "请选择一个目录" }
        resolver.takePersistableUriPermission(uri, readFlag)
        val old = prefs.getString(scope, null)
        prefs.edit().putString(scope, uri.toString()).apply()
        if (old != null && old != uri.toString()) releaseUnused(old)
    }

    fun forget(scope: String) {
        val old = prefs.getString(scope, null) ?: return
        prefs.edit().remove(scope).apply()
        releaseUnused(old)
    }

    private fun releaseUnused(value: String) {
        if (value !in prefs.all.values) {
            try { resolver.releasePersistableUriPermission(Uri.parse(value), readFlag) }
            catch (_: SecurityException) { /* The user already revoked the grant. */ }
        }
    }

    private data class Entry(val id: String, val name: String, val mime: String, val size: Long?, val modified: Long?)
    private fun children(root: Uri, parent: String, visit: (Entry) -> Boolean) {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(root, parent)
        val columns = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE, Document.COLUMN_LAST_MODIFIED)
        val cursor = resolver.query(uri, columns, null, null, null) ?: error("目录暂时不可用")
        cursor.use {
            while (it.moveToNext()) {
                val name = it.getString(1) ?: continue
                if (!visit(Entry(it.getString(0), name, it.getString(2).orEmpty(),
                    if (it.isNull(3)) null else it.getLong(3), if (it.isNull(4)) null else it.getLong(4)))) break
            }
        }
    }

    fun execute(scope: String, tool: String, args: ConnectorArgs): Map<String, Any?> {
        val root = root(scope) ?: error("请重新选择授权目录")
        val reading = tool == "android_files_read"
        val path = args.text(if (reading) "path" else "folder", 512, reading)
        val segments = if (path.isEmpty()) emptyList() else path.split('/')
        require(segments.size <= 24 && segments.all { it.isNotEmpty() && it != "." && it != ".." }) { "请输入目录内的相对路径" }
        var entry = Entry(DocumentsContract.getTreeDocumentId(root), "", Document.MIME_TYPE_DIR, null, null)
        for (part in segments) {
            require(entry.mime == Document.MIME_TYPE_DIR) { "路径不是目录" }
            var match: Entry? = null
            children(root, entry.id) {
                if (it.name == part) match = it
                match == null
            }
            entry = match ?: error("授权目录中找不到指定路径")
        }
        if (reading) return read(root, entry, args.number("offset", 0..1000000, 0))
        require(entry.mime == Document.MIME_TYPE_DIR) { "路径不是目录" }
        val filter = args.text("query", 80)
        val limit = args.limit
        val items = mutableListOf<Map<String, Any?>>()
        var more = false
        children(root, entry.id) {
            if (it.name.contains(filter, ignoreCase = true)) {
                if (items.size == limit) more = true
                else items.add(mapOf("path" to (segments + it.name).joinToString("/"),
                    "type" to if (it.mime == Document.MIME_TYPE_DIR) "folder" else it.mime,
                    "size_bytes" to it.size, "modified_ms" to it.modified))
            }
            !more
        }
        return mapOf("items" to items, "truncated" to more)
    }

    private fun read(root: Uri, entry: Entry, offset: Int): Map<String, Any?> {
        val text = entry.mime.startsWith("text/") || entry.mime in setOf("application/json", "application/xml",
            "application/yaml", "application/x-yaml", "application/javascript") ||
            (entry.mime == "application/octet-stream" && entry.name.substringAfterLast('.').lowercase() in
                setOf("txt", "md", "csv", "json", "xml", "yaml", "yml", "log"))
        require(text) { "此文件可查看信息，正文读取支持 UTF-8 文本" }
        val uri = DocumentsContract.buildDocumentUriUsingTree(root, entry.id)
        val stream = resolver.openInputStream(uri) ?: error("文件暂时无法打开")
        stream.bufferedReader(Charsets.UTF_8).use { reader ->
            var remaining = offset.toLong()
            while (remaining > 0) {
                val skipped = reader.skip(remaining)
                require(skipped > 0) { "偏移量超过文件长度" }
                remaining -= skipped
            }
            val buffer = CharArray(901)
            var count = 0
            while (count < buffer.size) {
                val n = reader.read(buffer, count, buffer.size - count)
                if (n <= 0) break
                count += n
            }
            var end = minOf(count, 900)
            if (end == 900 && count > end && buffer[end - 1].isHighSurrogate()) end--
            return mapOf("text" to String(buffer, 0, end), "next_offset" to if (count > end) offset + end else null)
        }
    }
}
