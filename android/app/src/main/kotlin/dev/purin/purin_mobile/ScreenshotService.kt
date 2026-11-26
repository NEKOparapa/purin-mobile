package dev.purin.purin_mobile

import android.app.Activity
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.graphics.Point
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.WindowManager
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt

/** One system grant and virtual display per session. Attach the image surface only for a due frame. */
class ScreenshotService : Service() {
    private val signals by lazy { MobileSignals.get(this) }
    private val shots get() = signals.screenshots
    private val main = Handler(Looper.getMainLooper())
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var token: String? = null
    private val timer = VisitScreenshotTimer()
    private var taking = false
    private var visible = true
    private val callback = object : MediaProjection.Callback() {
        override fun onStop() { stopProjection() }
        override fun onCapturedContentVisibilityChanged(isVisible: Boolean) {
            visible = isVisible
            if (!isVisible) {
                timer.reset()
                releaseSurface()
            }
        }
        // The framework also reports the current size each time a surface attaches.
        // A device rotation is handled by onConfigurationChanged and the next sample.
    }
    private val tick = object : Runnable {
        override fun run() {
            if (projection == null) return
            if (!usable()) timer.reset() else if (!taking) pollVisit()
            main.postDelayed(this, 2000)
        }
    }

    private fun usable(): Boolean = visible && getSystemService(PowerManager::class.java).isInteractive &&
        !getSystemService(KeyguardManager::class.java).isKeyguardLocked && shots.allowed(currentScope()) &&
        token != null && shots.generation == token
    private fun currentScope() = signals.store["scope"]
    private fun currentApp() = signals.store.transaction { signals.usage.foreground(System.currentTimeMillis()) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            stopProjection()
            stopSelf()
            return START_NOT_STICKY
        }
        val next = intent?.getStringExtra("token")
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(42, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } else startForeground(42, notification())
            @Suppress("DEPRECATION")
            val grant = intent?.getParcelableExtra<Intent>("grant")
            if (next == null || next != shots.generation || grant == null || !shots.allowed(currentScope())) {
                stopSelf()
                return START_NOT_STICKY
            }
            token = next
            val manager = getSystemService(MediaProjectionManager::class.java)
            val session = checkNotNull(manager.getMediaProjection(Activity.RESULT_OK, grant))
            projection = session
            session.registerCallback(callback, main)
            val (width,height) = dimensions()
            display = session.createVirtualDisplay("Purin", width, height, resources.displayMetrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, null, null, main)
            shots.activeGeneration = next
            timer.reset()
            main.post(tick)
            shots.changed()
        } catch (_: RuntimeException) {
            stopProjection()
            stopSelf()
        }
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION")
    private fun dimensions(): Pair<Int, Int> {
        val wm = getSystemService(WindowManager::class.java)
        val size = if (Build.VERSION.SDK_INT >= 30) {
            val bounds = wm.maximumWindowMetrics.bounds
            Point(bounds.width(), bounds.height())
        } else Point().also { wm.defaultDisplay.getRealSize(it) }
        val scale = minOf(1.0, 1280.0 / maxOf(size.x, size.y))
        return Pair(maxOf(2, (size.x * scale).roundToInt()), maxOf(2, (size.y * scale).roundToInt()))
    }

    private fun pollVisit() {
        val generation = token ?: return
        taking = true
        signals.execute {
            val app = currentApp()
            main.post {
                if (!usable() || token != generation || display == null) {
                    timer.reset()
                    taking = false
                    return@post
                }
                if (!timer.due(app?.id, SystemClock.elapsedRealtime()) || app == null) {
                    taking = false
                    return@post
                }
                try {
                    val (w,h) = dimensions()
                    val surface = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
                    reader = surface
                    surface.setOnImageAvailableListener({ incoming ->
                        if (reader !== incoming) return@setOnImageAvailableListener
                        val image = incoming.acquireLatestImage() ?: return@setOnImageAvailableListener
                        val at = System.currentTimeMillis()
                        val bitmap = try { if (usable()) pixels(image) else null } finally {
                            image.close()
                            releaseSurface()
                        }
                        if (bitmap != null) {
                            signals.execute {
                                try {
                                    if (shots.generation == generation && usable() && currentApp() == app) {
                                        jpeg(bitmap)?.let { shots.append(generation, at, app, it) }
                                    }
                                } finally { bitmap.recycle() }
                            }
                        }
                    }, main)
                    display?.resize(w, h, resources.displayMetrics.densityDpi)
                    display?.surface = surface.surface
                    main.postDelayed({ if (reader === surface) releaseSurface() }, 1800)
                } catch (_: RuntimeException) {
                    releaseSurface()
                }
            }
        }
    }

    private fun pixels(image: Image): Bitmap? {
        val plane = image.planes.firstOrNull() ?: return null
        if (plane.pixelStride != 4) return null
        val padded = Bitmap.createBitmap(plane.rowStride / 4, image.height, Bitmap.Config.ARGB_8888)
        return try {
            padded.copyPixelsFromBuffer(plane.buffer)
            if (padded.width == image.width) padded else {
                Bitmap.createBitmap(padded, 0, 0, image.width, image.height).also { padded.recycle() }
            }
        } catch (_: RuntimeException) { padded.recycle(); null }
    }

    private fun jpeg(bitmap: Bitmap): ByteArray? {
        // Protected windows are blacked out by Android. Ignore blank content even
        // when the status and navigation bars still contain visible system icons.
        var illuminated = 0
        for (y in 1..16) for (x in 1..16) {
            val color = bitmap.getPixel(bitmap.width * x / 17, bitmap.height * y / 17)
            if (color and 0xf0f0f0 != 0) illuminated++
        }
        if (illuminated < 3) return null
        val stream = ByteArrayOutputStream()
        for (quality in listOf(72, 50)) {
            stream.reset()
            if (bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream) && stream.size() <= 1024 * 1024)
                return stream.toByteArray()
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun notification(): Notification {
        val strings = purinStrings()
        val mgr = getSystemService(NotificationManager::class.java)
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            mgr.createNotificationChannel(NotificationChannel("screenshots", strings.getString(R.string.periodic_screenshots), NotificationManager.IMPORTANCE_LOW))
            Notification.Builder(this, "screenshots")
        } else Notification.Builder(this)
        val stop = PendingIntent.getService(this, 1, Intent(this, ScreenshotService::class.java).setAction(STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return builder.setSmallIcon(R.drawable.ic_stat_purin)
            .setLargeIcon(BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher))
            .setContentTitle(strings.getString(R.string.capturing_foreground)).setContentText(strings.getString(R.string.screenshot_timing))
            .setOngoing(true).addAction(android.R.drawable.ic_menu_close_clear_cancel, strings.getString(R.string.stop_sharing), stop).build()
    }

    private fun releaseSurface() {
        try { display?.surface = null } catch (_: RuntimeException) {}
        reader?.close()
        reader = null
        taking = false
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        releaseSurface()
    }

    private fun stopProjection() {
        val old = token
        token = null
        main.removeCallbacks(tick)
        releaseSurface()
        display?.release()
        display = null
        projection?.unregisterCallback(callback)
        projection?.stop()
        projection = null
        if (old != null) {
            // Invalidate queued image work before returning from the stop callback.
            shots.activeGeneration = null
            signals.execute { shots.ended(old) }
        }
        stopSelf()
    }

    override fun onDestroy() {
        stopProjection()
        super.onDestroy()
    }

    companion object {
        private const val STOP = "dev.purin.STOP_SCREENSHOTS"
    }
}
