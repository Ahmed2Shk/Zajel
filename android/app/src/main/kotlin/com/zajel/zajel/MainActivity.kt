package com.zajel.zajel

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.io.ByteArrayOutputStream
import java.io.File
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
