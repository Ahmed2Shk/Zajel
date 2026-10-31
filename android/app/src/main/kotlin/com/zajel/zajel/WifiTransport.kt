package com.zajel.zajel

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import java.security.SecureRandom

/**
 * The router-free transports: a LocalOnlyHotspot another phone can join, joining
 * such a hotspot, and Wi-Fi Direct with the receiver as group owner.
 *
 * Nothing here moves file bytes. It only creates a network; the normal TLS
 * transfer engine then runs over it. Every failure is reported with one of the
 * codes listed on [TransportApi] so the UI can say what to do.
 *
 * This code has been compiled but not run on devices.
 */
class WifiTransport(
    private val context: Context,
    /** Asks the activity for permissions; calls back with whether all were granted. */
    private val askPermissions: (Array<String>, (Boolean) -> Unit) -> Unit,
) : TransportApi {
    private val main = Handler(Looper.getMainLooper())
    private val random = SecureRandom()

    private val wifi get() = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val connectivity get() = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    // ---- Permissions and state ------------------------------------------------

    private fun neededPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun hasPermissions(): Boolean = neededPermissions().all {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }

    override fun requestWifiPermissions(callback: (Result<Boolean>) -> Unit) {
        askPermissions(neededPermissions()) { granted -> callback(Result.success(granted)) }
    }

    override fun isLocationEnabled(): Boolean {
        // Android 13+ no longer needs location for these features.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return true
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return manager.isLocationEnabled
    }

    override fun isWifiEnabled(): Boolean = wifi.isWifiEnabled

    override fun supports5GHz(): Boolean = wifi.is5GHzBandSupported

    private fun fail(code: String, message: String): Result<Nothing> =
        Result.failure(FlutterError(code, message, null))

    /** Common checks. Returns an error to report, or null when all is well. */
    private fun precondition(needsWifiOn: Boolean = true): FlutterError? {
        if (!hasPermissions()) return FlutterError("permission_denied", "Wi-Fi permission not granted", null)
        if (!isLocationEnabled()) return FlutterError("location_off", "Location is turned off", null)
        if (needsWifiOn && !isWifiEnabled()) return FlutterError("wifi_off", "Wi-Fi is turned off", null)
        return null
    }

    // ---- LocalOnlyHotspot -----------------------------------------------------

    private var hotspot: WifiManager.LocalOnlyHotspotReservation? = null

    @SuppressLint("MissingPermission")
    override fun startHotspot(callback: (Result<NativeNetworkInfo>) -> Unit) {
        precondition()?.let { return callback(Result.failure(it)) }
        stopHotspot()
        try {
            wifi.startLocalOnlyHotspot(
                object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                        hotspot = reservation
                        val info = readCredentials(reservation)
                        if (info == null) {
                            reservation.close()
                            hotspot = null
                            callback(fail("failed", "Hotspot started without credentials"))
                        } else {
                            callback(Result.success(info))
                        }
                    }

                    override fun onStopped() {
                        hotspot = null
                    }

                    override fun onFailed(reason: Int) {
                        val code = when (reason) {
                            ERROR_INCOMPATIBLE_MODE -> "busy" // e.g. the phone's own hotspot is on
                            ERROR_TETHERING_DISALLOWED -> "unsupported"
                            else -> "failed"
                        }
                        callback(fail(code, "Hotspot failed ($reason)"))
                    }
                },
                main,
            )
        } catch (e: SecurityException) {
            callback(fail("permission_denied", e.message ?: "Permission denied"))
        } catch (e: IllegalStateException) {
            callback(fail("failed", e.message ?: "Hotspot unavailable"))
        }
    }

    @Suppress("DEPRECATION")
    private fun readCredentials(reservation: WifiManager.LocalOnlyHotspotReservation): NativeNetworkInfo? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val config = reservation.softApConfiguration
            val ssid = config.ssid ?: return null
            val pass = config.passphrase ?: return null
            NativeNetworkInfo(ssid = ssid, passphrase = pass)
        } else {
            val config = reservation.wifiConfiguration ?: return null
            val ssid = config.SSID?.trim('"') ?: return null
            val pass = config.preSharedKey?.trim('"') ?: return null
            NativeNetworkInfo(ssid = ssid, passphrase = pass)
        }
    }

    override fun stopHotspot() {
        hotspot?.close()
        hotspot = null
    }

    // ---- Joining a hotspot ----------------------------------------------------

    private var joinCallback: ConnectivityManager.NetworkCallback? = null

    override fun joinNetwork(ssid: String, passphrase: String, callback: (Result<Unit>) -> Unit) {
        precondition()?.let { return callback(Result.failure(it)) }
        leaveNetwork()

        var answered = false
        fun answer(result: Result<Unit>) {
            if (answered) return
            answered = true
            callback(result)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val specifier = WifiNetworkSpecifier.Builder()
                .setSsid(ssid)
                .setWpa2Passphrase(passphrase)
                .build()
            // No internet capability: this network only reaches the other phone.
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(specifier)
                .build()
            val networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    // Send this app's traffic over the new network.
                    connectivity.bindProcessToNetwork(network)
                    answer(Result.success(Unit))
                }

                override fun onUnavailable() = answer(fail("timeout", "The network was not found or not approved"))

                override fun onLost(network: Network) {
                    connectivity.bindProcessToNetwork(null)
                }
            }
            joinCallback = networkCallback
            connectivity.requestNetwork(request, networkCallback, main, JOIN_TIMEOUT_MS)
        } else {
            joinLegacy(ssid, passphrase, ::answer)
        }
    }

    /** Android 8 and 9: add the network by hand and wait for the connection. */
    @Suppress("DEPRECATION")
    private fun joinLegacy(ssid: String, passphrase: String, answer: (Result<Unit>) -> Unit) {
        val config = WifiConfiguration().apply {
            SSID = "\"$ssid\""
            preSharedKey = "\"$passphrase\""
        }
        val id = wifi.addNetwork(config)
        if (id == -1) return answer(fail("failed", "Could not add the network"))

        val request = NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build()
        val networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (wifi.connectionInfo?.ssid?.trim('"') == ssid) {
                    connectivity.bindProcessToNetwork(network)
                    answer(Result.success(Unit))
                }
            }
        }
        joinCallback = networkCallback
        connectivity.registerNetworkCallback(request, networkCallback)
        wifi.disconnect()
        wifi.enableNetwork(id, true)
        wifi.reconnect()
        main.postDelayed({ answer(fail("timeout", "Could not join the network")) }, JOIN_TIMEOUT_MS.toLong())
    }

    override fun leaveNetwork() {
        joinCallback?.let {
            try {
                connectivity.unregisterNetworkCallback(it)
            } catch (_: IllegalArgumentException) {
                // Already unregistered.
            }
        }
        joinCallback = null
        connectivity.bindProcessToNetwork(null)
    }

    // ---- Wi-Fi Direct ---------------------------------------------------------

    private var p2p: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var directReceiverActive = false

    private fun p2pManager(): WifiP2pManager? {
        if (p2p == null) {
            p2p = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
            channel = p2p?.initialize(context, Looper.getMainLooper(), null)
        }
        return if (channel == null) null else p2p
    }

    private fun p2pFailure(reason: Int): FlutterError = when (reason) {
        WifiP2pManager.P2P_UNSUPPORTED -> FlutterError("unsupported", "Wi-Fi Direct is not supported", null)
        WifiP2pManager.BUSY -> FlutterError("busy", "Wi-Fi Direct is busy", null)
        else -> FlutterError("failed", "Wi-Fi Direct failed ($reason)", null)
    }

    private fun randomText(length: Int): String {
        val alphabet = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return (1..length).map { alphabet[random.nextInt(alphabet.length)] }.joinToString("")
    }

    @SuppressLint("MissingPermission")
    override fun startDirectReceiver(alias: String, fingerprint: String, port: Long, callback: (Result<Unit>) -> Unit) {
        precondition()?.let { return callback(Result.failure(it)) }
        val manager = p2pManager() ?: return callback(fail("unsupported", "Wi-Fi Direct is not available"))
        val ch = channel!!
        stopDirectReceiver()

        val txt = mutableMapOf(
            "alias" to alias.take(40),
            "fp" to fingerprint,
            "port" to port.toString(),
        )

        fun advertise() {
            val info = WifiP2pDnsSdServiceInfo.newInstance("zajel-${fingerprint.take(8)}", SERVICE_TYPE, txt)
            manager.clearLocalServices(ch, null)
            manager.addLocalService(ch, info, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    directReceiverActive = true
                    callback(Result.success(Unit))
                }

                override fun onFailure(reason: Int) = callback(Result.failure(p2pFailure(reason)))
            })
        }

        val listener = object : WifiP2pManager.ActionListener {
            override fun onSuccess() = advertise()
            override fun onFailure(reason: Int) = callback(Result.failure(p2pFailure(reason)))
        }

        manager.removeGroup(ch, null) // clear any old group first
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Our own credentials: senders get them through service discovery and
            // join without a prompt. On 5 GHz when the radio supports it.
            val name = "DIRECT-zj-${randomText(6)}"
            val pass = randomText(16)
            txt["ssid"] = name
            txt["pass"] = pass
            val builder = WifiP2pConfig.Builder()
                .setNetworkName(name)
                .setPassphrase(pass)
                .enablePersistentMode(false)
            if (supports5GHz()) builder.setGroupOperatingBand(WifiP2pConfig.GROUP_OWNER_BAND_5GHZ)
            manager.createGroup(ch, builder.build(), listener)
        } else {
            manager.createGroup(ch, listener)
        }
    }

    override fun stopDirectReceiver() {
        val manager = p2p ?: return
        val ch = channel ?: return
        if (directReceiverActive) {
            manager.clearLocalServices(ch, null)
            manager.removeGroup(ch, null)
            directReceiverActive = false
        }
    }

    @SuppressLint("MissingPermission")
    override fun discoverDirectPeers(timeoutMs: Long, callback: (Result<List<NativeDirectPeer>>) -> Unit) {
        precondition()?.let { return callback(Result.failure(it)) }
        val manager = p2pManager() ?: return callback(fail("unsupported", "Wi-Fi Direct is not available"))
        val ch = channel!!

        val found = LinkedHashMap<String, NativeDirectPeer>()
        manager.setDnsSdResponseListeners(
            ch,
            { _: String, _: String, _: WifiP2pDevice -> },
            { fullDomain: String, record: Map<String, String>, device: WifiP2pDevice ->
                val fingerprint = record["fp"]
                val port = record["port"]?.toLongOrNull()
                Log.d(TAG, "service seen: $fullDomain from ${device.deviceName}")
                if (fullDomain.contains("_zajel") && fingerprint != null && port != null) {
                    found[device.deviceAddress] = NativeDirectPeer(
                        deviceAddress = device.deviceAddress,
                        alias = record["alias"] ?: device.deviceName,
                        fingerprint = fingerprint,
                        port = port,
                        networkName = record["ssid"],
                        passphrase = record["pass"],
                    )
                }
            },
        )

        var finished = false
        fun finish(result: Result<List<NativeDirectPeer>>) {
            if (finished) return
            finished = true
            manager.clearServiceRequests(ch, null)
            callback(result)
        }

        // Service discovery alone often finds nothing: the radio must also be
        // scanning for peers, and the service query is repeated, because a single
        // query is easily missed. (Behaviour differs a lot between phone makers.)
        fun query() {
            if (finished) return
            manager.discoverServices(ch, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    Log.d(TAG, "discoverServices started")
                }

                override fun onFailure(reason: Int) {
                    // BUSY is normal while a previous query is still running.
                    Log.w(TAG, "discoverServices failed ($reason)")
                    if (reason == WifiP2pManager.P2P_UNSUPPORTED) finish(Result.failure(p2pFailure(reason)))
                }
            })
        }

        fun repeatQuery(round: Int) {
            if (finished || round > MAX_QUERY_ROUNDS) return
            query()
            main.postDelayed({ repeatQuery(round + 1) }, QUERY_INTERVAL_MS)
        }

        val request = WifiP2pDnsSdServiceRequest.newInstance()
        manager.clearServiceRequests(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = addRequest()
            override fun onFailure(reason: Int) = addRequest()

            fun addRequest() {
                manager.addServiceRequest(ch, request, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        manager.discoverPeers(ch, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() = Log.d(TAG, "discoverPeers started")
                            override fun onFailure(reason: Int) = Log.w(TAG, "discoverPeers failed ($reason)")
                        })
                        repeatQuery(0)
                    }

                    override fun onFailure(reason: Int) = finish(Result.failure(p2pFailure(reason)))
                })
            }
        })

        main.postDelayed({
            Log.d(TAG, "discovery finished with ${found.size} peer(s)")
            manager.stopPeerDiscovery(ch, null)
            finish(Result.success(found.values.toList()))
        }, timeoutMs)
    }

    private var directReceiver: BroadcastReceiver? = null

    @SuppressLint("MissingPermission")
    override fun connectDirect(peer: NativeDirectPeer, callback: (Result<String>) -> Unit) {
        precondition()?.let { return callback(Result.failure(it)) }
        val manager = p2pManager() ?: return callback(fail("unsupported", "Wi-Fi Direct is not available"))
        val ch = channel!!
        disconnectDirect()

        var answered = false
        fun answer(result: Result<String>) {
            if (answered) return
            answered = true
            directReceiver?.let {
                try {
                    context.unregisterReceiver(it)
                } catch (_: IllegalArgumentException) {
                }
            }
            directReceiver = null
            callback(result)
        }

        // The connection finishes asynchronously: wait until the group is formed.
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                manager.requestConnectionInfo(ch) { info ->
                    val owner = info?.groupOwnerAddress?.hostAddress
                    if (info != null && info.groupFormed && owner != null) answer(Result.success(owner))
                }
            }
        }
        directReceiver = receiver
        ContextCompat.registerReceiver(
            context,
            receiver,
            IntentFilter(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )

        val config = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            peer.networkName != null && peer.passphrase != null
        ) {
            WifiP2pConfig.Builder()
                .setNetworkName(peer.networkName!!)
                .setPassphrase(peer.passphrase!!)
                .enablePersistentMode(false)
                .build()
        } else {
            // Android 8 and 9: a normal invitation. The receiver's phone shows
            // the system's accept dialog.
            WifiP2pConfig().apply { deviceAddress = peer.deviceAddress }
        }

        manager.connect(ch, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                // Not connected yet; the broadcast above reports when it is.
            }

            override fun onFailure(reason: Int) = answer(Result.failure(p2pFailure(reason)))
        })
        main.postDelayed({ answer(fail("timeout", "Wi-Fi Direct connection timed out")) }, JOIN_TIMEOUT_MS.toLong())
    }

    override fun disconnectDirect() {
        val manager = p2p ?: return
        val ch = channel ?: return
        manager.cancelConnect(ch, null)
        manager.removeGroup(ch, null)
    }

    companion object {
        private const val JOIN_TIMEOUT_MS = 45_000
        private const val SERVICE_TYPE = "_zajel._tcp"
        private const val TAG = "ZajelWifi"
        private const val QUERY_INTERVAL_MS = 4_000L
        private const val MAX_QUERY_ROUNDS = 6
    }
}
