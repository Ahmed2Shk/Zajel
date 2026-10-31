package com.zajel.zajel

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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
    }

    override fun onDestroy() {
        dataServer?.stop()
        super.onDestroy()
    }

    private var dataServer: NativeDataServer? = null
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
