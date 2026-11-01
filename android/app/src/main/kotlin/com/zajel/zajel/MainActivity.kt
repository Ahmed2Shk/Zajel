package com.zajel.zajel

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        PlatformApi.setUp(messenger, PlatformApiImpl(applicationContext, this))

        // Flutter's channels must be used from the main thread, while the data
        // server works on its own threads, so callbacks hop over.
        val callbacks = NativeDataCallbacks(messenger)
        val main = Handler(Looper.getMainLooper())
        dataServer = NativeDataServer(
            onChunk = { sessionId, fileId, offset, length, reply ->
                main.post {
                    callbacks.onNativeChunk(sessionId, fileId, offset, length) { result ->
                        reply(result.fold({ it.toInt() }, { 500 }))
                    }
                }
            },
            onProgress = { sessionId, fileId, liveBytes ->
                main.post { callbacks.onNativeProgress(sessionId, fileId, liveBytes) { } }
            },
        )
        NativeDataApi.setUp(messenger, NativeDataApiImpl(dataServer!!))

        val transport = WifiTransport(applicationContext) { permissions, done ->
            requestWifiPermissions(permissions, done)
        }
        wifiTransport = transport
        TransportApi.setUp(messenger, transport)
    }

    /** Asks for runtime permissions and reports the outcome to [done]. */
    private fun requestWifiPermissions(permissions: Array<String>, done: (Boolean) -> Unit) {
        val missing = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            done(true)
            return
        }
        pendingPermission?.invoke(false) // a newer request replaces an unanswered one
        pendingPermission = done
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), WIFI_PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == WIFI_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermission?.invoke(granted)
            pendingPermission = null
        }
    }

    override fun onDestroy() {
        wifiTransport?.let {
            it.stopHotspot()
            it.leaveNetwork()
            it.stopDirectReceiver()
            it.disconnectDirect()
        }
        dataServer?.stop()
        super.onDestroy()
    }

    private var dataServer: NativeDataServer? = null
    private var wifiTransport: WifiTransport? = null
    private var pendingPermission: ((Boolean) -> Unit)? = null

    private companion object {
        const val WIFI_PERMISSION_REQUEST = 5318
    }
}

private class NativeDataApiImpl(private val server: NativeDataServer) : NativeDataApi {
    override fun startDataServer(certificatePem: String, privateKeyPem: String): Long =
        server.start(certificatePem, privateKeyPem).toLong()

    override fun registerUpload(
        sessionId: String,
        fileId: String,
        token: String,
        path: String,
        size: Long,
        senderAddress: String,
    ) = server.register(sessionId, fileId, token, path, size, senderAddress)

    override fun unregisterSession(sessionId: String) = server.unregisterSession(sessionId)

    override fun stopDataServer() = server.stop()
}

private const val COPY_BUFFER = 1 shl 20

