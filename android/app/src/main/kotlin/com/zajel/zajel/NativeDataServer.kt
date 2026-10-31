package com.zajel.zajel

import android.util.Base64
import java.io.BufferedInputStream
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.net.URLDecoder
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.security.KeyFactory
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.CertificateFactory
import java.security.spec.PKCS8EncodedKeySpec
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.KeyManager
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import kotlin.math.min

/**
 * The Android data path of Zajel's chunked upload.
 *
 * A small HTTPS server that does one job: take `POST /api/localsend/v2/upload`
 * requests carrying a chunk of a file and write the body to disk at the given
 * offset with [FileChannel]. The bytes go from the socket to the file without
 * ever entering Dart.
 *
 * Dart stays in charge of who may upload: it calls [register] for each
 * accepted file and is told after every chunk through [onChunk], whose answer
 * becomes the HTTP status. Requests for anything that was not registered, or
 * with a wrong token or from another address, are refused.
 */
class NativeDataServer(
    /** (sessionId, fileId, offset, length, reply). Must call [reply] with an HTTP status. */
    private val onChunk: (String, String, Long, Long, (Int) -> Unit) -> Unit,
) {
    private class Upload(
        val sessionId: String,
        val fileId: String,
        val token: String,
        val path: String,
        val size: Long,
        val senderAddress: String,
    )

    private val uploads = ConcurrentHashMap<String, Upload>()
    @Volatile private var server: SSLServerSocket? = null
    private var pool: ExecutorService? = null

    /** Starts listening on a free port and returns it. */
    @Synchronized
    fun start(certificatePem: String, privateKeyPem: String): Int {
        stop()
        val context = SSLContext.getInstance("TLS")
        context.init(keyManagers(certificatePem, privateKeyPem), null, null)
        val socket = context.serverSocketFactory.createServerSocket(0) as SSLServerSocket
        socket.reuseAddress = true
        val executor = Executors.newCachedThreadPool()
        pool = executor
        server = socket
        executor.execute { acceptLoop(socket, executor) }
        return socket.localPort
    }

    fun register(
        sessionId: String,
        fileId: String,
        token: String,
        path: String,
        size: Long,
        senderAddress: String,
    ) {
        uploads[key(sessionId, fileId)] = Upload(sessionId, fileId, token, path, size, senderAddress)
    }

    fun unregisterSession(sessionId: String) {
        uploads.keys.removeAll { it.startsWith("$sessionId|") }
    }

    @Synchronized
    fun stop() {
        try {
            server?.close()
        } catch (_: IOException) {
        }
        server = null
        pool?.shutdownNow()
        pool = null
        uploads.clear()
    }

    private fun key(sessionId: String, fileId: String) = "$sessionId|$fileId"

    private fun acceptLoop(socket: SSLServerSocket, executor: ExecutorService) {
        while (!socket.isClosed) {
            val client = try {
                socket.accept() as SSLSocket
            } catch (_: IOException) {
                return
            }
            try {
                executor.execute { handle(client) }
            } catch (_: Exception) {
                client.close()
                return
            }
        }
    }

    private fun handle(socket: SSLSocket) {
        try {
            socket.use {
                it.soTimeout = IDLE_TIMEOUT_MS
                it.tcpNoDelay = true
                it.receiveBufferSize = SOCKET_BUFFER
                val input = BufferedInputStream(it.inputStream, 64 * 1024)
                val remote = (it.inetAddress.hostAddress ?: "").substringBefore('%')
                while (serveOne(input, it.outputStream, remote)) {
                    // Keep-alive: the sender reuses one connection for many chunks.
                }
            }
        } catch (_: IOException) {
            // Connection dropped or timed out. The sender retries the chunk.
        }
    }

    /** Handles one request. Returns true if the connection can serve another. */
    private fun serveOne(input: InputStream, output: OutputStream, remote: String): Boolean {
        val requestLine = readLine(input) ?: return false
        val parts = requestLine.split(' ')
        if (parts.size < 3) return reply(output, 400, keepAlive = false)

        val headers = HashMap<String, String>()
        while (true) {
            val line = readLine(input) ?: return false
            if (line.isEmpty()) break
            val colon = line.indexOf(':')
            if (colon > 0) headers[line.substring(0, colon).trim().lowercase()] = line.substring(colon + 1).trim()
            if (headers.size > MAX_HEADERS) return false
        }

        if (parts[0] != "POST") return reply(output, 405, keepAlive = false)
        val target = parts[1]
        val path = target.substringBefore('?')
        if (path != UPLOAD_PATH) return reply(output, 404, keepAlive = false)

        val query = parseQuery(target.substringAfter('?', ""))
        val length = headers["content-length"]?.toLongOrNull() ?: return reply(output, 411, keepAlive = false)
        val sessionId = query["sessionId"]
        val fileId = query["fileId"]
        val token = query["token"]
        val offset = query["offset"]?.toLongOrNull()
        if (sessionId == null || fileId == null || token == null || offset == null) {
            return reply(output, 400, keepAlive = false)
        }

        val upload = uploads[key(sessionId, fileId)]
        if (upload == null ||
            !MessageDigest.isEqual(token.toByteArray(), upload.token.toByteArray()) ||
            upload.senderAddress != remote
        ) {
            return reply(output, 403, keepAlive = false)
        }
        if (offset < 0 || length <= 0 || offset + length > upload.size) {
            return reply(output, 400, keepAlive = false)
        }

        // The body goes socket -> file; nothing else touches it.
        RandomAccessFile(upload.path, "rw").use { file ->
            val channel = file.channel
            val buffer = ByteArray(COPY_BUFFER)
            var written = 0L
            while (written < length) {
                val want = min(buffer.size.toLong(), length - written).toInt()
                val n = input.read(buffer, 0, want)
                if (n < 0) throw IOException("sender closed mid-chunk")
                writeFully(channel, ByteBuffer.wrap(buffer, 0, n), offset + written)
                written += n
            }
        }

        val status = askDart(upload, offset, length)
        return reply(output, status, keepAlive = status == 200)
    }

    private fun askDart(upload: Upload, offset: Long, length: Long): Int {
        val answer = AtomicInteger(500)
        val latch = CountDownLatch(1)
        onChunk(upload.sessionId, upload.fileId, offset, length) { status ->
            answer.set(status)
            latch.countDown()
        }
        if (!latch.await(DART_REPLY_TIMEOUT_S, TimeUnit.SECONDS)) return 500
        return answer.get()
    }

    private fun writeFully(channel: FileChannel, buffer: ByteBuffer, position: Long) {
        var at = position
        while (buffer.hasRemaining()) at += channel.write(buffer, at)
    }

    private fun reply(output: OutputStream, status: Int, keepAlive: Boolean): Boolean {
        val reason = when (status) {
            200 -> "OK"
            400 -> "Bad Request"
            403 -> "Forbidden"
            404 -> "Not Found"
            405 -> "Method Not Allowed"
            411 -> "Length Required"
            422 -> "Unprocessable Entity"
            else -> "Error"
        }
        val connection = if (keepAlive) "keep-alive" else "close"
        output.write("HTTP/1.1 $status $reason\r\nContent-Length: 0\r\nConnection: $connection\r\n\r\n".toByteArray())
        output.flush()
        return keepAlive
    }

    private fun readLine(input: InputStream): String? {
        val line = StringBuilder()
        while (true) {
            val b = input.read()
            if (b == -1) return if (line.isEmpty()) null else throw IOException("unexpected end of stream")
            if (b == '\n'.code) return line.toString()
            if (b != '\r'.code) line.append(b.toChar())
            if (line.length > MAX_LINE) throw IOException("header line too long")
        }
    }

    private fun parseQuery(raw: String): Map<String, String> {
        if (raw.isEmpty()) return emptyMap()
        val result = HashMap<String, String>()
        for (pair in raw.split('&')) {
            val eq = pair.indexOf('=')
            if (eq <= 0) continue
            result[URLDecoder.decode(pair.substring(0, eq), "UTF-8")] =
                URLDecoder.decode(pair.substring(eq + 1), "UTF-8")
        }
        return result
    }

    private fun keyManagers(certificatePem: String, privateKeyPem: String): Array<KeyManager> {
        val certificate = CertificateFactory.getInstance("X.509")
            .generateCertificate(ByteArrayInputStream(certificatePem.toByteArray()))
        val keyBytes = Base64.decode(pemBody(privateKeyPem), Base64.DEFAULT)
        val privateKey = KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(keyBytes))

        val store = KeyStore.getInstance("PKCS12")
        store.load(null, null)
        store.setKeyEntry("zajel", privateKey, CharArray(0), arrayOf(certificate))
        val factory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
        factory.init(store, CharArray(0))
        return factory.keyManagers
    }

    private fun pemBody(pem: String): String =
        pem.lines().map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("-----") }.joinToString("")

    companion object {
        private const val UPLOAD_PATH = "/api/localsend/v2/upload"
        private const val IDLE_TIMEOUT_MS = 30_000
        private const val SOCKET_BUFFER = 1 shl 20
        private const val COPY_BUFFER = 256 * 1024
        private const val MAX_LINE = 8192
        private const val MAX_HEADERS = 64
        private const val DART_REPLY_TIMEOUT_S = 60L
    }
}
