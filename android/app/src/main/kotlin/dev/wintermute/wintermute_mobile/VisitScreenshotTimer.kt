package dev.wintermute.wintermute_mobile

/** Times one continuously observed foreground usage interval using the monotonic clock. */
internal class VisitScreenshotTimer {
    companion object { const val DWELL_MS = 10 * 60_000L }
    private var visit: String? = null
    private var since = 0L
    private var lastSeen = 0L
    private var attemptedVisit: String? = null

    fun reset() {
        visit = null
    }

    fun due(id: String?, now: Long): Boolean {
        if (now - lastSeen > 45_000L) reset()
        // A brief Activity transition inside one package can yield no sample.
        if (id == null) return false
        if (id != visit) {
            visit = id
            since = now
        }
        lastSeen = now
        if (attemptedVisit == id || now - since < DWELL_MS) return false
        attemptedVisit = id
        return true
    }
}