private class PlatformApiImpl(
    private val context: Context,
    private val activity: Activity,
) : PlatformApi {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun getDeviceInfo(): NativeDeviceInfo =
        NativeDeviceInfo(model = Build.MODEL, sdkInt = Build.VERSION.SDK_INT.toLong())

    override fun startTransferService(title: String, text: String) {
        val intent = Intent(context, TransferService::class.java)
            .putExtra(TransferService.EXTRA_TITLE, title)
            .putExtra(TransferService.EXTRA_TEXT, text)
        ContextCompat.startForegroundService(context, intent)
    }

    override fun stopTransferService() {
        context.stopService(Intent(context, TransferService::class.java))
    }

    override fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 5317)
        }
    }

    override fun getProcessCpuTimeMs(): Long = Process.getElapsedCpuTime()
    private val iconExecutor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun getAppIcon(packageName: String, sizePx: Long, callback: (Result<ByteArray?>) -> Unit) {
        iconExecutor.execute {
            val bytes = try {
                renderIcon(packageName, sizePx.toInt().coerceIn(16, 256))
            } catch (_: Exception) {
                null
            }
            mainHandler.post { callback(Result.success(bytes)) }
        }
    }

    private val ioExecutor = Executors.newSingleThreadExecutor()

    override fun publishFile(
        path: String,
        displayName: String,
        mimeType: String,
        callback: (Result<String?>) -> Unit,
    ) {
        ioExecutor.execute {
            val uri = try {
                publish(File(path), displayName, mimeType)
            } catch (_: Exception) {
                null
            }
            mainHandler.post { callback(Result.success(uri)) }
        }
    }

    /**
     * Copies [source] into a public MediaStore collection and deletes the
     * private copy. Photos go to Pictures, videos to Movies, audio to Music and
     * everything else to Download, always under a "Zajel" folder. The file is
     * hidden ("pending") until the copy is complete, so no half file shows up.
     */
    private fun publish(source: File, displayName: String, mimeType: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null // stays in the app folder

        val volume = MediaStore.VOLUME_EXTERNAL_PRIMARY
        val (collection, folder) = when {
            mimeType.startsWith("image/") -> MediaStore.Images.Media.getContentUri(volume) to Environment.DIRECTORY_PICTURES
            mimeType.startsWith("video/") -> MediaStore.Video.Media.getContentUri(volume) to Environment.DIRECTORY_MOVIES
            mimeType.startsWith("audio/") -> MediaStore.Audio.Media.getContentUri(volume) to Environment.DIRECTORY_MUSIC
            else -> MediaStore.Downloads.getContentUri(volume) to Environment.DIRECTORY_DOWNLOADS
        }

        // A sender may keep its folder structure ("trip/day1/a.jpg").
        val parts = displayName.split('/').filter { it.isNotEmpty() }
        val fileName = parts.lastOrNull() ?: return null
        val subFolder = parts.dropLast(1).joinToString("/")
        val relative = listOf(folder, "Zajel", subFolder).filter { it.isNotEmpty() }.joinToString("/")

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(collection, values) ?: return null
        try {
            val out = resolver.openOutputStream(uri) ?: throw IOException("cannot open $uri")
            out.use { stream -> source.inputStream().use { it.copyTo(stream, COPY_BUFFER) } }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            source.delete()
            return uri.toString()
        } catch (e: Exception) {
            resolver.delete(uri, null, null) // never leave a broken file behind
            throw e
        }
    }

    override fun openPublished(uri: String, mimeType: String): Boolean {
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(Uri.parse(uri), mimeType)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    @Suppress("DEPRECATION")
    override fun getWifiInfo(): NativeWifiInfo? {
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val info = wifi.connectionInfo ?: return null
        if (info.networkId == -1 && info.frequency <= 0) return null
        return NativeWifiInfo(
            frequencyMhz = info.frequency.toLong(),
            linkSpeedMbps = info.linkSpeed.toLong(),
            rssiDbm = info.rssi.toLong(),
        )
    }

    /** Draws the app's icon (adaptive icons included) onto a square bitmap. */
    private fun renderIcon(packageName: String, size: Int): ByteArray {
        val drawable = context.packageManager.getApplicationIcon(packageName)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        return ByteArrayOutputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            bitmap.recycle()
            it.toByteArray()
        }
    }


    @Suppress("DEPRECATION")
    override fun listInstalledApps(): List<NativeAppInfo> {
        val pm = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(launcher, 0)
            .mapNotNull { resolved ->
                val app = resolved.activityInfo.applicationInfo
                val apk = File(app.sourceDir)
                if (!apk.canRead()) {
                    null
                } else {
                    NativeAppInfo(
                        name = pm.getApplicationLabel(app).toString(),
                        packageName = app.packageName,
                        apkPath = app.sourceDir,
                        size = apk.length(),
                    )
                }
            }
            .distinctBy { it.packageName }
            .sortedBy { it.name.lowercase() }
    }

    override fun setMulticastLock(enabled: Boolean) {
        if (enabled) {
            if (multicastLock?.isHeld == true) return
            val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("zajel-discovery").apply {
                setReferenceCounted(false)
                acquire()
            }
        } else {
            multicastLock?.takeIf { it.isHeld }?.release()
            multicastLock = null
        }
    }
}
